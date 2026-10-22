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
	# `look` picks the placeholder build when it differs from the physical shape (premium blades are "sword" shaped
	# for contact, AI and sound but look different).
	var look: String = str(d.get("look", shape_kind))
	match look:
		"katana":
			_build_katana(tip, col)
		"laser":
			_build_laser(tip, parse_color(d.get("glow", "#33ffcc")), col)
		"machete":
			_build_machete(tip, col)
		"falchion":
			_build_falchion(tip, col)
		"mace":
			_build_mace(tip, col)
		"sledge":
			_build_sledge(tip, col)
		"warhammer":
			_build_warhammer(tip, col)
		"halberd":
			_build_halberd(tip, col)
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
			_add_box(Vector3(0.26, 0.04, 0.04), Vector3(0, tip - 0.02, 0), steel * 0.7)
			for i: int in range(5):
				_add_box(Vector3(0.012, 0.012, 0.09), Vector3(-0.1 + 0.05 * i, tip - 0.03, 0.06), steel * 0.7)
		"scutum":
			# Tall curved board (assets/armor/scutum.glb, grip at the boss): one box collider over the face.
			var half_h: float = length * 0.5
			tip_local = Vector3(0, half_h, 0.06)
			com_local = Vector3(0, 0, 0.05)
			_add_box(Vector3(float(d.get("width", 0.68)) - 0.02, length - 0.02, 0.06), Vector3(0, 0, 0.06), col)
			_add_box(Vector3(0.14, 0.03, 0.03), Vector3.ZERO, wood)
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
	_use_art_mesh()


## Art slot: res://assets/weapons/<id>.glb, or the def's "art" path (built in Houdini by tools/houdini/build_weapons.py: +Y along the weapon,
## origin at the grip, edges toward +-X) replaces the primitive meshes. Visual only: the collision shapes stay.
func _use_art_mesh() -> void:
	var path: String = str(def.get("art", "res://assets/weapons/%s.glb" % weapon_id))
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return
	for c: Node in get_children():
		if c is MeshInstance3D and not c.has_meta("glow"):
			(c as MeshInstance3D).visible = false
	var art: Node3D = scene.instantiate() as Node3D
	art.name = "Art"
	# Houdini marks every material alpha-blend (depth pre-pass); that sorts and flickers, so force opaque.
	_force_opaque_art(art)
	if weapon_id == "rake":
		# The art was built at 1.6 m with a 0.36 m head; the collider is 1.45 m with a 0.26 m crossbar (balance_rake.md).
		# The grip end stays at -0.2 m: y' = RAKE_ART_SCALE.y * y + offset.
		art.scale = RAKE_ART_SCALE
		art.position = Vector3(0, -RAKE_ART_BOTTOM * (1.0 - RAKE_ART_SCALE.y), 0)
	add_child(art)


## Rake art fit: x 0.36 -> 0.26 m, y 1.6 -> 1.45 m (z kept), see `_use_art_mesh`.
const RAKE_ART_SCALE: Vector3 = Vector3(0.7222, 0.90625, 1.0)
const RAKE_ART_BOTTOM: float = 0.2
## Blade material of an energy weapon: kept emissive and unshaded, never alpha-blended.
const ART_ENERGY_MATERIAL: String = "energy"
const ART_ENERGY_EMISSION: float = 2.5


