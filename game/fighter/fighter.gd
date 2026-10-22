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
## A shove, kick or grab: {"kind": "shove"|"kick"|"grab"|"hold"|"break"|"slip", "attacker": side, "target": side,
## "point": Vector3, "landed": bool, "blocked": bool (a kick met a shield or weapon)}. Kicks that connect also emit
## `hit` like any blow.
signal close(event: Dictionary)

const LAYER_BODIES: int = 2
## Quaternion grid for normalised poses (snapshot/restore).
const POSE_QUANTUM: float = 0.00001
const MASK_ALL: int = 7
## Head collider profile, part frame: rings of [y, half width, front z, back z] measured from the Houdini head art
## (assets/body/head.glb and head_b.glb, the larger of the two; the neck stub below y -0.10 sits in the torso). The old
## 0.11 m sphere was 2.3 cm wider per side than the drawn head, so blows that visibly missed still landed.
const HEAD_PROFILE: Array = [
	[-0.10, 0.060, -0.100, 0.062], [-0.07, 0.066, -0.099, 0.074], [-0.04, 0.086, -0.114, 0.093],
	[-0.01, 0.087, -0.104, 0.102], [0.02, 0.084, -0.101, 0.106], [0.05, 0.082, -0.095, 0.100],
	[0.08, 0.076, -0.091, 0.099], [0.10, 0.065, -0.075, 0.081], [0.118, 0.046, -0.043, 0.022],
]
const HEAD_RING_POINTS: int = 12

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
	"foot_lift": 0.13, "pelvis_inertia": 2.0, "torso_inertia": 2.5, "balance_inertia": 3.0, "leg_reaction": 0.25, "pd_margin": 0.5, "self_hit_min_speed": 6.0, "hold_freq": 2.0, "blade_pivot_back": 0.45, "swing_reach": 0.35, "guard_hand_speed": 2.5, "swing_hand_speed": 30.0, "offhand_hand_speed": 5.0, "hit_debounce": 0.25, "grab_radius": 0.6, "knockback_scale": 1.0,
	"arm_exertion": 0.7,
	"reach_height": 0.5, "reach_pitch": 0.55, "reach_bend": 0.65, "reach_time": 0.35, "reach_hold": 0.4,
	"reach_scan": 1.1, "reach_hand_lift": 0.05, "reach_hand_speed": 3.0, "reach_foot_fwd": 0.12,
}

const SWING: int = 1
const OFFHAND: int = 2
const HALF_SWORD: int = 4
const THRUST: int = 8
const SPRINT: int = 16
const CROUCH: int = 32
const GRAB: int = 64
const TURN_LOCK: int = 128
const ROLL: int = 256
const SHOVE: int = 512
const KICK: int = 1024
const CLINCH: int = 2048
const KICK_LEG: int = 0  ## the lead (left) leg kicks; gait index 0 is the left foot

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
var _gait: GaitLogic = GaitLogic.new()
var _roll: RollLogic = RollLogic.new()
var _close: CloseCombat = CloseCombat.new()
var _hold_excl: Array[PhysicsBody3D] = []  ## foe bodies the holding hand has collision exceptions with
var _hold_joint: Generic6DOFJoint3D = null  ## the hold: the holding forearm jointed to the held part
var _leg_prev: Dictionary = {}  ## last leg joint targets (rate feed-forward)
var _foot_prev: Array[Vector3] = [Vector3.INF, Vector3.INF]  ## last foot targets (their velocity)
var _stagger: float = 0.0
var _tick: int = 0
var _severed: PackedStringArray = PackedStringArray()
var _armor: Array[String] = []
var _armor_wear: Dictionary = {}
var _armor_meshes: Dictionary = {}
## Seed for the cosmetic skin tone and head pick (the match sets it before setup; visuals only).
var look_seed: int = 0
var _art: FighterArt = null
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
## Reaching down for a prop on the ground (CROUCH + GRAB, empty right hand): 0..1 blend of the kneel-and-bow pose,
## the seconds the last GRAB press keeps it wanted, and the world point the right hand goes for.
var _reach: float = 0.0
var _reach_hold: float = 0.0
var _reach_point: Vector3 = Vector3.ZERO
var _prop_serial: int = 0
var _anchor: Vector3 = Vector3.ZERO
var _anchor_set: bool = false
## Cumulative weapon losses and pickups for the match stats (debug_frame "weapon_log").
## "rearms_after_disarm" counts pickups made while a weapon knocked out of hand was still not replaced.
var _wlog: Dictionary = {"disarms": 0, "arm_drops": 0, "rearms": 0, "rearms_after_disarm": 0}
var _unreplaced_disarms: int = 0
## Perf sections (tests/perf only): microseconds summed over all fighters while `prof_on`.
static var prof_on: bool = false
static var prof: Dictionary = {}
## Build cut caps ahead, one per frame (see `_process`); tests/perf turns it off for before/after runs.
static var prebuild_caps: bool = true


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


## Presentation only: builds one cut cap ahead per frame (FighterArt.prebuild_step), so a sever attaches ready caps
## instead of stalling the frame of the blow. Off in headless runs (no one sees the caps; sims stay as fast).
func _process(_delta: float) -> void:
	if _art == null or not prebuild_caps or DisplayServer.get_name() == "headless" or not _art.prebuild_step(parts):
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _art != null:
		_art.free_ready_caps()


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
	_art = FighterArt.new(side, look_seed, OutfitRules.outfit_of(loadout))
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
	_spawn_guard_pose()
	_compute_inertia()
	_hand_target = _hand_pos("r")
	_hand_target_l = _hand_pos("l")
	_goal_r = _hand_target - (parts["pelvis"] as RigidBody3D).global_position
	_goal_l = _hand_target_l - (parts["pelvis"] as RigidBody3D).global_position
	_record_velocities()


## Spawn with the arms already in the idle guard (the pose neutral input drives them to) and the blade already at its
## guard angle, so nothing swings up and shoves the body back during the match intro (a spear backed its holder off
## 0.41 m while the plates showed). Moves each arm and what its hand holds rigidly, so every joint stays satisfied.
func _spawn_guard_pose() -> void:
	var torso: RigidBody3D = parts["torso"]
	var up := Vector3.UP
	var fwd: Vector3 = -global_transform.basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right: Vector3 = fwd.cross(up).normalized()
	var chest: Vector3 = torso.global_position + up * 0.1
	var origin: Vector3 = chest + fwd * _t("guard_forward") - up * 0.05
	var reach: float = (FighterRig.UPPER_ARM_LEN + FighterRig.FOREARM_LEN) * 0.97
	var gp: Dictionary = {"w": _t("guard_width"), "h": _t("guard_height"), "fwd": _t("guard_forward"),
		"thrust": _t("thrust_reach"), "min_fwd": 0.2}
	var shoulder_r: Vector3 = _shoulder_world("r")
	_pose_arm("r", FighterMath.guard_target(Vector2.ZERO, 0.0, origin, right, up, fwd, shoulder_r, reach, gp), fwd, right)
	if weapon != null and weapon.shape_kind != "shield":
		var fore: RigidBody3D = parts["forearm_r"]
		var hp: Vector3 = _hand_pos("r")
		var out: Vector3 = hp - (chest - fwd * _t("blade_pivot_back"))
		var blade: Vector3 = (out.normalized() * 0.8 + up * _t("blade_up_guard")).normalized()
		var natural: Vector3 = (fore.global_transform.basis * _grip_basis(weapon)).y.normalized()
		var ang: float = natural.angle_to(blade)
		if ang > _t("wrist_reach"):
			blade = natural.slerp(blade, _t("wrist_reach") / ang).normalized()
		var edge: Vector3 = fwd - blade * fwd.dot(blade)
		if edge.length_squared() < 0.0001:
			edge = right
		edge = edge.normalized()
		weapon.global_transform = Transform3D(Basis(edge, blade, edge.cross(blade)), weapon.global_position)
	var lt: Vector3 = chest + fwd * 0.3 - right * 0.22 - up * 0.2
	if offhand != null:
		lt = chest + fwd * 0.3 - right * 0.22 - up * 0.3
	elif weapon != null and bool(weapon.def.get("two_handed", false)):
		lt = weapon.global_transform * Vector3(0, -0.13, 0)
	_pose_arm("l", lt, fwd, right)


func _shoulder_world(h: String) -> Vector3:
	var torso: RigidBody3D = parts["torso"]
	return torso.global_transform * ((FighterRig.part("upper_arm_" + h)["pivot"] as Vector3) - (FighterRig.part("torso")["center"] as Vector3))


