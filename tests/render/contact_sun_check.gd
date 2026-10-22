extends Node
## Contact blobs against the sun shadow: the sand alone under a top camera, a sun with shadows and a wall that throws
## a shadow over the -X half, one foot blob in the sun (+X) and one in the wall's shadow (-X). Draws the frame with
## the sand's contact_sun_fade at 0 and at 1 and prints, for each, the luminance at both blob centres and on plain
## sand beside them: with the fade the blob in the sun should match the old one and the one in the shadow should
## nearly vanish. Prints CONTACT_SUN lines; optional --out=DIR saves both frames.
## xvfb-run -a -s "-screen 0 640x360x24" godot --path . --rendering-driver opengl3 --resolution 640x360 \
##     --fixed-fps 60 res://tests/render/contact_sun_check.tscn -- --quality=2 [--out=DIR]
## Never part of the check suite.

const SUN_X: float = 1.2
const SHADE_X: float = -1.2

var _sand: SandSurface = null
var _cam: Camera3D = null
var _frame: int = 0
var _fades: Array[float] = [0.0, 1.0]
var _out: String = ""


func _ready() -> void:
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "2")))
	_out = Flags.get_arg("out", "")
	_sand = SandSurface.new()
	add_child(_sand)
	_sand.setup(Tuning.shared().arena_radius)
	# The arena's sun (height, colour, energy) and environment (ambient, ACES), the sun turned to come from +X so a
	# wall at -X shades the -X half.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-Arena.SUN_ELEVATION, PI * 0.5, 0.0)
	sun.light_color = Arena.SUN_COLOR
	sun.light_energy = Arena.SUN_ENERGY
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.72, 0.64)
	env.ambient_light_energy = Arena.AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = Arena.EXPOSURE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sand.refresh_ambient()
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 1.5, 8.0)
	wall.mesh = box
	wall.position = Vector3(-0.3, 0.75, 0.0)
	add_child(wall)
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 4.0, 0.0)
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_cam.fov = 60.0
	add_child(_cam)
	_cam.current = true
	var t: Tuning = Tuning.shared()
	var blobs: Array[Vector4] = []
	var axes: Array[Vector4] = []
	for x: float in [SUN_X, SHADE_X]:
		blobs.append(ContactShadow.blob(Vector3(x, t.sand_contact_foot_rest, 0.0), 0.0, t.sand_contact_foot_r,
				t.sand_contact_foot_h, t.sand_contact_dark, t.sand_contact_spread))
		axes.append(ContactShadow.axis(Vector3(0, 0, -1), t.sand_contact_foot_aspect))
	_sand.set_contacts(ContactShadow.pack(blobs), ContactShadow.pack_axes(blobs, axes))


func _process(_d: float) -> void:
	_frame += 1
	var i: int = _frame / 20
	if i >= _fades.size():
		get_tree().quit()
		return
	if _frame % 20 == 1:
		_sand.get("_material").set_shader_parameter("contact_sun_fade", _fades[i])
	elif _frame % 20 == 10:
		var img: Image = get_viewport().get_texture().get_image()
		if _out != "":
			DirAccess.make_dir_recursive_absolute(_out)
			img.save_png("%s/contact_sun_fade%d.png" % [_out, int(_fades[i])])
		print("CONTACT_SUN fade=%.0f sun_blob=%.1f sun_plain=%.1f shade_blob=%.1f shade_plain=%.1f" % [_fades[i],
				_lum(img, Vector3(SUN_X, 0, 0)), _lum(img, Vector3(SUN_X, 0, 0.9)),
				_lum(img, Vector3(SHADE_X, 0, 0)), _lum(img, Vector3(SHADE_X, 0, 0.9))])


## Mean luminance (0..255) of a 5x5 pixel patch where world point `p` lands.
func _lum(img: Image, p: Vector3) -> float:
	var c: Vector2 = _cam.unproject_position(p) * Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var s: float = 0.0
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var col: Color = img.get_pixel(clampi(int(c.x) + dx, 0, img.get_width() - 1), clampi(int(c.y) + dy, 0, img.get_height() - 1))
			s += 255.0 * (0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b)
	return s / 25.0
