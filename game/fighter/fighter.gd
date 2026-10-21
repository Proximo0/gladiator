class_name Fighter
extends Node3D
## Active-ragdoll gladiator, built entirely in code (see docs/core_brief.md for the contract).
## 11 RigidBody3D parts joined by Generic6DOFJoint3D with angular limits. Each tick:
## - per-joint PD torques (equal and opposite on parent and child) drive the parts toward a target pose: legs from
##   a gait/IK, spine and head from the aim, arms from a 2-link IK toward the hand targets;
## - a balance controller holds the pelvis at stand height (support force), upright and facing (torque), and moves
##   it toward the input velocity, all capped so hits can knock the fighter over;
## - the right hand is pulled by a capped PD force toward the aim target in the guard plane, so weapon mass and
##   arm strength set how fast swings build up; a capped wrist torque orients the weapon;
## - weapon contacts with bodies (own body included, except the holding forearm) and weapons are resolved through
##   DamageModel. The struck fighter emits `hit` and `gore`; severs break joints; disarms drop the weapon.
## Strength scales with stamina, consciousness and each limb's hp. Knocked out or dead goes limp.

signal hit(event: Dictionary)
signal gore(event: Dictionary)
signal died

const LAYER_BODIES: int = 2
## Quaternion grid for normalised poses (snapshot/restore).
const POSE_QUANTUM: float = 0.00001
const MASK_ALL: int = 7

## Gameplay numbers read from Tuning each tick, with these fallbacks until the rows exist there.
const FALLBACK: Dictionary = {
	"gravity": 9.8, "move_speed": 2.5, "sprint_speed": 4.5, "arm_force": 900.0, "damage_min_speed": 3.0,
	"stand_height": 0.95, "crouch_height": 0.74, "support_freq": 9.0, "support_max": 2.2,
	"balance_freq": 9.0, "balance_torque": 450.0, "torso_assist": 0.35, "move_accel": 9.0, "move_response": 7.0,
	"turn_rate": 6.0, "joint_strength": 1.0, "joint_damping": 1.0,
	"arm_freq": 22.0, "arm_damping": 0.3, "arm_drive_mass": 3.5, "guard_force_frac": 0.45,
	"offhand_force_frac": 0.6, "arm_reaction": 0.4, "wrist_torque": 140.0, "wrist_freq": 16.0, "wrist_limit": 1.2, "wrist_roll": 0.3, "wrist_reach": 0.9, "wrist_lead": 0.15, "blade_up_guard": 0.75, "blade_up_swing": 0.25,
	"guard_width": 0.7, "guard_height": 0.5, "guard_forward": 0.42, "thrust_reach": 0.45, "half_sword_thrust": 1.6,
	"torso_twist": 0.7, "stumble_tilt": 0.35, "fall_tilt": 1.0, "stagger_down": 0.85, "stagger_recover": 0.8,
	"down_time": 1.5, "getup_time": 1.4, "down_strength": 0.3, "limp_strength": 0.04, "stamina_floor": 0.45,
	"limb_floor": 0.25, "weapon_drop_hp": 0.15, "stride_base": 0.15, "stride_per_speed": 0.08, "stride_max": 0.45,
	"foot_lift": 0.13, "pelvis_inertia": 2.0, "torso_inertia": 2.5, "balance_inertia": 3.0, "leg_reaction": 0.25, "pd_margin": 0.5, "self_hit_min_speed": 6.0, "hold_freq": 2.0, "blade_pivot_back": 0.45, "swing_reach": 0.35, "guard_hand_speed": 2.5, "swing_hand_speed": 30.0, "offhand_hand_speed": 5.0, "hit_debounce": 0.25, "grab_radius": 0.3, "knockback_scale": 1.0,
}

const SWING: int = 1
const OFFHAND: int = 2
const HALF_SWORD: int = 4
const THRUST: int = 8
const SPRINT: int = 16
const CROUCH: int = 32
const GRAB: int = 64
const TURN_LOCK: int = 128

## Weapon rest frames relative to the hand when the forearm hangs (columns X edge, Y blade, Z flat).
## A blade rests half way between square to the forearm and in line with it, so the wrist's range covers both an
## upright guard and a fully extended cut.
const GRIP_BLADE: Basis = Basis(Vector3(0, -0.70710678, 0.70710678), Vector3(0, -0.70710678, -0.70710678), Vector3(1, 0, 0))
const GRIP_SHIELD: Basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
const GRIP_FIST: Basis = Basis(Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))

var opponent: Fighter = null
var health: FighterHealth = null
var side: int = 0
var loadout: Dictionary = {}
var parts: Dictionary = {}
var joints: Dictionary = {}
## Held weapon in the right hand (null when empty-handed: the fist does the work).
var weapon: Weapon = null
## Held item in the left hand (shield), or null.
var offhand: Weapon = null
var fist_r: Weapon = null
var fist_l: Weapon = null

var _tun: Tuning = null
var _built: bool = false
var _rest: Dictionary = {}
var _inertia: Dictionary = {}
var _inertia_pair: Dictionary = {}
var _inertia_twist: Dictionary = {}
var _weapons: Array[Weapon] = []
var _input: FighterInput = null
var _state: String = "standing"
var _state_t: float = 0.0
var _yaw: float = 0.0
var _phase: float = 0.0
var _stagger: float = 0.0
var _tick: int = 0
var _severed: PackedStringArray = PackedStringArray()
var _armor: Array[String] = []
var _armor_wear: Dictionary = {}
var _armor_meshes: Dictionary = {}
var _debounce: Dictionary = {}
var _contacts: Array = []
var _contacts_frame: int = -1
var _vel_cur: Dictionary = {}
var _vel_prev: Dictionary = {}
var _vel_cur_frame: int = -1
var _died_emitted: bool = false
var _skip_contacts: int = 0
var _exertion: float = 0.0
var _hand_target: Vector3 = Vector3.ZERO
var _hand_target_l: Vector3 = Vector3.ZERO
var _goal_r: Vector3 = Vector3.ZERO
var _goal_l: Vector3 = Vector3.ZERO
var _grab_latch: bool = false
var _prop_serial: int = 0
var _anchor: Vector3 = Vector3.ZERO
var _anchor_set: bool = false


func _init() -> void:
	process_physics_priority = 10
	_input = FighterInput.new()


func _t(field: String) -> float:
	var v: Variant = _tun.get(field) if _tun != null else null
	if v is float or v is int:
		return float(v)
	return float(FALLBACK.get(field, 0.0))


func setup(p_loadout: Dictionary, p_side: int, tuning: Tuning) -> void:
	loadout = p_loadout
	side = p_side
	_tun = tuning if tuning != null else Tuning.shared()
	health = FighterHealth.new(_tun)
	if is_inside_tree():
		_build()


func _ready() -> void:
	if not _built and _tun != null:
		_build()


func apply_input(inp: FighterInput) -> void:
	if inp != null:
		_input = FighterInput.from_array(inp.to_array())


# --- construction ------------------------------------------------------------------------------------------------

func _build() -> void:
	_built = true
	_yaw = FighterMath.yaw_of(-global_transform.basis.z)
	var skin := Color(0.78, 0.6, 0.47)
	var cloth := Color(0.62, 0.16, 0.12) if side == 0 else Color(0.16, 0.26, 0.55)
	var legs := Color(0.36, 0.28, 0.2)
	for pd: Dictionary in FighterRig.PARTS:
		var n: String = pd["name"]
		_rest[n] = Transform3D(Basis(), pd["center"])
		var col: Color = skin
		if n == "torso" or n == "pelvis":
			col = cloth
		elif n.begins_with("thigh"):
			col = legs
		var look: Dictionary = (loadout.get("look", {}) as Dictionary).get(n, {})
		if look.has("color"):
			col = Weapon.parse_color(look["color"])
		_make_part(pd, col)
	for pd: Dictionary in FighterRig.PARTS:
		if pd["parent"] != "":
			_connect_joint(str(pd["name"]))
	var names: PackedStringArray = FighterRig.names()
	for i: int in range(names.size()):
		for k: int in range(i + 1, names.size()):
			_exclude(parts[names[i]], parts[names[k]])
	_build_armor()
	fist_r = _make_weapon(CombatData.weapon("fists"), 0.3)
	fist_l = _make_weapon(CombatData.weapon("fists"), 0.3)
	_attach(fist_r, "r")
	_attach(fist_l, "l")
	var wid: String = str(loadout.get("weapon", "fists"))
	if wid != "" and wid != "fists" and not CombatData.weapon(wid).is_empty():
		weapon = _make_weapon(CombatData.weapon(wid), -1.0)
		_attach(weapon, "r")
	var oid: String = str(loadout.get("offhand", ""))
	if oid != "" and oid != "fists" and not CombatData.weapon(oid).is_empty():
		offhand = _make_weapon(CombatData.weapon(oid), -1.0)
		_attach(offhand, "l")
	_compute_inertia()
	_hand_target = _hand_pos("r")
	_hand_target_l = _hand_pos("l")
	_goal_r = _hand_target - (parts["pelvis"] as RigidBody3D).global_position
	_goal_l = _hand_target_l - (parts["pelvis"] as RigidBody3D).global_position
	_record_velocities()


