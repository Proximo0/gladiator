extends Node
## Wound and shadow readability renders: a seeded presented bot fight runs headless-fast (only saved frames are drawn)
## for --secs seconds (or until it is over), then both fighters are frozen and the shots are saved: the fight camera,
## each fighter close up, the feet from a low camera, then the right forearm of side 1 is cut off and the stump is
## shot from the fight camera and from 2.5 m. Prints the fight camera's draw calls and primitives and how many wound
## marks were dropped from a full part during the fight (churn). Run in a real (xvfb) window:
## godot --path . --rendering-driver opengl3 --fixed-fps 60 --resolution 1280x720 \
##     res://tests/render/wound_look_capture.tscn -- --out=DIR --name=fight [--quality=0|1|2] [--seed=N] [--secs=18]
## Writes DIR/<name>_<shot>.png and a small copy (640 px wide at most) DIR/small/<name>_<shot>.png. Never part of
## the check suite; writes only the PNGs it is told to.

const SHOTS: Array = [["cam", 0], ["f0", 0], ["f1", 1], ["feet", 0]]
const SEVER_SHOTS: Array = [["sever_cam", 1], ["sever_mid", 1]]
const SEVER_WAIT: int = 50  ## frames between the cut and its shots (the arm falls, the fountain starts)
const SMALL_W: int = 640

var _out: String = "/tmp/wound_look/"
var _name: String = "fight"
var _seed: int = 11
var _secs: float = 18.0
var _match: Match = null
var _cam: Camera3D = null
var _frame: int = 0
var _phase: int = 0  ## 0 fighting, 1 shots, 2 waiting after the cut, 3 sever shots
var _queue: Array = []
var _at: int = 0
var _seen: Array = [{}, {}]  ## side -> {Mark: true} seen on the last scan
var _dropped: Array[int] = [0, 0]


func _ready() -> void:
	_out = Flags.get_arg("out", _out)
	if not _out.ends_with("/"):
		_out += "/"
	_name = Flags.get_arg("name", _name)
	_seed = int(Flags.get_arg("seed", str(_seed)))
	_secs = float(Flags.get_arg("secs", str(_secs)))
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "2")))
	DirAccess.make_dir_recursive_absolute(_out + "small")
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	var lo0: Dictionary = {"weapon": "gladius", "offhand": "", "armor": {"head": "helm_leather"}}
	var lo1: Dictionary = {"weapon": "club", "offhand": "", "armor": {"torso": "cuirass_leather"}}
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": _seed, "loadouts": [lo0, lo1], "loop": false, "time_limit_s": 600.0})
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)


func _process(_d: float) -> void:
	_frame += 1
	if _match == null or _match.fighters.size() < 2:
		return
	match _phase:
		0:
			if _frame % 6 == 0:
				_scan_churn()
			# Keyed on the fight: the time is up, or the match is over and the loser has had 1.5 s to fall.
			if _match.tick >= int(_secs * 60.0) or (_match.over and _at > 0 and _frame > _at + 90):
				_scan_churn()
				_freeze_all()
				_hide_ui()
				_report()
				_queue = SHOTS.duplicate()
				_phase = 1
				_at = _frame
			elif _match.over and _at == 0:
				_at = _frame
		1, 3:
			_shoot()
		2:
			if _frame >= _at + SEVER_WAIT:
				_queue = SEVER_SHOTS.duplicate()
				_phase = 3
				_at = _frame


