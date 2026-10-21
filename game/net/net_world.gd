class_name NetWorld
extends RefCounted
## The node side of a snapshot: reads a Fighter into a NetFighterSnap on the host, and on the client turns a
## Fighter into a puppet (no control, kinematic bodies) and poses it from a NetFighterSnap. Bodies are the 11 parts
## in FighterRig order, then the fighter's weapons in creation order (both sides build the same loadout, so the
## lists match). The client's discrete changes (a cut limb, armor knocked off, death) go through the Fighter's own
## functions so its art, blood and sound hooks see them as usual.

const STATE_DEAD: String = "dead"


static func bodies(f: Fighter) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for n: String in FighterRig.names():
		out.append(f.parts[n] as RigidBody3D)
	for w: Variant in f.get("_weapons"):
		if w is RigidBody3D:
			out.append(w as RigidBody3D)
	return out


const PROP_GROUP: String = "armor_props"
const PROP_MESH_BITS: int = 5  ## prop id = armor index << 5 | index of the armor mesh it was torn from


## Host: the knocked-off armor props of a fighter, oldest first (Fighter._dislodge adds them as children).
static func armor_props(f: Fighter) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for c: Node in f.get_children():
		if c is RigidBody3D and c.is_in_group(PROP_GROUP):
			out.append(c as RigidBody3D)
	return out


## Host: which armor piece and which of its meshes a prop was torn from (the prop copies that mesh's material), as
## armor index << 5 | mesh index; -1 when it cannot be told.
static func prop_id(f: Fighter, prop: RigidBody3D, armor_ids: Array[String]) -> int:
	var copy: MeshInstance3D = null
	for c: Node in prop.get_children():
		if c is MeshInstance3D:
			copy = c as MeshInstance3D
			break
	if copy == null:
		return -1
	var all: Dictionary = f.get("_armor_meshes")
	for ai: int in range(mini(armor_ids.size(), 8)):
		var meshes: Array = all.get(armor_ids[ai], [])
		for mi: int in range(mini(meshes.size(), 1 << PROP_MESH_BITS)):
			var m: Variant = meshes[mi]
			if m is MeshInstance3D and is_instance_valid(m) and (m as MeshInstance3D).material_override == copy.material_override \
					and (m as MeshInstance3D).mesh == copy.mesh:
				return (ai << PROP_MESH_BITS) | mi
	return -1


## Initial armor ids in the fighter's own order (the bit order of NetFighterSnap.armor_mask).
static func armor_order(f: Fighter) -> Array[String]:
	var out: Array[String] = []
	for aid: Variant in f.get("_armor"):
		out.append(str(aid))
	return out


static func capture(f: Fighter, armor_ids: Array[String]) -> NetFighterSnap:
	var s := NetFighterSnap.new()
	s.state = maxi(NetConfig.STATES.find(f.state()), 0)
	var h: FighterHealth = f.health
	var names: PackedStringArray = FighterRig.names()
	s.part_hp.resize(names.size())
	for i: int in range(names.size()):
		if f.is_limb_cut(names[i]) or (h != null and h.is_severed(names[i])):
			s.severed_mask |= 1 << i
		s.part_hp[i] = h.hp_frac(names[i]) if h != null else 1.0
	if h != null:
		s.dead = h.dead
		s.gutted = h.gutted
		s.blood = h.blood
		s.bleed_rate = h.bleed_rate
		s.stamina = h.stamina
		s.consciousness = h.consciousness
	var worn: Array = f.get("_armor")
	for i: int in range(mini(armor_ids.size(), 8)):
		if worn.has(armor_ids[i]):
			s.armor_mask |= 1 << i
	s.yaw = float(f.get("_yaw"))
	s.hand_target = f.get("_hand_target")
	for b: RigidBody3D in bodies(f):
		var xf: Transform3D = b.global_transform
		s.pos.append(xf.origin)
		s.rot.append(xf.basis.get_rotation_quaternion())
		s.vel.append(b.linear_velocity)
	for prop: RigidBody3D in armor_props(f):
		if s.prop_ids.size() >= NetFighterSnap.MAX_PROPS:
			break
		var pid: int = prop_id(f, prop, armor_ids)
		if pid < 0:
			continue
		var pxf: Transform3D = prop.global_transform
		s.pos.append(pxf.origin)
		s.rot.append(pxf.basis.get_rotation_quaternion())
		s.vel.append(prop.linear_velocity)
		s.prop_ids.append(pid)
	return s