func _make_part(pd: Dictionary, col: Color) -> void:
	var n: String = pd["name"]
	var b := RigidBody3D.new()
	b.name = n
	b.mass = float(pd["mass"])
	b.top_level = true
	b.collision_layer = LAYER_BODIES
	b.collision_mask = MASK_ALL
	b.can_sleep = false
	b.set_meta("fighter", self)
	b.set_meta("part", n)
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0 if n.begins_with("shin") else 0.6
	b.physics_material_override = pm
	var size: Vector3 = pd["size"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	match str(pd["shape"]):
		"box":
			var s := BoxShape3D.new()
			s.size = size
			var m := BoxMesh.new()
			m.size = size
			_add_shape(b, s, m, Vector3.ZERO, mat)
		"sphere":
			var s2 := SphereShape3D.new()
			s2.radius = size.x
			var m2 := SphereMesh.new()
			m2.radius = size.x
			m2.height = size.x * 2.0
			_add_shape(b, s2, m2, Vector3.ZERO, mat)
		_:
			var s3 := CapsuleShape3D.new()
			s3.radius = size.x
			s3.height = size.y
			var m3 := CapsuleMesh.new()
			m3.radius = size.x
			m3.height = size.y
			_add_shape(b, s3, m3, Vector3.ZERO, mat)
	if n.begins_with("shin"):
		var fs := BoxShape3D.new()
		fs.size = FighterRig.FOOT_SIZE
		var fm := BoxMesh.new()
		fm.size = FighterRig.FOOT_SIZE
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.25, 0.17, 0.1)
		_add_shape(b, fs, fm, FighterRig.FOOT_OFFSET, fmat)
	# The pelvis and torso sit between free ball joints and take the balance and spine torques; their own
	# inertia is boosted so those explicit PD torques stay stable at 60 Hz.
	if n == "pelvis" or n == "torso":
		b.inertia = Vector3.ONE * _t(n + "_inertia")
	parts[n] = b
	add_child(b)
	b.global_transform = global_transform * (_rest[n] as Transform3D)


func _add_shape(b: RigidBody3D, s: Shape3D, m: Mesh, pos: Vector3, mat: Material) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = pos
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	_slot(b, "Look").add_child(mi)


## Visual slot `slot_name` ("Look" for the body's own meshes, "ArmorSlot" for worn armor) on part body `b`.
func _slot(b: Node3D, slot_name: String) -> Node3D:
	var s: Node3D = b.get_node_or_null(slot_name) as Node3D
	if s == null:
		s = Node3D.new()
		s.name = slot_name
		b.add_child(s)
	return s


## Replaces part `part`'s look with `mesh` (any style, any era): the default meshes are removed. Physics shapes
## stay as they are. `xf` places the mesh in the part's frame (origin at the part centre, Y along the bone).
func set_part_look(part: String, mesh: Mesh, material: Material, xf: Transform3D = Transform3D()) -> void:
	if not parts.has(part):
		return
	var look: Node3D = _slot(parts[part], "Look")
	for c: Node in look.get_children():
		look.remove_child(c)
		c.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xf
	look.add_child(mi)


## Where worn items attach on part `part` (a Node3D in the part's frame), for armor or cosmetics of any style.
func armor_slot(part: String) -> Node3D:
	return _slot(parts[part], "ArmorSlot") if parts.has(part) else null


## Creates (or re-creates) the joint holding part `n` to its parent, with frames taken from the rest pose.
func _connect_joint(n: String) -> void:
	var pd: Dictionary = FighterRig.part(n)
	var parent: RigidBody3D = parts[pd["parent"]]
	var child: RigidBody3D = parts[n]
	var keep: Transform3D = child.global_transform
	var parent_rest_inv: Transform3D = (_rest[pd["parent"]] as Transform3D).affine_inverse()
	child.global_transform = parent.global_transform * parent_rest_inv * (_rest[n] as Transform3D)
	var j := Generic6DOFJoint3D.new()
	j.name = "J_" + n
	add_child(j)
	j.top_level = true
	j.global_transform = parent.global_transform * parent_rest_inv * Transform3D(Basis(), pd["pivot"])
	var lim: Array = pd["lim"]
	var axes: Array[String] = ["x", "y", "z"]
	for i: int in range(3):
		j.set("angular_limit_%s/enabled" % axes[i], true)
		# The 6DOF joint measures the angle with the opposite sign to the child's rotation: mirror the range.
		j.set("angular_limit_%s/lower_angle" % axes[i], -float(lim[i * 2 + 1]))
		j.set("angular_limit_%s/upper_angle" % axes[i], -float(lim[i * 2]))
	j.node_a = j.get_path_to(parent)
	j.node_b = j.get_path_to(child)
	joints[n] = j
	child.global_transform = keep


func _disconnect_joint(n: String) -> void:
	if not joints.has(n):
		return
	var j: Generic6DOFJoint3D = joints[n]
	j.node_b = NodePath("")
	j.node_a = NodePath("")
	remove_child(j)
	j.free()
	joints.erase(n)


func _exclude(a: PhysicsBody3D, b: PhysicsBody3D) -> void:
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)


func _make_weapon(d: Dictionary, physical_mass: float) -> Weapon:
	var w := Weapon.new()
	w.name = "W%d_%d_%s" % [side, _weapons.size(), str(d.get("id", "w"))]
	w.owner_side = side
	w.top_level = true
	w.build(d, physical_mass)
	add_child(w)
	_weapons.append(w)
	return w


func _grip_basis(w: Weapon) -> Basis:
	if w.is_fist:
		return GRIP_FIST
	if w.shape_kind == "shield":
		return GRIP_SHIELD
	return GRIP_BLADE


## Puts `w` in hand `h` ("r" or "l"): joint at the hand point, collision exceptions for a held weapon.
func _attach(w: Weapon, h: String) -> void:
	var fore: RigidBody3D = parts["forearm_" + h]
	var grip: Transform3D = fore.global_transform * Transform3D(_grip_basis(w), FighterRig.HAND_LOCAL)
	var lim: float = 0.02 if w.is_fist else _t("wrist_limit")
	if w.holder != null and w.holder != self:
		(w.holder as Fighter)._release(w)
	if w.lodged_in != null:
		w.detach()
	w.global_transform = grip
	w.linear_velocity = fore.linear_velocity
	w.angular_velocity = fore.angular_velocity
	w.attach(fore, grip, lim)
	w.holder = self
	w.hand = h
	if not w.is_fist:
		if h == "r":
			weapon = w
		else:
			offhand = w
	_set_exceptions(w)


## Drops whatever the fighter holds in `w` (it becomes a free prop).
func _release(w: Weapon) -> void:
	if weapon == w:
		weapon = null
	if offhand == w:
		offhand = null
	if w.holder == self:
		w.detach()
		_set_exceptions(w)


func _set_exceptions(w: Weapon) -> void:
	for o: Node in w.get_collision_exceptions():
		if o is PhysicsBody3D:
			w.remove_collision_exception_with(o)
			(o as PhysicsBody3D).remove_collision_exception_with(w)
	if w.holder == null:
		return
	var f: Fighter = w.holder as Fighter
	for pn: String in FighterRig.names():
		var own_hand: bool = pn == "forearm_" + w.hand
		var two_hand: bool = pn.begins_with("forearm") and w == f.weapon
		if w.is_fist or w.shape_kind == "shield" or own_hand or two_hand:
			f._exclude(w, f.parts[pn])
	for other: Weapon in [f.fist_r, f.fist_l, f.weapon, f.offhand]:
		if other != null and other != w:
			f._exclude(w, other)


func _build_armor() -> void:
	_armor.clear()
	var arm: Dictionary = loadout.get("armor", {})
	for slot: Variant in arm:
		var aid: String = str(arm[slot])
		var ad: Dictionary = CombatData.armor(aid)
		if ad.is_empty() or _armor.has(aid):
			continue
		_armor.append(aid)
		_armor_wear[aid] = 0.0
		var meshes: Array = []
		for pn: Variant in ad.get("covers", []):
			if not parts.has(str(pn)):
				continue
			meshes.append(_armor_mesh(parts[str(pn)], str(pn), ad))
		_armor_meshes[aid] = meshes