## Puts arm `h` on its IK solution for a hand at `target` (the bones as the arm drive aims them) and carries whatever
## the hand holds along with the forearm.
func _pose_arm(h: String, target: Vector3, fwd: Vector3, right: Vector3) -> void:
	var sgn: float = 1.0 if h == "r" else -1.0
	var shoulder: Vector3 = _shoulder_world(h)
	var ik: Array[Vector3] = FighterMath.arm_ik(shoulder, target, FighterRig.UPPER_ARM_LEN, FighterRig.FOREARM_LEN,
		-Vector3.UP + right * (0.5 * sgn) + fwd * -0.2)
	# Bones keep their rest roll about the body's yaw (the built rig's), so the elbow and wrist joints start inside
	# their limits whichever way the fighter faces.
	var yb: Basis = Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	var ub: Basis = yb * FighterMath.bone_basis(yb.inverse() * (ik[0] - shoulder))
	var fb: Basis = yb * FighterMath.bone_basis(yb.inverse() * (ik[1] - ik[0]))
	var upper: RigidBody3D = parts["upper_arm_" + h]
	var fore: RigidBody3D = parts["forearm_" + h]
	var ud: Dictionary = FighterRig.part("upper_arm_" + h)
	var fd: Dictionary = FighterRig.part("forearm_" + h)
	var fore_old: Transform3D = fore.global_transform
	upper.global_transform = Transform3D(ub, shoulder + ub * ((ud["center"] as Vector3) - (ud["pivot"] as Vector3)))
	fore.global_transform = Transform3D(fb, ik[0] + fb * ((fd["center"] as Vector3) - (fd["pivot"] as Vector3)))
	var carry: Transform3D = fore.global_transform * fore_old.affine_inverse()
	for w: Weapon in [fist_r, fist_l, weapon, offhand]:
		if w != null and w.holder == self and w.hand == h:
			w.global_transform = carry * w.global_transform


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
			var m2 := SphereMesh.new()
			m2.radius = size.x
			m2.height = size.x * 2.0
			if n == "head":
				# The collider follows the drawn head. Mass properties stay those of the old sphere (same inertia,
				# centre of mass at the part centre), so the joints and drives behave exactly as before.
				var hull := ConvexPolygonShape3D.new()
				hull.points = head_hull_points()
				m2.radius = 0.087
				m2.height = 0.23
				_add_shape(b, hull, m2, Vector3.ZERO, mat)
				b.inertia = Vector3.ONE * 0.4 * b.mass * size.x * size.x
				b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
				b.center_of_mass = Vector3.ZERO
			else:
				var s2 := SphereShape3D.new()
				s2.radius = size.x
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
		# The kicking foot's contacts are read like a weapon's (see _kick_contacts).
		b.contact_monitor = true
		b.max_contacts_reported = 8
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
	if not (loadout.get("look", {}) as Dictionary).has(n):
		_art.dress(b, n)


## Convex hull points of the head collider (part frame): an elliptical ring per HEAD_PROFILE row, the front (-Z) and
## back halves with their own depth.
static func head_hull_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for row: Array in HEAD_PROFILE:
		for k: int in range(HEAD_RING_POINTS):
			var a: float = TAU * float(k) / float(HEAD_RING_POINTS)
			var cz: float = cos(a)
			var depth: float = float(row[3]) if cz > 0.0 else -float(row[2])
			out.append(Vector3(sin(a) * float(row[1]), float(row[0]), cz * depth))
	return out


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
		# A two-handed pole (spear, rake) lies along both arms and its butt runs back past the grip: in round 3/4
		# bot matches the spear butt (0.3 m behind the hand) clipped the holder's own upper arms on most self hits.
		var along_arms: bool = pn.begins_with("upper_arm") and w == f.weapon and bool(w.def.get("two_handed", false))
		if w.is_fist or w.shape_kind == "shield" or own_hand or two_hand or along_arms:
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
	var fit: Dictionary = FighterArt.armor_fit(pn) if b.has_node("Look/Art") else {}
	if not fit.is_empty():
		mi.mesh = fit["mesh"]
		mi.position = fit["pos"]
	elif pd["shape"] == "sphere":
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
	# Houdini art for this part (armor def "art": {part: asset id}) replaces the placeholder and keeps its own materials.
	var art_ids: Variant = ad.get("art", {})
	var art: Mesh = FighterArt.armor_art(str((art_ids as Dictionary).get(pn, ""))) if art_ids is Dictionary else null
	if art != null:
		mi.mesh = art
		mi.position = Vector3.ZERO
	else:
		mi.material_override = mat
	mi.name = "Armor_" + pn
	_slot(b, "ArmorSlot").add_child(mi)
	FighterArt.apply_shadow(mi, pn)
	if _art.shows_armor(pn):
		# The outfit art already draws armor here: keep the node (a knocked-off piece copies its mesh) but draw nothing.
		# Not `visible`, which restore() and _dislodge() own: an empty render layer draws it for no camera.
		mi.layers = 0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if prof_on:
		_physics_profiled(delta)
		return
	_tick += 1
	if _skip_contacts > 0:
		_skip_contacts -= 1
	else:
		_process_contacts()
		_kick_contacts()
	if health != null:
		health.tick(delta, _exertion)
	_update_state(delta)
	_control(delta)
	_record_velocities()


