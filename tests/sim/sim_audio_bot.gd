extends "res://tests/sim/sim_base.gd"
## Audio over bot matches: a SfxDirector tracks both fighters of heavy-vs-cleaver matches. Checks every sound key it
## asked for exists, nothing spams (plays per second, per key), the pool never runs dry for important sounds, and
## prints the per-key counts as INFO. Voice stealing: no important sound (SfxLogic.is_important) is ever dropped or
## cut, in the bot fights and in a flood where a finisher lands on a full pool. No wall clock; sim seconds only.

const CASES: Array = [[101, "sledgehammer", "falchion"], [202, "halberd", "mace"], [303, "machete", "warhammer"]]
const SECONDS: float = 40.0
const TAIL_SECONDS: float = 7.0
const MAX_PLAYS_PER_S: float = 45.0
## A fight shorter than this is mostly its opening clash and finisher burst (max/s covers bursts), so the mean uses at least this many seconds.
const MEAN_MIN_SECS: float = 8.0
const MAX_MEAN_PLAYS_PER_S: float = 25.0  # requests, before the voice caps drop any; run-to-run varies by about 10 percent
const MAX_STEPS_PER_S: float = 7.0
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
		"dropped": d.dropped_count, "capped": d.capped_count, "stolen": d.stolen_count, "lost": d.lost_important.duplicate(), "lost_log": d.lost_log.duplicate(), "inversions": d.inversions, "finisher_plays": d.finisher_plays, "dropped_keys": d.dropped_keys, "peak_use": peak_use, "pool_mean": float(sum_playing) / maxf(float(n_samples), 1.0), "pool_size": SfxDirector.POOL_SIZE, "secs": float(m.tick) / 60.0, "mean": float(d.played_count) / maxf(float(m.tick) / 60.0, MEAN_MIN_SECS)}
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
	var lost_total: int = 0
	var inversions: int = 0
	for c: Array in CASES:
		var o: Dictionary = await _play(int(c[0]), str(c[1]), str(c[2]))
		worst_rate = maxf(worst_rate, float(o["max_per_s"]))
		worst_mean = maxf(worst_mean, float(o["mean"]))
		missing += int(o["missing"])
		peak = maxi(peak, int(o["peak"]))
		var steps: int = int((o["counts"] as Dictionary).get("move/footstep_sand", 0)) + int((o["counts"] as Dictionary).get("move/footstep_run", 0))
		worst_steps = maxf(worst_steps, float(steps) / maxf(float(o["secs"]), MEAN_MIN_SECS))  # a 3 s fight is all opening footwork
		for k: Variant in o["counts"]:
			all_keys[k] = int(all_keys.get(k, 0)) + int(o["counts"][k])
		rows.append(row("audio %s v %s" % [c[1], c[2]], null, "secs=%.1f peak_players=%d/%d mean_players=%.1f max/s=%.0f mean/s=%.1f pool_full_drops=%d capped=%d stolen=%d finisher_plays=%d lost_important=%s inversions=%d peak_use=%s" % [o["secs"], o["peak"], o["pool_size"], o["pool_mean"], o["max_per_s"], o["mean"], o["dropped"], o["capped"], o["stolen"], o["finisher_plays"], o["lost"], o["inversions"], o["peak_use"]]))
		lost_total += _sum(o["lost"] as Dictionary)
		for ll: String in (o["lost_log"] as PackedStringArray):
			rows.append(row("audio lost %s v %s" % [c[1], c[2]], null, ll))
		inversions += int(o["inversions"])
		var cc: Dictionary = o["counts"]
		var wh: String = ""
		for wk: String in ["slow", "mid", "fast", "heavy", "cleave"]:
			wh += " %s=%.2f/s" % [wk, float(cc.get("move/whoosh_" + wk, 0)) / maxf(float(o["secs"]), 1.0)]
		var st: float = float(int(cc.get("move/footstep_sand", 0)) + int(cc.get("move/footstep_run", 0))) / maxf(float(o["secs"]), 1.0)
		rows.append(row("audio whooshes %s v %s" % [c[1], c[2]], null, wh.strip_edges() + " steps=%.2f/s dropped_keys=%s" % [st, str(o["dropped_keys"])]))
	rows.append(row("audio: pool headroom", peak <= int(SfxDirector.POOL_SIZE * MAX_POOL_FRACTION), "peak %d of %d" % [peak, SfxDirector.POOL_SIZE]))
	rows.append(row("audio keys played", null, str(all_keys)))
	rows.append(row("audio mix", null, _mix(all_keys)))
	rows.append(row("audio: no important sound lost in bot fights", lost_total == 0 and inversions == 0, "lost=%d inversions=%d" % [lost_total, inversions]))
	rows.append_array(await _flood())
	rows.append(row("audio: all keys exist", missing == 0, "missing=%d" % missing))
	rows.append(row("audio: no spam", worst_rate <= MAX_PLAYS_PER_S, "max plays/s %.0f" % worst_rate))
	rows.append(row("audio: mean rate sane", worst_mean <= MAX_MEAN_PLAYS_PER_S, "mean plays/s %.1f" % worst_mean))
	rows.append(row("audio: footstep rate sane", worst_steps <= MAX_STEPS_PER_S, "steps/s %.1f" % worst_steps))
	rows.append(row("audio: footsteps heard", (all_keys.get("move/footstep_sand", 0) as int) + (all_keys.get("move/footstep_run", 0) as int) > 0, "steps"))
	rows.append(row("audio: gush heard after a behead or gut", (all_keys.get("gore/behead", 0) as int) + (all_keys.get("gore/gut", 0) as int) == 0 or (all_keys.get("gore/gush_pulse", 0) as int) > 0, "gush_pulse"))
	rows.append(row("audio: weapon whooshes heard", (all_keys.get("move/whoosh_heavy", 0) as int) + (all_keys.get("move/whoosh_cleave", 0) as int) > 0, "heavy/cleave whoosh"))
	return rows