## Placeholder armor mesh on part `pn` (shape from the part, colour from the armor kind or the def's "color").
func _armor_mesh(b: RigidBody3D, pn: String, ad: Dictionary) -> MeshInstance3D:
	var kind: String = str(ad.get("kind", "leather"))
	var pd: Dictionary = FighterRig.part(pn)
	var size: Vector3 = pd["size"]
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match kind:
		"plate":
			mat.albedo_color = Color(0.62, 0.64, 0.67)
			mat.metallic = 0.7
			mat.roughness = 0.35
		"mail":
			mat.albedo_color = Color(0.45, 0.47, 0.5)
			mat.metallic = 0.5
			mat.roughness = 0.6
		_:
			mat.albedo_color = Color(0.4, 0.26, 0.14)
			mat.roughness = 0.8
	if ad.has("color"):
		mat.albedo_color = Weapon.parse_color(ad["color"])
	if pd["shape"] == "sphere":
		var sm := SphereMesh.new()
		sm.radius = size.x + 0.015
		sm.height = sm.radius * 1.6
		mi.mesh = sm
		mi.position = Vector3(0, 0.03, 0)
	elif pd["shape"] == "box":
		var bm := BoxMesh.new()
		bm.size = size + Vector3(0.02, -0.04, 0.02)
		mi.mesh = bm
	else:
		var cm := CapsuleMesh.new()
		cm.radius = size.x + 0.012
		cm.height = size.y * 0.8
		mi.mesh = cm
	mi.material_override = mat
	mi.name = "Armor_" + pn
	_slot(b, "ArmorSlot").add_child(mi)
	return mi


func _compute_inertia() -> void:
	for pd: Dictionary in FighterRig.PARTS:
		var n: String = pd["name"]
		if pd["parent"] == "":
			continue
		var extra_m: float = 0.0
		var extra_r: float = 0.0
		if n.ends_with("_r") and n.contains("arm") and weapon != null:
			extra_m = weapon.mass
			extra_r = 0.5
		_inertia[n] = FighterRig.joint_inertia(n, extra_m, extra_r)
		var boost: Dictionary = {"pelvis": _t("pelvis_inertia"), "torso": _t("torso_inertia")}
		_inertia_pair[n] = FighterRig.pair_inertia(n, boost)
		_inertia_twist[n] = FighterRig.twist_inertia(n, boost)


# --- per-tick control --------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built:
		return
	_tick += 1
	if _skip_contacts > 0:
		_skip_contacts -= 1
	else:
		_process_contacts()
	if health != null:
		health.tick(delta, _exertion)
	_update_state(delta)
	_control(delta)
	_record_velocities()


func _frame() -> int:
	return Engine.get_physics_frames()


func state() -> String:
	return _state


func is_limb_cut(n: String) -> bool:
	return _severed.has(n)


func _hp(n: String) -> float:
	if _severed.has(n):
		return 0.0
	return health.hp_frac(n) if health != null else 1.0


func tilt() -> float:
	var t: RigidBody3D = parts["torso"]
	var p: RigidBody3D = parts["pelvis"]
	var up_t: float = t.global_transform.basis.y.normalized().dot(Vector3.UP)
	var up_p: float = p.global_transform.basis.y.normalized().dot(Vector3.UP)
	return acos(clampf((up_t + up_p) * 0.5, -1.0, 1.0))


func balance() -> float:
	return FighterMath.balance_from_tilt(tilt(), _t("fall_tilt"))


func _legs_ok() -> bool:
	for n: String in ["thigh_l", "thigh_r", "shin_l", "shin_r"]:
		if _severed.has(n):
			return false
	return true


func _update_state(delta: float) -> void:
	_state_t += delta
	_stagger = maxf(_stagger - _t("stagger_recover") * delta, 0.0)
	if _state == "dead":
		return
	if health != null and health.dead:
		_die()
		return
	if health != null and health.knocked_out():
		_set_state("ko")
		return
	var tl: float = tilt()
	var h: float = (parts["pelvis"] as RigidBody3D).global_position.y
	match _state:
		"ko":
			_set_state("down")
		"standing", "stumbling":
			if not _legs_ok() or tl > _t("fall_tilt") or h < _t("stand_height") * 0.5 or _stagger >= _t("stagger_down"):
				_set_state("down")
			elif tl > _t("stumble_tilt") or _stagger > 0.25:
				if _state != "stumbling":
					_set_state("stumbling")
			elif _state != "standing" and _state_t > 0.2:
				_set_state("standing")
		"down":
			if _state_t > _t("down_time") and _legs_ok() and _stagger < 0.3:
				_set_state("getting_up")
		"getting_up":
			var done: bool = _state_t >= _t("getup_time")
			if done and tl < _t("stumble_tilt") and h > _t("stand_height") * 0.85:
				_set_state("standing")
			elif _state_t > _t("getup_time") * 3.0 or not _legs_ok():
				_set_state("down")


func _set_state(s: String) -> void:
	if s != _state:
		_state = s
		_state_t = 0.0


func _die() -> void:
	_set_state("dead")
	if not _died_emitted:
		_died_emitted = true
		died.emit()


func _strength() -> float:
	if health == null:
		return 1.0
	return FighterMath.strength(health.stamina, health.consciousness, _t("stamina_floor"))