## The same tick as `_physics_process`, with each step timed into `prof` (tests/perf only).
func _physics_profiled(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_tick += 1
	if _skip_contacts > 0:
		_skip_contacts -= 1
	else:
		_process_contacts()
	var t1: int = Time.get_ticks_usec()
	if health != null:
		health.tick(delta, _exertion)
	_update_state(delta)
	var t2: int = Time.get_ticks_usec()
	_control(delta)
	var t3: int = Time.get_ticks_usec()
	_record_velocities()
	var t4: int = Time.get_ticks_usec()
	prof["f_contacts"] = int(prof.get("f_contacts", 0)) + t1 - t0
	prof["f_state"] = int(prof.get("f_state", 0)) + t2 - t1
	prof["f_control"] = int(prof.get("f_control", 0)) + t3 - t2
	prof["f_velrec"] = int(prof.get("f_velrec", 0)) + t4 - t3


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
	var rk: float = smoothstep(0.0, 1.0, _reach)
	var ut: Vector3 = t.global_transform.basis.y.normalized()
	var upv: Vector3 = p.global_transform.basis.y.normalized()
	var want_t: Vector3 = Vector3.UP
	var want_p: Vector3 = Vector3.UP
	# The stance lean is intended: a forward pitch up to it does not count as tilt.
	var lean: float = _t("stance_lean") + _t("lean_per_speed") * _t("sprint_speed")
	want_t = _bow_up(ut, -Basis(Vector3.UP, _yaw).z, lean, 1.0)
	if rk > 0.0:
		# While reaching down the bow is intended: a forward pitch anywhere between upright and the reach pose
		# does not count as tilt (sideways lean and bending past the pose still do).
		var fwd: Vector3 = -Basis(Vector3.UP, _yaw).z
		want_t = _bow_up(ut, fwd, _t("reach_pitch") + _t("reach_bend"), rk)
		want_p = _bow_up(upv, fwd, _t("reach_pitch"), rk)
	return acos(clampf((ut.dot(want_t) + upv.dot(want_p)) * 0.5, -1.0, 1.0))


## The up vector nearest `up` on the forward arc from straight up to a bow of `full` * `rk` radians.
func _bow_up(up: Vector3, fwd: Vector3, full: float, rk: float) -> Vector3:
	var pitch: float = clampf(atan2(up.dot(fwd), up.y), 0.0, full * rk)
	return Vector3.UP * cos(pitch) + fwd * sin(pitch)


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
			var low: float = _t("stand_height") * 0.5
			if _reach > 0.0:
				low = minf(low, _t("reach_height") - 0.2)
			if _roll.active():
				# Turning over in a roll is intended: only lost legs or a heavy stagger put a roller down.
				if not _legs_ok() or _stagger >= _t("stagger_down"):
					_roll.t = -1.0
					_set_state("down")
			elif not _legs_ok() or tl > _t("fall_tilt") or h < low or _stagger >= _t("stagger_down"):
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
			var done: bool = _state_t >= _getup_time()
			if done and tl < _t("stumble_tilt") and h > _t("stand_height") * 0.85:
				_set_state("standing")
			elif _state_t > _getup_time() * 3.0 or not _legs_ok():
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


## Worn armor as a share of a full load (ArmorLoad): slows the gait and the get-up and costs stamina per step and swing.
func _armor_load() -> float:
	return ArmorLoad.load_of(ArmorLoad.mass(_armor), _tun)


func _getup_time() -> float:
	return _t("getup_time") * ArmorLoad.getup_scale(_armor_load(), _tun)


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
			support = clampf(_state_t / maxf(_getup_time(), 0.01), 0.15, 1.0)
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
	_update_reach(inp, crouch, delta)
	var rk: float = smoothstep(0.0, 1.0, _reach)
	var stamina: float = health.stamina if health != null else 1.0
	if _roll.press(inp.has(ROLL), _state == "standing" and _reach <= 0.01, stamina, _t("roll_stamina")):
		_roll.start(inp.move())
		if health != null:
			health.stamina = maxf(health.stamina - _t("roll_stamina"), 0.0)
		_anchor_set = false
	if _roll.tick(delta, _t("roll_time"), _t("roll_cooldown")):
		_gait.replant([_foot_point("shin_l"), _foot_point("shin_r")])
	if _roll.active() and not active:
		_roll.t = -1.0
	_close_moves(inp, active, delta)
	var rolling: bool = _roll.active()
	var ru: float = _roll.progress(_t("roll_time"))
	var tk: float = RollLogic.tuck(ru) if rolling else 0.0
	var roll_dir: Vector3 = (right * _roll.dir.x + fwd * _roll.dir.y).normalized()
	var roll_axis: Vector3 = RollLogic.axis(roll_dir, _t("roll_shoulder") * RollLogic.shoulder_side(_roll.dir))
	# The feet leave the sand only once the body is low (sat down or over the shoulder), or a roll starts airborne.
	var gate: float = _t("roll_tuck_gate")
	var tk_leg: float = tk * clampf((gate - pelvis.global_position.y) / 0.15, 0.0, 1.0) if gate > 0.0 else tk
	tk_leg = _roll.hold_leg_tuck(tk_leg, ru, tk)
	if rolling and RollLogic.crossed(_roll.t, delta, _t("roll_time"), RollLogic.OPEN_START):
		# The body has come round: the legs open onto spots under the hips, a little on along the roll.
		var lead: Vector3 = roll_dir * _t("roll_land_lead")
		_gait.replant([_hip_point(0) + lead, _hip_point(1) + lead])
	var h_target: float = _t("crouch_height") if crouch else _t("stand_height")
	var sp0: float = Vector2(pelvis.linear_velocity.x, pelvis.linear_velocity.z).length()
	if not crouch:
		h_target += _t("walk_height_add") * clampf(sp0 / maxf(_t("sprint_speed"), 0.1), 0.0, 1.0)
		h_target += _t("gait_bob") * _gait.bob()
	if rolling:
		# Dip first on planted feet, then the tucked ball rolls low on the sand.
		h_target = lerpf(h_target, _t("roll_dip_height"), RollLogic.dip(ru))
		h_target = lerpf(h_target, _t("roll_height"), tk)
	if rk > 0.0:
		h_target = lerpf(h_target, _t("reach_height"), rk)
	if _state == "getting_up":
		h_target = lerpf(pelvis.global_position.y, h_target, clampf(_state_t / maxf(_getup_time(), 0.01), 0.3, 1.0))
	var grounded: bool = _lowest_foot() < 0.3 or pelvis.global_position.y < h_target + 0.15
	var pvel: Vector3 = pelvis.linear_velocity
	var hvel := Vector3(pvel.x, 0.0, pvel.z)

	# Support and locomotion force on the pelvis.
	var move: Vector2 = inp.move().limit_length(1.0)
	var speed: float = _t("sprint_speed") if inp.has(SPRINT) else _t("move_speed")
	speed *= lerpf(0.35, 1.0, leg_factor)
	var armor_ld: float = _armor_load()
	speed *= ArmorLoad.speed_scale(armor_ld, _tun)
	if crouch:
		speed *= 0.6
	speed *= lerpf(1.0, 0.5, rk)
	var v_des: Vector3 = (right * (move.x * _t("strafe_speed_scale")) + fwd * move.y) * speed
	if _state != "standing":
		v_des *= 0.3 if _state == "stumbling" else 0.0
	if _close.kicking():
		# On one leg: no walking through a kick, but the hips drive in behind the extending leg.
		var ku: float = CloseCombat.progress(_close.kick_t, _t("kick_time"))
		v_des = v_des * 0.2 + fwd * (_t("kick_lunge") * (1.0 if ku > CloseCombat.KICK_CHAMBER and ku < CloseCombat.KICK_HOLD else 0.0))
	var v_move: Vector3 = v_des  # what the feet plan for (the sway below is the body's, not a step's)
	if _close.shoving():
		v_des += fwd * (_t("shove_lunge") * CloseCombat.shove_extend(CloseCombat.progress(_close.shove_t, _t("shove_time"))))
	# Hip sway: the pelvis shifts over the planted foot while the other swings.
	v_des += right * (_t("gait_sway") * _gait.sway_rate())
	if rolling:
		v_des = roll_dir * (_t("roll_speed") * RollLogic.drive(ru))
	if grounded and support > 0.0:
		var w: float = _t("support_freq")
		var fy: float = total_mass * (g + w * w * (h_target - pelvis.global_position.y) - 2.0 * w * pvel.y)
		# Dipping, the body weight goes onto the folding legs: a stiffer spring alone, without the weight term.
		var wd: float = _t("roll_dip_freq")
		var fy_dip: float = total_mass * (wd * wd * (h_target - pelvis.global_position.y) - 2.0 * wd * pvel.y)
		var fy_turn: float = fy
		# Tucked, the sand carries the ball: the support only eases the body down, so it cannot be held up in the air.
		var fy_cap: float = lerpf(_t("support_max"), _t("roll_support"), tk) if rolling else _t("support_max")
		fy = clampf(fy, 0.0, fy_cap * total_mass * g) * support
		var fh: Vector3 = (v_des - hvel) * (total_mass * _t("move_response"))
		# Standing still holds its spot (a weak spring) so idle drift does not wander off.
		if _state == "standing" and move.length() < 0.05 and not rolling:
			if not _anchor_set:
				_anchor = Vector3(pelvis.global_position.x, 0.0, pelvis.global_position.z)
				_anchor_set = true
			var hf: float = _t("hold_freq")
			var off: Vector3 = _anchor - Vector3(pelvis.global_position.x, 0.0, pelvis.global_position.z)
			fh += off * (total_mass * hf * hf)
		else:
			_anchor_set = false
		var acc_max: float = _t("roll_accel") if rolling else _t("move_accel") * ArmorLoad.accel_scale(armor_ld, _tun)
		fh = fh.limit_length(acc_max * total_mass * support * (0.5 if _state == "stumbling" else 1.0))
		pelvis.apply_central_force(Vector3(fh.x, fy, fh.z))
		if tk < 0.5:
			_load_feet(fy, fh)
		if rolling and ru < RollLogic.OPEN_START:
			# Through the turn the same pull keeps the ball low: without it the turning body vaults up over its
			# planted legs and the head into a handstand.
			_roll_dip_pull(fy_dip if ru < RollLogic.DIP_END else minf(fy_dip, fy_turn), total_mass * g)

	# Fighting-stance lean, more when moving forward (the torso assist holds it, the spine target shapes it).
	var lean: float = _t("stance_lean") + _t("lean_per_speed") * maxf(hvel.dot(fwd), 0.0) + (0.25 if crouch else 0.0)
	if _close.kicking():
		lean -= _t("kick_lean_back") * CloseCombat.kick_lean(CloseCombat.progress(_close.kick_t, _t("kick_time")))
	lean = lerpf(lean, _t("reach_bend"), rk)

	# Balance: pelvis upright and facing; torso assisted upright.
	var bal_scale: float = support * (1.0 - 0.7 * clampf(_stagger, 0.0, 1.0))
	if bal_scale > 0.0:
		var bf: float = _t("balance_freq")
		var cap: float = _t("balance_torque") * bal_scale * s
		if held_part() == "head":
			cap *= _t("clinch_head_balance")
		var p_want: Basis = yb * _reach_pitch(rk, false) * Basis(Vector3(0, 0, 1), _t("gait_hip_roll") * _gait.sway())
		if rolling:
			# One turn of the whole body about the axis across the roll, led by the pelvis.
			p_want = Basis(roll_axis, RollLogic.spin(ru)) * yb
			cap = maxf(cap, _t("roll_torque") * s)
		var err: Vector3 = FighterMath.rotation_error(pelvis.global_transform.basis, p_want)
		# Rolling, the turn's own rate is fed forward, so the body is carried round instead of dragged after it.
		var w_roll: Vector3 = roll_axis * RollLogic.spin_rate(ru, _t("roll_time")) if rolling else Vector3.ZERO
		var bi: float = _t("balance_inertia") * (_t("roll_inertia_scale") if rolling else 1.0)
		pelvis.apply_torque(FighterMath.pd_torque(err, pelvis.angular_velocity - w_roll, bi, bf, 1.0, cap))
		var torso: RigidBody3D = parts["torso"]
		var t_want: Basis = yb * _reach_pitch(rk, true) if rk > 0.0 else yb * Basis(Vector3.RIGHT, -lean)
		if rolling:
			t_want = p_want * Basis(Vector3.RIGHT, -_t("stance_lean") - 0.8 * tk)
		var terr: Vector3 = FighterMath.rotation_error(torso.global_transform.basis, t_want)
		var tf: float = _t("torso_assist")
		var t_cap: float = cap if rolling else cap * tf
		torso.apply_torque(FighterMath.pd_torque(terr, torso.angular_velocity - w_roll, _inertia["torso"] * (_t("roll_inertia_scale") if rolling else 1.0), bf, 1.0, t_cap))

	# Footwork: planted feet hold their spot on the sand, one foot at a time steps on a cadence set by speed.
	if not active:
		_gait.ready = false
		_leg_prev.clear()
		_foot_prev = [Vector3.INF, Vector3.INF]
	elif not rolling or ru >= RollLogic.OPEN_START:
		# The plan follows the intended velocity (feet lead the body; a fighter held by planted feet still steps off).
		# Drift (a shove, a stumble) is caught by corrective steps, not by the cadence.
		var v_plan: Vector3 = v_move if not rolling else Vector3.ZERO  # landing a roll: feet stay where they open
		if not _gait.ready:
			_gait.replant([_foot_point("shin_l"), _foot_point("shin_r")])  # start from where the feet are
		var steps0: int = _gait.steps
		_gait.tick(delta, [_hip_point(0), _hip_point(1)], yb, v_plan, _gait_params(), _state != "getting_up" and not _close.kicking(),
			[_foot_point("shin_l"), _foot_point("shin_r")])
		if _gait.steps > steps0:
			_pay_stamina(ArmorLoad.step_cost(armor_ld, _tun) * float(_gait.steps - steps0))

	# Pose targets (child relative to parent).
	var targets: Dictionary = {}
	var aim: Vector2 = inp.aim()
	var twist: float = -aim.x * _t("torso_twist") if active else 0.0
	if active and _close.holding() and _close.hold_part == "forearm_r":
		twist += _t("clinch_twist")  # the chest turns to the free side: the body goes into the haul
	targets["torso"] = Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, -lean - 0.8 * tk)
	# The head stays level on the foe over the leaning chest (tucked in a roll).
	targets["head"] = Basis(Vector3.UP, -twist * 0.8) * Basis(Vector3.RIGHT, lean * 0.8 - 0.5 * tk)
	if active:
		# Kneeling to reach down, the legs fold toward the lower target height themselves (the support force only
		# pushes up) and the feet go a little forward under the bowed body.
		var drop: float = maxf(pelvis.global_position.y - h_target, 0.0) * rk
		var h_leg: float = h_target
		if rolling and ru < RollLogic.TUCK_IN:
			# The legs fold only a little ahead of the dropping pelvis, or the feet fold up off the sand.
			h_leg = maxf(h_target, pelvis.global_position.y - _t("roll_fold_lead"))
		_leg_targets(targets, yb, delta, h_leg, drop, _t("reach_foot_fwd") * rk, tk_leg)
	else:
		for n: String in ["thigh_l", "thigh_r"]:
			targets[n] = Basis(Vector3.RIGHT, 0.25)
		for n: String in ["shin_l", "shin_r"]:
			targets[n] = Basis(Vector3.RIGHT, -0.4)
	var used: float = _arms(targets, yb, fwd, right, active, s, delta, rk)
	if active:
		_shove_contact(fwd, right, s)
		_hold_tick(delta, s)

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
		var leg: bool = n.begins_with("thigh") or n.begins_with("shin")
		if rolling and tk_leg > 0.0 and leg:
			# Tucked legs hold their fold against the spin's throw (a tucked roller clutches the knees).
			freq *= lerpf(1.0, _t("roll_leg_hold"), tk_leg)
		var arm_drive: bool = n.contains("arm") and active
		if arm_drive:
			freq *= 0.6
		var cap_t: float = float(pd["torque"]) * joint_scale * limb
		if rolling and tk_leg > 0.0 and leg:
			cap_t *= lerpf(1.0, _t("roll_leg_hold"), tk_leg)
		var damp: float = _t("joint_damping")
		var margin: float = _t("pd_margin")
		var inertia: float = FighterMath.stable_inertia(_inertia[n], _inertia_pair[n], freq, damp, delta, margin)
		# Twist about the bone has a tiny inertia: it gets its own, much smaller gain (one gain for all axes
		# makes the limbs spin up about their own axes).
		var axis: Vector3 = ch.global_transform.basis.y.normalized()
		var w_rel: Vector3 = ch.angular_velocity - par.angular_velocity
		if n.begins_with("thigh") or n.begins_with("shin"):
			# Legs track a moving plan (a planted foot under a moving hip, a swing): damp toward the target's own
			# rate of change, not toward rest, or the leg lags a stride behind its plan.
			var tb: Basis = targets[n]
			if _leg_prev.has(n) and delta > 0.0:
				var rv: Vector3 = FighterMath.rotation_error(_leg_prev[n] as Basis, tb) / delta
				w_rel -= par.global_transform.basis * rv.limit_length(_t("leg_ff_max"))
			_leg_prev[n] = tb
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
	# Arm effort is the force used measured against the fresh arm (`used` is against the cap, which shrinks with
	# stamina). Round 3 trace, seed 9008: a club guard used all of the shrunken cap at 0 stamina, so exertion stayed
	# above the recovery line and stamina sat at 0 for 14 s; now a spent arm costs less and stamina comes back.
	_exertion = clampf(used * s * _t("arm_exertion") + (0.6 if sprinting else 0.0) + (0.2 if inp.has(SWING) else 0.0), 0.0, 1.0)
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


