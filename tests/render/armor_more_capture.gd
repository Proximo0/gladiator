extends Node3D
## Armored gladiators on a sand disc, for checking armor and shield art fit (no clipping, right scale). Run in a real
## (xvfb) window:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##   res://tests/render/armor_more_capture.tscn -- --scripted --out=DIR --name=land
## Writes <name>_<set>_full.png (both fighters) and <name>_<set>_armored<k>_front/back.png (each fighter) per set.
## Never part of the check suite; writes only the PNGs it is told to.

const SETS: Array = [
	["a", {"weapon": "gladius", "offhand": "tower_shield", "armor": {"head": "helm_murmillo", "torso": "lorica_segmentata", "upper_arm_l": "retiarius_arm", "thigh_l": "fasciae"}},
		{"weapon": "gladius", "offhand": "aspis", "armor": {"head": "helm_thraex", "torso": "lorica_squamata", "upper_arm_l": "spaulders", "thigh_l": "greaves_iron"}}],
	["b", {"weapon": "gladius", "offhand": "kite_shield", "armor": {"head": "helm_secutor", "torso": "balteus", "upper_arm_l": "spaulders", "thigh_l": "fasciae"}},
		{"weapon": "gladius", "offhand": "pelta", "armor": {"head": "helm_iron", "torso": "lorica_segmentata", "upper_arm_l": "bracers_iron", "thigh_l": "fasciae"}}],
	["c", {"weapon": "gladius", "offhand": "buckler", "armor": {"head": "helm_murmillo", "torso": "lorica_squamata", "upper_arm_l": "retiarius_arm", "thigh_l": "greaves_iron"}},
		{"weapon": "gladius", "offhand": "parma", "armor": {"head": "helm_thraex", "torso": "balteus", "upper_arm_l": "spaulders", "thigh_l": "fasciae"}}],
]
const SETTLE_FRAMES: int = 70  ## the fighters stand up into their guard pose
const SPACING: float = 1.0

var _out: String = "/tmp/armor_capture/"
var _name: String = "shot"
var _set: int = 0
var _frame: int = 0
var _stage: Node3D
var _cam: Camera3D
var _fighters: Array[Fighter] = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.27, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.54, 0.45)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(1.5, 3.0, -2.5), Vector3(0.0, 1.0, 0.0))
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 0.05
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.62, 0.48, 0.3)
	sand.roughness = 1.0
	cm.material = sand
	disc.mesh = cm
	disc.position = Vector3(0.0, -0.03, 0.0)
	add_child(disc)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 1.0, 12.0)
	fcs.shape = box
	fcs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(fcs)
	add_child(floor_body)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(_cam)
	_cam.current = true
	_stage = Node3D.new()
	add_child(_stage)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_build(0)


func _build(i: int) -> void:
	for f: Fighter in _fighters:
		_stage.remove_child(f)
		f.free()
	_fighters.clear()
	var s: Array = SETS[i]
	for k: int in 2:
		var f := Fighter.new()
		f.name = "Armored%d" % k
		_stage.add_child(f)
		f.global_transform = Transform3D(Basis(), Vector3((0.5 - float(k)) * 2.0 * SPACING, 0.0, 0.0))
		f.setup(s[k + 1], k, Tuning.shared())
		_fighters.append(f)
	_frame = 0


func _process(_d: float) -> void:
	_frame += 1
	# [tag, camera, target, fov]: both fighters, then each fighter's front and back three-quarter.
	var shots: Array = [["full", Vector3(0.0, 1.2, -4.6), Vector3(0.0, 0.9, 0.0), 42.0]]
	for f: Fighter in _fighters:
		var x: float = f.global_position.x
		shots.append(["%s_front" % f.name.to_lower(), Vector3(x - 0.5, 1.6, -2.2), Vector3(x, 1.2, 0.0), 45.0])
		shots.append(["%s_back" % f.name.to_lower(), Vector3(x + 1.0, 1.7, 2.0), Vector3(x, 1.2, 0.0), 45.0])
	var k: int = _frame - SETTLE_FRAMES
	if k >= 0 and k < shots.size() * 3 and k % 3 == 0:
		var sh: Array = shots[k / 3]
		_cam.fov = float(sh[3])
		_cam.look_at_from_position(sh[1], sh[2])
		RenderingServer.render_loop_enabled = true
	elif k >= 0 and k < shots.size() * 3 and k % 3 == 2:
		_save("%s_%s" % [str((SETS[_set] as Array)[0]), str((shots[k / 3] as Array)[0])])
		RenderingServer.render_loop_enabled = false
	elif k == shots.size() * 3:
		_set += 1
		if _set >= SETS.size():
			print("ARMORCAP done sets=", SETS.size())
			get_tree().quit()
		else:
			_build(_set)


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
	if tag.ends_with("full"):
		for f: Fighter in _fighters:
			print("ARMORCAP %s %s state=%s" % [tag, f.name, f.state_name()])
