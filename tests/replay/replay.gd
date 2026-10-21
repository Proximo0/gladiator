extends Node
## Replays a flight recording from tick 0 (see tools/replay.sh). Args after `--`:
##   --file=<recording.json>  --tune=<preset.json> (what-if: a Tuning preset applied on top of the recorded diff)
##   --render (arena visuals, PNG frames into out/replay/<seed>/)  --render_every=<ticks> (default 30)
## Prints `REPLAY ticks=N divergence=<m> result_match=yes|no first_div_tick=T winner=W reason=R [tuned=yes]`.
## Exit 0 on success, 1 when an untuned replay diverges, 2 on an unreadable file.

const START_WAIT: int = 12  ## physics ticks of an empty world before the match is built (same as tests/bot/bot.gd)
const MATCH_SCRIPT: String = "res://game/match/match.gd"

var _rec: Dictionary = {}
var _match: Node = null
var _recorder: FlightRecorder = null
var _result: Dictionary = {}
var _end: int = 0
var _tuned: bool = false
var _render: bool = false
var _every: int = 30
var _next_shot: int = 0
var _out_dir: String = ""
var _done: bool = false
var _wait: int = 0
var _world: SubViewport = null


func _ready() -> void:
	var path: String = Flags.get_arg("file")
	_rec = FlightRecorder.load_file(path)
	if _rec.has("error"):
		print("REPLAY FAIL cannot load %s: %s" % [path, _rec["error"]])
		get_tree().quit(2)
		return
	_end = int(_rec["ticks"])
	_render = Flags.args.has("render")
	_every = maxi(int(Flags.get_arg("render_every", "30")), 1)
	var tun: Tuning = Tuning.shared()
	tun.reset()
	tun.apply_dict(_rec.get("tuning", {}) as Dictionary)
	var tune_file: String = Flags.get_arg("tune")
	if tune_file != "":
		var f: FileAccess = FileAccess.open(tune_file, FileAccess.READ)
		var preset: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if not (preset is Dictionary):
			print("REPLAY FAIL cannot read tune preset %s" % tune_file)
			get_tree().quit(2)
			return
		tun.apply_dict(preset as Dictionary)
		_tuned = true
	_wait = START_WAIT
	if _render:
		_out_dir = ProjectSettings.globalize_path("res://out/replay/%d" % int(_rec["seed"]))
		DirAccess.make_dir_recursive_absolute(_out_dir)
		_hide_from_import(_out_dir.get_base_dir())


## Built inside _physics_process after START_WAIT empty ticks, exactly like tests/bot/bot.gd does.
func _start() -> void:
	var ms: GDScript = load(Flags.get_arg("match_script", MATCH_SCRIPT)) as GDScript
	_match = ms.new()
	if _render:
		add_child(_match)  # on screen: the main viewport's world, so the camera and the frame grab work
	else:
		_world = SubViewport.new()  # a fresh physics world, like bot.gd gives every match
		_world.own_world_3d = true
		_world.size = Vector2i(64, 64)
		_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_world)
		_world.add_child(_match)
	_match.call("setup", {
		"mode": "bot_vs_bot", "seed": _rec["seed"], "loadouts": _rec["loadouts"], "personalities": _rec["personalities"],
		"presentation": _render, "loop": false, "time_limit_s": _limit_s(),
	})
	_match.call("force_inputs", _rec["inputs"])
	_recorder = FlightRecorder.new()
	add_child(_recorder)
	_recorder.attach(_match)
	_match.connect("match_over", func(r: Dictionary) -> void: _result = r)


## The recorded time limit (the match must end by time at the same tick), else just past the recording.
func _limit_s() -> float:
	var lim: float = float(_rec.get("time_limit_s", 0.0))
	return lim if lim > 0.0 else float(_end) / 60.0 + 1.0


func _physics_process(_delta: float) -> void:
	if _done:
		return
	if _match == null:
		_wait -= 1
		if _wait <= 0:
			_start()
		return
	var t: int = int(_match.get("tick"))
	if _render and t >= _next_shot:
		_next_shot = t + _every
		_shoot(t)
	if not _result.is_empty() or t >= _end + 5:
		_done = true
		_finish.call_deferred()


## An empty .gdignore keeps Godot from importing the PNGs.
func _hide_from_import(dir: String) -> void:
	var f: FileAccess = FileAccess.open(dir + "/.gdignore", FileAccess.WRITE)
	if f != null:
		f.close()


func _shoot(t: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/frame_%05d.png" % [_out_dir, t])


func _finish() -> void:
	var cmp: Dictionary = FlightRecorder.compare(_rec, _recorder.recording())
	var orig: Dictionary = _rec.get("result", {}) as Dictionary
	var match_ok: bool = not _result.is_empty() and not orig.is_empty() \
		and int(_result.get("winner", -2)) == int(orig.get("winner", -3)) \
		and str(_result.get("reason", "")) == str(orig.get("reason", "?")) \
		and int(_result.get("ticks", -1)) == int(orig.get("ticks", -2))
	if orig.is_empty():
		match_ok = not _result.is_empty()
	var line: String = "REPLAY ticks=%d divergence=%.3f result_match=%s first_div_tick=%d winner=%s reason=%s" % [
		_end, float(cmp["divergence"]), "yes" if match_ok else "no", int(cmp["first_tick"]),
		str(_result.get("winner", "none")), str(_result.get("reason", "none"))]
	if _tuned:
		line += " tuned=yes"
	if _render:
		line += " frames=%s" % _out_dir
	print(line)
	if Flags.args.has("dump"):
		_recorder.save(Flags.get_arg("dump"))
	var bad: bool = not _tuned and (float(cmp["divergence"]) > 0.0005 or not match_ok or not bool(cmp["hash_match"]))
	get_tree().quit(1 if bad else 0)