func _control(delta: float) -> void:
	var inp: FighterInput = _input
	var s: float = _strength()
	var joint_scale: float = s * _t("joint_strength")
	var support: float = 1.0
	match _state:
		"stumbling":
			support = 1.0 - 0.5 * clampf(_stagger, 0.0, 1.0)
		"down":
			support = 0.0
			joint_scale = s * _t("down_strength")
		"getting_up":
			support = clampf(_state_t / maxf(_t("getup_time"), 0.01), 0.15, 1.0)
		"ko", "dead":
			support = 0.0
			joint_scale = _t("limp_strength")
	var legs_hp: float = minf(minf(_hp("thigh_l"), _hp("shin_l")), minf(_hp("thigh_r"), _hp("shin_r")))
	var leg_factor: float = FighterMath.limb_factor(legs_hp, _t("limb_floor"))
	support *= lerpf(0.75, 1.0, leg_factor)
	var active: bool = _state == "standing" or _state == "stumbling" or _state == "getting_up"

	# Facing.
	if active and _state != "getting_up":
		var target_yaw: float = _yaw
		if opponent != null and is_instance_valid(opponent) and not inp.has(TURN_LOCK) and opponent._built:
			var d: Vector3 = (opponent.parts["pelvis"] as RigidBody3D).global_position - (parts["pelvis"] as RigidBody3D).global_position
			d.y = 0.0
			if d.length_squared() > 0.01:
				target_yaw = FighterMath.yaw_of(d)
		_yaw = FighterMath.turn_toward(_yaw, target_yaw, _t("turn_rate") * delta * s)
	var yb := Basis(Vector3.UP, _yaw)
	var fwd: Vector3 = -yb.z
	var right: Vector3 = yb.x

	var pelvis: RigidBody3D = parts["pelvis"]
	var total_mass: float = _total_mass()
	var g: float = _t("gravity")
	var crouch: bool = inp.has(CROUCH)
	var h_target: float = _t("crouch_height") if crouch else _t("stand_height")
	if _state == "getting_up":
		h_target = lerpf(pelvis.global_position.y, h_target, clampf(_state_t / maxf(_t("getup_time"), 0.01), 0.3, 1.0))
	var grounded: bool = _lowest_foot() < 0.3 or pelvis.global_position.y < h_target + 0.15
	var pvel: Vector3 = pelvis.linear_velocity
	var hvel := Vector3(pvel.x, 0.0, pvel.z)

	# Support and locomotion force on the pelvis.
	var move: Vector2 = inp.move().limit_length(1.0)
	var speed: float = _t("sprint_speed") if inp.has(SPRINT) else _t("move_speed")
	speed *= lerpf(0.35, 1.0, leg_factor)
	if crouch:
		speed *= 0.6
	var v_des: Vector3 = (right * move.x + fwd * move.y) * speed
	if _state != "standing":
		v_des *= 0.3 if _state == "stumbling" else 0.0
	if grounded and support > 0.0:
		var w: float = _t("support_freq")
		var fy: float = total_mass * (g + w * w * (h_target - pelvis.global_position.y) - 2.0 * w * pvel.y)
		fy = clampf(fy, 0.0, _t("support_max") * total_mass * g) * support
		var fh: Vector3 = (v_des - hvel) * (total_mass * _t("move_response"))
		# Standing still holds its spot (a weak spring) so idle drift does not wander off.
		if _state == "standing" and move.length() < 0.05:
			if not _anchor_set:
				_anchor = Vector3(pelvis.global_position.x, 0.0, pelvis.global_position.z)
				_anchor_set = true
			var hf: float = _t("hold_freq")
			var off: Vector3 = _anchor - Vector3(pelvis.global_position.x, 0.0, pelvis.global_position.z)
			fh += off * (total_mass * hf * hf)
		else:
			_anchor_set = false
		fh = fh.limit_length(_t("move_accel") * total_mass * support * (0.5 if _state == "stumbling" else 1.0))
		pelvis.apply_central_force(Vector3(fh.x, fy, fh.z))

	# Balance: pelvis upright and facing; torso assisted upright.
	var bal_scale: float = support * (1.0 - 0.7 * clampf(_stagger, 0.0, 1.0))
	if bal_scale > 0.0:
		var bf: float = _t("balance_freq")
		var cap: float = _t("balance_torque") * bal_scale * s
		var err: Vector3 = FighterMath.rotation_error(pelvis.global_transform.basis, yb)
		pelvis.apply_torque(FighterMath.pd_torque(err, pelvis.angular_velocity, _t("balance_inertia"), bf, 1.0, cap))
		var torso: RigidBody3D = parts["torso"]
		var terr: Vector3 = FighterMath.rotation_error(torso.global_transform.basis, yb)
		var tf: float = _t("torso_assist")
		torso.apply_torque(FighterMath.pd_torque(terr, torso.angular_velocity, _inertia["torso"], bf, 1.0, cap * tf))

	# Gait phase from actual horizontal speed.
	var sp: float = hvel.length()
	var amp: float = FighterMath.stride_amp(sp, _t("stride_base"), _t("stride_per_speed"), _t("stride_max"))
	if amp > 0.0 and active:
		_phase = fposmod(_phase + delta * TAU * sp / (4.0 * amp), TAU)
	var mdir: Vector2 = Vector2.ZERO
	if sp > 0.05:
		mdir = Vector2(hvel.dot(right), hvel.dot(fwd)) / sp

	# Pose targets (child relative to parent).
	var targets: Dictionary = {}
	var aim: Vector2 = inp.aim()
	var twist: float = -aim.x * _t("torso_twist") if active else 0.0
	var lean: float = 0.06 + (0.25 if crouch else 0.0)
	targets["torso"] = Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, -lean)
	targets["head"] = Basis(Vector3.UP, -twist * 0.8) * Basis(Vector3.RIGHT, lean * 0.5)
	if active:
		_leg_targets(targets, yb, amp * (1.0 if _state == "standing" else 0.6), mdir)
	else:
		for n: String in ["thigh_l", "thigh_r"]:
			targets[n] = Basis(Vector3.RIGHT, 0.25)
		for n: String in ["shin_l", "shin_r"]:
			targets[n] = Basis(Vector3.RIGHT, -0.4)
	var used: float = _arms(targets, yb, fwd, right, active, s, delta)

	# Joint PD.
	for pd: Dictionary in FighterRig.PARTS:
		var n: String = pd["name"]
		if pd["parent"] == "" or _severed.has(n) or not joints.has(n) or not targets.has(n):
			continue
		var par: RigidBody3D = parts[pd["parent"]]
		var ch: RigidBody3D = parts[n]
		var want: Basis = par.global_transform.basis * (targets[n] as Basis)
		var e: Vector3 = FighterMath.rotation_error(ch.global_transform.basis, want)
		var limb: float = FighterMath.limb_factor(_hp(n), _t("limb_floor"))
		var freq: float = float(pd["freq"])
		var arm_drive: bool = n.contains("arm") and active
		if arm_drive:
			freq *= 0.6
		var cap_t: float = float(pd["torque"]) * joint_scale * limb
		var damp: float = _t("joint_damping")
		var margin: float = _t("pd_margin")
		var inertia: float = FighterMath.stable_inertia(_inertia[n], _inertia_pair[n], freq, damp, delta, margin)
		# Twist about the bone has a tiny inertia: it gets its own, much smaller gain (one gain for all axes
		# makes the limbs spin up about their own axes).
		var axis: Vector3 = ch.global_transform.basis.y.normalized()
		var w_rel: Vector3 = ch.angular_velocity - par.angular_velocity
		var e_tw: Vector3 = axis * e.dot(axis)
		var w_tw: Vector3 = axis * w_rel.dot(axis)
		var i_tw: float = FighterMath.stable_inertia(_inertia_twist[n], _inertia_twist[n], freq, damp, delta, margin)
		var tq: Vector3 = FighterMath.pd_torque(e - e_tw, w_rel - w_tw, inertia, freq, damp, cap_t)
		tq += FighterMath.pd_torque(e_tw, w_tw, i_tw, freq, damp, cap_t)
		ch.apply_torque(tq)
		# Feet are not anchored, so a hip's full reaction would spin the pelvis: only part of it is passed on.
		var react: Vector3 = -tq * (_t("leg_reaction") if n.begins_with("thigh") else 1.0)
		# A bent knee or elbow pushes partly along the parent limb's own axis, where its inertia is tiny: that
		# share would spin the thigh or upper arm up, so it is left out.
		if pd["parent"] != "pelvis" and pd["parent"] != "torso":
			var p_axis: Vector3 = par.global_transform.basis.y.normalized()
			react -= p_axis * react.dot(p_axis)
		par.apply_torque(react)

	var sprinting: bool = inp.has(SPRINT) and move.length() > 0.1
	_exertion = clampf(used * 0.7 + (0.6 if sprinting else 0.0) + (0.2 if inp.has(SWING) else 0.0), 0.0, 1.0)
	if not active:
		_exertion = 0.0
	_handle_grab(inp)


func _total_mass() -> float:
	var m: float = 0.0
	for n: String in FighterRig.names():
		if not _severed.has(n) or not _is_cut_off(n):
			m += (parts[n] as RigidBody3D).mass
	for w: Weapon in [fist_r, fist_l, weapon, offhand]:
		if w != null and w.holder == self:
			m += w.mass
	return m


## True when part `n` is no longer connected to the pelvis.
func _is_cut_off(n: String) -> bool:
	var cur: String = n
	while cur != "pelvis" and cur != "":
		if _severed.has(cur):
			return true
		cur = str(FighterRig.part(cur).get("parent", ""))
	return false


func _lowest_foot() -> float:
	var lo: float = 9.0
	for n: String in ["shin_l", "shin_r"]:
		if _is_cut_off(n):
			continue
		var b: RigidBody3D = parts[n]
		lo = minf(lo, (b.global_transform * FighterRig.ANKLE_LOCAL).y)
	return lo


func _leg_targets(targets: Dictionary, yb: Basis, amp: float, mdir: Vector2) -> void:
	var pelvis: RigidBody3D = parts["pelvis"]
	var pinv: Basis = pelvis.global_transform.basis.inverse()
	for i: int in range(2):
		var sfx: String = "_l" if i == 0 else "_r"
		var hip_local: Vector3 = (FighterRig.part("thigh" + sfx)["pivot"] as Vector3) - (FighterRig.part("pelvis")["center"] as Vector3)
		var hip: Vector3 = pelvis.global_transform * hip_local
		var off: Vector3 = FighterMath.foot_offset(_phase + PI * i, mdir, amp, _t("foot_lift"))
		var stance := Vector3(hip_local.x * 0.25, 0.0, 0.0)
		var foot_w: Vector3 = hip + yb * Vector3(off.x + stance.x, 0.0, off.z)
		foot_w.y = FighterRig.ANKLE_HEIGHT + off.y
		var rel: Vector3 = pinv * (foot_w - hip)
		var ang: Vector3 = FighterMath.leg_ik(rel, FighterRig.THIGH_LEN, FighterRig.SHIN_LEN)
		var bases: Array[Basis] = FighterMath.leg_bases(ang)
		targets["thigh" + sfx] = bases[0]
		targets["shin" + sfx] = bases[1]


func _hand_pos(h: String) -> Vector3:
	return (parts["forearm_" + h] as RigidBody3D).global_transform * FighterRig.HAND_LOCAL


func _hand_vel(h: String) -> Vector3:
	var f: RigidBody3D = parts["forearm_" + h]
	return f.linear_velocity + f.angular_velocity.cross(_hand_pos(h) - f.global_position)


func grip() -> String:
	if weapon != null and _input.has(HALF_SWORD) and bool(weapon.def.get("half_sword", false)) and not _is_cut_off("forearm_l"):
		return "half"
	return "normal"


