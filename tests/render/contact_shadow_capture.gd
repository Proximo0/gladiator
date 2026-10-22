extends Node
## Contact-shadow renders: a presented bot fight, frozen at observed moments, each drawn with the sand's contact
## blobs off ("before") and on ("after") from the fight camera and from a low close camera at the feet.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --fixed-fps 60 res://tests/render/contact_shadow_capture.tscn -- --out=DIR --quality=0 [--seed=S]
## Moments: "fight" when both stand within 2.6 m (fallback tick 360), "down" when a fighter is down, ko or dead
## (fallback tick 2400). Never part of the check suite; writes only the PNGs it is told to.

const FIGHT_FALLBACK: int = 360
const DOWN_FALLBACK: int = 2400

var _out: String = "/tmp/contact_capture/"
var _match: Match = null
var _moments: Array[String] = ["fight", "down"]
var _shot_step: int = -1  ## frames into the current moment's shot sequence, -1 while waiting
var _close: Camera3D = null
var _tag: String = ""


func _ready() -> void:
	_out = Flags.get_arg("out", _out)
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "2")))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_match = Match.new()
	add_child(_match)
	_match.process_mode = Node.PROCESS_MODE_PAUSABLE
	_match.setup({"mode": "bot_vs_bot", "seed": int(Flags.get_arg("seed", "1002")), "presentation": true,
			"loop": false, "time_limit_s": 600.0})
	_match.presenter.blood.set_quality(GfxQuality.blood_level())
	Engine.time_scale = 4.0  # fast-forward between moments (--fixed-fps keeps physics and frames in step)
	_close = Camera3D.new()
	_close.fov = 50.0
	add_child(_close)


func _ready_for(moment: String) -> bool:
	var f: Array = _match.fighters
	if f.size() < 2:
		return false
	var a: Fighter = f[0]
	var b: Fighter = f[1]
	if moment == "fight":
		var pa: Vector3 = (a.parts["pelvis"] as RigidBody3D).global_position
		var pb: Vector3 = (b.parts["pelvis"] as RigidBody3D).global_position
		var near: bool = Vector2(pa.x - pb.x, pa.z - pb.z).length() < 2.6 and a.state_name() == "standing" \
				and b.state_name() == "standing"
		return (near and _match.tick > 90) or _match.tick >= FIGHT_FALLBACK
	for x: Fighter in [a, b]:
		if x.state_name() in ["down", "ko", "dead"]:
			return true
	return _match.tick >= DOWN_FALLBACK


func _process(_d: float) -> void:
	if _moments.is_empty():
		return
	var moment: String = _moments[0]
	if _shot_step < 0:
		if _ready_for(moment):
			get_tree().paused = true
			Engine.time_scale = 1.0
			print("CSCAP %s tick=%d states=%s/%s" % [moment, _match.tick, (_match.fighters[0] as Fighter).state_name(),
					(_match.fighters[1] as Fighter).state_name()])
			_shot_step = 0
		return
	# Each setting is drawn for two frames before it is saved, so the sand material has taken the new blobs.
	var steps: Array = [["fight_cam", false], ["fight_cam", true], ["close", false], ["close", true]]
	var i: int = _shot_step / 3
	var phase: int = _shot_step % 3
	if i >= steps.size():
		_match.presenter.camera.current = true
		get_tree().paused = false
		Engine.time_scale = 4.0
		_moments.remove_at(0)
		_shot_step = -1
		if _moments.is_empty():
			get_tree().quit()
		return
	var cam: String = steps[i][0]
	var on: bool = steps[i][1]
	if phase == 0:
		if cam == "close":
			_aim_close()
		else:
			_match.presenter.camera.current = true
		if on:
			_match.presenter.call("_contact_shadows")
		else:
			_match.presenter.sand.call("set_contacts", PackedVector4Array())
	elif phase == 2:
		var size: Vector2i = DisplayServer.window_get_size()
		_tag = "%dx%d_q%d" % [size.x, size.y, GfxQuality.level]
		var name: String = "%s%s_%s_%s.png" % [_out, "after" if on else "before", _tag, moment + ("_close" if cam == "close" else "")]
		get_viewport().get_texture().get_image().save_png(name)
		print("CSCAP saved ", name)
	_shot_step += 1


## A low camera 2.6 m from the first fighter's pelvis, from the side facing the fight camera, looking at its feet.
func _aim_close() -> void:
	var f: Fighter = _match.fighters[0]
	var p: Vector3 = (f.parts["pelvis"] as RigidBody3D).global_position
	var fc: Vector3 = _match.presenter.camera.global_position
	var dir: Vector3 = Vector3(fc.x - p.x, 0.0, fc.z - p.z).normalized()
	if dir.length() < 0.5:
		dir = Vector3(0.0, 0.0, 1.0)
	_close.global_position = Vector3(p.x, 0.0, p.z) + dir * 2.6 + Vector3(0.0, 0.9, 0.0)
	_close.look_at(Vector3(p.x, 0.25, p.z), Vector3.UP)
	_close.current = true
