class_name LoadoutPreview
extends SubViewportContainer
## 3D preview of one or two real Fighters (the same class a match builds, standing in their guard pose with neutral
## input) on a stone plinth, in a private world with warm key, fill and rim lights. Call show_loadouts([a, b]); a
## null entry leaves that side empty. Rebuilds are debounced.
## One fighter: a turntable that turns all the way round. Two: a slow sway either side of the front view, so both
## stay in view. Dragging across it (mouse or finger, see drag()) turns it by hand; it picks up turning again after
## a moment. show_weapon(id, locked) adds a weapon close-up beside a lone fighter, slowly spinning, shown as a dark
## silhouette while it is locked.

const TURN_RATE: float = 0.42  ## rad/s of the turntable
const SWAY_RATE: float = 0.7  ## rad/s of the sway phase (two fighters)
const SWAY_ANGLE: float = 0.55  ## rad each side of the front view
const CAM_DIST: float = 4.7
const CAM_DIST_SOLO: float = 3.9
const CAM_HEIGHT: float = 1.2
const LOOK_Y: float = 0.9
const PREVIEW_HFOV: float = 42.0  ## horizontal field of view, degrees (a frame taller than wide)
const PREVIEW_VFOV: float = 34.0  ## vertical field of view in a frame wider than tall (a phone's preview strip)
const SPACING: float = 0.75
const REBUILD_DELAY_S: float = 0.12
const DRAG_RATE: float = 0.011  ## rad per layout unit dragged
const DRAG_HOLD_S: float = 1.6  ## the turntable waits this long after a drag before turning again
const SHOWCASE_X: float = 0.62  ## weapon close-up across the view (fraction of the half-width, from the centre)
const SHOWCASE_H: float = 1.25  ## m the longest side of a weapon close-up is scaled to
const SHOWCASE_SPIN: float = 0.9  ## rad/s
const SOLO_SHIFT: float = 0.36  ## m the lone fighter moves left to make room for the weapon close-up

var _vp: SubViewport
var _rig: Node3D
var _cam: Camera3D
var _stage: Node3D
var _fighters: Array = []
var _pending: Array = []
var _timer: float = -1.0
var _spin: float = 0.0
var _angle: float = 0.0
var _drag_hold: float = 0.0
var _show_pivot: Node3D
var _show_weapon: Node3D = null
var _show_id: String = ""
var _show_locked: bool = false
var _show_spin: float = 0.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.55, 0.44)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_build_plinth()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 1.0, 12.0)
	fcs.shape = box
	fcs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(fcs)
	_stage.add_child(floor_body)
	_rig = Node3D.new()
	_vp.add_child(_rig)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH  # a narrow preview must still hold both fighters, shields and sway
	_cam.fov = PREVIEW_HFOV
	_rig.add_child(_cam)
	_place_cam(CAM_DIST)
	_cam.current = true
	# Key light (warm, high front left), fill (cool, low right) and rim (hot, from behind): they turn with the camera,
	# so the fighter is lit the same from every side.
	_light(Vector3(1.4, 3.2, -2.4), Color(1.0, 0.86, 0.68), 1.35)
	_light(Vector3(-2.2, 1.0, -1.6), Color(0.72, 0.78, 0.92), 0.35)
	_light(Vector3(-0.6, 2.0, 3.0), Color(1.0, 0.62, 0.32), 1.1)
	_show_pivot = Node3D.new()
	_show_pivot.name = "Showcase"
	_cam.add_child(_show_pivot)


func _light(from: Vector3, col: Color, energy: float) -> void:
	var l := DirectionalLight3D.new()
	l.light_color = col
	l.light_energy = energy
	_rig.add_child(l)
	l.look_at_from_position(from, Vector3(0.0, 1.0, 0.0))


## A round travertine plinth with a bronze rim and a darker sand top.
func _build_plinth() -> void:
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.95
	cm.bottom_radius = 1.05
	cm.height = 0.24
	cm.radial_segments = 48
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.46, 0.38, 0.29)
	stone.roughness = 1.0
	cm.material = stone
	base.mesh = cm
	base.position = Vector3(0.0, -0.13, 0.0)
	_stage.add_child(base)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 0.96
	tm.rings = 48
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.5, 0.33, 0.16)
	bronze.metallic = 0.6
	bronze.roughness = 0.5
	tm.material = bronze
	rim.mesh = tm
	rim.position = Vector3(0.0, -0.01, 0.0)
	_stage.add_child(rim)
	var top := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.9
	dm.bottom_radius = 0.9
	dm.height = 0.02
	dm.radial_segments = 48
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.36, 0.27, 0.17)
	sand.roughness = 1.0
	sand.specular_mode = BaseMaterial3D.SPECULAR_DISABLED  # no glare streaks on the flat top
	dm.material = sand
	top.mesh = dm
	top.position = Vector3(0.0, -0.004, 0.0)  # lifted clear of the stone's top face (they z-fought in stripes)
	_stage.add_child(top)


func _place_cam(dist: float) -> void:
	_cam.position = Vector3(0.0, CAM_HEIGHT, -dist)
	_cam.look_at_from_position(_cam.position, Vector3(0.0, LOOK_Y, 0.0))


