extends "res://tests/sim/sim_base.gd"
## Hit feel over bot matches. Every resolved hit is classed and fed to HitStopLogic stepped at 60 fps (the shown
## frame rate), giving hold lengths per hit class, the longest continuous stall and the share of time stalled
## (INFO rows, checked against caps). One match also runs the real HitStop node on the live fighters with a probe
## that, at physics time, checks every part's mesh slot is back at its rest transform (physics never sees the lagged
## pose) and, at draw time, counts the frames it was drawn lagged. Sim seconds only.

const CASES: Array = [[4401, "longsword", "axe"], [4404, "axe", "longsword"], [4202, "sledgehammer", "spear"], [4408, "falchion", "halberd"]]  ## two end in a finisher (run through, gut)
const SECONDS: float = 45.0
const MAX_STALL_S: float = 0.25  ## longest continuous run of frames shown at under half speed
const MAX_STALL_SHARE: float = 0.15
const PROBE_PRIORITY: int = -999  ## right after HitStop restores (-1000), before any game physics


class RestProbe:
	extends Node
	var stop: HitStop = null
	var fighters: Array = []
	var off_at_physics: int = 0
	var lagged_draws: int = 0
	var checks: int = 0

	func _init() -> void:
		process_physics_priority = -999
		process_priority = 1001

	func _looks() -> Array:
		var out: Array = []
		for f: Variant in fighters:
			if not is_instance_valid(f):
				continue
			for b: Variant in (f as Fighter).parts.values():
				var look: Node3D = (b as Node).get_node_or_null("Look") as Node3D
				if look != null:
					out.append(look)
		return out

	func _physics_process(_d: float) -> void:
		for look: Node3D in _looks():
			checks += 1
			if not look.transform.is_equal_approx(Transform3D.IDENTITY):
				off_at_physics += 1

	func _process(_d: float) -> void:
		for look: Node3D in _looks():
			if not look.transform.is_equal_approx(Transform3D.IDENTITY):
				lagged_draws += 1
				return


func _play(seed_value: int, wa: String, wb: String, probe: bool) -> Dictionary:
	await sandbox()
	var tun: Tuning = Tuning.shared()
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
	var events: Array[Dictionary] = []
	var on_hit: Callable = func(ev: Dictionary) -> void: events.append(ev)
	for f: Variant in m.fighters:
		(f as Fighter).hit.connect(on_hit)
	var stop: HitStop = null
	var rp: RestProbe = null
	if probe:
		stop = HitStop.new()
		world.add_child(stop)
		stop.bind(m.fighters)
		rp = RestProbe.new()
		rp.stop = stop
		rp.fighters = m.fighters
		world.add_child(rp)
	var logic := HitStopLogic.new()
	var per: Dictionary = {}
	var run: float = 0.0
	var longest: float = 0.0
	var stalled: float = 0.0
	var max_lag: float = 0.0
	var ticks: int = 0
	var tail: int = -1
	for i: int in range(int(SECONDS * 60.0) + 120):
		await host.get_tree().physics_frame
		ticks += 1
		for ev: Dictionary in events:
			var imp: float = FeelLogic.impact(ev, tun)
			var cls: String = HitStopLogic.hit_class(ev, imp, tun)
			var held: float = logic.request(ev, imp, tun)
			if stop != null:
				stop.on_hit(ev, imp)
			var r: Dictionary = per.get(cls, {"n": 0, "held": 0, "sum": 0.0, "max": 0.0})
			r["n"] = int(r["n"]) + 1
			if held > 0.0:
				r["held"] = int(r["held"]) + 1
				r["sum"] = float(r["sum"]) + held
				r["max"] = maxf(float(r["max"]), held)
			per[cls] = r
		events.clear()
		var rate: float = logic.step(DT, tun)
		max_lag = maxf(max_lag, logic.lag)
		if rate < 0.5:
			run += DT
			stalled += DT
			longest = maxf(longest, run)
		else:
			run = 0.0
		if m.result.size() > 0 and tail < 0:
			tail = i + 30
		if tail >= 0 and i >= tail:
			break
	var out: Dictionary = {"per": per, "longest": longest, "share": stalled / maxf(float(ticks) * DT, 1.0),
		"max_lag": max_lag, "secs": float(ticks) * DT, "reason": str(m.result.get("reason", "time"))}
	if rp != null:
		out["off_at_physics"] = rp.off_at_physics
		out["checks"] = rp.checks
		out["lagged_draws"] = rp.lagged_draws
		out["max_shift"] = stop.max_shift
	await clear()
	return out