func _leg_targets(targets: Dictionary, yb: Basis, delta: float, h_target: float, drop: float = 0.0, foot_fwd: float = 0.0, tk: float = 0.0) -> void:
	var pelvis: RigidBody3D = parts["pelvis"]
	var pinv: Basis = pelvis.global_transform.basis.inverse()
	for i: int in range(2):
		var sfx: String = "_l" if i == 0 else "_r"
		# The legs reach for the pelvis height the support wants (the hip drive's partial reaction would otherwise
		# let straight legs prop the body up out of its crouch).
		var hip: Vector3 = _hip_point(i) + Vector3(0.0, (h_target - pelvis.global_position.y) * _t("leg_height_follow"), 0.0)
		var foot_w: Vector3 = _gait.target(i) + yb * Vector3(0.0, 0.0, -foot_fwd)
		if i == KICK_LEG and _close.kicking():
			foot_w = _kick_foot_world(yb)
		foot_w.y += FighterRig.ANKLE_HEIGHT + drop
		var rel: Vector3 = pinv * (foot_w - hip)
		if tk < 0.5:
			_foot_force(i, foot_w, hip, delta)
		var ang: Vector3 = FighterMath.leg_ik(rel, FighterRig.THIGH_LEN, FighterRig.SHIN_LEN)
		var bases: Array[Basis] = FighterMath.leg_bases(ang)
		if tk > 0.0:
			# Tucked in a roll: knees to the chest.
			bases[0] = bases[0].slerp(Basis(Vector3.RIGHT, 1.9), tk)
			bases[1] = bases[1].slerp(Basis(Vector3.RIGHT, -2.2), tk)
		targets["thigh" + sfx] = bases[0]
		targets["shin" + sfx] = bases[1]


## The support and drive forces on the pelvis come from the ground through the planted feet: each planted foot is
## pressed down by its share of the support (so its friction carries the body, and a foot that loses its grip
## slides for real) and pushed back by its share of the drive, the reaction that moves the body on.
func _load_feet(fy: float, fh: Vector3) -> void:
	var down: Array[String] = []
	for i: int in range(2):
		var n: String = "shin_l" if i == 0 else "shin_r"
		if _gait.planted(i) and not _is_cut_off(n) and _foot_point(n).y < FighterRig.ANKLE_HEIGHT + _t("foot_contact") \
				and not (i == KICK_LEG and _close.kicking()):
			down.append(n)
	if down.is_empty():
		return
	var share: float = 1.0 / float(down.size())
	var f := Vector3(-fh.x * _t("foot_drive"), -fy * _t("foot_load"), -fh.z * _t("foot_drive")) * share
	for n: String in down:
		var b: RigidBody3D = parts[n]
		b.apply_force(f, _foot_point(n) - b.global_position)


## Dipping into a roll, the support goes negative: the body weight the support stands in for drops onto the folding
## legs. Without it the support only lets go, the stiff legs hold the pelvis, and the light feet fold up to it (the
## roll started with a hop). `fy` below zero is what the height spring wants, capped at roll_pull of body weight;
## the planted feet are pressed into the sand by the same amount, as the weight coming down the legs would.
func _roll_dip_pull(fy: float, weight: float) -> void:
	var pull: float = minf(-fy, _t("roll_pull") * weight)
	if pull <= 0.0:
		return
	var down: Array[String] = []
	for i: int in range(2):
		var n: String = "shin_l" if i == 0 else "shin_r"
		if not _is_cut_off(n) and _foot_point(n).y < FighterRig.ANKLE_HEIGHT + _t("foot_contact"):
			down.append(n)
	if down.is_empty():
		return
	var pelvis: RigidBody3D = parts["pelvis"]
	pelvis.apply_central_force(Vector3.DOWN * pull)
	for n: String in down:
		var b: RigidBody3D = parts[n]
		b.apply_force(Vector3.DOWN * (pull / float(down.size())), _foot_point(n) - b.global_position)


## Leg muscle force on foot `i` toward its planned point (a PD on the foot like the hand's, damped toward the plan's
## own velocity), with the full reaction on the pelvis at the hip: the joint drives alone lag a swing by a stride.
func _foot_force(i: int, target: Vector3, hip: Vector3, delta: float) -> void:
	var n: String = "shin_l" if i == 0 else "shin_r"
	var kick: bool = i == KICK_LEG and _close.kicking()
	var cap: float = _t("kick_force" if kick else "foot_force_max") * FighterMath.limb_factor(minf(_hp(n), _hp("thigh" + n.substr(4))), _t("limb_floor"))
	if _is_cut_off(n) or cap <= 0.0 or delta <= 0.0:
		_foot_prev[i] = target
		return
	var b: RigidBody3D = parts[n]
	var fp: Vector3 = _foot_point(n)
	var fv: Vector3 = b.linear_velocity + b.angular_velocity.cross(fp - b.global_position)
	var tv: Vector3 = (target - (_foot_prev[i] as Vector3)) / delta if _foot_prev[i] != Vector3.INF else Vector3.ZERO
	_foot_prev[i] = target
	var err: Vector3 = target - fp
	var planted: bool = _gait.planted(i) and not kick
	if planted:
		# A planted foot only resists slipping: a spring toward its spot would push the body through the sand's grip.
		err = Vector3.ZERO
	var f: Vector3 = FighterMath.pd_force(err, fv - tv.limit_length(12.0), _t("foot_drive_mass"), _t("foot_freq"), 1.0, cap)
	if planted:
		f.y = 0.0  # its load comes from the support (_load_feet)
	b.apply_force(f, fp - b.global_position)
	var pelvis: RigidBody3D = parts["pelvis"]
	pelvis.apply_force(-f, hip - pelvis.global_position)


