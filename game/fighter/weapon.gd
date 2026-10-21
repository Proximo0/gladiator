class_name Weapon
extends RigidBody3D
## A weapon, shield or fist built from a CombatData weapon def, with placeholder meshes and colliders.
## Local frame: origin at the grip, +Y along the weapon toward the tip, +X the cutting edge direction, +Z the
## flat normal (for a shield, its face). The centre of mass sits `balance_point` up +Y.
## A Weapon is either held (a locked 6DOF joint with angular wrist limits to a fighter's forearm) or a free prop
## (in group "weapon_props") that any fighter can pick up with GRAB.

const LAYER_WEAPONS: int = 4
const MASK_ALL: int = 7
const PROP_GROUP: String = "weapon_props"

var def: Dictionary = {}
var weapon_id: String = ""
var shape_kind: String = ""
var length: float = 0.3
var grip_offset: float = 0.0
var balance_point: float = 0.0
var edge_len: float = 0.0
var tip_local: Vector3 = Vector3.ZERO
var com_local: Vector3 = Vector3.ZERO
## Scalar inertia about the centre of mass along the weapon's long axis (kg·m²).
var inertia_com: float = 0.01
## Inertia about the grip point (kg·m²).
var inertia_grip: float = 0.01
## Inertia about the long axis (kg·m²).
var inertia_roll: float = 0.001
var is_fist: bool = false
## The Fighter holding it (null when it is a free prop or lodged in a body).
var holder: Node = null
## "r" or "l" while held.
var hand: String = ""
## Side of the fighter that created it (for snapshots).
var owner_side: int = 0
var grip_joint: Generic6DOFJoint3D = null
## Body it is stuck in (run through), or null.
var lodged_in: RigidBody3D = null


func build(d: Dictionary, physical_mass: float = -1.0) -> void:
	def = d
	weapon_id = str(d.get("id", "fists"))
	shape_kind = str(d.get("shape", "club"))
	length = maxf(float(d.get("length", 0.3)), 0.05)
	grip_offset = float(d.get("grip_offset", 0.0))
	balance_point = float(d.get("balance_point", length * 0.5))
	edge_len = float(d.get("edge_len", 0.0))
	is_fist = shape_kind == "fist"
	var m: float = maxf(float(d.get("mass", 1.0)), 0.05)
	mass = physical_mass if physical_mass > 0.0 else m
	tip_local = Vector3(0, length - grip_offset, 0)
	com_local = Vector3(0, balance_point, 0)
	inertia_com = m * length * length / 12.0
	inertia_grip = inertia_com + m * balance_point * balance_point
	inertia_roll = m * 0.0015
	collision_layer = LAYER_WEAPONS
	collision_mask = MASK_ALL
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	physics_material_override = pm
	var col: Color = parse_color(d.get("color", "#a0a0a0"))
	var wood := Color(0.42, 0.29, 0.16)
	var steel := Color(0.72, 0.74, 0.77)
	var tip: float = tip_local.y
	match shape_kind:
		"fist":
			tip_local = Vector3(0, 0.03, 0)
			com_local = Vector3(0, 0.02, 0)
			_add_sphere(0.055, Vector3(0, 0.02, 0), col)
		"sword":
			var guard_y: float = maxf(tip - edge_len - 0.03, 0.06)
			_add_box(Vector3(0.035, grip_offset + guard_y, 0.03), Vector3(0, (guard_y - grip_offset) * 0.5, 0), Color(0.3, 0.2, 0.12))
			_add_box(Vector3(0.05, 0.05, 0.05), Vector3(0, -grip_offset - 0.02, 0), steel * 0.8)
			_add_box(Vector3(0.2, 0.025, 0.04), Vector3(0, guard_y, 0), steel * 0.85)
			_add_box(Vector3(0.05, tip - guard_y, 0.02), Vector3(0, (tip + guard_y) * 0.5, 0), col)
		"axe":
			_add_box(Vector3(0.035, length, 0.03), Vector3(0, tip - length * 0.5, 0), wood)
			_add_box(Vector3(0.14, maxf(edge_len, 0.1), 0.025), Vector3(0.06, tip - maxf(edge_len, 0.1) * 0.5, 0), col)
		"spear":
			_add_box(Vector3(0.032, length - 0.2, 0.032), Vector3(0, tip - 0.2 - (length - 0.2) * 0.5, 0), wood)
			_add_box(Vector3(0.05, 0.22, 0.015), Vector3(0, tip - 0.11, 0), steel)
		"rake":
			_add_box(Vector3(0.03, length, 0.03), Vector3(0, tip - length * 0.5, 0), col)
			_add_box(Vector3(0.36, 0.04, 0.04), Vector3(0, tip - 0.02, 0), steel * 0.7)
			for i: int in range(5):
				_add_box(Vector3(0.012, 0.012, 0.09), Vector3(-0.15 + 0.075 * i, tip - 0.03, 0.06), steel * 0.7)
		"shield":
			var r: float = length * 0.5
			tip_local = Vector3(0, r, 0.05)
			com_local = Vector3(0, 0, 0.04)
			_add_cylinder(r, 0.035, Vector3(0, 0, 0.05), Basis(Vector3(1, 0, 0), PI * 0.5), col)
			_add_sphere(0.07, Vector3(0, 0, 0.08), steel * 0.8)
			_add_box(Vector3(0.04, 0.14, 0.03), Vector3.ZERO, wood)
		_:
			# bat and club: thin handle, thick head toward the tip.
			var head_len: float = length * 0.6
			var head_r: float = 0.045 if shape_kind == "club" else 0.035
			_add_box(Vector3(0.032, length - head_len, 0.032), Vector3(0, -grip_offset + (length - head_len) * 0.5, 0), col * 0.9)
			_add_capsule(head_r, head_len, Vector3(0, tip - head_len * 0.5, 0), col)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_local