## Hand forces, arm IK targets and wrist torques. Returns the fraction of arm force used (0..1).
func _arms(targets: Dictionary, yb: Basis, fwd: Vector3, right: Vector3, active: bool, s: float, _delta: float) -> float:
	var inp: FighterInput = _input
	var torso: RigidBody3D = parts["torso"]
	var tb: Basis = torso.global_transform.basis
	var up: Vector3 = Vector3.UP
	var chest: Vector3 = torso.global_position + up * 0.1
	var origin: Vector3 = chest + fwd * _t("guard_forward") - up * 0.05
	var reach: float = (FighterRig.UPPER_ARM_LEN + FighterRig.FOREARM_LEN) * 0.97
	var half: bool = grip() == "half"
	var thrust: float = 1.0 if inp.has(THRUST) else (_t("swing_reach") if inp.has(SWING) else 0.0)
	var gp: Dictionary = {"w": _t("guard_width"), "h": _t("guard_height"), "fwd": _t("guard_forward"),
		"thrust": _t("thrust_reach") * (0.6 if half else 1.0), "min_fwd": 0.2}
	var shoulder_r: Vector3 = torso.global_transform * ((FighterRig.part("upper_arm_r")["pivot"] as Vector3) - (FighterRig.part("torso")["center"] as Vector3))
	var shoulder_l: Vector3 = torso.global_transform * ((FighterRig.part("upper_arm_l")["pivot"] as Vector3) - (FighterRig.part("torso")["center"] as Vector3))
	var aim: Vector2 = inp.aim()
	if half:
		aim *= 0.6
	# The hand goal (kept relative to the pelvis) chases the aim at a limited speed: slow in guard, fast while
	# SWING or THRUST is held, so only a committed swing whips the weapon.
	var pp: Vector3 = (parts["pelvis"] as RigidBody3D).global_position
	var raw_r: Vector3 = FighterMath.guard_target(aim, thrust, origin, right, up, fwd, shoulder_r, reach, gp)
	var rate_r: float = _t("swing_hand_speed") if inp.has(SWING) or inp.has(THRUST) else _t("guard_hand_speed")
	_goal_r = _goal_r.move_toward(raw_r - pp, rate_r * _delta)
	_hand_target = pp + _goal_r
	if not active:
		_hand_target = _hand_pos("r")
		_goal_r = _hand_target - pp

	# Left hand target.
	var lt: Vector3
	var main_w: Weapon = weapon
	if half and main_w != null:
		lt = main_w.global_transform * Vector3(0, main_w.tip_local.y * 0.45, 0)
	elif offhand != null:
		var raise: float = 1.0 if inp.has(OFFHAND) else 0.0
		lt = chest + fwd * lerpf(0.3, 0.42, raise) - right * lerpf(0.22, 0.05, raise) + up * lerpf(-0.3, 0.05, raise)
	elif main_w != null and bool(main_w.def.get("two_handed", false)):
		lt = main_w.global_transform * Vector3(0, -0.13, 0)
	elif inp.has(OFFHAND):
		lt = chest + fwd * 0.38 - right * 0.08 + up * 0.15
	else:
		lt = chest + fwd * 0.3 - right * 0.22 - up * 0.2
	var on_weapon: bool = (half or bool(main_w.def.get("two_handed", false))) if main_w != null else false
	if on_weapon or not active:
		_goal_l = (lt if active else _hand_pos("l")) - pp
	else:
		_goal_l = _goal_l.move_toward(lt - pp, _t("offhand_hand_speed") * _delta)
		lt = pp + _goal_l
	_hand_target_l = lt

	var used: float = 0.0
	if active:
		var arm_hp_r: float = minf(_hp("upper_arm_r"), _hp("forearm_r"))
		var cap_r: float = _t("arm_force") * s * FighterMath.limb_factor(arm_hp_r, _t("limb_floor"))
		cap_r *= 1.0 if inp.has(SWING) or inp.has(THRUST) else _t("guard_force_frac")
		if half and inp.has(THRUST):
			cap_r *= _t("half_sword_thrust")
		used = _hand_force("r", _hand_target, cap_r, shoulder_r)
		var arm_hp_l: float = minf(_hp("upper_arm_l"), _hp("forearm_l"))
		var cap_l: float = _t("arm_force") * _t("offhand_force_frac") * s * FighterMath.limb_factor(arm_hp_l, _t("limb_floor"))
		_hand_force("l", lt, cap_l, shoulder_l)
	for h: String in ["r", "l"]:
		var shoulder: Vector3 = shoulder_r if h == "r" else shoulder_l
		var tgt: Vector3 = _hand_target if h == "r" else lt
		var sgn: float = 1.0 if h == "r" else -1.0
		var hint: Vector3 = -up + right * (0.5 * sgn) + fwd * -0.2
		var ik: Array[Vector3] = FighterMath.arm_ik(shoulder, tgt, FighterRig.UPPER_ARM_LEN, FighterRig.FOREARM_LEN, hint)
		if not active:
			continue
		var ub: Basis = FighterMath.bone_basis(ik[0] - shoulder)
		var fb: Basis = FighterMath.bone_basis(ik[1] - ik[0])
		targets["upper_arm_" + h] = tb.inverse() * ub
		targets["forearm_" + h] = ub.inverse() * fb
	_wrist(weapon, "r", fwd, right, chest, half, s)
	_wrist(offhand, "l", fwd, right, chest, false, s)
	return used


## PD force pulling hand `h` toward `target`, reaction on the torso at the shoulder. Returns force used / cap.
func _hand_force(h: String, target: Vector3, cap: float, shoulder: Vector3) -> float:
	var fn: String = "forearm_" + h
	if _is_cut_off(fn) or cap <= 0.0:
		return 0.0
	var fore: RigidBody3D = parts[fn]
	var hp: Vector3 = _hand_pos(h)
	var rel_v: Vector3 = _hand_vel(h) - (parts["pelvis"] as RigidBody3D).linear_velocity
	var f: Vector3 = FighterMath.pd_force(target - hp, rel_v, _t("arm_drive_mass"), _t("arm_freq"), _t("arm_damping"), cap)
	var carried: float = fore.mass + (parts["upper_arm_" + h] as RigidBody3D).mass * 0.5
	for w: Weapon in [weapon if h == "r" else offhand, fist_r if h == "r" else fist_l]:
		if w != null and w.holder == self:
			carried += w.mass
	f += Vector3.UP * carried * _t("gravity")
	f = f.limit_length(cap)
	fore.apply_force(f, hp - fore.global_position)
	var torso: RigidBody3D = parts["torso"]
	torso.apply_force(-f * _t("arm_reaction"), shoulder - torso.global_position)
	return f.length() / cap


## Wrist torque turning the held weapon toward its stance orientation.
func _wrist(w: Weapon, h: String, fwd: Vector3, right: Vector3, chest: Vector3, half: bool, s: float) -> void:
	if w == null or w.holder != self or _is_cut_off("forearm_" + h) or not (_state == "standing" or _state == "stumbling" or _state == "getting_up"):
		return
	var fore: RigidBody3D = parts["forearm_" + h]
	var target: Basis
	if w.shape_kind == "shield":
		var zf: Vector3 = fwd
		var yu: Vector3 = (Vector3.UP - zf * Vector3.UP.dot(zf)).normalized()
		target = Basis(yu.cross(zf), yu, zf)
	else:
		var hp: Vector3 = _hand_pos(h)
		var pivot: Vector3 = chest - fwd * _t("blade_pivot_back")
		var out: Vector3 = hp - pivot
		var up_w: float = _t("blade_up_swing") if _input.has(SWING) else _t("blade_up_guard")
		var blade: Vector3 = (out.normalized() * (1.0 if half else 0.8) + Vector3.UP * (0.15 if half else up_w)).normalized()
		if half:
			blade = (blade + fwd * 1.5).normalized()
		# In a swing the wrist throws the tip ahead along the hand's motion, which is what makes the tip whip.
		var hv_lead: Vector3 = _hand_vel(h) - (parts["pelvis"] as RigidBody3D).linear_velocity
		blade = (blade + (hv_lead - blade * hv_lead.dot(blade)) * _t("wrist_lead")).normalized()
		# Keep the target within what the wrist can reach from the forearm's natural grip direction.
		var natural: Vector3 = (fore.global_transform.basis * _grip_basis(w)).y.normalized()
		var ang: float = natural.angle_to(blade)
		var reach: float = _t("wrist_reach")
		if ang > reach:
			blade = natural.slerp(blade, reach / ang).normalized()
		var hv: Vector3 = _hand_vel(h)
		var edge: Vector3 = hv - blade * hv.dot(blade)
		if edge.length() < 1.0:
			edge = fwd - blade * fwd.dot(blade)
		if edge.length_squared() < 0.0001:
			edge = right
		edge = edge.normalized()
		target = Basis(edge, blade, edge.cross(blade))
	var err: Vector3 = FighterMath.rotation_error(w.global_transform.basis, target)
	# Pointing the weapon (swing axes, inertia about the grip) and rolling it about its own long axis (tiny
	# inertia) are driven separately: one inertia for both makes the roll damping blow up.
	var axis: Vector3 = w.global_transform.basis.y.normalized()
	var rel_w: Vector3 = w.angular_velocity - (parts["torso"] as RigidBody3D).angular_velocity
	var err_roll: Vector3 = axis * err.dot(axis)
	var w_roll: Vector3 = axis * rel_w.dot(axis)
	var arm_hp: float = minf(_hp("forearm_" + h), _hp("upper_arm_" + h))
	var cap: float = _t("wrist_torque") * s * FighterMath.limb_factor(arm_hp, _t("limb_floor"))
	var freq: float = _t("wrist_freq")
	var tq: Vector3 = FighterMath.pd_torque(err - err_roll, rel_w - w_roll, w.inertia_grip, freq, 0.9, cap)
	tq += FighterMath.pd_torque(err_roll * _t("wrist_roll"), w_roll, w.inertia_roll, freq, 1.0, cap * 0.3)
	# The whole arm turns the weapon, not the wrist alone: the reaction goes to the torso (partly), never the
	# forearm, which would just spin the other way.
	w.apply_torque(tq)
	(parts["torso"] as RigidBody3D).apply_torque(-tq * _t("arm_reaction"))