## World position of hip `i` (0 left, 1 right).
func _hip_point(i: int) -> Vector3:
	var sfx: String = "_l" if i == 0 else "_r"
	var hip_local: Vector3 = (FighterRig.part("thigh" + sfx)["pivot"] as Vector3) - (FighterRig.part("pelvis")["center"] as Vector3)
	return (parts["pelvis"] as RigidBody3D).global_transform * hip_local


## World ankle point of shin `n`.
func _foot_point(n: String) -> Vector3:
	return (parts[n] as RigidBody3D).global_transform * FighterRig.ANKLE_LOCAL


## GaitLogic parameters from Tuning.
func _gait_params() -> Dictionary:
	var w: float = _t("stance_width")
	var f: float = _t("stance_fwd")
	var g: float = _t("stance_stagger") * 0.5
	return {
		"cadence_base": _t("cadence_base"), "cadence_per_speed": _t("cadence_per_speed"),
		"cadence_lateral": _t("cadence_lateral"), "span": _t("gait_span"), "span_lat": _t("gait_span_lat"), "stance_max": _t("stance_max"),
		"swing_min": _t("swing_min"), "swing_max": _t("swing_max"), "lift": _t("foot_lift"),
		"shuffle_lift": _t("shuffle_lift"), "reach": _t("gait_reach"), "lead_max": _t("gait_lead_max"),
		"min_gap": _t("gait_min_gap"), "idle_err": _t("gait_idle_err"), "min_speed": _t("gait_min_speed"),
		"stance_l": Vector3(-w, 0.0, -(f + g)), "stance_r": Vector3(w, 0.0, -(f - g)),
	}


## True while a dodge roll is under way.
func rolling() -> bool:
	return _roll.active()


## Share of a blow's effective mass that lands on this fighter now (below 1 only while tucked in a roll).
func roll_guard() -> float:
	return RollLogic.guard_scale(_roll.active(), _roll.progress(_t("roll_time")), _t("roll_guard"),
		_t("roll_guard_start"), _t("roll_guard_end"))


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
func _arms(targets: Dictionary, yb: Basis, fwd: Vector3, right: Vector3, active: bool, s: float, _delta: float, rk: float = 0.0) -> float:
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
	if rk > 0.0:
		# Reaching down: the empty hand goes for the prop (as far as the arm reaches from the bowed shoulder).
		var to_p: Vector3 = _reach_point - shoulder_r
		raw_r = raw_r.lerp(shoulder_r + to_p.limit_length(reach), rk)
		rate_r = maxf(rate_r, _t("reach_hand_speed"))
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
		if rk > 0.0 and not _is_cut_off("thigh_l"):
			# Bowing down to pick something up, the free hand braces on the left knee.
			var knee: Vector3 = (parts["thigh_l"] as RigidBody3D).global_transform * Vector3(0, -0.2, -0.06)
			lt = lt.lerp(knee, rk)
	# A shove drives the free hand (or shield) out; a grab reaches for the foe's arm or head, a hold draws it in.
	var close_lt: bool = false
	if _close.shoving() and _shove_hand():
		var ext: float = CloseCombat.shove_extend(CloseCombat.progress(_close.shove_t, _t("shove_time")))
		lt = chest + fwd * lerpf(0.3, _t("shove_reach"), ext) - right * lerpf(0.15, 0.02, ext) - up * lerpf(0.15, 0.05, ext)
		close_lt = true
	elif _close.reaching() and _grab_point() != Vector3.INF:
		lt = _grab_point()
		close_lt = true
	elif _close.holding() and _hold_point() != Vector3.INF:
		# The holding hand stays on the held point and hauls it: a weapon arm across and down, a head down.
		var goal: Vector3 = CloseCombat.hold_pull_goal(_close.hold_part == "head", chest, fwd, right, up, _t("clinch_pull"),
			_t("clinch_pull_side"), _t("clinch_pull_down"), _t("clinch_head_down"))
		lt = CloseCombat.hold_pull_target(_hold_point(), goal, _t("clinch_pull_step"))
		close_lt = true
	var on_weapon: bool = (half or bool(main_w.def.get("two_handed", false))) if main_w != null else false
	on_weapon = on_weapon and not close_lt
	if on_weapon or not active:
		_goal_l = (lt if active else _hand_pos("l")) - pp
	else:
		var fast: bool = close_lt and not _close.holding()
		_goal_l = _goal_l.move_toward(lt - pp, _t("swing_hand_speed" if fast else "offhand_hand_speed") * _delta)
		lt = pp + _goal_l
	_hand_target_l = lt

	var used: float = 0.0
	if active:
		var arm_hp_r: float = minf(_hp("upper_arm_r"), _hp("forearm_r"))
		var cap_r: float = _t("arm_force") * s * FighterMath.limb_factor(arm_hp_r, _t("limb_floor"))
		cap_r *= ArmorLoad.arm_force_scale(ArmorLoad.arm_mass(_armor, "r"), _tun)
		cap_r *= 1.0 if inp.has(SWING) or inp.has(THRUST) else _t("guard_force_frac")
		if held_part() == "forearm_r":
			cap_r *= _t("clinch_pin")
		if half and inp.has(THRUST):
			cap_r *= _t("half_sword_thrust")
		used = _hand_force("r", _hand_target, cap_r, shoulder_r)
		var arm_hp_l: float = minf(_hp("upper_arm_l"), _hp("forearm_l"))
		var frac_l: String = "offhand_force_frac"
		if close_lt:
			frac_l = "clinch_pull_force_frac" if _close.holding() else "shove_force_frac"
		var cap_l: float = _t("arm_force") * _t(frac_l) * s * FighterMath.limb_factor(arm_hp_l, _t("limb_floor"))
		cap_l *= ArmorLoad.arm_force_scale(ArmorLoad.arm_mass(_armor, "l"), _tun)
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
			var crippled: bool = _is_cut_off("forearm_" + h) or hpf < _t("weapon_drop_hp")
			if crippled or _state == "ko" or _state == "dead":
				if crippled:
					_wlog["arm_drops"] = int(_wlog["arm_drops"]) + 1
				_release(w)
	var want: bool = inp.has(GRAB)
	var upright: bool = _state == "standing" or (_state == "stumbling" and _reach > 0.5)
	if want and not _grab_latch and weapon == null and not _is_cut_off("forearm_r") and upright:
		var hand: Vector3 = _hand_pos("r")
		var best: Weapon = null
		var best_d: float = _t("grab_radius")
		for n: Node in get_tree().get_nodes_in_group(Weapon.PROP_GROUP):
			var pw: Weapon = n as Weapon
			if pw == null or pw.is_fist or pw.lodged_in != null:
				continue
			# Never into a hand too hurt to hold it: it would drop at once and be grabbed again every pulse.
			if not _hand_can_hold(_grab_hand(pw)):
				continue
			var d: float = pw.global_position.distance_to(hand)
			if d < best_d:
				best_d = d
				best = pw
		if best != null:
			_attach(best, _grab_hand(best))
			_compute_inertia()
			_wlog["rearms"] = int(_wlog["rearms"]) + 1
			if _unreplaced_disarms > 0:
				_unreplaced_disarms -= 1
				_wlog["rearms_after_disarm"] = int(_wlog["rearms_after_disarm"]) + 1
	_grab_latch = want


## Reach-down state: CROUCH with GRAB pressed recently, an empty right hand and a free prop near the feet bows the
## fighter down (pelvis low and pitched, torso bent) and sends the right hand to the prop.
func _update_reach(inp: FighterInput, crouch: bool, delta: float) -> void:
	var can: bool = crouch and weapon == null and not _is_cut_off("forearm_r") and (_state == "standing" or _state == "stumbling")
	if can and inp.has(GRAB):
		_reach_hold = _t("reach_hold")
	var want: bool = false
	if can and _reach_hold > 0.0:
		var pw: Weapon = _reach_prop()
		if pw != null:
			want = true
			_reach_point = pw.global_position + Vector3.UP * _t("reach_hand_lift")
	if not can:
		_reach_hold = 0.0
	_reach_hold = maxf(_reach_hold - delta, 0.0)
	_reach = move_toward(_reach, 1.0 if want else 0.0, delta / maxf(_t("reach_time"), 0.01))


## The free prop nearest the pelvis (horizontally) within reach_scan, or null.
func _reach_prop() -> Weapon:
	if not is_inside_tree():
		return null
	var pp: Vector3 = (parts["pelvis"] as RigidBody3D).global_position
	var best: Weapon = null
	var best_d: float = _t("reach_scan")
	for n: Node in get_tree().get_nodes_in_group(Weapon.PROP_GROUP):
		var pw: Weapon = n as Weapon
		if pw == null or pw.is_fist or pw.lodged_in != null or pw.holder != null or not _hand_can_hold(_grab_hand(pw)):
			continue
		var d: float = Vector2(pw.global_position.x - pp.x, pw.global_position.z - pp.z).length()
		if d < best_d:
			best_d = d
			best = pw
	return best