static func parse_color(c: Variant) -> Color:
	if c is Color:
		return c
	if c is String and Color.html_is_valid(c):
		return Color.html(c)
	if c is Array and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(0.6, 0.6, 0.6)


func tip_position() -> Vector3:
	return global_transform * tip_local


func com_position() -> Vector3:
	return global_transform * com_local


func point_velocity(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - com_position())


func is_held() -> bool:
	return holder != null and grip_joint != null


func is_prop() -> bool:
	return is_in_group(PROP_GROUP)


## Joints the weapon to `forearm` with its grip at the forearm's hand point and its frame at `rest_basis`
## (world). The forearm must be in its rest pose relative to `rest_basis` only for the joint frame; the caller
## restores transforms afterwards.
func attach(forearm: RigidBody3D, grip_world: Transform3D, wrist_limit: float) -> void:
	detach()
	var keep: Transform3D = global_transform
	global_transform = grip_world
	grip_joint = Generic6DOFJoint3D.new()
	grip_joint.name = "Grip"
	add_child(grip_joint)
	grip_joint.top_level = true
	grip_joint.global_transform = Transform3D(grip_world.basis, grip_world.origin)
	# X is the forearm's long axis at rest: the wrist hardly twists about it (the elbow rolls the forearm).
	var lims: Vector3 = Vector3(minf(wrist_limit, 0.25), wrist_limit, wrist_limit)
	var axes: Array[String] = ["x", "y", "z"]
	for i: int in range(3):
		grip_joint.set("angular_limit_%s/enabled" % axes[i], true)
		grip_joint.set("angular_limit_%s/lower_angle" % axes[i], -lims[i])
		grip_joint.set("angular_limit_%s/upper_angle" % axes[i], lims[i])
	grip_joint.node_a = grip_joint.get_path_to(forearm)
	grip_joint.node_b = grip_joint.get_path_to(self)
	global_transform = keep
	if is_in_group(PROP_GROUP):
		remove_from_group(PROP_GROUP)


## Breaks the grip joint and the lodge joint. Fists never become props; other weapons do.
func detach() -> void:
	if grip_joint != null:
		grip_joint.node_a = NodePath("")
		grip_joint.node_b = NodePath("")
		remove_child(grip_joint)
		grip_joint.free()
		grip_joint = null
	holder = null
	hand = ""
	lodged_in = null
	if not is_fist and is_inside_tree() and not is_in_group(PROP_GROUP):
		add_to_group(PROP_GROUP)


func _add_shape(shape: Shape3D, mesh: Mesh, pos: Vector3, basis_in: Basis, color: Color) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis_in, pos)
	add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis_in, pos)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6 if color.s < 0.15 and color.v > 0.5 else 0.0
	mat.roughness = 0.45 if mat.metallic > 0.0 else 0.85
	mi.material_override = mat
	add_child(mi)


func _add_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var s := BoxShape3D.new()
	s.size = size
	var m := BoxMesh.new()
	m.size = size
	_add_shape(s, m, pos, Basis(), color)


func _add_sphere(r: float, pos: Vector3, color: Color) -> void:
	var s := SphereShape3D.new()
	s.radius = r
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	_add_shape(s, m, pos, Basis(), color)


func _add_capsule(r: float, h: float, pos: Vector3, color: Color) -> void:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = maxf(h, r * 2.0)
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = s.height
	_add_shape(s, m, pos, Basis(), color)


func _add_cylinder(r: float, h: float, pos: Vector3, b: Basis, color: Color) -> void:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	_add_shape(s, m, pos, b, color)
