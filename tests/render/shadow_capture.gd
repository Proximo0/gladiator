extends Node3D
## Shadow acne on small props: weapons and armor pieces on the sand in the real arena light, each shot taken with the
## sun's shadow on and then off in the same process. Acne is the speckle the shadow adds: pixels the shadow darkens
## by over ACNE_DROP whose 8 neighbours are mostly not darkened (a real cast shadow is a solid patch). Prints
## `SHADOWCAP <name> q<tier> <shot> acne=<n> shade=<n>` per shot (acne: speckle pixels, shade: all darkened pixels).
## Run in a real (xvfb) window: godot --path . --resolution 1280x720 --fixed-fps 60
## res://tests/render/shadow_capture.tscn -- --out=DIR --name=after [--quality=0|1|2] [--bias=B --normal_bias=N]
## (bias overrides sweep values without code changes). Never part of the check suite; writes only its PNGs.

const WEAPONS: PackedStringArray = ["longsword", "gladius", "axe", "mace", "warhammer", "halberd", "rake", "bat",
		"shield_round", "scutum"]
const ARMOR: PackedStringArray = ["galea", "manica_r", "manica_l", "greave_r", "greave_l"]
const SETTLE_FRAMES: int = 20
const ACNE_DROP: float = 0.12
const ACNE_MAX_NEIGHBOURS: int = 3

var _out: String = "/tmp/shadow_capture/"
var _name: String = "shot"
var _arena: Arena
var _cam: Camera3D
var _shots: Array = []  ## [tag, group, camera position, look target]
var _frame: int = 0
var _lit: Image = null


func _ready() -> void:
	var bias: float = -1.0
	var nbias: float = -1.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--quality="):
			GfxQuality.set_level(int(a.substr(10)))
		elif a.begins_with("--bias="):
			bias = float(a.substr(7))
		elif a.begins_with("--normal_bias="):
			nbias = float(a.substr(14))
	DirAccess.make_dir_recursive_absolute(_out)
	_arena = Arena.new()
	add_child(_arena)
	if bias >= 0.0:
		_arena.sun.shadow_bias = bias
	if nbias >= 0.0:
		_arena.sun.shadow_normal_bias = nbias
	print("SHADOWCAP %s q%d bias=%.3f normal_bias=%.3f" % [_name, GfxQuality.level, _arena.sun.shadow_bias,
			_arena.sun.shadow_normal_bias])
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	var w: Node3D = _weapons()
	var ar: Node3D = _armor()
	_shots.append(["weapons", w, Vector3(0.0, 1.6, 1.8), Vector3(0.0, 0.0, 0.2)])
	_shots.append(["armor", ar, Vector3(0.0, 0.9, 1.1), Vector3(0.0, 0.15, 0.0)])


func _weapons() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var x: float = -1.2
	for id: String in WEAPONS:
		var w := Weapon.new()
		w.build(CombatData.weapon(id))
		w.freeze = true
		g.add_child(w)
		w.transform = Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3(x, 0.06, 0.6))
		x += 0.25
	return g


func _armor() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var x: float = -0.6
	for id: String in ARMOR:
		var mi := MeshInstance3D.new()
		mi.mesh = FighterArt.armor_art(id)
		g.add_child(mi)
		mi.position = Vector3(x, 0.2, 0.0)
		x += 0.3
	return g


## Each shot: SETTLE_FRAMES with the shadow on (save), SETTLE_FRAMES with it off (save, measure), then the next.
func _process(_d: float) -> void:
	_frame += 1
	var step: int = _frame / SETTLE_FRAMES
	var shot: int = step / 2
	if shot >= _shots.size():
		get_tree().quit()
		return
	var spec: Array = _shots[shot]
	var lit_pass: bool = step % 2 == 0
	_arena.sun.shadow_enabled = lit_pass
	for s: Array in _shots:
		(s[1] as Node3D).visible = s == spec
	_cam.look_at_from_position(spec[2] as Vector3, spec[3] as Vector3)
	if _frame % SETTLE_FRAMES != SETTLE_FRAMES - 1:
		return
	var img: Image = get_viewport().get_texture().get_image()
	if lit_pass:
		_lit = img
		img.save_png("%s%s_q%d_%s.png" % [_out, _name, GfxQuality.level, spec[0]])
		return
	var m: Vector2i = measure(_lit, img)
	print("SHADOWCAP %s q%d %s acne=%d shade=%d" % [_name, GfxQuality.level, spec[0], m.x, m.y])


## (speckle pixels, all darkened pixels) between the shadowed and the unshadowed frame.
static func measure(shadowed: Image, open: Image) -> Vector2i:
	var w: int = shadowed.get_width()
	var h: int = shadowed.get_height()
	var dark := PackedByteArray()
	dark.resize(w * h)
	var shade: int = 0
	for y: int in h:
		for x: int in w:
			var a: float = shadowed.get_pixel(x, y).get_luminance()
			var b: float = open.get_pixel(x, y).get_luminance()
			if b > 0.02 and a < b * (1.0 - ACNE_DROP):
				dark[y * w + x] = 1
				shade += 1
	var acne: int = 0
	for y: int in range(1, h - 1):
		for x: int in range(1, w - 1):
			if dark[y * w + x] == 0:
				continue
			var n: int = 0
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					n += dark[(y + dy) * w + x + dx]
			if n - 1 <= ACNE_MAX_NEIGHBOURS:
				acne += 1
	return Vector2i(acne, shade)