## Forward pitch (in the facing frame) of the reach pose at blend `rk`: the pelvis tips by reach_pitch, the torso
## by reach_pitch plus its bend over the hips.
func _reach_pitch(rk: float, torso: bool) -> Basis:
	var a: float = _t("reach_pitch") + (_t("reach_bend") if torso else 0.0)
	return Basis(Vector3.RIGHT, -a * rk)


## The hand a picked-up prop goes to: a shield to the free left hand, anything else to the right.
func _grab_hand(w: Weapon) -> String:
	return "r" if w.shape_kind != "shield" or offhand != null else "l"


## False when hand `h` is cut off or its arm is below weapon_drop_hp (it would let go at once).
func _hand_can_hold(h: String) -> bool:
	return not _is_cut_off("forearm_" + h) and minf(_hp("forearm_" + h), _hp("upper_arm_" + h)) >= _t("weapon_drop_hp")


## Releases the right-hand weapon (it becomes a prop). Public for scripted tests.
func drop_weapon() -> void:
	if weapon != null:
		_release(weapon)


# --- close range: shove, kick, grab ------------------------------------------------------------------------------

## CloseCombat timing parameters from Tuning.
func _close_params() -> Dictionary:
	return {
		"shove_time": _t("shove_time"), "shove_cooldown": _t("shove_cooldown"), "kick_time": _t("kick_time"),
		"kick_cooldown": _t("kick_cooldown"), "clinch_time": _t("clinch_time"), "clinch_max": _t("clinch_max"),
		"clinch_cooldown": _t("clinch_cooldown"),
	}


## Starts a shove, kick or grab on the press of its button, keeps a hold only while CLINCH is held, and advances
## their timers. Nothing starts mid roll or while reaching down; a fighter that goes down stops them all.
func _close_moves(inp: FighterInput, active: bool, delta: float) -> void:
	var pressed: int = _close.edges(inp.buttons)
	var stamina: float = health.stamina if health != null else 1.0
	var free: bool = not _roll.active() and _reach <= 0.01 and opponent != null and is_instance_valid(opponent) and opponent._built
	var able: bool = free and (_state == "standing" or _state == "stumbling")
	if (pressed & SHOVE) != 0 and _close.can_shove(able, stamina, _t("shove_stamina")):
		if _close.holding() or _close.reaching():
			_close_release(false)  # the holding hand lets go to push
		_close.start_shove()
		_pay_stamina(_t("shove_stamina"))
	if (pressed & KICK) != 0 and _close.can_kick(free and _state == "standing", _legs_ok(), stamina, _t("kick_stamina")):
		_close.start_kick()
		_pay_stamina(_t("kick_stamina"))
	if (pressed & (SWING | THRUST)) != 0 and active:
		_pay_stamina(ArmorLoad.swing_cost(_armor_load(), _tun))
	if (pressed & CLINCH) != 0 and _close.can_grab(able, _left_free()):
		_close.start_grab(inp.aim().y > 0.35)
	if (_close.holding() or _close.reaching()) and (not inp.has(CLINCH) or not _left_free()):
		_close_release(false)
	var was_kicking: bool = _close.kicking()
	if not active:
		_close.shove_t = -1.0
		_close.kick_t = -1.0
		if _close.holding() or _close.reaching():
			_close_release(false)
	_close.tick(delta, _close_params())
	if _close.holding() and health != null:
		health.stamina = maxf(health.stamina - _t("clinch_stamina") * delta, 0.0)
	if was_kicking and not _close.kicking() and active:
		_gait.replant([_foot_point("shin_l"), _foot_point("shin_r")])


func _pay_stamina(cost: float) -> void:
	if health != null:
		health.stamina = maxf(health.stamina - cost, 0.0)


## Lets go of a hold (or a reach). `broken`: the foe broke free (counted, and announced as a break).
func _close_release(broken: bool) -> void:
	var was: bool = _close.holding()
	for o: PhysicsBody3D in _hold_excl:
		if is_instance_valid(o):
			fist_l.remove_collision_exception_with(o)
			o.remove_collision_exception_with(fist_l)
	_hold_excl.clear()
	if _hold_joint != null:
		_hold_joint.node_a = NodePath("")
		_hold_joint.node_b = NodePath("")
		remove_child(_hold_joint)
		_hold_joint.free()
		_hold_joint = null
	_close.release(_close_params(), broken)
	if was:
		_emit_close("break" if broken else "slip", _hand_pos("l"), false)


## The left hand can grab: no shield in it, not cut off or too hurt to hold.
func _left_free() -> bool:
	return offhand == null and _hand_can_hold("l")


## True when a shove drives the left hand (or shield) out; with both hands on the weapon it is a shoulder charge.
func _shove_hand() -> bool:
	if _is_cut_off("forearm_l"):
		return false
	if weapon != null and (bool(weapon.def.get("two_handed", false)) or grip() == "half"):
		return false
	return true


## The foe part a hold has or a reach goes for: the head when aiming high, else the weapon (right) forearm.
func _grab_part() -> String:
	if _close.holding():
		return _close.hold_part
	return "head" if _close.grab_head else "forearm_r"


## World point the reaching hand goes for on the foe (its near surface), or INF when that part is gone.
func _grab_point() -> Vector3:
	if opponent == null or not is_instance_valid(opponent) or not opponent._built:
		return Vector3.INF
	var part: String = _grab_part()
	if opponent._is_cut_off(part):
		return Vector3.INF
	var b: RigidBody3D = opponent.parts[part]
	var c: Vector3 = b.global_position if part == "head" else b.global_transform * (FighterRig.HAND_LOCAL * 0.7)
	var to_me: Vector3 = (parts["torso"] as RigidBody3D).global_position - c
	to_me.y = 0.0
	var skin: float = 0.12 if part == "head" else 0.06
	return c + (to_me.normalized() * skin if to_me.length_squared() > 0.0001 else Vector3.ZERO)


## The foe's bodies the holding hand wraps round: the held part, and for the weapon arm the fist and hilt in it.
func _hold_bodies() -> Array[PhysicsBody3D]:
	var out: Array[PhysicsBody3D] = [opponent.parts[_close.hold_part] as PhysicsBody3D]
	if _close.hold_part == "forearm_r":
		for w: Weapon in [opponent.fist_r, opponent.weapon]:
			if w != null and w.holder == opponent and w.hand == "r":
				out.append(w)
	return out


## The grip: a joint between the holding forearm and the held part at point `p`, free to turn, its points kept within
## clinch_slack of each other. The hand's own capped drive pulls through it; the struggle or a slip breaks it.
func _make_hold_joint(body: RigidBody3D, p: Vector3) -> void:
	var j := Generic6DOFJoint3D.new()
	j.name = "Hold"
	add_child(j)
	j.top_level = true
	j.global_transform = Transform3D(Basis(), p)
	var slack: float = _t("clinch_slack")
	for ax: String in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/lower_distance" % ax, -slack)
		j.set("linear_limit_%s/upper_distance" % ax, slack)
		j.set("angular_limit_%s/enabled" % ax, false)
	j.node_a = j.get_path_to(parts["forearm_l"])
	j.node_b = j.get_path_to(body)
	_hold_joint = j


## World point of the foe part this fighter holds, or INF.
func _hold_point() -> Vector3:
	if not _close.holding() or opponent == null or not is_instance_valid(opponent) or opponent._is_cut_off(_close.hold_part):
		return Vector3.INF
	return (opponent.parts[_close.hold_part] as RigidBody3D).global_transform * _close.hold_local


## The foe part this fighter is held by ("" when free).
func held_part() -> String:
	if opponent == null or not is_instance_valid(opponent) or not opponent._built:
		return ""
	return opponent._close.hold_part


## A shove in its window lands when the pushing hand (or the shoulder) reaches the foe's torso or pelvis: an impulse
## on the foe (more when the shover is strong), a little back on the shover, and stagger that floors a foe already
## off balance. A held foe that shoves breaks the hold.
func _shove_contact(fwd: Vector3, right: Vector3, s: float) -> void:
	if not _close.shoving() or _close.shove_landed or opponent == null or not opponent._built:
		return
	if not CloseCombat.shove_window(CloseCombat.progress(_close.shove_t, _t("shove_time"))):
		return
	var torso: RigidBody3D = parts["torso"]
	var hand: bool = _shove_hand()
	var pt: Vector3 = _hand_pos("l") + fwd * 0.05 if hand else torso.global_position + fwd * 0.2 - right * 0.08
	var ft: RigidBody3D = opponent.parts["torso"]
	var fp: RigidBody3D = opponent.parts["pelvis"]
	var reach: float = _t("shove_contact")
	var touching: bool = pt.distance_to(ft.global_position) <= reach or pt.distance_to(fp.global_position) <= reach
	if not touching and hand:
		# The palm (or shield) meeting any part of the foe, or the guard in front of it, pushes the whole foe.
		var pusher: Weapon = offhand if offhand != null else fist_l
		var cp: Vector3 = _touching_foe(pusher)
		if cp != Vector3.INF:
			touching = true
			pt = cp
	if not touching:
		return
	_close.landed_shove()
	var dir: Vector3 = ft.global_position - torso.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else fwd
	var limb: float = FighterMath.limb_factor(minf(_hp("upper_arm_l"), _hp("forearm_l")), _t("limb_floor")) if hand else 1.0
	var j: float = CloseCombat.shove_impulse(_t("shove_impulse"), s, limb)
	ft.apply_central_impulse(dir * (j * 0.6))
	fp.apply_central_impulse(dir * (j * 0.4))
	torso.apply_central_impulse(-dir * (j * _t("shove_recoil")))
	var off: bool = opponent._state == "stumbling" or opponent._close.kicking() or opponent.balance() < 0.6
	var st: float = CloseCombat.shove_stagger(_t("shove_stagger"), _t("shove_stagger_off"), off)
	opponent._stagger = minf(opponent._stagger + st * (_t("kick_stagger_take") if opponent._close.kicking() else 1.0), 1.5)
	if opponent._close.holding():
		opponent._close_release(true)
	_emit_close("shove", pt, true)