# --- weapons: grab, drop -----------------------------------------------------------------------------------------

func _handle_grab(inp: FighterInput) -> void:
	# Very hurt or severed weapon arm drops what it holds.
	for h: String in ["r", "l"]:
		var w: Weapon = weapon if h == "r" else offhand
		if w != null and w.holder == self:
			var hpf: float = minf(_hp("forearm_" + h), _hp("upper_arm_" + h))
			if _is_cut_off("forearm_" + h) or hpf < _t("weapon_drop_hp") or _state == "ko" or _state == "dead":
				_release(w)
	var want: bool = inp.has(GRAB)
	if want and not _grab_latch and weapon == null and not _is_cut_off("forearm_r") and _state == "standing":
		var hand: Vector3 = _hand_pos("r")
		var best: Weapon = null
		var best_d: float = _t("grab_radius")
		for n: Node in get_tree().get_nodes_in_group(Weapon.PROP_GROUP):
			var pw: Weapon = n as Weapon
			if pw == null or pw.is_fist or pw.lodged_in != null:
				continue
			var d: float = pw.global_position.distance_to(hand)
			if d < best_d:
				best_d = d
				best = pw
		if best != null:
			_attach(best, "r" if best.shape_kind != "shield" or offhand != null else "l")
			_compute_inertia()
	_grab_latch = want


## Releases the right-hand weapon (it becomes a prop). Public for scripted tests.
func drop_weapon() -> void:
	if weapon != null:
		_release(weapon)


# --- contacts and damage ----------------------------------------------------------------------------------------

func _record_velocities() -> void:
	var d: Dictionary = {}
	for n: String in FighterRig.names():
		var b: RigidBody3D = parts[n]
		d[n] = [b.linear_velocity, b.angular_velocity, b.global_position]
	for w: Weapon in _weapons:
		d[w.name] = [w.linear_velocity, w.angular_velocity, w.com_position()]
	var f: int = _frame()
	if f != _vel_cur_frame:
		_vel_prev = _vel_cur
		_vel_cur_frame = f
	_vel_cur = d


## Velocity of body `key` at point `p` just before the last physics step.
func pre_step_velocity(key: String, body: RigidBody3D, p: Vector3) -> Vector3:
	var f: int = _frame()
	var src: Dictionary = _vel_cur if _vel_cur_frame < f else _vel_prev
	if src.has(key):
		var e: Array = src[key]
		return (e[0] as Vector3) + (e[1] as Vector3).cross(p - (e[2] as Vector3))
	if body is Weapon:
		return (body as Weapon).point_velocity(p)
	return body.linear_velocity + body.angular_velocity.cross(p - body.global_position)


func _process_contacts() -> void:
	var tick_window: int = maxi(int(round(_t("hit_debounce") * 60.0)), 1)
	for w: Weapon in [fist_r, fist_l, weapon, offhand]:
		if w == null or w.holder != self:
			continue
		var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(w.get_rid())
		if st == null:
			continue
		# Jolt reports contacts in a thread-dependent order and the debounce keeps the first contact per key, so
		# visit them in a stable order (collider name, then point) or same-seed fights diverge.
		var order: Array = []
		for i: int in range(st.get_contact_count()):
			var o: Object = st.get_contact_collider_object(i)
			var nm: String = str((o as Node).name) if o is Node else ""
			var lp: Vector3 = st.get_contact_local_position(i)
			order.append([nm, lp.x, lp.y, lp.z, i])
		order.sort()
		for entry: Array in order:
			var i: int = int(entry[4])
			var obj: Object = st.get_contact_collider_object(i)
			if not obj is RigidBody3D:
				continue
			var body: RigidBody3D = obj as RigidBody3D
			var target: Fighter = null
			var part: String = ""
			var on_weapon: bool = false
			if body is Weapon:
				var ow: Weapon = body as Weapon
				if ow.holder == null or ow.holder == self:
					continue
				target = ow.holder as Fighter
				part = "forearm_" + ow.hand
				if ow.is_fist:
					# A fist is the hand: hitting it hits the forearm.
					body = target.parts[part]
				else:
					on_weapon = true
			elif body.has_meta("fighter"):
				target = body.get_meta("fighter") as Fighter
				part = str(body.get_meta("part"))
			if target == null or target._severed.has(part) or target._is_cut_off(part):
				continue
			var p: Vector3 = st.get_contact_local_position(i)
			var key: String = "%s|%d|%s" % [w.name, target.side, body.name]
			var v_w: Vector3 = pre_step_velocity(w.name, w, p)
			var v_t: Vector3 = target.pre_step_velocity(body.name, body, p)
			var rel: Vector3 = v_w - v_t
			# Weapon on weapon: only the faster of the two strikes (the other side's own pass handles it), so a
			# fast blade meeting a still fist or guard is not counted as the still one hitting the blade.
			if body is Weapon and v_w.length_squared() < v_t.length_squared():
				continue
			var last: int = int(_debounce.get(key, -100000))
			if _tick - last <= tick_window:
				_debounce[key] = _tick
				continue
			var min_speed: float = _t("damage_min_speed")
			if target == self:
				min_speed = maxf(min_speed, _t("self_hit_min_speed"))
			if rel.length() < min_speed:
				continue
			_debounce[key] = _tick
			var n_raw: Vector3 = st.get_contact_local_normal(i)
			var ctr: Vector3 = body.global_position
			var nrm: Vector3 = n_raw.normalized() if n_raw.length_squared() > 0.0001 else rel.normalized()
			if nrm.dot(ctr - p) < 0.0:
				nrm = -nrm
			_resolve_hit(w, target, body, part, p, nrm, rel, on_weapon)
	# Forget pairs not touched for a while.
	var stale: Array = []
	for k: Variant in _debounce:
		if _tick - int(_debounce[k]) > tick_window * 4:
			stale.append(k)
	for k: Variant in stale:
		_debounce.erase(k)


func _resolve_hit(w: Weapon, target: Fighter, body: RigidBody3D, part: String, p: Vector3, nrm: Vector3, rel: Vector3, on_weapon: bool) -> void:
	var inv: Transform3D = w.global_transform.affine_inverse()
	var local_p: Vector3 = inv * p
	var rel_local: Vector3 = inv.basis * rel
	var cls: Dictionary = FighterMath.classify_contact(w.def, local_p.y, rel_local)
	var fore: RigidBody3D = parts["forearm_" + w.hand] if w.hand != "" else null
	var arm_mass: float = 0.0
	if fore != null:
		arm_mass = fore.mass * 0.6 + (parts["upper_arm_" + w.hand] as RigidBody3D).mass * 0.3
	var wdef_mass: float = float(w.def.get("mass", w.mass))
	var r: float = (local_p - w.com_local).length()
	var hit_in: Dictionary = {
		"part": part, "weapon_id": w.weapon_id, "contact": cls["contact"], "rel_vel": rel, "normal": nrm,
		"edge_alignment": cls["edge_alignment"],
		"effective_mass": FighterMath.effective_mass(wdef_mass, w.inertia_com, r, arm_mass),
		"armor_ids": target.armor_on(part), "armor_wear": target._armor_wear.duplicate(),
		"part_hp_frac": target._hp(part), "blood_frac": target.health.blood_frac() if target.health != null else 1.0,
		"hit_on_weapon": on_weapon,
	}
	var res: Dictionary = DamageModel.resolve(hit_in, _tun)
	var ev: Dictionary = hit_in.duplicate()
	ev.merge(res, true)
	ev["attacker"] = side
	ev["target"] = target.side
	ev["point"] = p
	target._take_hit(ev, body, w, self)


