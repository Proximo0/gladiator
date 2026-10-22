extends Node3D
## Textured-art renders in the real arena light: every textured weapon, the armor pieces and the gut spill pieces laid
## on the sand, through the same loaders the game uses (Weapon, FighterArt.armor_art, GutArt). Run in a real (xvfb)
## window: godot --path . --resolution 1280x720 res://tests/render/art_capture.tscn -- --out=DIR --name=after
## [--untextured] (TexturedArt off: the before shot). Writes <name>_weapons.png, <name>_armor.png, <name>_gore.png,
## then prints the video memory in use. Never part of the check suite; writes only the PNGs it is told to.

const WEAPONS: PackedStringArray = ["longsword", "gladius", "falchion", "machete", "dai_katana", "axe", "mace", "warhammer",
		"sledgehammer", "halberd", "spear", "rake", "bat", "club", "shield_round", "scutum", "laser_sword"]
const ARMOR: PackedStringArray = ["galea", "manica_r", "manica_l", "greave_r", "greave_l"]

var _out: String = "/tmp/art_capture/"
var _name: String = "shot"
var _frame: int = 0
var _cam: Camera3D
var _groups: Dictionary = {}  ## shot -> [Node3D group, camera position, look target]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a == "--untextured":
			TexturedArt.enabled = false
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(Arena.new())
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_groups["weapons"] = [_weapons(), Vector3(0.0, 2.6, 2.4), Vector3(0.0, 0.0, -0.2)]
	_groups["armor"] = [_armor(), Vector3(0.0, 1.0, 1.25), Vector3(0.0, 0.15, 0.0)]
	_groups["gore"] = [_gore(), Vector3(0.0, 0.75, 0.9), Vector3(0.0, 0.05, 0.0)]


## Every weapon flat on the sand, grip toward the camera, in a row along x.
func _weapons() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var x: float = -2.0
	for id: String in WEAPONS:
		var d: Dictionary = CombatData.weapon(id)
		if d.is_empty():
			continue
		var w := Weapon.new()
		w.build(d)
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


## One of each spill piece with the red blood palette as its instance colour, the way BloodFx draws them.
func _gore() -> Node3D:
	var g := Node3D.new()
	add_child(g)
	var mat: BaseMaterial3D = GutArt.material()
	var red: Color = Color(0.7, 0.08, 0.06)
	for k: int in GutSim.KINDS:
		var mmi := MultiMeshInstance3D.new()
		mmi.material_override = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = GutArt.mesh(k)
		mm.instance_count = 1
		var s: float = GutArt.authored_size(k) if k != GutSim.K_LINK and k != GutSim.K_TORN else 0.03
		var sc := Vector3(s, s, s) if k != GutSim.K_LINK and k != GutSim.K_TORN else Vector3(0.03, 0.03, 0.12)
		mm.set_instance_transform(0, Transform3D(Basis.from_scale(sc), Vector3(-0.45 + 0.15 * k, s * GutArt.floor_share(k), 0.0)))
		mm.set_instance_color(0, red)
		mmi.multimesh = mm
		g.add_child(mmi)
	return g


func _process(_d: float) -> void:
	_frame += 1
	var shots: Array = _groups.keys()
	var i: int = _frame / 30 - 1
	if i < 0 or i >= shots.size():
		if i >= shots.size():
			print("ARTCAP %s video_mem_mb=%.1f texture_mem_mb=%.1f" % [_name,
					Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
					Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
			get_tree().quit()
		return
	var shot: String = shots[i]
	var spec: Array = _groups[shot]
	for k: String in _groups:
		((_groups[k] as Array)[0] as Node3D).visible = k == shot
	_cam.look_at_from_position(spec[1] as Vector3, spec[2] as Vector3)
	if _frame % 30 == 29:
		get_viewport().get_texture().get_image().save_png("%s%s_%s.png" % [_out, _name, shot])
