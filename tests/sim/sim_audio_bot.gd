extends "res://tests/sim/sim_base.gd"
## Audio over bot matches: a SfxDirector tracks both fighters of heavy-vs-cleaver matches. Checks every sound key it
## asked for exists, nothing spams (plays per second, per key), the pool never runs dry for important sounds, and
## prints the per-key counts as INFO. No wall clock; sim seconds only.

const CASES: Array = [[101, "sledgehammer", "falchion"], [202, "halberd", "mace"], [303, "machete", "warhammer"]]
const SECONDS: float = 40.0
const TAIL_SECONDS: float = 7.0
const MAX_PLAYS_PER_S: float = 45.0
## A fight shorter than this is mostly its opening clash and finisher burst (max/s covers bursts), so the mean uses at least this many seconds.
const MEAN_MIN_SECS: float = 8.0
const MAX_MEAN_PLAYS_PER_S: float = 25.0  # requests, before the voice caps drop any; run-to-run varies by about 10 percent
const MAX_STEPS_PER_S: float = 7.0
## Both fighters sprint in to the opening clash, so a fight that ends soon after is mostly run steps; the step rate uses at least this many seconds.
const STEPS_MIN_SECS: float = 12.0
const MAX_POOL_FRACTION: float = 0.8


func _play(seed_value: int, wa: String, wb: String) -> Dictionary:
	await sandbox()
	var m := Match.new()
	world.add_child(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var la: Dictionary = MatchConfig.random_loadout(rng)
	var lb: Dictionary = MatchConfig.random_loadout(rng)
	la["weapon"] = wa
	lb["weapon"] = wb
	la["offhand"] = ""
	lb["offhand"] = ""
	m.setup({"mode": "bot_vs_bot", "seed": seed_value, "presentation": false, "time_limit_s": SECONDS, "loadouts": [la, lb]})
	var d := SfxDirector.new()
	world.add_child(d)
	for f: Variant in m.fighters:
		d.track(f as Node3D)
	var counts: Dictionary = {}
	var missing: int = 0
	var peak_playing: int = 0
	var sum_playing: int = 0
	var peak_use: Dictionary = {}
	var n_samples: int = 0
	var max_per_s: float = 0.0
	var last_total: int = 0
	var ticks: int = int(SECONDS * 60.0)
	var seen: int = 0
	var tail: int = -1
	for i: int in range(ticks):
		await host.get_tree().physics_frame
		var rk: PackedStringArray = d.recent_keys
		# recent_keys is a rolling log; count newly played keys by played_count delta.
		var fresh: int = d.played_count - seen
		seen = d.played_count
		for j: int in range(maxi(rk.size() - fresh, 0), rk.size()):
			counts[rk[j]] = int(counts.get(rk[j], 0)) + 1
		if (i + 1) % 60 == 0:
			max_per_s = maxf(max_per_s, float(d.played_count - last_total))
			last_total = d.played_count
		var playing: int = 0
		for c: Node in d.get_children():
			if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).playing:
				playing += 1
		if playing > peak_playing:
			peak_use = d.group_use()
		peak_playing = maxi(peak_playing, playing)
		sum_playing += playing
		n_samples += 1
		if m.result.size() > 0 and tail < 0:
			tail = i + int(TAIL_SECONDS * 60.0)  # keep listening: the fountain and gut spill outlast the match
		if tail >= 0 and i >= tail:
			break
	for k: Variant in counts:
		if SfxLogic.variant_count(str(k)) <= 0:
			missing += 1
	var out: Dictionary = {"counts": counts, "missing": missing, "peak": peak_playing, "max_per_s": max_per_s,
		"dropped": d.dropped_count, "capped": d.capped_count, "dropped_keys": d.dropped_keys, "peak_use": peak_use, "pool_mean": float(sum_playing) / maxf(float(n_samples), 1.0), "pool_size": SfxDirector.POOL_SIZE, "secs": float(m.tick) / 60.0, "mean": float(d.played_count) / maxf(float(m.tick) / 60.0, MEAN_MIN_SECS)}
	await clear()
	return out


func run() -> Array:
	var rows: Array = []
	var worst_rate: float = 0.0
	var worst_steps: float = 0.0
	var worst_mean: float = 0.0
	var missing: int = 0
	var peak: int = 0
	var all_keys: Dictionary = {}
	for c: Array in CASES:
		var o: Dictionary = await _play(int(c[0]), str(c[1]), str(c[2]))
		worst_rate = maxf(worst_rate, float(o["max_per_s"]))
		worst_mean = maxf(worst_mean, float(o["mean"]))
		missing += int(o["missing"])
		peak = maxi(peak, int(o["peak"]))
		var steps: int = int((o["counts"] as Dictionary).get("move/footstep_sand", 0)) + int((o["counts"] as Dictionary).get("move/footstep_run", 0))
		worst_steps = maxf(worst_steps, float(steps) / maxf(float(o["secs"]), STEPS_MIN_SECS))
		for k: Variant in o["counts"]:
			all_keys[k] = int(all_keys.get(k, 0)) + int(o["counts"][k])
		rows.append(row("audio %s v %s" % [c[1], c[2]], null, "secs=%.1f peak_players=%d/%d mean_players=%.1f max/s=%.0f mean/s=%.1f pool_full_drops=%d capped=%d peak_use=%s" % [o["secs"], o["peak"], o["pool_size"], o["pool_mean"], o["max_per_s"], o["mean"], o["dropped"], o["capped"], o["peak_use"]]))
		var cc: Dictionary = o["counts"]
		var wh: String = ""
		for wk: String in ["slow", "mid", "fast", "heavy", "cleave"]:
			wh += " %s=%.2f/s" % [wk, float(cc.get("move/whoosh_" + wk, 0)) / maxf(float(o["secs"]), 1.0)]
		var st: float = float(int(cc.get("move/footstep_sand", 0)) + int(cc.get("move/footstep_run", 0))) / maxf(float(o["secs"]), 1.0)
		rows.append(row("audio whooshes %s v %s" % [c[1], c[2]], null, wh.strip_edges() + " steps=%.2f/s dropped_keys=%s" % [st, str(o["dropped_keys"])]))
	rows.append(row("audio: pool headroom", peak <= int(SfxDirector.POOL_SIZE * MAX_POOL_FRACTION), "peak %d of %d" % [peak, SfxDirector.POOL_SIZE]))
	rows.append(row("audio keys played", null, str(all_keys)))
	rows.append(row("audio: all keys exist", missing == 0, "missing=%d" % missing))
	rows.append(row("audio: no spam", worst_rate <= MAX_PLAYS_PER_S, "max plays/s %.0f" % worst_rate))
	rows.append(row("audio: mean rate sane", worst_mean <= MAX_MEAN_PLAYS_PER_S, "mean plays/s %.1f" % worst_mean))
	rows.append(row("audio: footstep rate sane", worst_steps <= MAX_STEPS_PER_S, "steps/s %.1f" % worst_steps))
	rows.append(row("audio: footsteps heard", (all_keys.get("move/footstep_sand", 0) as int) + (all_keys.get("move/footstep_run", 0) as int) > 0, "steps"))
	rows.append(row("audio: gush heard after a behead or gut", (all_keys.get("gore/behead", 0) as int) + (all_keys.get("gore/gut", 0) as int) == 0 or (all_keys.get("gore/gush_pulse", 0) as int) > 0, "gush_pulse"))
	rows.append(row("audio: weapon whooshes heard", (all_keys.get("move/whoosh_heavy", 0) as int) + (all_keys.get("move/whoosh_cleave", 0) as int) > 0, "heavy/cleave whoosh"))
	return rows