func _sum(d: Dictionary) -> int:
	var n: int = 0
	for k: Variant in d:
		n += int(d[k])
	return n


## Plays per family (requests, before the caps), and the share of each.
func _mix(keys: Dictionary) -> String:
	var fam: Dictionary = {}
	var total: int = 0
	for k: Variant in keys:
		var ks: String = str(k)
		var f: String = ks.get_slice("/", 0)
		if ks.begins_with("move/footstep") or ks == "move/armor_rattle":
			f = "steps"
		elif ks.begins_with("move/whoosh") or ks == "move/roll_whoosh":
			f = "whoosh"
		elif ks == "gore/spurt_hiss" or ks == "gore/gush_pulse" or ks == "gore/gut_flop" or ks == "gore/blood_spatter_sand":
			f = "gore_bed"
		fam[f] = int(fam.get(f, 0)) + int(keys[k])
		total += int(keys[k])
	var out: String = ""
	for f: Variant in fam:
		out += "%s=%d (%.0f%%) " % [f, fam[f], 100.0 * float(fam[f]) / maxf(float(total), 1.0)]
	return out.strip_edges()


## A finisher lands while the pool, the impact group and the crowd pool are full of minor sounds, and more minor hits
## follow: every immediate layer of it (and of a heavy warhammer hit), the behead stinger, the death gurgle and the
## finisher roar must be playing afterwards, and nothing important may be lost.
func _flood() -> Array:
	await sandbox()
	var d := SfxDirector.new()
	world.add_child(d)
	await host.get_tree().physics_frame
	var minor: Dictionary = {"part": "forearm_l", "weapon_id": "gladius", "contact": "blunt", "energy": 25.0, "total": 2.0,
		"blunt": 2.0, "hit_on_weapon": false, "glanced": false, "armor_ids": [], "target": 1, "point": Vector3(0.5, 1.0, 0.0)}
	for _i: int in range(4):
		for _j: int in range(6):
			d.on_hit(minor, null)
			d.play_key("move/whoosh_cleave", Vector3.ZERO, -6.0)
			d.play_key("move/roll_thud", Vector3.ZERO, -6.0)
			d.play_key("voice/grunt", Vector3.ZERO, -4.0, 1.0, "Voice")
			d.play_key("move/footstep_sand", Vector3.ZERO, -6.0)
			d.play_key("gore/gut_squelch", Vector3.ZERO, -8.0)
			d.play_2d("crowd/gasp", -2.0)
			d.play_2d("crowd/cheer", -2.0)
		await host.get_tree().physics_frame
	var busy_before: int = d.group_use().values().reduce(func(a: int, b: int) -> int: return a + b, 0)
	var impact_before: int = int(d.group_use().get("impact", 0))
	var lost_before: int = _sum(d.lost_important)
	var fin: Dictionary = {"part": "head", "weapon_id": "warhammer", "contact": "blunt", "energy": 400.0, "total": 60.0,
		"blunt": 50.0, "hit_on_weapon": false, "glanced": false, "armor_ids": [], "target": 0, "point": Vector3(0.0, 1.6, 0.0),
		"finisher": "skull_crush"}
	var heavy: Dictionary = fin.duplicate()
	heavy.erase("finisher")
	heavy["part"] = "torso"
	heavy["energy"] = 260.0
	d.on_hit(heavy, null)
	d.on_hit(fin, null)
	d.on_gore({"kind": "behead", "part": "head", "point": Vector3(0.0, 1.6, 0.0)}, null)
	var want: Array[String] = ["gore/behead"]
	for l: Dictionary in SfxLogic.limit_layers(SfxLogic.impact_plan(fin, "steel", "", "")):
		if float(l["delay"]) <= 0.004:
			want.append(str(l["key"]))
	for l: Dictionary in SfxLogic.limit_layers(SfxLogic.impact_plan(heavy, "steel", "", "")):
		if float(l["delay"]) <= 0.004 and SfxLogic.is_important(SfxLogic.priority(str(l["key"]), float(l["gain_db"]), SfxLogic.hit_boost_db(heavy))):
			want.append(str(l["key"]))
	for _i: int in range(2):  # more minor hits right after: they must not cut the finisher
		for _j: int in range(6):
			d.on_hit(minor, null)
			d.play_key("move/whoosh_cleave", Vector3.ZERO, -6.0)
			d.play_key("gore/gut_squelch", Vector3.ZERO, -8.0)
		await host.get_tree().physics_frame
	var playing: Dictionary = _playing_keys(d)
	var missing: Array[String] = []
	for k: String in want:
		if int(playing.get(k, 0)) <= 0:
			missing.append(k)
		else:
			playing[k] = int(playing[k]) - 1
	d.on_died(null)
	for _i: int in range(40):  # the death gurgle (0.15 s) and the finisher roar (0.2 s) are delayed
		await host.get_tree().physics_frame
	var late: Dictionary = _playing_keys(d)
	for k: String in ["voice/death_gurgle", "crowd/finisher_roar"]:
		if int(late.get(k, 0)) <= 0:
			missing.append(k)
	var rows: Array = []
	rows.append(row("audio flood: pool full of minor sounds", null, "busy=%d/%d impact=%d lost_before=%d" % [busy_before, SfxDirector.POOL_SIZE, impact_before, lost_before]))
	rows.append(row("audio flood: finisher and heavy hit never dropped", missing.is_empty() and _sum(d.lost_important) == 0 and d.inversions == 0,
		"missing=%s lost_important=%s inversions=%d stolen=%d" % [str(missing), str(d.lost_important), d.inversions, d.stolen_count]))
	await clear()
	return rows


func _playing_keys(d: SfxDirector) -> Dictionary:
	var out: Dictionary = {}
	for i: int in range(d._pool.size()):
		if d._pool[i].playing:
			var k: String = str(d._meta[i].get("key", "?"))
			out[k] = int(out.get(k, 0)) + 1
	for i: int in range(d._pool_2d.size()):
		if d._pool_2d[i].playing:
			var k2: String = str(d._meta_2d[i].get("key", "?"))
			out[k2] = int(out.get(k2, 0)) + 1
	return out
