extends Node3D
## Material look check for the textured models: a bronze helmet (galea), a steel blade (longsword) and a wood shield
## (shield_round), each alone in the arena light, framed from the sun side the way the fight camera sees a fighter's
## gear. Run in a real (xvfb) window: godot --path . --resolution 1280x720 --fixed-fps 60
## res://tests/render/material_capture.tscn -- --out=DIR --name=after [--untextured] [--quality=low|medium|high].
## For each item and view it saves <name>_<item>_<view>.png, then renders the item once more in flat magenta to find its pixels and
## prints "MATCAP <shot> mean=r,g,b luma sat contrast=<luma std> patch=<mean luma change 8 px down> spec=<share
## of pixels over 230>" over those pixels (sRGB 0-255), then one line with the video and texture memory in use. Never part of the check suite.

const ITEMS: PackedStringArray = ["bronze_helmet", "steel_blade", "wood_shield"]
## Camera elevation (rad) per view: "side" near eye level (reflects the sand and horizon), "high" the fight camera's
## look down (reflects the sky).
const VIEWS: Dictionary = {"side": 0.35, "high": 0.9}
const SETTLE: int = 30  ## frames before each saved shot (shadows and sky radiance settle)
const MASK: Color = Color(1.0, 0.0, 1.0)
const STEP: int = 8  ## px between the samples of the patch measure

var _out: String = "/tmp/material_capture/"
var _name: String = "shot"
var _frame: int = 0
var _shot: int = 0
var _cam: Camera3D
var _items: Array[Node3D] = []
var _mask_mat: StandardMaterial3D
var _lit: Image
var _strip: String = ""  ## debug: turn one map off on every item's materials (normal, orm, albedo)


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a == "--untextured":
			TexturedArt.enabled = false
		elif a.begins_with("--quality="):
			GfxQuality.level = GfxQuality.NAMES.find(a.substr(10))
		elif a.begins_with("--strip="):
			_strip = a.substr(8)
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(Arena.new())
	_cam = Camera3D.new()
	_cam.fov = 35.0
	add_child(_cam)
	_mask_mat = StandardMaterial3D.new()
	_mask_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mask_mat.albedo_color = MASK
	_mask_mat.disable_fog = true
	_items.append(_helmet())
	_items.append(_weapon("longsword", Basis(Vector3(1, 0, 0), -0.5)))
	_items.append(_weapon("shield_round", Basis(Vector3(1, 0, 0), -0.25)))
	if _strip != "":
		for item: Node3D in _items:
			_strip_maps(item)


## Debug: copies of every surface material with one map turned off, to see which map a look comes from.
func _strip_maps(item: Node3D) -> void:
	for mi: MeshInstance3D in _meshes(item):
		for s: int in mi.mesh.get_surface_count():
			var bm: BaseMaterial3D = mi.get_active_material(s) as BaseMaterial3D
			if bm == null:
				continue
			bm = bm.duplicate() as BaseMaterial3D
			match _strip:
				"normal":
					bm.normal_enabled = false
				"orm":
					bm.set_texture(BaseMaterial3D.TEXTURE_ORM, null)
				"albedo":
					bm.albedo_texture = null
			mi.set_surface_override_material(s, bm)


func _helmet() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var mi := MeshInstance3D.new()
	mi.mesh = FighterArt.armor_art("galea")
	g.add_child(mi)
	g.position = Vector3(0.0, 1.1, 0.0)
	return g


## A weapon held up, tilted back toward the camera so its face catches the sky and the sun.
func _weapon(id: String, tilt: Basis) -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var w := Weapon.new()
	w.build(CombatData.weapon(id))
	w.freeze = true
	g.add_child(w)
	w.transform = Transform3D(tilt, Vector3.ZERO)
	g.position = Vector3(0.0, 0.6, 0.0)
	return g


## Every mesh under `n`.
func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _meshes(n):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _shot_name(shot: int) -> String:
	return "%s_%s" % [ITEMS[shot / VIEWS.size()], VIEWS.keys()[shot % VIEWS.size()]]