## One shot every 4 frames: aim on the first, save on the fourth (the renderer settles in between).
func _shoot() -> void:
	if _queue.is_empty():
		if _phase == 1:
			_sever(_match.fighters[1] as Fighter)
			_phase = 2
			_at = _frame
		else:
			get_tree().quit()
		return
	var spec: Array = _queue[0]
	var tag: String = str(spec[0])
	if _frame == _at + 1:
		_aim(tag, int(spec[1]))
		RenderingServer.render_loop_enabled = true
	elif _frame == _at + 4:
		_save(tag)
		if tag == "cam":
			print("WLOOK draw_calls=%d primitives=%d" % [
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
		RenderingServer.render_loop_enabled = false
		_queue.pop_front()
		_at = _frame


## Counts marks that were on a fighter at the last scan and are gone now (dropped from a full part).
func _scan_churn() -> void:
	var wfx: Variant = _match.presenter.get("wounds") if _match.presenter != null else null
	if not (wfx is Node):
		return
	for side: int in 2:
		var wm: Variant = (wfx as Node).call("marks_of", side)
		if wm == null:
			continue
		var now: Dictionary = {}
		for part: String in (wm as Object).get("marks"):
			for m: Object in (wm as Object).get("marks")[part]:
				now[m] = true
		for m: Variant in (_seen[side] as Dictionary):
			if not now.has(m):
				_dropped[side] += 1
		_seen[side] = now


func _report() -> void:
	print("WLOOK fight ticks=%d over=%s quality=%d" % [_match.tick, str(_match.over), GfxQuality.level])
	var wfx: Variant = _match.presenter.get("wounds") if _match.presenter != null else null
	if not (wfx is Node):
		return
	for side: int in 2:
		var wm: Variant = (wfx as Node).call("marks_of", side)
		var by: Dictionary = {}
		var full: int = 0
		for part: String in (wm as Object).get("marks"):
			var list: Array = (wm as Object).get("marks")[part]
			if list.size() >= int((wm as Object).get("cap")):
				full += 1
			for m: Object in list:
				by[int(m.get("kind"))] = int(by.get(int(m.get("kind")), 0)) + 1
		print("WLOOK side=%d marks=%d kinds=%s full_parts=%d dropped=%d" % [side, (wm as Object).call("count", ""),
				str(by), full, _dropped[side]])


func _freeze_all() -> void:
	for f: Variant in _match.fighters:
		for n: Variant in (f as Fighter).parts:
			((f as Fighter).parts[n] as RigidBody3D).freeze = true
		(f as Fighter).set_physics_process(false)


func _hide_ui() -> void:
	var p: MatchPresenter = _match.presenter
	if p != null and p.hud != null:
		p.hud.visible = false
	if p != null and p.aim != null:
		p.aim.visible = false


## Cuts side `v`'s right forearm off at the elbow, the way a severing blow does (tests/render/gore_capture.gd).
func _sever(v: Fighter) -> void:
	var arm: RigidBody3D = v.parts["forearm_r"]
	var elbow: Vector3 = arm.to_global(Vector3(0, 0.17, 0))
	var up: Vector3 = (v.parts["upper_arm_r"] as Node3D).global_position
	v.call("_sever", "forearm_r")
	arm.freeze = false
	v.gore.emit({"kind": "sever", "part": "forearm_r", "point": elbow, "normal": (elbow - up).normalized(), "amount": 1.0})


func _aim(tag: String, side: int) -> void:
	var p: MatchPresenter = _match.presenter
	if tag == "cam" or tag == "sever_cam":
		p.camera.current = true
		return
	var f: Fighter = _match.fighters[side]
	var o: Fighter = _match.fighters[1 - side]
	var at: Vector3 = (f.parts["torso"] as Node3D).global_position
	var dist: float = 1.25
	if tag == "sever_mid":
		at = (f.parts["upper_arm_r"] as Node3D).global_position
		dist = 2.5
	var dir: Vector3 = (o.parts["torso"] as Node3D).global_position - at
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var sun: Vector3 = _sun_dir()
	dir = (dir + sun * 0.9).normalized() if (dir + sun * 0.9).length() > 0.2 else dir.rotated(Vector3.UP, 0.35)
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	_cam.keep_aspect = Camera3D.KEEP_WIDTH if vp.y > vp.x else Camera3D.KEEP_HEIGHT
	if tag == "feet":
		# Low, from the sun side, between the two fighters' feet.
		var mid: Vector3 = ((f.parts["pelvis"] as Node3D).global_position + (o.parts["pelvis"] as Node3D).global_position) * 0.5
		mid.y = 0.0
		var side_dir: Vector3 = sun if sun.length() > 0.1 else Vector3.BACK
		_cam.global_position = mid + side_dir * 2.4 + Vector3(0, 1.1, 0)
		_cam.look_at(mid, Vector3.UP)
	else:
		var lying: bool = at.y < 0.7
		_cam.global_position = at + (dir * 0.45 + Vector3(0, 0.95, 0)) * dist if lying else at + dir * dist + Vector3(0, 0.25 * dist, 0)
		_cam.look_at(at, Vector3.UP)
	_cam.current = true


func _sun_dir() -> Vector3:
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var z: Vector3 = (n as Node3D).global_transform.basis.z
		z.y = 0.0
		return z.normalized() if z.length() > 0.01 else Vector3.ZERO
	return Vector3.ZERO


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
	var k: float = float(SMALL_W) / float(img.get_width())
	if k < 1.0:
		img.resize(roundi(img.get_width() * k), roundi(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.save_png("%ssmall/%s_%s.png" % [_out, _name, tag])
	print("WLOOK saved ", tag)
