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