func show_loadouts(loadouts: Array) -> void:
	_pending = loadouts.duplicate(true)
	_timer = REBUILD_DELAY_S if not _fighters.is_empty() else 0.0


## A weapon close-up beside a lone fighter: `id` "" for none; a `locked` weapon shows as a dark silhouette.
func show_weapon(id: String, locked: bool) -> void:
	if id == _show_id and locked == _show_locked:
		return
	_show_id = id
	_show_locked = locked
	if _show_weapon != null:
		_show_pivot.remove_child(_show_weapon)
		_show_weapon.free()
		_show_weapon = null
	if id == "" or CombatData.weapon(id).is_empty():
		return
	# Build the real weapon, then keep only copies of its meshes: a physics body ignores any scale above it, and the
	# close-up scales every weapon to one height.
	var w := Weapon.new()
	w.build(CombatData.weapon(id))
	var holder := Node3D.new()
	var body := Node3D.new()
	holder.add_child(body)
	for c: Node in w.get_children():
		if c is VisualInstance3D or (c is Node3D and not (c is CollisionShape3D) and not (c is Joint3D)):
			body.add_child(c.duplicate())
	var span: float = maxf(w.length, 0.3)
	var k: float = SHOWCASE_H / maxf(span, SHOWCASE_H * 0.5)  # small weapons grow, long ones shrink
	holder.scale = Vector3.ONE * k
	# Centre it on its pivot: the grip is at the origin and the weapon runs up +Y.
	body.position = Vector3(0.0, -(w.tip_local.y - span * 0.5) if w.shape_kind != "shield" else 0.0, 0.0)
	w.free()
	if locked:
		_silhouette(body)
	_show_weapon = holder
	_show_pivot.add_child(holder)
	_fit_showcase()


## Dark, flat iron for a locked weapon: its outline shows, its details don't.
static func _silhouette(n: Node) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.05, 0.04)
	m.roughness = 0.6
	m.metallic = 0.3
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = m


func _fit_showcase() -> void:
	var solo: bool = _solo()
	_show_pivot.visible = solo and _show_weapon != null
	_cam.h_offset = SOLO_SHIFT if _show_pivot.visible else 0.0
	if not _show_pivot.visible:
		return
	var d: float = 2.6
	var half_w: float = d * _half_tan()
	# h_offset moves the whole view, the close-up with it: add it back so the weapon keeps its place.
	_show_pivot.position = Vector3(half_w * SHOWCASE_X + _cam.h_offset, 0.05, -d)


## Turns the view by a drag of `dx` layout units (a finger or the mouse across the preview).
func drag(dx: float) -> void:
	_angle += dx * DRAG_RATE
	_drag_hold = DRAG_HOLD_S


func _solo() -> bool:
	var n: int = 0
	for l: Variant in _pending:
		if l is Dictionary:
			n += 1
	return n == 1


## tan of half the horizontal view angle for the frame's current shape.
func _half_tan() -> float:
	if _cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		return tan(deg_to_rad(PREVIEW_VFOV) * 0.5) * size.x / maxf(size.y, 1.0)
	return tan(deg_to_rad(PREVIEW_HFOV) * 0.5)


## A wide, short frame keeps the fighter's full height in view (fixed vertical angle); a tall one keeps its width.
func _fit_lens() -> void:
	var wide: bool = size.x > size.y * 1.05
	var mode: Camera3D.KeepAspect = Camera3D.KEEP_HEIGHT if wide else Camera3D.KEEP_WIDTH
	if mode != _cam.keep_aspect:
		_cam.keep_aspect = mode
		_cam.fov = PREVIEW_VFOV if wide else PREVIEW_HFOV
		_fit_showcase()


func _process(delta: float) -> void:
	_fit_lens()
	_drag_hold = maxf(0.0, _drag_hold - delta)
	var solo: bool = _solo()
	if solo:
		if _drag_hold <= 0.0:
			_angle += delta * TURN_RATE
		_rig.rotation.y = _angle
	else:
		if _drag_hold <= 0.0:
			_spin += delta * SWAY_RATE
			_angle = lerpf(_angle, 0.0, 1.0 - exp(-1.5 * delta))
		_rig.rotation.y = sin(_spin) * SWAY_ANGLE + _angle
	if _show_weapon != null:
		_show_spin += delta * SHOWCASE_SPIN
		_show_weapon.rotation = Vector3(0.18, _show_spin, 0.12)
	if _timer >= 0.0:
		_timer -= delta
		if _timer < 0.0:
			_rebuild()


func _rebuild() -> void:
	for f: Variant in _fighters:
		if is_instance_valid(f):
			_stage.remove_child(f as Node)
			(f as Node).free()
	_fighters = []
	var n: int = _pending.size()
	_place_cam(CAM_DIST_SOLO if _solo() else CAM_DIST)
	for i: int in n:
		if not (_pending[i] is Dictionary):
			continue
		var f := Fighter.new()
		f.name = "Preview%d" % i
		_stage.add_child(f)
		var x: float = (float(n - 1) * 0.5 - float(i)) * 2.0 * SPACING if n > 1 else 0.0  # seen from -Z, +X is screen-left
		f.global_transform = Transform3D(Basis(), Vector3(x, 0.0, 0.0))
		f.setup(_pending[i], i, Tuning.shared())
		_fighters.append(f)
	_fit_showcase()
