extends "res://tests/sim/sim_base.gd"
## Flight recording across an intro: a headless match holds its fight clock (as MatchShow does offline), the skip
## releases it between two physics ticks, the match runs out its time limit, and the recording (through JSON) replays
## from tick 0 to the same end. Checks the recording keeps fight_start_tick and that the replay ends on the same match
## tick, fight tick, reason and MatchStats ticks.

const SEED: int = 4242
const LIMIT_S: float = 6.0
const INTRO_TICKS: int = 77  ## held ticks before the skip (not a multiple of anything the recorder uses)
const GUARD_TICKS: int = 900
const FISTS: Dictionary = {"weapon": "fists", "offhand": "", "armor": {}}


func run() -> Array:
	var orig: Dictionary = await _record()
	var rec: Dictionary = FlightRecorder.parse(FlightRecorder.to_json(orig["rec"] as Dictionary))
	var kept: int = int(rec.get("fight_start_tick", -1))
	var rep: Dictionary = await _replay(rec)
	var a: Dictionary = orig["result"]
	var b: Dictionary = rep
	var same: bool = not a.is_empty() and not b.is_empty() and str(a.get("reason")) == str(b.get("reason")) \
		and int(a.get("ticks", -1)) == int(b.get("ticks", -2)) and int(a.get("fight_ticks", -1)) == int(b.get("fight_ticks", -2)) \
		and int((a.get("stats", {}) as Dictionary).get("ticks", -1)) == int((b.get("stats", {}) as Dictionary).get("ticks", -2))
	var limit_ticks: int = roundi(LIMIT_S * 60.0)
	return [
		row("replay_clock_kept", kept == int(orig["start"]) and kept >= INTRO_TICKS,
			"recording fight_start_tick=%d, match released at %d" % [kept, int(orig["start"])]),
		row("replay_clock_fight_ticks", int(a.get("fight_ticks", -1)) == limit_ticks and str(a.get("reason")) == "time"
			and int((a.get("stats", {}) as Dictionary).get("ticks", -1)) == limit_ticks + 1,
			"reason=%s fight_ticks=%s stats.ticks=%s (limit %d ticks)" % [a.get("reason"), a.get("fight_ticks"),
			(a.get("stats", {}) as Dictionary).get("ticks"), limit_ticks]),
		row("replay_clock_same_end", same, "original ticks=%s fight=%s reason=%s, replay ticks=%s fight=%s reason=%s" % [
			a.get("ticks"), a.get("fight_ticks"), a.get("reason"), b.get("ticks"), b.get("fight_ticks"), b.get("reason")]),
	]


func _record() -> Dictionary:
	await sandbox(true)
	var m := Match.new()
	var over: Array = []
	m.match_over.connect(func(r: Dictionary) -> void: over.append(r))
	world.add_child(m)
	var rec := FlightRecorder.new()
	world.add_child(rec)
	rec.attach(m)
	m.setup({"mode": "bot_vs_bot", "seed": SEED, "presentation": false, "loop": false, "time_limit_s": LIMIT_S,
		"loadouts": [FISTS, FISTS]})
	m.hold_fight_clock()
	await step(INTRO_TICKS)
	await host.get_tree().process_frame  # the skip lands in an idle frame, between two physics ticks
	m.start_fight_clock()
	var n: int = 0
	while over.is_empty() and n < GUARD_TICKS:
		await step(1)
		n += 1
	var out: Dictionary = {"rec": rec.recording(), "start": m.fight_start_tick,
		"result": (over[0] as Dictionary).duplicate(true) if not over.is_empty() else {}}
	await clear()
	return out


func _replay(rec: Dictionary) -> Dictionary:
	if rec.has("error"):
		return {}
	await sandbox(true)
	var m := Match.new()
	var over: Array = []
	m.match_over.connect(func(r: Dictionary) -> void: over.append(r))
	world.add_child(m)
	m.setup(FlightRecorder.replay_config(rec, false))
	m.force_inputs(rec["inputs"] as Array)
	var n: int = 0
	while over.is_empty() and n < GUARD_TICKS:
		await step(1)
		n += 1
	var out: Dictionary = (over[0] as Dictionary).duplicate(true) if not over.is_empty() else {}
	await clear()
	return out