## Makes every surface material of an art scene opaque (the glb's own alpha flags are import noise). The material
## named "energy" becomes an unshaded emissive white-hot core; the game's halo (meta "glow") provides the glow.
static func _force_opaque_art(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			mi.mesh = mi.mesh.duplicate() as Mesh
			for s: int in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null:
					continue
				var o := m.duplicate() as BaseMaterial3D
				o.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				o.albedo_color.a = 1.0
				if o.resource_name == ART_ENERGY_MATERIAL:
					o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					o.emission_enabled = true
					o.emission_energy_multiplier = ART_ENERGY_EMISSION
				mi.set_surface_override_material(s, o)
	for c: Node in root.get_children():
		_force_opaque_art(c)


## Dai-katana placeholder: a long wrapped tsuka, a round tsuba and a slightly curved blade of tilted segments
## (the tip bends toward the cutting edge, +X). Visual detail is mesh only; colliders are the tsuka, tsuba and segments.
const KATANA_SEGMENTS: int = 6
const KATANA_CURVE: float = 0.04
const KATANA_WRAPS: int = 7


func _build_katana(tip: float, steel_col: Color) -> void:
	var guard_y: float = maxf(tip - edge_len - 0.03, 0.06)
	var cord := Color(0.1, 0.12, 0.2)
	var gold := Color(0.62, 0.5, 0.2)
	var handle_len: float = guard_y + grip_offset
	_add_box(Vector3(0.032, handle_len, 0.026), Vector3(0, (guard_y - grip_offset) * 0.5, 0), cord)
	for i: int in range(KATANA_WRAPS):
		var wy: float = -grip_offset + handle_len * (float(i) + 0.5) / float(KATANA_WRAPS)
		_add_visual(_box_mesh(Vector3(0.036, 0.011, 0.03)), Vector3(0, wy, 0), Basis(Vector3(0, 0, 1), 0.5), Color(0.78, 0.68, 0.42))
	_add_box(Vector3(0.04, 0.025, 0.034), Vector3(0, -grip_offset - 0.008, 0), gold)
	_add_cylinder(0.052, 0.008, Vector3(0, guard_y, 0), Basis(), Color(0.16, 0.14, 0.1))
	_add_box(Vector3(0.034, 0.03, 0.02), Vector3(0, guard_y + 0.02, 0), gold)
	var y0: float = guard_y + 0.035
	var span: float = tip - y0
	for i: int in range(KATANA_SEGMENTS):
		var s0: float = float(i) / float(KATANA_SEGMENTS)
		var s1: float = float(i + 1) / float(KATANA_SEGMENTS)
		var p0 := Vector3(KATANA_CURVE * s0 * s0, y0 + span * s0, 0)
		var p1 := Vector3(KATANA_CURVE * s1 * s1, y0 + span * s1, 0)
		var dir: Vector3 = p1 - p0
		var tilt: float = atan2(dir.x, dir.y)
		var wide: float = lerpf(0.04, 0.024, s1)
		_add_shape_box(Vector3(wide, dir.length() + 0.004, 0.012), (p0 + p1) * 0.5, Basis(Vector3(0, 0, 1), -tilt), steel_col)


## Laser sword placeholder: a dark hilt with an emitter, an emissive white-hot core and a translucent halo of `glow`
## colour (the halo carries meta "glow" so a Houdini glb never hides it), plus a BladeGlow node (light, trail, hum).
func _build_laser(tip: float, glow: Color, hilt_col: Color) -> void:
	var guard_y: float = maxf(tip - edge_len - 0.03, 0.06)
	_add_box(Vector3(0.034, guard_y + grip_offset, 0.034), Vector3(0, (guard_y - grip_offset) * 0.5, 0), hilt_col)
	_add_box(Vector3(0.046, 0.03, 0.046), Vector3(0, -grip_offset, 0), Color(0.6, 0.62, 0.66))
	_add_box(Vector3(0.05, 0.035, 0.05), Vector3(0, guard_y - 0.01, 0), Color(0.7, 0.72, 0.76))
	_add_box(Vector3(0.1, 0.012, 0.022), Vector3(0, guard_y - 0.03, 0), Color(0.6, 0.62, 0.66))
	var blade_len: float = tip - guard_y
	var mid := Vector3(0, guard_y + blade_len * 0.5, 0)
	var blade_shape := BoxShape3D.new()
	blade_shape.size = Vector3(0.04, blade_len, 0.025)
	var blade_cs := CollisionShape3D.new()  # collider only: the visible blade is the core and halo below
	blade_cs.shape = blade_shape
	blade_cs.position = mid
	add_child(blade_cs)
	var core := CapsuleMesh.new()
	core.radius = 0.011
	core.height = blade_len
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = glow.lerp(Color.WHITE, 0.85)
	core_mat.emission_enabled = true
	core_mat.emission = glow.lerp(Color.WHITE, 0.6)
	core_mat.emission_energy_multiplier = 3.0
	var core_mi := _add_visual(core, mid, Basis(), glow)
	core_mi.material_override = core_mat
	var halo := CapsuleMesh.new()
	halo.radius = 0.03
	halo.height = blade_len + 0.03
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.albedo_color = Color(glow.r, glow.g, glow.b, 0.32)
	halo_mat.emission_enabled = true
	halo_mat.emission = glow
	var halo_mi := _add_visual(halo, mid, Basis(), glow)
	halo_mi.material_override = halo_mat
	halo_mi.set_meta("glow", true)
	halo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if DisplayServer.get_name() != "headless":
		var fx := BladeGlow.new()
		fx.name = "BladeGlow"
		add_child(fx)
		fx.setup(self, glow, guard_y, tip)


# --- unlockable weapons (docs/weapons_unlocks.md) ----------------------------------------------------------------
# Same frame as every weapon: grip at the origin, +Y to the tip, edges (and hammer beaks) toward +X. Colliders follow
# the striking parts; small decoration (rivets, flanges, wraps) is mesh only.

const UNLOCK_WOOD: Color = Color(0.42, 0.29, 0.16)
const UNLOCK_DARK_GRIP: Color = Color(0.12, 0.1, 0.08)
const MACHETE_SEGMENTS: int = 4
const FALCHION_SEGMENTS: int = 5
const MACE_FLANGES: int = 6


## Machete: a dark slab grip and a long single-edged blade that widens toward a clipped tip (spine straight along -X).
func _build_machete(tip: float, steel_col: Color) -> void:
	var blade_y: float = maxf(tip - edge_len - 0.02, 0.02)
	_add_box(Vector3(0.03, blade_y + grip_offset, 0.026), Vector3(0, (blade_y - grip_offset) * 0.5, 0), UNLOCK_DARK_GRIP)
	for i: int in range(3):
		var ry: float = -grip_offset + (blade_y + grip_offset) * (float(i) + 0.5) / 3.0
		_add_visual(_box_mesh(Vector3(0.034, 0.008, 0.03)), Vector3(0, ry, 0), Basis(), Color(0.6, 0.6, 0.62))
	_add_box(Vector3(0.05, 0.016, 0.03), Vector3(0.006, blade_y, 0), UNLOCK_DARK_GRIP)
	var span: float = tip - blade_y
	for i: int in range(MACHETE_SEGMENTS):
		var s0: float = float(i) / float(MACHETE_SEGMENTS)
		var s1: float = float(i + 1) / float(MACHETE_SEGMENTS)
		var w: float = lerpf(0.04, 0.062, s1)
		var h: float = span * (s1 - s0)
		if i == MACHETE_SEGMENTS - 1:
			w *= 0.75  # the clipped tip
		# Spine fixed at x = -0.02: the blade widens toward the edge (+X).
		_add_shape_box(Vector3(w, h + 0.002, 0.01), Vector3(-0.02 + w * 0.5, blade_y + span * (s0 + s1) * 0.5, 0), Basis(), steel_col)


## Falchion: a short grip, a straight crossguard and a broad single-edged blade that bellies out toward the tip and
## sweeps back to a point on the spine side.
func _build_falchion(tip: float, steel_col: Color) -> void:
	var guard_y: float = maxf(tip - edge_len - 0.03, 0.06)
	_add_box(Vector3(0.032, guard_y + grip_offset, 0.028), Vector3(0, (guard_y - grip_offset) * 0.5, 0), Color(0.3, 0.2, 0.12))
	_add_box(Vector3(0.045, 0.04, 0.04), Vector3(0, -grip_offset - 0.015, 0), steel_col * 0.8)
	_add_box(Vector3(0.17, 0.022, 0.032), Vector3(0, guard_y, 0), steel_col * 0.85)
	var y0: float = guard_y + 0.012
	var span: float = tip - y0
	var widths: Array[float] = [0.038, 0.046, 0.056, 0.062, 0.03]
	for i: int in range(FALCHION_SEGMENTS):
		var s0: float = float(i) / float(FALCHION_SEGMENTS)
		var s1: float = float(i + 1) / float(FALCHION_SEGMENTS)
		var w: float = widths[i]
		_add_shape_box(Vector3(w, span * (s1 - s0) + 0.002, 0.012), Vector3(-0.018 + w * 0.5, y0 + span * (s0 + s1) * 0.5, 0), Basis(), steel_col)


## Flanged mace: an iron-shod haft and a head of six radiating flanges around a core, with a knob on top.
func _build_mace(tip: float, steel_col: Color) -> void:
	var head_len: float = 0.17
	var head_y: float = tip - head_len * 0.5 - 0.02
	_add_box(Vector3(0.03, tip - head_len - 0.02 + grip_offset, 0.03), Vector3(0, (tip - head_len - 0.02 - grip_offset) * 0.5, 0), steel_col * 0.55)
	for i: int in range(4):
		var wy: float = -grip_offset + 0.03 + 0.035 * float(i)
		_add_visual(_box_mesh(Vector3(0.036, 0.02, 0.036)), Vector3(0, wy, 0), Basis(), Color(0.32, 0.2, 0.1))
	_add_capsule(0.032, head_len, Vector3(0, head_y, 0), steel_col * 0.8)
	_add_sphere(0.024, Vector3(0, tip - 0.016, 0), steel_col)
	for i: int in range(MACE_FLANGES):
		var a: float = TAU * float(i) / float(MACE_FLANGES)
		var b := Basis(Vector3.UP, a)
		_add_visual(_box_mesh(Vector3(0.05, head_len * 0.85, 0.008)), b * Vector3(0.042, 0, 0) + Vector3(0, head_y, 0), b, steel_col)
	# One collider wide enough to cover the flange tips.
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.066
	cyl.height = head_len * 0.85
	cs.shape = cyl
	cs.position = Vector3(0, head_y, 0)
	add_child(cs)


## Sledgehammer: a long wooden handle and a heavy steel block across the top (faces toward +X and -X).
func _build_sledge(tip: float, steel_col: Color) -> void:
	var head_h: float = 0.085
	_add_box(Vector3(0.034, tip - head_h + grip_offset, 0.03), Vector3(0, (tip - head_h - grip_offset) * 0.5, 0), UNLOCK_WOOD)
	_add_box(Vector3(0.21, head_h, 0.085), Vector3(0, tip - head_h * 0.5, 0), steel_col)
	_add_visual(_box_mesh(Vector3(0.012, head_h + 0.004, 0.089)), Vector3(0.1, tip - head_h * 0.5, 0), Basis(), steel_col.lightened(0.3))
	_add_visual(_box_mesh(Vector3(0.012, head_h + 0.004, 0.089)), Vector3(-0.1, tip - head_h * 0.5, 0), Basis(), steel_col.lightened(0.3))


## War hammer (two-handed): a long haft with steel langets, a square hammer face toward -X, a curved beak (the "pick")
## toward +X and a short top spike.
func _build_warhammer(tip: float, steel_col: Color) -> void:
	var head_y: float = tip - 0.08
	_add_box(Vector3(0.032, tip - 0.04 + grip_offset, 0.032), Vector3(0, (tip - 0.04 - grip_offset) * 0.5, 0), UNLOCK_WOOD)
	_add_visual(_box_mesh(Vector3(0.036, 0.3, 0.036)), Vector3(0, head_y - 0.12, 0), Basis(), steel_col * 0.7)
	_add_box(Vector3(0.05, 0.07, 0.05), Vector3(0, head_y, 0), steel_col * 0.8)
	_add_box(Vector3(0.07, 0.055, 0.055), Vector3(-0.055, head_y, 0), steel_col)
	_add_shape_box(Vector3(0.07, 0.03, 0.028), Vector3(0.06, head_y - 0.005, 0), Basis(Vector3(0, 0, 1), -0.2), steel_col)
	_add_shape_box(Vector3(0.06, 0.018, 0.014), Vector3(0.12, head_y - 0.028, 0), Basis(Vector3(0, 0, 1), -0.45), steel_col)
	_add_box(Vector3(0.018, 0.06, 0.018), Vector3(0, tip - 0.025, 0), steel_col)


## Halberd: a long ash haft, a broad axe blade toward +X under a top spike, and a back fluke toward -X.
func _build_halberd(tip: float, steel_col: Color) -> void:
	_add_box(Vector3(0.032, tip - 0.16 + grip_offset, 0.032), Vector3(0, (tip - 0.16 - grip_offset) * 0.5, 0), UNLOCK_WOOD)
	_add_visual(_box_mesh(Vector3(0.036, 0.35, 0.036)), Vector3(0, tip - 0.36, 0), Basis(), steel_col * 0.65)
	_add_box(Vector3(0.026, 0.18, 0.016), Vector3(0, tip - 0.09, 0), steel_col)
	var blade_h: float = maxf(edge_len, 0.12)
	_add_box(Vector3(0.15, blade_h, 0.012), Vector3(0.09, tip - 0.06 - blade_h * 0.5, 0), steel_col)
	_add_shape_box(Vector3(0.09, 0.035, 0.012), Vector3(-0.055, tip - 0.17, 0), Basis(Vector3(0, 0, 1), 0.35), steel_col * 0.85)


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


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## A mesh with no collider (decoration).
func _add_visual(mesh: Mesh, pos: Vector3, basis_in: Basis, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis_in, pos)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_shape_box(size: Vector3, pos: Vector3, basis_in: Basis, color: Color) -> void:
	var s := BoxShape3D.new()
	s.size = size
	_add_shape(s, _box_mesh(size), pos, basis_in, color)


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
