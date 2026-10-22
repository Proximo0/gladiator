extends "res://tests/sim/sim_net_soak.gd"
## A cheating client against a real host over ENet on localhost (docs/net_security.md). One match: 6 s of the
## honest bot and 6 s of legal max-effort mashing as baselines, then 10 s where the client is modded: its inputs flip the aim between opposite
## corners every tick with every button bit set at random, and alongside its real input stream it sends raw abuse
## (ticks near 2^32, ticks walking ahead, 16-row packets, every message type mutated, a 500-packet flood, a 64 KB
## packet, HELLO and LOADOUT with wrong types or a premium weapon). Then 2 s where the host turns hostile and sends
## the client mutated snapshots and events. Checks: the host's hand goal never moves faster than Tuning allows,
## its fighter 1 runs no faster than the legal baselines allow, the loadout cannot change mid-match, the host's
## buffers stay bounded, the flood is dropped, nothing logs a script error, both sessions stay open, and a forged OVER
## (a killing blow on a fighter the snapshots show alive) is flagged by the client.

const BASELINE_TICKS: int = 360
const CHEAT_TICKS: int = 600
const HOSTILE_TICKS: int = 120
const CheatFuzz: GDScript = preload("res://tests/unit/test_net_fuzz.gd")

var _cheating: bool = false
var _mashing: bool = false  ## legal but max effort: sprint at the foe, swing held, roll tapped at 6 Hz, aim swept
var _rng := RandomNumberGenerator.new()
var _cheat_tick: int = 0


func _client_input() -> FighterInput:
	var honest: FighterInput = super()
	_cheat_tick += 1
	if _mashing:
		var sweep: int = roundi(sin(float(_cheat_tick) * 0.6) * 1000.0)
		var b: int = FighterInput.SPRINT | FighterInput.SWING | (FighterInput.ROLL if _cheat_tick % 10 == 0 else 0)
		return FighterInput.from_array([0, 1000, sweep, -sweep, b])
	if not _cheating:
		return honest
	var corner: int = 1000 if _cheat_tick % 2 == 0 else -1000
	return FighterInput.from_array([_rng.randi_range(-1000, 1000), 1000, corner, -corner, _rng.randi_range(0, 0xffff)])


## Raw packets a modded client sends next to its real stream, on cheat tick `k`.
func _abuse(k: int) -> void:
	var newest: int = _client.client_driver.packer.newest_tick
	var p := NetInputPacker.new()
	if k % 30 == 0:
		p.record(4294967000, FighterInput.from_array([0, 1000, 1000, 1000, 0xffff]))
		_client.send(p.pack(), false)
	if k % 7 == 0:
		var rows := StreamPeerBuffer.new()
		rows.put_u8(NetConfig.MSG_INPUT)
		rows.put_u32(newest + 3)
		rows.put_u8(16)
		for _i: int in 16:
			for _j: int in 4:
				rows.put_16(_rng.randi_range(-32768, 32767))
			rows.put_u16(0xffff)
		_client.send(rows.data_array, false)
	if k % 11 == 0:
		var seeds: Array = [_valid_snap_bytes(), NetEvents.encode([[1, 0, "hit", {"total": 50.0, "sever": true}]]),
			NetLobby.over({"winner": 1, "reason": "ko", "ticks": 999, "seed": 1}), NetLobby.start(1, [{}, {}], 1.0, ["a", "b"])]
		for s: PackedByteArray in seeds:
			_client.send(CheatFuzz.mutate(_rng, s), _rng.randf() < 0.5)
			_client.send(s, true)  # well-formed but the wrong direction: the host must ignore it
	if k % 13 == 0:
		_client.send(NetLobby.encode(NetConfig.MSG_HELLO, {"v": [1], "h": 5, "name": {}, "loadout": "laser_sword"}), true)
		_client.send(NetLobby.encode(NetConfig.MSG_LOADOUT, {"loadout": {"weapon": "laser_sword", "armor": [1]}}), true)
	if k == 120:
		for _i: int in 500:
			_client.send(CheatFuzz.mutate(_rng, PackedByteArray([NetConfig.MSG_INPUT, 0, 0, 0, 0, 1])), false)
	if k == 200:
		var big := PackedByteArray()
		big.resize(65536)
		big[0] = NetConfig.MSG_LOADOUT
		_client.send(big, true)
	if k == 400:
		p.record(newest + NetInputBuffer.MAX_AHEAD - 1, FighterInput.new())  # walks the host's buffer ahead (only hurts the cheater)
		_client.send(p.pack(), false)


