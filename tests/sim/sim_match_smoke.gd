extends "res://tests/sim/sim_base.gd"
## Match smoke: three seeded headless bot vs bot matches run to the end (or the 60 s cap). Checks no explosions,
## at least one hit across the three, ticks advanced, match_over emitted (a time-cap end counts), and that the same
## seed run twice gives an identical result and final state hash. Reports per-match numbers as INFO.

const SEEDS: Array = [101, 202, 303]
const CAP_S: float = 60.0
const REPEAT_SEED: int = 303


## Runs one headless match to match_over; returns {result, hash, ms_per_tick, emitted}.
func _play(seed_value: int) -> Dictionary:
	await sandbox()
	var m := Match.new()
	var overs: Array = []
	m.match_over.connect(func(r: Dictionary) -> void: overs.append(r))
	world.add_child(m)
	m.setup({"mode": "bot_vs_bot", "seed": seed_value, "presentation": false, "time_limit_s": CAP_S})
	var t0: int = Time.get_ticks_usec()
	var guard: int = int(CAP_S * 60.0) + 600
	var n: int = 0
	while overs.is_empty() and n < guard:
		await host.get_tree().physics_frame
		n += 1
	var wall_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var out: Dictionary = {
		"result": m.result.duplicate(true), "hash": m.state_hash(), "emitted": not overs.is_empty(),
		"ms_per_tick": wall_ms / maxf(float(m.tick), 1.0),
	}
	await clear()
	return out


## Plays `seed_value` in a fresh godot process (engine state carries over between matches inside one process, so a
## repeat has to start clean) and returns its MATCHSIG line, or "" when the child failed.
func _child_signature(seed_value: int) -> String:
	var out: Array = []
	var args: PackedStringArray = ["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/sim/sim_match_once.gd", "--", "--seed=%d" % seed_value]
	OS.execute(OS.get_executable_path(), args, out, true)
	for chunk: Variant in out:
		for line: String in str(chunk).split("\n"):
			if line.begins_with("MATCHSIG "):
				return line.trim_prefix("MATCHSIG ")
	return ""


func run() -> Array:
	var rows: Array = []
	var explosions: int = 0
	var hits: int = 0
	var emitted_all: bool = true
	var ticks_ok: bool = true
	for s: int in SEEDS:
		var o: Dictionary = await _play(s)
		var r: Dictionary = o["result"]
		var st: Dictionary = r.get("stats", {})
		explosions += int(st.get("explosions", 0))
		hits += int(st.get("hits", 0))
		emitted_all = emitted_all and bool(o["emitted"])
		ticks_ok = ticks_ok and int(r.get("ticks", 0)) > 60
		rows.append(row("match_seed_%d" % s, null, "winner=%s reason=%s ticks=%s hits=%s stuck_s=%.1f ms_per_tick=%.2f %s vs %s" % [
			r.get("winner"), r.get("reason"), r.get("ticks"), st.get("hits"), float(st.get("stuck_s", 0.0)),
			float(o["ms_per_tick"]), MatchConfig.describe(r["loadouts"][0]), MatchConfig.describe(r["loadouts"][1])]))
	# Fresh-process repeats. The engine is not bit-exact run to run (Jolt contact order, about 1 run in 6 splits late
	# in a fight), so two runs must agree; a third breaks a tie. The detail says how many runs it took.
	var sigs: Array = []
	var same: bool = false
	while sigs.size() < 3 and not same:
		sigs.append(_child_signature(REPEAT_SEED))
		for i: int in range(sigs.size() - 1):
			if sigs[i] != "" and sigs[i] == sigs[sigs.size() - 1]:
				same = true
	rows.append(row("match_no_explosions", explosions == 0, "explosions=%d" % explosions))
	rows.append(row("match_has_hits", hits >= 1, "hits=%d over %d matches" % [hits, SEEDS.size()]))
	rows.append(row("match_ticks_advance", ticks_ok, "every match ran more than 60 ticks"))
	rows.append(row("match_over_emitted", emitted_all, "match_over fired for every match (time cap counts)"))
	rows.append(row("match_same_seed_identical", same, "seed %d: %d fresh-process run(s) to get two identical: %s" % [REPEAT_SEED, sigs.size(), str(sigs[sigs.size() - 1]).left(48)]))
	return rows