func run() -> Array:
	var rows: Array = []
	var all: Dictionary = {}
	var longest: float = 0.0
	var share: float = 0.0
	var max_lag: float = 0.0
	var probe: Dictionary = {}
	for k: int in CASES.size():
		var c: Array = CASES[k]
		var o: Dictionary = await _play(int(c[0]), str(c[1]), str(c[2]), k == 0)
		if k == 0:
			probe = o
		longest = maxf(longest, float(o["longest"]))
		share = maxf(share, float(o["share"]))
		max_lag = maxf(max_lag, float(o["max_lag"]))
		var line: String = ""
		for cls: Variant in o["per"]:
			var r: Dictionary = o["per"][cls]
			var a: Dictionary = all.get(cls, {"n": 0, "held": 0, "sum": 0.0, "max": 0.0})
			a["n"] = int(a["n"]) + int(r["n"])
			a["held"] = int(a["held"]) + int(r["held"])
			a["sum"] = float(a["sum"]) + float(r["sum"])
			a["max"] = maxf(float(a["max"]), float(r["max"]))
			all[cls] = a
			line += " %s=%d" % [cls, int(r["n"])]
		rows.append(row("hit feel %s v %s" % [c[1], c[2]], null, "secs=%.1f end=%s hits:%s longest_stall=%.0fms stalled=%.1f%% max_lag=%.0fms" % [
			o["secs"], o["reason"], line, float(o["longest"]) * 1000.0, float(o["share"]) * 100.0, float(o["max_lag"]) * 1000.0]))
	var table: String = ""
	for cls: String in ["light", "medium", "heavy", "clash", "sever", "finisher", "none"]:
		if not all.has(cls):
			continue
		var a: Dictionary = all[cls]
		table += " %s: n=%d stopped=%d mean=%.0fms max=%.0fms;" % [cls, int(a["n"]), int(a["held"]),
			1000.0 * float(a["sum"]) / maxf(float(a["held"]), 1.0), 1000.0 * float(a["max"])]
	rows.append(row("hit feel: hold per class", null, table.strip_edges()))
	rows.append(row("hit feel: no long stall", longest <= MAX_STALL_S, "longest %.0f ms (cap %.0f)" % [longest * 1000.0, MAX_STALL_S * 1000.0]))
	rows.append(row("hit feel: stall share", share <= MAX_STALL_SHARE, "worst %.1f%% (cap %.0f%%)" % [share * 100.0, MAX_STALL_SHARE * 100.0]))
	rows.append(row("hit feel: lag capped", max_lag <= Tuning.shared().feel_hitstop_lag_max + 0.0001, "max %.0f ms" % (max_lag * 1000.0)))
	rows.append(row("hit feel: physics sees rest poses", int(probe.get("off_at_physics", 1)) == 0 and int(probe.get("checks", 0)) > 0,
		"off=%d of %d checks" % [int(probe.get("off_at_physics", -1)), int(probe.get("checks", 0))]))
	rows.append(row("hit feel: drawn lagged", int(probe.get("lagged_draws", 0)) > 0,
		"frames=%d max_shift=%.3fm" % [int(probe.get("lagged_draws", 0)), float(probe.get("max_shift", 0.0))]))
	return rows
