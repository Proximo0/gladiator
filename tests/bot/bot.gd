extends Node
## Seeded headless bot vs bot matches (presentation off). Args after `--`:
##   --shard=i --nshards=n   this process runs global matches i, i+n, i+2n, ... (default 0 of 1)
##   --matches=M             matches this shard runs (default 4)
##   --seed=S                base seed (default 1000); global match g uses seed S+g
##   --time_limit=<s>        game seconds per match (default 60)
##   --keep                  also write the flight recording of passing matches
## Prints one `BOT match ...` line per match and `BOT score=<pass fraction> matches=N failed=F ...`.
## Writes out/bot/<seed>.json (result + MatchStats) and out/bot/<seed>.rec.json (flight recording) for every FAIL.
## A match that fails is also explained on a `BOT why seed=.. ...` line (it never contains the word FAIL in capitals
## surrounded by spaces, so CI greps for ` FAIL ` only hit the match line).

const MATCH_SCRIPT: String = "res://game/match/match.gd"
const STUCK_FAIL_S: float = 20.0
const START_WAIT: int = 12  ## physics ticks of an empty world before a match is built

var _plan: Array = []
var _idx: int = 0
var _match: Node = null
var _recorder: FlightRecorder = null
var _t0: int = 0
var _time_limit: float = 60.0
var _limit_ticks: int = 0
var _passed: int = 0
var _failed: int = 0
var _hits_total: int = 0
var _ms_total: float = 0.0
var _ticks_total: int = 0
var _out_dir: String = ""
var _result: Dictionary = {}
var _match_script: GDScript = null
var _wait: int = 0
var _world: SubViewport = null


func _ready() -> void:
	var shard: int = int(Flags.get_arg("shard", "0"))
	var nshards: int = maxi(int(Flags.get_arg("nshards", "1")), 1)
	var matches: int = int(Flags.get_arg("matches", "4"))
	var base: int = int(Flags.get_arg("seed", "1000"))
	_time_limit = float(Flags.get_arg("time_limit", "60"))
	_out_dir = ProjectSettings.globalize_path("res://out/bot")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var gi: FileAccess = FileAccess.open(_out_dir + "/.gdignore", FileAccess.WRITE)  # keep the editor out of out/bot
	if gi != null:
		gi.close()
	_match_script = load(Flags.get_arg("match_script", MATCH_SCRIPT)) as GDScript
	for k: int in range(matches):
		_plan.append(base + shard + k * nshards)
	_wait = START_WAIT


## A match always starts inside _physics_process, START_WAIT ticks after the previous one was freed, the same way
## tests/replay/replay.gd starts one, so a recording replays from a fresh process exactly.
func _start() -> void:
	if _idx >= _plan.size():
		_summary()
		return
	var seed_v: int = int(_plan[_idx])
	_result = {}
	_match = _match_script.new()
	_world = SubViewport.new()
	_world.own_world_3d = true
	_world.size = Vector2i(64, 64)
	_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_world)
	_world.add_child(_match)
	_match.call("setup", {"mode": "bot_vs_bot", "seed": seed_v, "presentation": false, "loop": false, "time_limit_s": _time_limit})
	_recorder = FlightRecorder.new()
	add_child(_recorder)
	_recorder.attach(_match)
	_match.connect("match_over", func(r: Dictionary) -> void: _result = r)
	_limit_ticks = int(_time_limit * 60.0) + 600
	_t0 = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	if _match == null:
		if _wait > 0:
			_wait -= 1
			if _wait == 0:
				_start()
		return
	var t: int = int(_match.get("tick"))
	if _result.is_empty() and t < _limit_ticks:
		return
	var wall_us: int = Time.get_ticks_usec() - _t0
	var seed_v: int = int(_plan[_idx])
	var hung: bool = _result.is_empty()
	_judge(seed_v, _result, t, wall_us, hung)
	_world.queue_free()
	_recorder.queue_free()
	_match = null
	_idx += 1
	_wait = START_WAIT


func _judge(seed_v: int, res: Dictionary, ticks_now: int, wall_us: int, hung: bool) -> void:
	var stats: Dictionary = res.get("stats", {}) as Dictionary
	var ticks: int = int(res.get("ticks", ticks_now))
	var hits: int = int(stats.get("hits", 0))
	var stuck: float = float(stats.get("stuck_s", 0.0))
	var expl: int = int(stats.get("explosions", 0))
	var reason: String = str(res.get("reason", "hang"))
	var mspt: float = float(wall_us) / 1000.0 / float(maxi(ticks_now, 1))
	var why: PackedStringArray = PackedStringArray()
	if hung:
		why.append("match_over never fired")
	if expl > 0:
		why.append("explosions=%d" % expl)
	if stuck > STUCK_FAIL_S:
		why.append("stuck_s=%.1f" % stuck)
	if hits == 0:
		why.append("time limit with both fighters untouched" if reason == "time" else "no hits")
	var ok: bool = why.is_empty()
	print("BOT match seed=%d winner=%s reason=%s ticks=%d hits=%d stuck_s=%.1f explosions=%d ms_per_tick=%.2f %s" % [
		seed_v, str(res.get("winner", -1)), reason, ticks, hits, stuck, expl, mspt, "PASS" if ok else "FAIL"])
	_ticks_total += ticks_now
	_ms_total += float(wall_us) / 1000.0
	_hits_total += hits
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("BOT why seed=%d %s" % [seed_v, ", ".join(why)])
	var out: Dictionary = FlightRecorder.json_safe({"seed": seed_v, "result": res, "stats": stats, "ms_per_tick": mspt,
		"ok": ok, "why": Array(why)}) as Dictionary
	var f: FileAccess = FileAccess.open("%s/%d.json" % [_out_dir, seed_v], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))
		f.close()
	if not ok or Flags.args.has("keep"):
		var rp: String = _recorder.save("%s/%d.rec.json" % [_out_dir, seed_v])
		if rp != "":
			print("BOT recording %s" % rp)


func _summary() -> void:
	var n: int = _passed + _failed
	var score: float = float(_passed) / float(maxi(n, 1))
	print("BOT score=%.2f matches=%d failed=%d hits=%d ms_per_tick=%.2f" % [
		score, n, _failed, _hits_total, _ms_total / float(maxi(_ticks_total, 1))])
	get_tree().quit(1 if _failed > 0 or n == 0 else 0)
