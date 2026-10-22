extends Node
## Seeded headless bot vs bot matches (presentation off). Args after `--`:
##   --shard=i --nshards=n   this process runs global matches i, i+n, i+2n, ... (default 0 of 1)
##   --matches=M             matches this shard runs (default 4)
##   --seed=S                base seed (default 1000); global match g uses seed S+g
##   --time_limit=<s>        game seconds per match (default 60)
##   --keep                  also write the flight recording of passing matches
##   --difficulty=<id>       AI difficulty (easy, normal, hard) of the side given by --side; the other side
##                           is normal. Without it nothing changes (the seeded personalities as before).
##   --side=0|1              which side gets --difficulty (default 0)
##   --w0=<id> --w1=<id>     force a side's weapon (no offhand); --armor=none|leather forces both sides' armor
##   --o0=<id> --o1=<id>     force a side's off hand (after --w0/--w1; "" for none)
##   --a0=<ids> --a1=<ids>   force a side's armor, comma-separated armor ids ("" for none)
##   --wide=0|1              that side swings broad horizontal sweeps (a human-style proxy)
##   --hitlog                add per-hit sums (damage, bleed, contact kinds, by weapon) to the stats as "hitlog"
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
var _hitlog: Dictionary = {}


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
	var cfg: Dictionary = {"mode": "bot_vs_bot", "seed": seed_v, "presentation": false, "loop": false, "time_limit_s": _time_limit}
	var diff: String = Flags.get_arg("difficulty", "")
	if diff != "":
		var side: int = clampi(int(Flags.get_arg("side", "0")), 0, 1)
		var pers: Array = (MatchConfig.normalize({"seed": seed_v}, seed_v)["personalities"] as Array).duplicate(true)
		(pers[side] as Dictionary)["difficulty"] = diff
		(pers[1 - side] as Dictionary)["difficulty"] = "normal"
		cfg["personalities"] = pers
	var forced: Array = _forced_loadouts(seed_v)
	if not forced.is_empty():
		cfg["loadouts"] = forced
	var wide: String = Flags.get_arg("wide", "")
	if wide != "":
		var pw: Array = (MatchConfig.normalize({"seed": seed_v}, seed_v)["personalities"] as Array).duplicate(true)
		if cfg.has("personalities"):
			pw = cfg["personalities"]
		var ws: int = clampi(int(wide), 0, 1)
		(pw[ws] as Dictionary)["preset"] = "berserker"
		(pw[ws] as Dictionary)["preferred_attacks"] = ["horizontal"]
		cfg["personalities"] = pw
	_match.call("setup", cfg)
	_hitlog = {}
	if Flags.args.has("hitlog"):
		for f: Variant in _match.get("fighters"):
			(f as Object).connect("hit", _on_hitlog)
	_recorder = FlightRecorder.new()
	add_child(_recorder)
	_recorder.attach(_match)
	_match.connect("match_over", func(r: Dictionary) -> void: _result = r)
	_limit_ticks = int(_time_limit * 60.0) + 600
	_t0 = Time.get_ticks_usec()


func _forced_loadouts(seed_v: int) -> Array:
	var w0: String = Flags.get_arg("w0", "")
	var w1: String = Flags.get_arg("w1", "")
	var arm: String = Flags.get_arg("armor", "")
	var offs: Array = [Flags.get_arg("o0", "-"), Flags.get_arg("o1", "-")]
	var sets: Array = [Flags.get_arg("a0", "-"), Flags.get_arg("a1", "-")]
	if w0 == "" and w1 == "" and arm == "" and offs == ["-", "-"] and sets == ["-", "-"]:
		return []
	var base: Array = MatchConfig.normalize({"seed": seed_v}, seed_v)["loadouts"]
	var out: Array = []
	for i: int in 2:
		var l: Dictionary = (base[i] as Dictionary).duplicate(true)
		var w: String = w0 if i == 0 else w1
		if w != "":
			l["weapon"] = w
			l["offhand"] = ""
		if arm == "none":
			l["armor"] = {}
		elif arm == "leather":
			l["armor"] = {"head": "helm_leather", "torso": "cuirass_leather", "upper_arm_l": "bracers_leather", "thigh_l": "greaves_leather"}
		if str(offs[i]) != "-":
			l["offhand"] = str(offs[i])
		if str(sets[i]) != "-":
			l["armor"] = {}
			for aid: String in str(sets[i]).split(",", false):
				l["armor"][str(CombatData.armor(aid).get("part", ""))] = aid
		out.append(l)
	return out


func _on_hitlog(ev: Dictionary) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		return
	var k: String = str(ev.get("weapon_id", "?"))
	var d: Dictionary = _hitlog.get(k, {"n": 0, "total": 0.0, "pierce": 0.0, "cut": 0.0, "blunt": 0.0, "bleed": 0.0, "energy": 0.0, "speed": 0.0, "emass": 0.0, "point": 0, "blunt_n": 0})
	d["n"] = int(d["n"]) + 1
	for f: String in ["total", "pierce", "cut", "blunt", "bleed", "energy"]:
		d[f] = float(d[f]) + float(ev.get(f, 0.0))
	d["speed"] = float(d["speed"]) + (ev.get("rel_vel", Vector3.ZERO) as Vector3).length()
	d["emass"] = float(d["emass"]) + float(ev.get("effective_mass", 0.0))
	if str(ev.get("contact", "")) == "point":
		d["point"] = int(d["point"]) + 1
	if not (ev.get("armor_ids", []) as Array).is_empty():  # hits on armor, and those that found a plate gap (ArmorGaps)
		d["armored_n"] = int(d.get("armored_n", 0)) + 1
		if float(ev.get("armor_gap", 0.0)) > 0.0:
			d["gap_n"] = int(d.get("gap_n", 0)) + 1
	if str(ev.get("part", "")) == "head":
		d["head_n"] = int(d.get("head_n", 0)) + 1
		d["head_blunt"] = float(d.get("head_blunt", 0.0)) + float(ev.get("blunt", 0.0))
	_hitlog[k] = d


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
	if not _hitlog.is_empty():
		stats["hitlog"] = _hitlog.duplicate(true)
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
