class_name BladeGlow
extends Node3D
## Presentation of an energy blade (the laser sword), a child of its Weapon: a soft light that flickers, a fading
## motion trail ribbon, and a hum whose pitch follows the blade's speed. Never touches physics. Not created in
## headless runs. Quality comes from GfxQuality (light and trail off or shorter on low).

const FLICKER_HZ: float = 38.0
const FLICKER_AMOUNT: float = 0.06

var _weapon: Weapon = null
var _glow: Color = Color(0.2, 1.0, 0.8)
var _y0: float = 0.0
var _y1: float = 1.0
var _light: OmniLight3D = null
var _trail_mi: MeshInstance3D = null
var _trail_mesh: ImmediateMesh = null
var _trail: BladeTrailLogic = BladeTrailLogic.new()
var _hum: AudioStreamPlayer3D = null
var _pitch: float = LaserHumLogic.PITCH_IDLE
var _clock: float = 0.0
var _light_base: float = 0.0


func setup(w: Weapon, glow: Color, y0: float, y1: float) -> void:
	_weapon = w
	_glow = glow
	_y0 = y0
	_y1 = y1
	_trail.max_samples = GfxQuality.pick_i(GfxQuality.BLADE_TRAIL_SAMPLES)
	_light_base = GfxQuality.pick_f(GfxQuality.BLADE_LIGHT_ENERGY)
	if _light_base > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = glow
		_light.light_energy = _light_base
		_light.omni_range = 2.2
		_light.shadow_enabled = false
		_light.position = Vector3(0, (y0 + y1) * 0.5, 0)
		add_child(_light)
	if _trail.max_samples > 0:
		_trail_mesh = ImmediateMesh.new()
		_trail_mi = MeshInstance3D.new()
		_trail_mi.mesh = _trail_mesh
		_trail_mi.top_level = true
		_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		_trail_mi.material_override = mat
		add_child(_trail_mi)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = LaserSynth.hum()
	_hum.unit_size = 4.0
	_hum.max_distance = 30.0
	_hum.volume_db = LaserHumLogic.GAIN_IDLE_DB
	_hum.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_hum.position = Vector3(0, (y0 + y1) * 0.5, 0)
	add_child(_hum)


func _process(delta: float) -> void:
	if _weapon == null or not is_instance_valid(_weapon) or not _weapon.is_inside_tree():
		return
	_clock += delta
	var xf: Transform3D = _weapon.global_transform
	var tip: Vector3 = xf * Vector3(0, _y1, 0)
	var base: Vector3 = xf * Vector3(0, _y0, 0)
	var speed: float = _weapon.point_velocity(tip).length()
	if _hum != null:
		if not _hum.playing:
			_hum.play()
		_pitch = LaserHumLogic.glide(_pitch, LaserHumLogic.pitch_for(speed), delta)
		_hum.pitch_scale = _pitch
		_hum.volume_db = LaserHumLogic.gain_db_for(speed)
	if _light != null:
		_light.light_energy = _light_base * (1.0 + FLICKER_AMOUNT * sin(_clock * FLICKER_HZ * TAU))
	if _trail_mesh != null:
		_trail.step(delta)
		_trail.push(base, tip, speed)
		_rebuild_trail()


func _rebuild_trail() -> void:
	_trail_mesh.clear_surfaces()
	var n: int = _trail.count()
	if n < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in n:
		var a: float = _trail.alpha(i) * 0.55
		_trail_mesh.surface_set_color(Color(_glow.r, _glow.g, _glow.b, a * 0.2))
		_trail_mesh.surface_add_vertex(_trail.base_at(i))
		_trail_mesh.surface_set_color(Color(_glow.r, _glow.g, _glow.b, a))
		_trail_mesh.surface_add_vertex(_trail.tip_at(i))
	_trail_mesh.surface_end()
