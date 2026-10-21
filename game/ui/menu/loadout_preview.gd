class_name LoadoutPreview
extends SubViewportContainer
## Rotating 3D preview of one or two real Fighters (the same class a match builds, frozen in their rest pose) in a
## private world. Call show_loadouts([a, b]); a null entry leaves that side empty. Rebuilds are debounced.

const SPIN_RATE: float = 0.45  ## rad/s
const CAM_DIST: float = 4.7
const CAM_HEIGHT: float = 1.2
const LOOK_Y: float = 0.9
const SPACING: float = 0.75
const REBUILD_DELAY_S: float = 0.12

var _vp: SubViewport
var _rig: Node3D
var _stage: Node3D
var _fighters: Array = []
var _pending: Array = []
var _timer: float = -1.0
var _spin: float = 0.4


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
	env.ambient_light_color = Color(0.62, 0.54, 0.45)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.9
	cm.bottom_radius = 1.9
	cm.height = 0.05
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.5, 0.38, 0.24)
	sand.roughness = 1.0
	cm.material = sand
	disc.mesh = cm
	disc.position = Vector3(0.0, -0.03, 0.0)
	_stage.add_child(disc)
	_rig = Node3D.new()
	_vp.add_child(_rig)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.position = Vector3(0.0, CAM_HEIGHT, -CAM_DIST)
	_rig.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, LOOK_Y, 0.0))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.position = Vector3(1.0, 3.0, -2.0)
	_rig.add_child(sun)
	sun.look_at_from_position(sun.position, Vector3(0.0, 1.0, 0.0))
	_rig.rotation.y = _spin


func show_loadouts(loadouts: Array) -> void:
	_pending = loadouts.duplicate(true)
	_timer = REBUILD_DELAY_S if not _fighters.is_empty() else 0.0


func _process(delta: float) -> void:
	_spin += delta * SPIN_RATE
	_rig.rotation.y = _spin
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
	for i: int in n:
		if not (_pending[i] is Dictionary):
			continue
		var f := Fighter.new()
		f.name = "Preview%d" % i
		f.set_physics_process(false)
		_stage.add_child(f)
		var x: float = (float(n - 1) * 0.5 - float(i)) * 2.0 * SPACING if n > 1 else 0.0  # seen from -Z, +X is screen-left
		f.global_transform = Transform3D(Basis(), Vector3(x, 0.0, 0.0))
		f.setup(_pending[i], i, Tuning.shared())
		for part: Variant in f.parts.values():
			(part as RigidBody3D).freeze = true
		for w: Variant in [f.weapon, f.offhand, f.fist_l, f.fist_r]:
			if w != null:
				(w as RigidBody3D).freeze = true
		_fighters.append(f)