## First contact point of `w` with the foe's body or a weapon the foe holds, or INF.
func _touching_foe(w: Weapon) -> Vector3:
	if w == null:
		return Vector3.INF
	var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(w.get_rid())
	if st == null:
		return Vector3.INF
	var best: Vector3 = Vector3.INF
	var best_key: String = ""
	for i: int in range(st.get_contact_count()):
		var o: Object = st.get_contact_collider_object(i)
		var foe_body: bool = o is Node and (o as Node).has_meta("fighter") and (o as Node).get_meta("fighter") == opponent
		var foe_weapon: bool = o is Weapon and (o as Weapon).holder == opponent
		if not foe_body and not foe_weapon:
			continue
		var p: Vector3 = st.get_contact_local_position(i)
		var key: String = "%s|%.4f|%.4f|%.4f" % [(o as Node).name, p.x, p.y, p.z]  # stable pick whatever the engine's order
		if best_key == "" or key < best_key:
			best_key = key
			best = p
	return best


## A reaching hand that closes on its point latches; a hold pulls the held point toward the hand with a capped
## spring (equal and opposite on the holding forearm), slips when pulled too far apart, and the held foe's struggle
## (its input effort and strength against the holder's) breaks it.
func _hold_tick(delta: float, s: float) -> void:
	if _close.reaching():
		var gp: Vector3 = _grab_point()
		if gp == Vector3.INF:
			_close_release(false)
			return
		if _hand_pos("l").distance_to(gp) <= _t("clinch_latch"):
			var b: RigidBody3D = opponent.parts[_grab_part()]
			_close.latch(_grab_part(), b.global_transform.affine_inverse() * _hand_pos("l"))
			_emit_close("hold", gp, true)
		return
	if not _close.holding():
		return
	if opponent._is_cut_off(_close.hold_part):
		_close_release(false)
		return
	var body: RigidBody3D = opponent.parts[_close.hold_part]
	# The hand closes round the held part (and the hilt in that hand) instead of bouncing off it.
	for o: PhysicsBody3D in _hold_bodies():
		if not _hold_excl.has(o):
			_exclude(fist_l, o)
			_hold_excl.append(o)
	var pf: Vector3 = body.global_transform * _close.hold_local
	var ph: Vector3 = _hand_pos("l")
	if CloseCombat.hold_slips(pf.distance_to(ph), _t("clinch_break_dist")):
		_close_release(false)
		return
	if _hold_joint == null:
		_make_hold_joint(body, pf)
	var fi: FighterInput = opponent._input
	var busy: bool = fi.has(SWING | THRUST | SHOVE | KICK | CLINCH | GRAB | ROLL)
	var rate: float = CloseCombat.struggle_rate(_t("clinch_struggle"), CloseCombat.struggle_effort(fi.move().y, busy),
		opponent._strength(), _strength())
	if opponent._is_limp():
		rate = 0.0
	if _close.add_struggle(rate, delta):
		_close_release(true)


## World target of the kicking foot (ground point plus height) for the kick's progress.
func _kick_foot_world(yb: Basis) -> Vector3:
	var hip: Vector3 = _hip_point(KICK_LEG)
	hip.y = 0.0
	var sl: Vector3 = _gait_params()["stance_l" if KICK_LEG == 0 else "stance_r"]
	var u: float = CloseCombat.progress(_close.kick_t, _t("kick_time"))
	var k: Vector3 = CloseCombat.kick_foot(u, Vector3(sl.x, 0.0, -sl.z), _t("kick_chamber"), _t("kick_reach"), _t("kick_height"))
	return hip + yb * Vector3(k.x, k.y, -k.z)


## The kicking foot's contacts in the kick's window: the first foe body part it meets takes a blunt blow (the foot's
## real speed and the kick's mass through DamageModel) and a push; a shield or weapon in the way blocks it. A kick
## that meets nothing leaves the kicker over-extended on one leg (stagger).
func _kick_contacts() -> void:
	if not _close.kicking() or _close.kick_landed:
		return
	var u: float = CloseCombat.progress(_close.kick_t, _t("kick_time"))
	if u > CloseCombat.KICK_HIT1:
		if not _close.kick_missed:
			_close.kick_missed = true
			_stagger = minf(_stagger + _t("kick_miss_stagger"), 1.5)
			_emit_close("kick", _foot_point(_kick_shin()), false)
		return
	if not CloseCombat.kick_window(u) or _is_cut_off(_kick_shin()):
		return
	var shin: RigidBody3D = parts[_kick_shin()]
	var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(shin.get_rid())
	if st == null:
		return
	var order: Array = []
	for i: int in range(st.get_contact_count()):
		var o: Object = st.get_contact_collider_object(i)
		var lp: Vector3 = st.get_contact_local_position(i)
		order.append([str((o as Node).name) if o is Node else "", lp.x, lp.y, lp.z, i])
	order.sort()
	for entry: Array in order:
		var i: int = int(entry[4])
		var obj: Object = st.get_contact_collider_object(i)
		if obj is Weapon:
			var ow: Weapon = obj as Weapon
			if ow.holder != null and ow.holder != self:
				_close.kick_landed = true  # blocked: no miss, no blow
				_emit_close("kick", st.get_contact_local_position(i), false, true)
				return
			continue
		if not obj is RigidBody3D or not (obj as Node).has_meta("fighter"):
			continue
		var target: Fighter = (obj as Node).get_meta("fighter") as Fighter
		var body: RigidBody3D = obj as RigidBody3D
		var part: String = str(body.get_meta("part"))
		if target == self or target._is_cut_off(part):
			continue
		var p: Vector3 = st.get_contact_local_position(i)
		var rel: Vector3 = pre_step_velocity(shin.name, shin, p) - target.pre_step_velocity(body.name, body, p)
		_close.landed_kick()
		var dir: Vector3 = (target.parts["pelvis"] as RigidBody3D).global_position - (parts["pelvis"] as RigidBody3D).global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.0001 else -Basis(Vector3.UP, _yaw).z
		var push: float = _t("kick_push") * _strength()
		(target.parts["pelvis"] as RigidBody3D).apply_central_impulse(dir * (push * 0.6))
		(target.parts["torso"] as RigidBody3D).apply_central_impulse(dir * (push * 0.4))
		if rel.length() >= _t("damage_min_speed"):
			var nrm: Vector3 = rel.normalized()
			var hit_in: Dictionary = {
				"part": part, "weapon_id": "fists", "contact": "blunt", "rel_vel": rel, "normal": nrm, "edge_alignment": 0.0,
				"effective_mass": _t("kick_mass") * _strength() * target.roll_guard(),
				"armor_ids": target.armor_on(part), "armor_wear": target._armor_wear.duplicate(),
				"part_hp_frac": target._hp(part), "blood_frac": target._finish_frac(), "hit_on_weapon": false,
				"target_down": target._state == "down" or target._state == "ko", "attacker_limp": _is_limp(),
				"attacker_conscious": _is_conscious(),
			}
			var ev: Dictionary = hit_in.duplicate()
			ev.merge(DamageModel.resolve(hit_in, _tun), true)
			ev["finisher"] = ""  # a kick knocks down and hurts; it never finishes
			ev["sever"] = false
			ev["gut"] = false
			ev["behead"] = false
			ev["attacker"] = side
			ev["target"] = target.side
			ev["point"] = p
			ev["kick"] = true
			target._take_hit(ev, body, null, self)
		else:
			target._stagger = minf(target._stagger + _t("shove_stagger"), 1.5)
		_emit_close("kick", p, true)
		return


func _kick_shin() -> String:
	return "shin_l" if KICK_LEG == 0 else "shin_r"