func _frame_item(shot: int) -> void:
	var i: int = shot / VIEWS.size()
	for k: int in _items.size():
		_items[k].visible = k == i
	var item: Node3D = _items[i]
	# Camera between the sun and the viewer's usual side: sun azimuth plus 40 degrees, raised by the view's elevation.
	var az: float = Arena.SUN_AZIMUTH + 0.7
	var el: float = VIEWS.values()[shot % VIEWS.size()]
	var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
	item.rotation.y = atan2(dir.x, dir.z)
	var box: AABB = _bounds(item)
	var dist: float = box.size.length() * 0.5 / tan(deg_to_rad(_cam.fov * 0.5)) * 1.15
	_cam.look_at_from_position(box.get_center() + dir * dist, box.get_center())


func _set_mask(i: int, on: bool) -> void:
	for mi: MeshInstance3D in _meshes(_items[i]):
		mi.material_override = _mask_mat if on else null


func _process(_d: float) -> void:
	_frame += 1
	if _shot >= ITEMS.size() * VIEWS.size():
		print("MATCAP %s quality=%s video_mem_mb=%.1f texture_mem_mb=%.1f" % [_name, GfxQuality.name_of(GfxQuality.level),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		get_tree().quit()
		return
	var f: int = _frame - _shot * (SETTLE + 4)
	if f == 1:
		_frame_item(_shot)
	elif f == SETTLE:
		_lit = get_viewport().get_texture().get_image()
		_lit.save_png("%s%s_%s.png" % [_out, _name, _shot_name(_shot)])
		_set_mask(_shot / VIEWS.size(), true)
	elif f == SETTLE + 3:
		_stats(_shot_name(_shot), _lit, get_viewport().get_texture().get_image())
		_set_mask(_shot / VIEWS.size(), false)
		_shot += 1


func _stats(shot: String, lit: Image, mask: Image) -> void:
	var n: int = 0
	var sum := Vector3.ZERO
	var luma_sum: float = 0.0
	var luma_sq: float = 0.0
	var sat_sum: float = 0.0
	var bright: int = 0
	var step_sum: float = 0.0  ## |luma change| over STEP px down the image: patchy bands along an upright blade
	var steps: int = 0
	for y: int in range(0, lit.get_height(), 2):
		for x: int in range(0, lit.get_width(), 2):
			var m: Color = mask.get_pixel(x, y)
			if m.r < 0.8 or m.g > 0.35 or m.b < 0.7:  # the flat magenta, after the tonemapper
				continue
			var c: Color = lit.get_pixel(x, y)
			n += 1
			sum += Vector3(c.r, c.g, c.b)
			var l: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			luma_sum += l
			luma_sq += l * l
			sat_sum += c.s
			if l > 230.0 / 255.0:
				bright += 1
			if y + STEP < lit.get_height():
				var m2: Color = mask.get_pixel(x, y + STEP)
				if m2.r >= 0.8 and m2.g <= 0.35 and m2.b >= 0.7:
					var c2: Color = lit.get_pixel(x, y + STEP)
					step_sum += absf(0.2126 * c2.r + 0.7152 * c2.g + 0.0722 * c2.b - l)
					steps += 1
	if n == 0:
		print("MATCAP %s no_pixels" % shot)
		return
	var mean: Vector3 = sum / n * 255.0
	var lm: float = luma_sum / n
	var sd: float = sqrt(maxf(luma_sq / n - lm * lm, 0.0)) * 255.0
	print("MATCAP %s mean=%d,%d,%d luma=%.1f sat=%.3f contrast=%.1f patch=%.1f spec=%.3f px=%d" % [shot, roundi(mean.x),
			roundi(mean.y), roundi(mean.z), lm * 255.0, sat_sum / n, sd, step_sum / maxi(steps, 1) * 255.0,
			float(bright) / n, n])