## Armor ids currently worn over part `n`.
func armor_on(n: String) -> Array:
	var out: Array = []
	for aid: String in _armor:
		if (CombatData.armor(aid).get("covers", []) as Array).has(n):
			out.append(aid)
	return out


func _add_contact(ev: Dictionary) -> void:
	var f: int = _frame()
	if f != _contacts_frame:
		_contacts = []
		_contacts_frame = f
	_contacts.append(ev)


func _take_hit(ev: Dictionary, body: RigidBody3D, w: Weapon, attacker: Fighter) -> void:
	var part: String = ev["part"]
	var p: Vector3 = ev["point"]
	var nrm: Vector3 = ev["normal"]
	var kb: Vector3 = (ev.get("knockback", Vector3.ZERO) as Vector3) * _t("knockback_scale")
	if kb.length_squared() > 0.0:
		body.apply_impulse(kb, p - body.global_position)
	_add_contact(ev)
	if attacker != self:
		attacker._add_contact(ev)
	var wear: Dictionary = ev.get("armor_wear", {})
	for aid: Variant in wear:
		if _armor_wear.has(aid):
			_armor_wear[aid] = float(wear[aid])
	# Disarm: the hand holding the struck weapon (or forearm) checks its grip.
	var dis: float = float(ev.get("disarm_impulse", 0.0))
	if dis > 0.0:
		var h: String = "r" if part == "forearm_r" else ("l" if part == "forearm_l" else "")
		var held: Weapon = weapon if h == "r" else (offhand if h == "l" else null)
		if held != null and held.holder == self:
			var two: bool = held == weapon and (bool(held.def.get("two_handed", false)) or grip() == "half")
			if not DamageModel.grip_holds(dis, minf(_hp("forearm_" + h), _hp("upper_arm_" + h)), health.stamina, two, _tun):
				_release(held)
				ev["disarmed"] = true
	if bool(ev.get("hit_on_weapon", false)):
		hit.emit(ev)
		return
	_stagger = minf(_stagger + float(ev.get("stagger", 0.0)), 1.5)
	if bool(ev.get("dislodge", false)):
		_dislodge(str(ev.get("dislodged_id", "")), part, kb)
	var gore_events: Array = health.apply(ev, part) if health != null else []
	hit.emit(ev)
	if str(ev.get("finisher", "")) == "run_through" and w != null and not w.is_fist and w.holder == attacker:
		_lodge(w, body, attacker)
	for g: Variant in gore_events:
		var gd: Dictionary = (g as Dictionary).duplicate()
		gd["point"] = p
		gd["normal"] = nrm
		var kind: String = str(gd.get("kind", ""))
		if kind == "sever" or kind == "behead":
			_sever(str(gd.get("part", part)))
		gore.emit(gd)
	if health != null and health.dead:
		_die()


## Detaches part `n` (and everything below it) from the body.
func _sever(n: String) -> void:
	if _severed.has(n) or n == "pelvis" or n == "torso":
		return
	_severed.append(n)
	_disconnect_joint(n)
	if health != null and not health.severed.has(n):
		health.severed.append(n)
	for h: String in ["r", "l"]:
		if _is_cut_off("forearm_" + h):
			var w: Weapon = weapon if h == "r" else offhand
			if w != null:
				_release(w)
	if n == "head":
		_die()


## The struck weapon stays stuck in the body (run through): it is jointed to the hit part and leaves the hand.
func _lodge(w: Weapon, body: RigidBody3D, attacker: Fighter) -> void:
	attacker._release(w)
	var j_xf: Transform3D = w.global_transform
	w.detach()
	w.remove_from_group(Weapon.PROP_GROUP)
	w.grip_joint = Generic6DOFJoint3D.new()
	w.grip_joint.name = "Grip"
	w.add_child(w.grip_joint)
	w.grip_joint.top_level = true
	w.grip_joint.global_transform = j_xf
	w.grip_joint.node_a = w.grip_joint.get_path_to(body)
	w.grip_joint.node_b = w.grip_joint.get_path_to(w)
	w.lodged_in = body
	_exclude(w, body)


## Armor piece `aid` tears off: hidden on the body, spawned as a free prop near the hit part, no longer worn.
func _dislodge(aid: String, part: String, kb: Vector3) -> void:
	if aid == "" or not _armor.has(aid):
		return
	_armor.erase(aid)
	var meshes: Array = _armor_meshes.get(aid, [])
	for m: Variant in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		if mi.get_parent().get_parent() == parts.get(part):
			var prop := RigidBody3D.new()
			prop.name = "ArmorProp%d_%d" % [side, _prop_serial]
			_prop_serial += 1
			prop.mass = maxf(float(CombatData.armor(aid).get("mass", 1.0)) / maxf(float(meshes.size()), 1.0), 0.2)
			prop.collision_layer = Weapon.LAYER_WEAPONS
			prop.collision_mask = 1
			prop.top_level = true
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = mi.get_aabb().size
			cs.shape = bs
			prop.add_child(cs)
			var copy := MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.material_override = mi.material_override
			prop.add_child(copy)
			add_child(prop)
			prop.global_transform = mi.global_transform
			var src: RigidBody3D = parts[part]
			prop.linear_velocity = src.linear_velocity + kb.normalized() * 3.0 + Vector3.UP * 2.0
			prop.add_to_group("armor_props")
		mi.visible = false


# --- snapshot / hash / debug -------------------------------------------------------------------------------------

## Everything needed to resume this fighter exactly. Taking a snapshot also re-creates the fighter's joints (and
## skips the next tick's contact pass), the same normalisation restore() does, so the engine's warm-start state is
## identical on both sides and a restore followed by the same inputs replays the run.
func snapshot() -> Dictionary:
	_normalize_engine_state()
	var bodies: Dictionary = {}
	for n: String in FighterRig.names():
		var b: RigidBody3D = parts[n]
		bodies[n] = [b.global_transform, b.linear_velocity, b.angular_velocity]
	var ws: Array = []
	for w: Weapon in _weapons:
		var hs: int = -1
		if w.holder != null:
			hs = (w.holder as Fighter).side
		ws.append([w.name, w.global_transform, w.linear_velocity, w.angular_velocity, hs, w.hand])
	return {
		"tick": _tick, "state": _state, "state_t": _state_t, "yaw": _yaw, "phase": _phase, "stagger": _stagger,
		"severed": Array(_severed), "armor": _armor.duplicate(), "armor_wear": _armor_wear.duplicate(),
		"debounce": _debounce.duplicate(), "died": _died_emitted, "exertion": _exertion, "grab_latch": _grab_latch,
		"input": _input.to_array(), "bodies": bodies, "weapons": ws, "anchor": _anchor, "anchor_set": _anchor_set,
		"goal_r": _goal_r, "goal_l": _goal_l,
		"weapon": weapon.name if weapon != null else "", "offhand": offhand.name if offhand != null else "",
		"health": health.to_dict() if health != null else {},
	}


