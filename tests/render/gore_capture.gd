extends Node
## Gut spill renders in the real arena: a bot bout is built, both fighters are frozen in their stance once standing,
## then the victim (side 1) is run through or gutted and the camera saves the gush and the settled guts. Run in a
## real (xvfb) window:
## godot --path . --resolution 1280x720 res://tests/render/gore_capture.tscn -- --out=DIR --name=run [--kind=gut] [--alien]
## --kind=sever cuts the victim's right forearm off at the elbow instead and frames the stump and the fallen arm.
## Never part of the check suite; writes only the PNGs it is told to.

var _out: String = "/tmp/gore_capture/"
var _name: String = "gore"
var _kind: String = "run_through"
var _alien: bool = false
var _match: Match = null
var _cam: Camera3D = null
var _frame: int = 0
var _gored_at: int = -1
var _shots: Array = []  ## [frames after the gore, tag, camera mode]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--kind="):
			_kind = a.substr(7)
		elif a == "--alien":
			_alien = true
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_match = Match.new()
	add_child(_match)
	var victim: Dictionary = {"weapon": "fists", "offhand": "", "armor": {}}
	if _alien:
		victim = OutfitRules.with_outfit(victim, "alien")
	_match.setup({"mode": "bot_vs_bot", "seed": 7, "loop": false, "time_limit_s": 600.0,
			"loadouts": [{"weapon": "gladius", "offhand": "", "armor": {}}, victim]})
	_shots = [[18, "gush", "close"], [60, "spill", "close"], [420, "settled", "low"]]
	if _kind == "sever":
		_shots = [[18, "cut", "arm"], [120, "stump", "arm"]]


func _process(_d: float) -> void:
	_frame += 1
	if _match == null or _match.fighters.size() < 2:
		return
	var v: Fighter = _match.fighters[1] as Fighter
	# Gore once the victim stands (an observed condition), with a frame fallback.
	if _gored_at < 0 and (_frame >= 240 or (_frame >= 90 and _standing(v))):
		_freeze_all()
		_gore(v)
		_gored_at = _frame
	if _gored_at < 0:
		return
	var since: int = _frame - _gored_at
	for s: Array in _shots:
		if since == int(s[0]) - 3:
			_aim(v, str(s[2]))
			RenderingServer.render_loop_enabled = true
		if since == int(s[0]):
			_save(str(s[1]))
			RenderingServer.render_loop_enabled = false
	if since > int((_shots[_shots.size() - 1] as Array)[0]):
		get_tree().quit()


func _standing(f: Fighter) -> bool:
	var p: RigidBody3D = f.parts["pelvis"]
	return p.global_position.y > 0.8 and p.linear_velocity.length() < 0.6


func _freeze_all() -> void:
	for f: Variant in _match.fighters:
		for n: Variant in (f as Fighter).parts:
			((f as Fighter).parts[n] as RigidBody3D).freeze = true
		(f as Fighter).set_physics_process(false)


func _facing(v: Fighter) -> Vector3:
	var a: Fighter = _match.fighters[0] as Fighter
	var d: Vector3 = (a.parts["pelvis"] as Node3D).global_position - (v.parts["pelvis"] as Node3D).global_position
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


func _gore(v: Fighter) -> void:
	var fwd: Vector3 = _facing(v)
	var torso: Node3D = v.parts["torso"]
	var pelvis: Node3D = v.parts["pelvis"]
	var at: Vector3 = pelvis.global_position.lerp(torso.global_position, 0.6) + fwd * 0.13
	if _kind == "sever":
		var arm: RigidBody3D = v.parts["forearm_r"]
		var elbow: Vector3 = arm.to_global(Vector3(0, 0.17, 0))
		var up: Vector3 = (v.parts["upper_arm_r"] as Node3D).global_position
		v.call("_sever", "forearm_r")
		arm.freeze = false  # the cut arm drops; the stump stays frozen in the stance
		v.gore.emit({"kind": "sever", "part": "forearm_r", "point": elbow, "normal": (elbow - up).normalized(), "amount": 1.0})
		return
	v.gore.emit({"kind": _kind, "part": "torso", "point": at, "normal": fwd, "amount": 60.0})


func _aim(v: Fighter, mode: String) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		add_child(_cam)
	_cam.make_current()
	var fwd: Vector3 = _facing(v)
	var side: Vector3 = fwd.cross(Vector3.UP).normalized()
	var c: Vector3 = (v.parts["pelvis"] as Node3D).global_position
	if mode == "arm":
		var look3: Vector3 = (v.parts["upper_arm_r"] as Node3D).global_position + Vector3(0, -0.2, 0)
		var out: Vector3 = look3 - (v.parts["torso"] as Node3D).global_position  # from the body out past the stump
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else side
		_cam.global_position = look3 + out * 0.5 + fwd * 0.25 + Vector3(0, -0.2, 0)
		if _match.presenter != null and _match.presenter.hud != null:
			_match.presenter.hud.visible = false
		_cam.look_at(look3, Vector3.UP)
	elif mode == "low":
		var look: Vector3 = Vector3(c.x, 0.15, c.z) + fwd * 0.45
		var g: GutSim = _match.presenter.blood.guts if _match.presenter != null else null
		if g != null and g.organ_count() > 0:  # frame the organs on the sand and the victim's feet
			var sum: Vector3 = Vector3(c.x, 0.1, c.z)
			for j: int in g.blob_pos.size():
				if GutSim.is_organ(g.blob_kind[j]):
					sum += g.blob_pos[j]
					print("GORECAP organ ", g.blob_kind[j], " at ", g.blob_pos[j] - Vector3(c.x, 0, c.z))
			look = sum / float(g.organ_count() + 1)
		_cam.global_position = look + fwd * 1.6 + side * 1.0 + Vector3(0, 1.6, 0)
		_cam.look_at(look, Vector3.UP)
	else:
		var look2: Vector3 = c + fwd * 0.2 + Vector3(0, -0.15, 0)
		_cam.global_position = look2 + fwd * 1.9 + side * 0.8 + Vector3(0, 0.25, 0)
		_cam.look_at(look2, Vector3.UP)


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var k: float = 560.0 / float(maxi(img.get_width(), img.get_height()))  # keeps each PNG small (docs renders < 300 KB)
	if k < 1.0:
		img.resize(roundi(img.get_width() * k), roundi(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
	print("GORECAP saved ", tag)