func _emit_close(kind: String, p: Vector3, landed: bool, blocked: bool = false) -> void:
	close.emit({"kind": kind, "attacker": side, "target": opponent.side if opponent != null else 1 - side, "point": p,
		"landed": landed, "blocked": blocked})


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
		# A shoving palm or a grabbing hand is not a punch (a shield bash still is a blow).
		if w == fist_l and (_close.shoving() or _close.reaching() or _close.holding()):
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
				if _tick < int(round(_t("self_hit_grace_s") * 60.0)):
					continue
				# Tucked in a roll, the own blade is held in against the body: it turns over with it, not into it.
				if _roll.active():
					continue
				# The handle or pommel behind the hand bumping its own holder is not a blow (round 4: most non-spear
				# self hits were pommels at about 6 m/s into the own upper arm). Only the part ahead of the grip counts.
				if (w.global_transform.affine_inverse() * p).y < 0.0:
					continue
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
		"effective_mass": FighterMath.effective_mass(wdef_mass, w.inertia_com, r, arm_mass) * target.roll_guard(),
		"armor_ids": target.armor_on(part), "armor_wear": target._armor_wear.duplicate(),
		"armor_gap": ArmorGaps.bypass(part, body.global_transform.affine_inverse() * p, _tun),
		"part_hp_frac": target._hp(part), "blood_frac": target._finish_frac(),
		"hit_on_weapon": on_weapon,
		"target_down": target._state == "down" or target._state == "ko", "attacker_limp": _is_limp(), "attacker_conscious": _is_conscious(),
	}
	var res: Dictionary = DamageModel.resolve(hit_in, _tun)
	var ev: Dictionary = hit_in.duplicate()
	ev.merge(res, true)
	ev["attacker"] = side
	ev["target"] = target.side
	ev["point"] = p
	target._take_hit(ev, body, w, self)


## KO'd or dead: a weapon still flying from this fighter has no grip or drive behind it.
func hand_target() -> Vector3:
	return _hand_target


func state_name() -> String:
	return _state


func _is_limp() -> bool:
	return _state == "ko" or _state == "dead" or (health != null and (health.dead or health.knocked_out()))


## Only a conscious attacker can land a finisher.
func _is_conscious() -> bool:
	return not _is_limp() and (health == null or health.consciousness >= _t("finisher_consc"))


## Blood fraction as the finisher rules see it: a dazed or downed fighter counts as deep in the finisher window.
func _finish_frac() -> float:
	if health == null:
		return 1.0
	var bf: float = health.blood_frac()
	if health.consciousness < _t("finisher_consc") or _state == "down" or _state == "ko":
		bf = minf(bf, _t("finisher_blood_frac") * 0.5)
	return bf


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
	var lost_h: String = ""
	if dis > 0.0:
		var h: String = "r" if part == "forearm_r" else ("l" if part == "forearm_l" else "")
		var held: Weapon = weapon if h == "r" else (offhand if h == "l" else null)
		if held != null and held.holder == self:
			var two: bool = held == weapon and (bool(held.def.get("two_handed", false)) or grip() == "half")
			if not DamageModel.grip_holds(dis, minf(_hp("forearm_" + h), _hp("upper_arm_" + h)), health.stamina, two, _tun, float(held.def.get("mass", 0.0))):
				_release(held)
				ev["disarmed"] = true
				lost_h = h
	if bool(ev.get("hit_on_weapon", false)):
		if lost_h != "":
			_wlog["disarms"] = int(_wlog["disarms"]) + 1
			_unreplaced_disarms += 1
		hit.emit(ev)
		return
	_stagger = minf(_stagger + float(ev.get("stagger", 0.0)) * (_t("kick_stagger_take") if _close.kicking() else 1.0), 1.5)
	if _close.holding() and (part == "forearm_l" or part == "upper_arm_l") and float(ev.get("stagger", 0.0)) > 0.2:
		# Only a real blow breaks the grip: the striker's own speed, not the holding arm running into a still fist.
		var own: Vector3 = pre_step_velocity(body.name, body, p)
		var striker: Vector3 = (ev.get("rel_vel", Vector3.ZERO) as Vector3) + own
		if CloseCombat.blow_breaks_hold(striker.length(), _t("clinch_break_min_speed")):
			_close_release(true)
	if bool(ev.get("dislodge", false)):
		_dislodge(str(ev.get("dislodged_id", "")), part, kb)
	var gore_events: Array = health.apply(ev, part) if health != null else []
	if lost_h != "":
		# The same blow crippled or cut the arm: it would have let go anyway, so this is an arm drop, not a disarm.
		var cut: bool = false
		for g: Variant in gore_events:
			var gk: String = str((g as Dictionary).get("kind", ""))
			if (gk == "sever" or gk == "behead") and FighterRig.subtree(str((g as Dictionary).get("part", ""))).has("forearm_" + lost_h):
				cut = true
		if cut or minf(_hp("forearm_" + lost_h), _hp("upper_arm_" + lost_h)) < _t("weapon_drop_hp"):
			ev["disarmed"] = false
			ev["arm_drop"] = true
			_wlog["arm_drops"] = int(_wlog["arm_drops"]) + 1
		else:
			_wlog["disarms"] = int(_wlog["disarms"]) + 1
			_unreplaced_disarms += 1
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
	_art.cut(parts, n)
	if health != null and not health.severed.has(n):
		health.severed.append(n)
	for h: String in ["r", "l"]:
		if _is_cut_off("forearm_" + h):
			var w: Weapon = weapon if h == "r" else offhand
			if w != null:
				_wlog["arm_drops"] = int(_wlog["arm_drops"]) + 1
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
			# On no layer, so nothing pushes against it: it only rests on the arena. With a layer the fighters scan but
			# a mask that ignored them, Godot made it an immovable block to them, and a cuirass knocked off onto a
			# fallen fighter's thigh pinned him in the sand for 40 s (round 3 trace, seed 5007).
			prop.collision_layer = 0
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
		"tick": _tick, "state": _state, "state_t": _state_t, "yaw": _yaw, "gait": _gait.to_array(), "roll": _roll.to_array(), "close": _close.to_array(), "leg_prev": _leg_prev.duplicate(), "foot_prev": _foot_prev.duplicate(), "stagger": _stagger,
		"severed": Array(_severed), "armor": _armor.duplicate(), "armor_wear": _armor_wear.duplicate(),
		"debounce": _debounce.duplicate(), "died": _died_emitted, "exertion": _exertion, "grab_latch": _grab_latch,
		"reach": _reach, "reach_hold": _reach_hold, "reach_point": _reach_point,
		"input": _input.to_array(), "bodies": bodies, "weapons": ws, "anchor": _anchor, "anchor_set": _anchor_set,
		"goal_r": _goal_r, "goal_l": _goal_l, "wlog": _wlog.duplicate(), "unreplaced_disarms": _unreplaced_disarms,
		"weapon": weapon.name if weapon != null else "", "offhand": offhand.name if offhand != null else "",
		"health": health.to_dict() if health != null else {},
	}


func restore(d: Dictionary) -> void:
	_tick = int(d.get("tick", 0))
	_state = str(d.get("state", "standing"))
	_state_t = float(d.get("state_t", 0.0))
	_yaw = float(d.get("yaw", 0.0))
	_gait.from_array(d.get("gait", []))
	_roll.from_array(d.get("roll", []))
	_close.from_array(d.get("close", []))
	_leg_prev = (d.get("leg_prev", {}) as Dictionary).duplicate()
	_foot_prev.assign(d.get("foot_prev", [Vector3.INF, Vector3.INF]))
	_stagger = float(d.get("stagger", 0.0))
	_died_emitted = bool(d.get("died", false))
	_exertion = float(d.get("exertion", 0.0))
	_grab_latch = bool(d.get("grab_latch", false))
	_reach = float(d.get("reach", 0.0))
	_reach_hold = float(d.get("reach_hold", 0.0))
	_reach_point = d.get("reach_point", Vector3.ZERO)
	_anchor = d.get("anchor", Vector3.ZERO)
	_anchor_set = bool(d.get("anchor_set", false))
	_goal_r = d.get("goal_r", Vector3.ZERO)
	_goal_l = d.get("goal_l", Vector3.ZERO)
	var wl: Dictionary = d.get("wlog", {})
	for k: String in ["disarms", "arm_drops", "rearms", "rearms_after_disarm"]:
		_wlog[k] = int(wl.get(k, 0))
	_unreplaced_disarms = int(d.get("unreplaced_disarms", 0))
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
			_art.uncut(n)
	for n: String in want_sev:
		if not _severed.has(n):
			_severed.append(n)
			_disconnect_joint(n)
			_art.cut(parts, n)
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
		# A grab's joint ties two fighters' bodies together; it is not carried through a re-normalised engine state.
		if f._close.holding() or f._close.reaching():
			f._close_release(false)
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
	if not prof_on:
		return _debug_frame_build()
	var t0: int = Time.get_ticks_usec()
	var d: Dictionary = _debug_frame_build()
	prof["debug_frame"] = int(prof.get("debug_frame", 0)) + Time.get_ticks_usec() - t0
	prof["debug_frame_n"] = int(prof.get("debug_frame_n", 0)) + 1
	return d


func _debug_frame_build() -> Dictionary:
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
		"contacts": _contacts.duplicate() if _contacts_frame == _frame() else [], "state": _state, "rolling": _roll.active(),
		"blood_frac": health.blood_frac() if health != null else 1.0, "armor": worn_armor(),
		"offhand_id": offhand.weapon_id if offhand != null else "", "props": props(), "weapon_log": _wlog.duplicate(),
		"foot_contacts": {"l": _gait.planted(0), "r": _gait.planted(1)},  # gait index 0 is the left foot (see replant)
		"close": {"shoving": _close.shoving(), "kicking": _close.kicking(), "reaching": _close.reaching(),
			"holding": _close.hold_part, "held": held_part(), "struggle": _close.struggle},
		"close_log": _close.counts.duplicate(),
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