## Client: the fighter stops controlling itself and its bodies stop simulating; snapshots move them.
static func make_puppet(f: Fighter) -> void:
	f.set_physics_process(false)
	for b: RigidBody3D in bodies(f):
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true


## Client: poses the bodies and copies health and state; cuts limbs, drops armor and dies when the host did.
static func apply(f: Fighter, s: NetFighterSnap, armor_ids: Array[String]) -> void:
	var bs: Array[RigidBody3D] = bodies(f)
	for i: int in range(mini(bs.size(), s.body_count())):
		var b: RigidBody3D = bs[i]
		b.global_transform = Transform3D(Basis(s.rot[i]), s.pos[i])
		b.linear_velocity = s.vel[i]
	var h: FighterHealth = f.health
	var names: PackedStringArray = FighterRig.names()
	if h != null:
		h.blood = s.blood
		h.bleed_rate = s.bleed_rate
		h.stamina = s.stamina
		h.consciousness = s.consciousness
		h.gutted = s.gutted
		for i: int in range(mini(names.size(), s.part_hp.size())):
			h.parts[names[i]] = s.part_hp[i] * float(CombatData.part_info(names[i]).get("hp", 0.0))
	for i: int in range(names.size()):
		if (s.severed_mask & (1 << i)) != 0 and not f.is_limb_cut(names[i]):
			f.call("_sever", names[i])
	_apply_armor(f, s.armor_mask, armor_ids)
	_apply_props(f, s, armor_ids)
	f.set("_yaw", s.yaw)
	f.set("_hand_target", s.hand_target)
	if h != null:
		h.dead = s.dead
	var st: String = NetConfig.STATES[clampi(s.state, 0, NetConfig.STATES.size() - 1)]
	if st == STATE_DEAD or s.dead:
		if f.state() != STATE_DEAD:
			f.call("_die")
	else:
		f.set("_state", st)


static func _apply_armor(f: Fighter, mask: int, armor_ids: Array[String]) -> void:
	var worn: Array = f.get("_armor")
	var meshes: Dictionary = f.get("_armor_meshes")
	for i: int in range(mini(armor_ids.size(), 8)):
		var aid: String = armor_ids[i]
		if (mask & (1 << i)) != 0 or not worn.has(aid):
			continue
		worn.erase(aid)
		for m: Variant in meshes.get(aid, []):
			if m is MeshInstance3D and is_instance_valid(m):
				(m as MeshInstance3D).visible = false


## Client: the knocked-off armor pieces fly as props. Each one is a frozen body without collision (like a weapon
## on the client) holding a copy of the mesh it was torn from, created the first time a snapshot lists it and posed
## from the snapshot like the other bodies.
static func _apply_props(f: Fighter, s: NetFighterSnap, armor_ids: Array[String]) -> void:
	var made: Array = f.get_meta("net_props", []) as Array
	var base: int = s.base_body_count()
	for k: int in range(s.prop_ids.size()):
		var bi: int = base + k
		if bi >= s.body_count():
			break
		if k >= made.size():
			made.append(_make_prop(f, int(s.prop_ids[k]), armor_ids))
		var prop: Variant = made[k]
		if prop is RigidBody3D and is_instance_valid(prop):
			(prop as RigidBody3D).global_transform = Transform3D(Basis(s.rot[bi]), s.pos[bi])
			(prop as RigidBody3D).linear_velocity = s.vel[bi]
	f.set_meta("net_props", made)


static func _make_prop(f: Fighter, pid: int, armor_ids: Array[String]) -> Variant:
	var ai: int = pid >> PROP_MESH_BITS
	var mesh_i: int = pid & ((1 << PROP_MESH_BITS) - 1)
	if ai >= armor_ids.size():
		return null
	var meshes: Array = (f.get("_armor_meshes") as Dictionary).get(armor_ids[ai], [])
	if mesh_i >= meshes.size() or not (meshes[mesh_i] is MeshInstance3D) or not is_instance_valid(meshes[mesh_i]):
		return null
	var src: MeshInstance3D = meshes[mesh_i] as MeshInstance3D
	var prop := RigidBody3D.new()
	prop.name = "NetArmorProp%d" % (f.get_meta("net_props", []) as Array).size()
	prop.collision_layer = 0
	prop.collision_mask = 0
	prop.top_level = true
	prop.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	prop.freeze = true
	var copy := MeshInstance3D.new()
	copy.mesh = src.mesh
	copy.material_override = src.material_override
	prop.add_child(copy)
	f.add_child(prop)
	prop.add_to_group(PROP_GROUP)
	return prop