func restore(d: Dictionary) -> void:
	_tick = int(d.get("tick", 0))
	_state = str(d.get("state", "standing"))
	_state_t = float(d.get("state_t", 0.0))
	_yaw = float(d.get("yaw", 0.0))
	_phase = float(d.get("phase", 0.0))
	_stagger = float(d.get("stagger", 0.0))
	_died_emitted = bool(d.get("died", false))
	_exertion = float(d.get("exertion", 0.0))
	_grab_latch = bool(d.get("grab_latch", false))
	_anchor = d.get("anchor", Vector3.ZERO)
	_anchor_set = bool(d.get("anchor_set", false))
	_goal_r = d.get("goal_r", Vector3.ZERO)
	_goal_l = d.get("goal_l", Vector3.ZERO)
	_input = FighterInput.from_array(d.get("input", []))
	_debounce = (d.get("debounce", {}) as Dictionary).duplicate()
	if health != null:
		health.from_dict(d.get("health", {}))
	# Body poses first (joints are rebuilt from the rest frames, so order does not matter for them).
	var bodies: Dictionary = d.get("bodies", {})
	for n: Variant in bodies:
		var b: RigidBody3D = parts[str(n)]
		var e: Array = bodies[n]
		b.global_transform = e[0]
		b.linear_velocity = e[1]
		b.angular_velocity = e[2]
	var want_sev := PackedStringArray()
	for s: Variant in d.get("severed", []):
		want_sev.append(str(s))
	for n: String in _severed.duplicate():
		if not want_sev.has(n):
			_severed.remove_at(_severed.find(n))
			_connect_joint(n)
	for n: String in want_sev:
		if not _severed.has(n):
			_severed.append(n)
			_disconnect_joint(n)
	# Armor.
	var want_armor: Array = d.get("armor", [])
	_armor.clear()
	for aid: Variant in want_armor:
		_armor.append(str(aid))
	for aid: Variant in _armor_meshes:
		for m: Variant in _armor_meshes[aid]:
			if m is MeshInstance3D:
				(m as MeshInstance3D).visible = _armor.has(str(aid))
	_armor_wear = (d.get("armor_wear", {}) as Dictionary).duplicate()
	# Weapons this fighter created: pose, then who holds them.
	weapon = null
	offhand = null
	for e: Variant in d.get("weapons", []):
		var arr: Array = e
		var w: Weapon = _find_weapon(str(arr[0]))
		if w == null:
			continue
		if w.holder != null:
			(w.holder as Fighter)._release(w)
		elif w.lodged_in != null:
			w.detach()
		w.global_transform = arr[1]
		w.linear_velocity = arr[2]
		w.angular_velocity = arr[3]
		var hs: int = int(arr[4])
		var who: Fighter = self if hs == side else (opponent if opponent != null and hs == opponent.side else null)
		if who != null:
			who._reattach(w, str(arr[5]))
	var wn: String = str(d.get("weapon", ""))
	var on: String = str(d.get("offhand", ""))
	weapon = _find_weapon(wn) if wn != "" else null
	offhand = _find_weapon(on) if on != "" else null
	_compute_inertia()
	_vel_cur = {}
	_vel_prev = {}
	_vel_cur_frame = -1
	_record_velocities()
	_normalize_engine_state()


## Re-creates every body joint and weapon grip from the current poses (fresh solver state) and skips the next
## contact pass (the engine's contact list belongs to the previous step).
func _normalize_engine_state() -> void:
	var group: Array[Fighter] = [self]
	if opponent != null and is_instance_valid(opponent) and opponent._built and opponent.is_inside_tree():
		group.append(opponent)
		if opponent.side < side:
			group.reverse()
	Fighter.normalize_group(group)


## Brings the engine state of these fighters (sorted by side) to a canonical form that depends only on their
## poses: every joint and grip is removed, every body leaves the space and comes back (dropping cached contacts
## and warm starts, twice so the engine's body id order returns to the same order), poses are written back as
## read, then joints and grips are re-created in a fixed order. snapshot() and restore() both end with this.
static func normalize_group(group: Array[Fighter]) -> void:
	var held: Array = []
	var bodies: Array[RigidBody3D] = []
	for f: Fighter in group:
		for pd: Dictionary in FighterRig.PARTS:
			f._disconnect_joint(str(pd["name"]))
		for w: Weapon in [f.fist_r, f.fist_l, f.weapon, f.offhand]:
			if w != null and w.holder == f and w.lodged_in == null:
				held.append([f, w, w.hand])
				w.detach()
		for n: String in FighterRig.names():
			bodies.append(f.parts[n])
		for w: Weapon in f._weapons:
			bodies.append(w)
	if group.is_empty():
		return
	var space: RID = group[0].get_world_3d().space
	for _pass: int in range(2):
		for b: RigidBody3D in bodies:
			PhysicsServer3D.body_set_space(b.get_rid(), RID())
		for b: RigidBody3D in bodies:
			PhysicsServer3D.body_set_space(b.get_rid(), space)
	# Poses snapped to a grid survive the engine's write/read round trip unchanged, so normalising again after a
	# restore lands on exactly the state the snapshot normalised to.
	for b: RigidBody3D in bodies:
		var xf: Transform3D = FighterMath.quantize_transform(b.global_transform, POSE_QUANTUM)
		var lv: Vector3 = b.linear_velocity
		var av: Vector3 = b.angular_velocity
		b.global_transform = xf
		b.linear_velocity = lv
		b.angular_velocity = av
	for f: Fighter in group:
		for pd: Dictionary in FighterRig.PARTS:
			var n: String = pd["name"]
			if pd["parent"] != "" and not f._severed.has(n):
				f._connect_joint(n)
	for e: Array in held:
		(e[0] as Fighter)._reattach(e[1] as Weapon, str(e[2]))
	for f: Fighter in group:
		f._skip_contacts = 1


func _find_weapon(n: String) -> Weapon:
	for w: Weapon in _weapons:
		if w.name == n:
			return w
	if opponent != null:
		for w: Weapon in opponent._weapons:
			if w.name == n:
				return w
	return null


## Re-joints `w` to hand `h` keeping its current (restored) transform as the relative pose.
func _reattach(w: Weapon, h: String) -> void:
	var fore: RigidBody3D = parts["forearm_" + h]
	var keep: Transform3D = w.global_transform
	var lv: Vector3 = w.linear_velocity
	var av: Vector3 = w.angular_velocity
	var grip: Transform3D = fore.global_transform * Transform3D(_grip_basis(w), FighterRig.HAND_LOCAL)
	w.attach(fore, grip, 0.02 if w.is_fist else _t("wrist_limit"))
	w.holder = self
	w.hand = h
	w.global_transform = keep
	w.linear_velocity = lv
	w.angular_velocity = av
	if not w.is_fist:
		if h == "r":
			weapon = w
		else:
			offhand = w
	_set_exceptions(w)


func state_hash() -> int:
	var a := PackedInt64Array()
	for n: String in FighterRig.names():
		var b: RigidBody3D = parts[n]
		var o: Vector3 = b.global_position
		var v: Vector3 = b.linear_velocity
		a.append_array([roundi(o.x * 1000.0), roundi(o.y * 1000.0), roundi(o.z * 1000.0),
			roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0)])
	for w: Weapon in _weapons:
		var t: Vector3 = w.tip_position()
		a.append_array([roundi(t.x * 1000.0), roundi(t.y * 1000.0), roundi(t.z * 1000.0)])
	a.append(_tick)
	a.append(["standing", "stumbling", "down", "getting_up", "ko", "dead"].find(_state))
	a.append(_severed.size())
	if health != null:
		a.append(roundi(health.blood * 1000.0))
		a.append(roundi(health.stamina * 1000.0))
		a.append(roundi(health.consciousness * 1000.0))
	return hash(a)


func debug_frame() -> Dictionary:
	var pelvis: RigidBody3D = parts.get("pelvis")
	var pd: Dictionary = {}
	for n: String in FighterRig.names():
		pd[n] = {"pos": (parts[n] as RigidBody3D).global_position, "hp": health.hp(n) if health != null else 0.0,
			"severed": _severed.has(n) or (health != null and health.is_severed(n))}
	var w: Weapon = weapon if weapon != null else fist_r
	var tip: Vector3 = w.tip_position() if w != null else Vector3.ZERO
	var tip_v: float = w.point_velocity(tip).length() if w != null else 0.0
	return {
		"tick": _tick, "side": side, "pelvis_pos": pelvis.global_position if pelvis else Vector3.ZERO,
		"pelvis_vel": pelvis.linear_velocity if pelvis else Vector3.ZERO, "facing_yaw": _yaw, "balance": balance(),
		"stamina": health.stamina if health != null else 1.0,
		"consciousness": health.consciousness if health != null else 1.0,
		"hand_target": _hand_target, "hand_pos": _hand_pos("r"), "tip_pos": tip, "tip_speed": tip_v,
		"weapon_id": weapon.weapon_id if weapon != null else "fists", "grip": grip(), "parts": pd,
		"contacts": _contacts.duplicate() if _contacts_frame == _frame() else [], "state": _state,
		"blood_frac": health.blood_frac() if health != null else 1.0, "armor": worn_armor(),
		"offhand_id": offhand.weapon_id if offhand != null else "", "props": props(),
	}


## {part: armor_id} for every worn piece (the first listed piece when two cover the same part).
func worn_armor() -> Dictionary:
	var out: Dictionary = {}
	for aid: String in _armor:
		for pn: Variant in CombatData.armor(aid).get("covers", []):
			if not out.has(str(pn)):
				out[str(pn)] = aid
	return out


## Free weapon props lying around: [{"pos": Vector3, "weapon_id": String}].
func props() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for n: Node in get_tree().get_nodes_in_group(Weapon.PROP_GROUP):
		var w: Weapon = n as Weapon
		if w != null and w.holder == null and w.lodged_in == null:
			out.append({"pos": w.global_position, "weapon_id": w.weapon_id})
	return out