func _valid_snap_bytes() -> PackedByteArray:
	var s: NetSnapshot = _host.host_driver.last_snapshot
	return s.encode() if s != null else PackedByteArray([NetConfig.MSG_SNAP])


func run() -> Array:
	var rows: Array = []
	_rng.seed = 9400
	loss = 0.0
	time_limit_s = 120.0
	port = PORT + 60
	await sandbox()
	if not await _setup(0, 0, 0, 9400):
		await _teardown()
		return [row("net_cheat_lobby", false, "no lobby")]
	var n: int = 0
	while (_hm == null or _cm == null) and n < 300:
		await host.get_tree().physics_frame
		n += 1
	var errlog: Logger = CheatFuzz.NetFuzzErrorLog.new()
	errlog.set("allow_unmarshal", true)
	OS.add_logger(errlog)
	var f1: Fighter = _hm.fighters[1]
	var weapon0: String = str(f1.loadout.get("weapon", ""))
	var goal_cap: float = maxf(float(f1.call("_t", "swing_hand_speed")), float(f1.call("_t", "reach_hand_speed"))) / 60.0
	var base: Dictionary = await _measure(f1, BASELINE_TICKS, false)
	_mashing = true
	var mash: Dictionary = await _measure(f1, BASELINE_TICKS, false)
	_mashing = false
	var errors_honest: int = int(errlog.get("count"))
	_cheating = true
	var dropped0: int = _host.dropped_packets
	var snaps0: int = _host.host_driver.snapshots_sent
	var cheat: Dictionary = await _measure(f1, CHEAT_TICKS, true)
	var errors_cheat: int = int(errlog.get("count")) - errors_honest
	_cheating = false
	var hostile_ok: bool = true
	for k: int in HOSTILE_TICKS:
		await host.get_tree().physics_frame
		if _host == null or not _host.is_open():
			break
		var good: PackedByteArray = _valid_snap_bytes()
		_host.send(CheatFuzz.mutate(_rng, good), false)
		_host.send(CheatFuzz.mutate(_rng, NetEvents.encode([[_hm.tick + _rng.randi_range(0, 1 << 30), 1, "hit",
			{"total": 9.0, "part": "head", "point": Vector3(0, 1.6, 0)}]])), true)
		if _cm != null:
			for side: int in 2:
				var pv: Vector3 = ((_cm.fighters[side] as Fighter).parts["pelvis"] as RigidBody3D).global_position
				hostile_ok = hostile_ok and is_finite(pv.x + pv.y + pv.z)
	var errors_hostile: int = int(errlog.get("count")) - errors_honest - errors_cheat
	OS.remove_logger(errlog)
	var forged: Array = await _forged_over_row()
	var buf: NetInputBuffer = _host.host_driver.inputs
	var held: int = (buf.get("_inputs") as Dictionary).size()
	rows.append(row("net_cheat_hand_goal_capped", float(cheat["goal_step"]) <= goal_cap * 1.02,
		"max hand goal speed %.1f m/s cheating, %.1f honest, cap %.1f (Tuning swing/reach hand speed)" % [
			float(cheat["goal_step"]) * 60.0, float(base["goal_step"]) * 60.0, goal_cap * 60.0]))
	var speed_cap: float = maxf(maxf(float(base["speed"]), float(mash["speed"])), float(f1.call("_t", "sprint_speed"))) * 1.25
	rows.append(row("net_cheat_speed_bounded", float(cheat["speed"]) <= speed_cap,
		"fighter 1 peak pelvis speed %.2f m/s cheating, %.2f legal mashing, %.2f bot (cap %.2f)" % [float(cheat["speed"]),
			float(mash["speed"]), float(base["speed"]), speed_cap]))
	rows.append(row("net_cheat_hits_info", null, "side-1 hits/s: bot %.1f (max %.1f), legal mashing %.1f (max %.1f), cheating %.1f (max %.1f); mashing hand goal %.1f m/s" % [
		float(base["hits"]) * 60.0 / BASELINE_TICKS, float(base["max_hit"]), float(mash["hits"]) * 60.0 / BASELINE_TICKS, float(mash["max_hit"]),
		float(cheat["hits"]) * 60.0 / CHEAT_TICKS, float(cheat["max_hit"]), float(mash["goal_step"]) * 60.0]))
	rows.append(row("net_cheat_loadout_fixed", str(f1.loadout.get("weapon", "")) == weapon0,
		"fighter 1 kept %s through HELLO/LOADOUT spam (lobby loadout for a rematch: %s)" % [weapon0, str(_host.remote_loadout.get("weapon", ""))]))
	rows.append(row("net_cheat_buffers_bounded", held <= NetInputBuffer.MAX_HELD and buf.rejected > 0,
		"host input buffer held %d, rejected %d, skipped %d" % [held, buf.rejected, buf.skipped]))
	rows.append(row("net_cheat_flood_dropped", _host.dropped_packets - dropped0 >= 100 and _host.is_open() and _client.is_open()
		and _host.host_driver.snapshots_sent - snaps0 >= CHEAT_TICKS / NetConfig.SNAP_EVERY_TICKS - 5,
		"dropped %d packets, both sessions open, %d snapshots sent while cheating" % [_host.dropped_packets - dropped0, _host.host_driver.snapshots_sent - snaps0]))
	rows.append(row("net_cheat_no_script_errors", errors_cheat == 0 and errors_hostile == 0 and hostile_ok,
		"errors: honest %d, cheating client %d, hostile host %d; engine unmarshal noise %d; client poses finite %s" % [
			errors_honest, errors_cheat, errors_hostile, int(errlog.get("unmarshal")), str(hostile_ok)]))
	rows.append(forged)
	await _teardown()
	return rows


