extends Node
## Script cost of the hit-feel nodes (FeelDirector, HitStop, ScreenPunch) in a presented bot match, per frame, and how
## often each runs. Their `_process` is switched off and called here between timers instead (same order as in the
## game: director, hit-stop draw, punch). Args after `--`: --seed=S --wa=W --wb=W --quality=0|1|2 --frames=N.
## Prints one `FEELCOST {json}` line and quits. Run headless with fixed frames:
## godot --headless --fixed-fps 60 --path . res://tests/perf/feel_cost.tscn -- --quality=0

var _match: Match = null
var _fd: FeelDirector = null
var _frames: int = 0
var _max_frames: int = 3600
var _us: Dictionary = {"director": 0, "hit_stop": 0, "punch": 0}
var _peak: Dictionary = {"director": 0, "hit_stop": 0, "punch": 0}
var _active: Dictionary = {"hit_stop": 0, "punch": 0, "cine": 0}
var _over_at: int = -1
var _active_us: Array[int] = []  ## total feel us on frames where any effect is playing
var _idle_us: Array[int] = []


func _init() -> void:
	process_priority = 1000


func _ready() -> void:
	var seed_value: int = int(Flags.get_arg("seed", "4401"))
	GfxQuality.set_level(int(Flags.get_arg("quality", "0")))
	_max_frames = int(Flags.get_arg("frames", "3600"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var la: Dictionary = MatchConfig.random_loadout(rng)
	var lb: Dictionary = MatchConfig.random_loadout(rng)
	la["weapon"] = Flags.get_arg("wa", "longsword")
	lb["weapon"] = Flags.get_arg("wb", "axe")
	la["offhand"] = ""
	lb["offhand"] = ""
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": seed_value, "presentation": true, "loop": false, "time_limit_s": 60.0,
		"loadouts": [la, lb]})
	_fd = _match.presenter.feel
	_fd.set_process(false)
	_fd.hit_stop.set_process(false)
	_fd.punch.set_process(false)


func _time(key: String, c: Callable) -> int:
	var t0: int = Time.get_ticks_usec()
	c.call()
	var dt: int = Time.get_ticks_usec() - t0
	_us[key] = int(_us[key]) + dt
	_peak[key] = maxi(int(_peak[key]), dt)
	return dt


static func _pct(a: Array[int], q: float) -> int:
	if a.is_empty():
		return 0
	var b: Array[int] = a.duplicate()
	b.sort()
	return b[clampi(int(q * float(b.size() - 1)), 0, b.size() - 1)]


func _process(delta: float) -> void:
	_frames += 1
	var busy: bool = _fd.hit_stop.logic.active() or _fd.punch.logic.active() or _fd.cine_time() >= 0.0
	var total: int = _time("director", func() -> void: _fd._process(delta))
	total += _time("hit_stop", func() -> void: _fd.hit_stop._process(delta))
	total += _time("punch", func() -> void: _fd.punch._process(delta))
	busy = busy or _fd.hit_stop.logic.active() or _fd.punch.logic.active()
	if busy:
		_active_us.append(total)
	else:
		_idle_us.append(total)
	if _fd.hit_stop.logic.active():
		_active["hit_stop"] = int(_active["hit_stop"]) + 1
	if _fd.punch.logic.active():
		_active["punch"] = int(_active["punch"]) + 1
	if _fd.cine_time() >= 0.0:
		_active["cine"] = int(_active["cine"]) + 1
	if _frames >= _max_frames or (_match.over and _frames > 0 and _fd.cine_time() < 0.0 and _match.tick > 0 and _over_long()):
		var n: float = float(maxi(_frames, 1))
		var out: Dictionary = {"quality": GfxQuality.level, "frames": _frames, "hits": _fd.hit_log.size(),
			"mean_us": {"director": int(_us["director"]) / n, "hit_stop": int(_us["hit_stop"]) / n, "punch": int(_us["punch"]) / n},
			"peak_us": _peak, "active_us_p50_p95_p99": [_pct(_active_us, 0.5), _pct(_active_us, 0.95), _pct(_active_us, 0.99)],
			"idle_us_p50_p99": [_pct(_idle_us, 0.5), _pct(_idle_us, 0.99)], "active_frames": _active, "hit_stop_max_shift_m": _fd.hit_stop.max_shift}
		print("FEELCOST ", JSON.stringify(out))
		get_tree().quit()


func _over_long() -> bool:
	if _over_at < 0:
		_over_at = _frames
	return _frames - _over_at > 180
