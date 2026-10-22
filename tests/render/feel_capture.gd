extends Node
## Hit-feel renders in a presented bot match, keyed on observed hit classes: two ticks into the first heavy or sever
## hit's hit-stop ("punch_<class>"), two ticks into a finisher ("finisher") and half a second into its cinematic
## ("cine"). Quits once the match is over and its captures are saved. --nofeel switches hit-stop, punch and grade off
## for the matching "before" frames. Run in a real (xvfb) window with fixed frames:
## godot --path . --resolution 1280x720 --fixed-fps 60 res://tests/render/feel_capture.tscn -- --out=DIR --name=after
##   [--seed=4404 --wa=axe --wb=longsword --quality=1 --nofeel]
## Never part of the check suite; writes only the PNGs it is told to (downscaled to 640 wide).

const SAVE_W: int = 640
const MAX_FRAMES: int = 4200

var _out: String = "/tmp/feel_capture/"
var _name: String = "shot"
var _match: Match = null
var _frame: int = 0
var _seen: int = 0
var _plan: Array = []  ## [frame, tag]
var _nofeel: bool = false
var _fin_done: bool = false
var _hard_done: bool = false
var _over_frame: int = -1


func _ready() -> void:
	var seed_value: int = 4404
	var wa: String = "axe"
	var wb: String = "longsword"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--wa="):
			wa = a.substr(5)
		elif a.begins_with("--wb="):
			wb = a.substr(5)
		elif a.begins_with("--quality="):
			GfxQuality.set_level(int(a.substr(10)))
		elif a == "--nofeel":
			_nofeel = true
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var la: Dictionary = MatchConfig.random_loadout(rng)
	var lb: Dictionary = MatchConfig.random_loadout(rng)
	la["weapon"] = wa
	lb["weapon"] = wb
	la["offhand"] = ""
	lb["offhand"] = ""
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": seed_value, "presentation": true, "loop": false, "time_limit_s": 60.0,
		"loadouts": [la, lb]})
	if _nofeel:
		var fd: FeelDirector = _match.presenter.feel
		fd.hit_stop.enabled = false
		fd.punch.visible = false


func _process(_d: float) -> void:
	_frame += 1
	var fd: FeelDirector = _match.presenter.feel if _match != null and _match.presenter != null else null
	if fd == null:
		return
	while _seen < fd.hit_log.size():
		var cls: String = str(fd.hit_log[_seen]["class"])
		_seen += 1
		if cls == "finisher" and not _fin_done:
			_fin_done = true
			_plan.append([_frame + 2, "finisher"])
			_plan.append([_frame + 30, "cine"])
		elif (cls == "heavy" or cls == "sever") and not _hard_done:
			_hard_done = true
			_plan.append([_frame + 2, "punch_" + cls])
	if not _plan.is_empty():
		var next: Array = _plan[0]
		RenderingServer.render_loop_enabled = _frame >= int(next[0]) - 2
		if _frame >= int(next[0]):
			_save(str(next[1]))
			print("FEELCAP saved %s frame=%d lag=%.3f grade=%.2f punch=%.2f ts=%.2f" % [next[1], _frame, fd.hit_stop.lag(),
				fd.punch.logic.grade, fd.punch.logic.current(), Engine.time_scale])
			_plan.remove_at(0)
	else:
		RenderingServer.render_loop_enabled = false
	var finished: bool = _match.over and _plan.is_empty() and (_fin_done or _frame > _over_frame + 200)
	if _match.over and _over_frame < 0:
		_over_frame = _frame
	if (finished and _over_frame >= 0) or _frame > MAX_FRAMES:
		get_tree().quit()


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var h: int = roundi(float(img.get_height()) * float(SAVE_W) / float(maxi(img.get_width(), 1)))
	img.resize(SAVE_W, h, Image.INTERPOLATE_BILINEAR)
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
