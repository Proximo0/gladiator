class_name TitleBackdrop
extends Node3D
## The live 3D scene behind the menus: the arena with its crowd, two gladiators squared up in the middle of the sand
## (real Fighters on neutral input with a little guard sway, far enough apart that nothing ever connects), dust
## motes drifting through warm low sun and haze, and a camera on a slow drift (TitleCam). MenuFlow builds it when a
## menu opens and frees it when a fight starts. `frame_x` slides the pair right of centre while the landscape title
## menu covers the left side; it eases there, so switching screens never jumps the camera.

const HALF_GAP: float = 1.75  ## m from the centre to each fighter (3.5 m apart: no weapon here reaches that)
const FOV: float = 46.0
const FRAME_EASE: float = 1.6  ## 1/s, how fast the framing follows a new frame_x
const MOTES: int = 150
const HAZE_DENSITY: float = 0.013
const LOADOUTS: Array = [
	{"weapon": "gladius", "offhand": "shield_round", "armor": {"head": "helm_iron", "torso": "cuirass_leather", "thigh_l": "greaves_iron"}},
	{"weapon": "axe", "offhand": "", "armor": {"head": "helm_leather", "torso": "mail", "upper_arm_l": "bracers_iron"}},
]

var arena: Arena
var cam: Camera3D
var fighters: Array[Fighter] = []
var frame_x: float = 0.0
var _frame_now: float = 0.0
var _t: float = 0.0
var _tick: int = 0
var _with_fighters: bool = true


func _init(with_fighters: bool = true) -> void:
	name = "MenuBackdrop"
	_with_fighters = with_fighters
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	cam = Camera3D.new()
	cam.name = "TitleCam"
	cam.fov = FOV
	add_child(cam)


func _ready() -> void:
	_warm_haze()
	_add_rim_light()
	_add_motes()
	if _with_fighters:
		_add_fighters()
		arena.stock_racks(LOADOUTS)  # the racks hold the pair's spares
	cam.current = true
	_frame_now = frame_x
	_place_camera()
	if arena.has_method("set_crowd_excitement"):
		arena.set_crowd_excitement(0.25)


func _process(delta: float) -> void:
	_t += delta
	_frame_now += (frame_x - _frame_now) * (1.0 - exp(-FRAME_EASE * delta))
	_place_camera()


func _physics_process(_delta: float) -> void:
	_tick += 1
	for i: int in fighters.size():
		var f: Fighter = fighters[i]
		if not is_instance_valid(f):
			continue
		# Guard sway: each fighter shifts its weapon hand slowly, out of phase, like sizing the other up.
		var ph: float = float(_tick) / 60.0 + float(i) * 2.3
		var inp := FighterInput.new()
		inp.aim_x = int(220.0 * sin(ph * 0.55) + 90.0 * sin(ph * 1.3))
		inp.aim_y = int(160.0 + 140.0 * sin(ph * 0.41 + 1.0))
		f.apply_input(inp)


func _place_camera() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16.0, 9.0)
	var p: Dictionary = TitleCam.pose(_t, _frame_now, FOV, vp.x / maxf(vp.y, 1.0))
	cam.look_at_from_position(p["pos"], p["target"], Vector3.UP)


## Thicker, warmer haze than in a fight: the dust hanging in low afternoon sun.
func _warm_haze() -> void:
	var we: WorldEnvironment = arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env: Environment = we.environment
	env.fog_density = HAZE_DENSITY
	env.fog_light_color = Color(0.93, 0.72, 0.48)
	env.fog_sun_scatter = 0.35
	env.ambient_light_color = Color(0.86, 0.7, 0.55)


## A warm back light low over the far wall, so the fighters get a bright rim against the stands.
func _add_rim_light() -> void:
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(1.0, 0.68, 0.38)
	rim.light_energy = 0.55
	rim.shadow_enabled = false
	var a: float = TitleCam.ANGLE0 + PI
	var from: Vector3 = Vector3(cos(a), 0.35, sin(a))
	rim.transform = Transform3D(Basis.looking_at(-from, Vector3.UP), Vector3.ZERO)
	add_child(rim)


## Dust motes: tiny warm specks drifting on the air round the pair, fading in and out.
func _add_motes() -> void:
	var p := CPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = MOTES
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.6, 1.8, 3.6)  # well inside the camera path: no blurry blob filling the lens
	p.position = Vector3(0.0, 1.9, 0.0)
	p.direction = Vector3(1.0, 0.25, 0.3)
	p.spread = 60.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.22
	p.gravity = Vector3(0.02, -0.012, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.86, 0.62, 0.0))
	ramp.set_color(1, Color(1.0, 0.86, 0.62, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.88, 0.66, 0.85))
	ramp.add_point(0.8, Color(1.0, 0.84, 0.6, 0.7))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.026, 0.026)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.no_depth_test = false
	m.disable_receive_shadows = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


func _add_fighters() -> void:
	for side: int in 2:
		var f := Fighter.new()
		f.name = "TitleFighter%d" % side
		add_child(f)
		var tf: Transform3D = Arena.spawn_transform(side, 100.0)
		tf.origin = tf.origin.normalized() * HALF_GAP
		f.global_transform = tf
		f.look_seed = 7 + side * 31
		f.setup(LoadoutRules.sanitize(LOADOUTS[side]), side, Tuning.shared())
		fighters.append(f)
	fighters[0].opponent = fighters[1]
	fighters[1].opponent = fighters[0]