## The host's OVER names a killing blow on a fighter its own snapshots show alive: the client flags the result
## (NetResultCheck) so its report disagrees and the match is not rated.
func _forged_over_row() -> Array:
	await step(90)  # only real snapshots in the client's buffer again
	if _host == null or not _host.is_open() or _cm == null:
		return row("net_cheat_forged_over_flagged", false, "session gone before the forged result")
	var alive: Array = [not (_hm.fighters[0] as Fighter).health.dead, not (_hm.fighters[1] as Fighter).health.dead]
	if not alive[0] and not alive[1]:
		return row("net_cheat_forged_over_flagged", null, "both fighters dead: nothing to forge")
	var winner: int = 0 if alive[1] else 1
	_host.send(NetLobby.over({"winner": winner, "reason": "behead", "ticks": _hm.tick - 30, "seed": 1}), true)
	var n: int = 0
	while n < 120 and not _cm.over:
		await host.get_tree().physics_frame
		n += 1
	var why: String = str(_cm.result.get("suspect", ""))
	return row("net_cheat_forged_over_flagged", _cm.over and why != "", "client result %s/%s, flagged: \"%s\"" % [
		str(_cm.result.get("winner", "?")), str(_cm.result.get("reason", "?")), why])


## Over `ticks` host ticks: the largest per-tick step of fighter 1's hand goal while it stands (the arm is driven),
## its peak horizontal pelvis speed, and its hits.
func _measure(f1: Fighter, ticks: int, abuse: bool) -> Dictionary:
	var out: Dictionary = {"goal_step": 0.0, "speed": 0.0, "hits": 0, "max_hit": 0.0}
	var on_hit: Callable = func(ev: Dictionary) -> void:
		if int(ev.get("attacker", -1)) == 1:
			out["hits"] = int(out["hits"]) + 1
			out["max_hit"] = maxf(float(out["max_hit"]), float(ev.get("total", 0.0)))
	for side: int in 2:
		(_hm.fighters[side] as Fighter).hit.connect(on_hit)
	var prev_goal: Vector3 = f1.get("_goal_r")
	var prev_ok: bool = false
	for k: int in ticks:
		if abuse:
			_abuse(k)
		await host.get_tree().physics_frame
		if _hm.over:
			break
		var goal: Vector3 = f1.get("_goal_r")
		var ok: bool = f1.state() == "standing" or f1.state() == "stumbling"
		if ok and prev_ok:
			out["goal_step"] = maxf(float(out["goal_step"]), (goal - prev_goal).length())
		prev_goal = goal
		prev_ok = ok
		var v: Vector3 = (f1.parts["pelvis"] as RigidBody3D).linear_velocity
		out["speed"] = maxf(float(out["speed"]), Vector2(v.x, v.z).length())
	for side: int in 2:
		(_hm.fighters[side] as Fighter).hit.disconnect(on_hit)
	return out
