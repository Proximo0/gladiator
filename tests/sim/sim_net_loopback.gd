extends "res://tests/sim/sim_base.gd"
## Online 1v1 over real ENet sockets on localhost, host and client in one process: the host match in the sim world,
## the client match in a SubViewport with its own World3D (own physics space). Both sides send through a fake link
## (50 ms one way, 0-33 ms jitter, 5% loss of unreliable packets). The host's side 0 is a CPU brain, the client's
## side 1 is scripted: idle, walk forward, then swing. A 10 s time limit, counted from START's fight tick (the intro
## release, FIGHT_TICK), ends the match.
## Checks: lobby completes, the client gets snapshots, its inputs reach the host and move its fighter, both
## directions stay in the byte budget, both sides end with the same result, the client's last snapshot matches the
## host's state at that tick within quantisation, every hit/gore event arrives, and both sides' fight clocks (result
## "fight_ticks", what a ranked report sends) agree and start at the fight tick.

const PORT: int = 17931
const SEED: int = 4711
const TIME_LIMIT_S: float = 10.0
const LAG_TICKS: int = 3
const JITTER_TICKS: int = 2
const LOSS: float = 0.05
const WALK_FROM: int = 60
const WALK_TO: int = 240
const CAP_TICKS: int = 1200
const DISLODGE_TICK: int = 100
const FIGHT_TICK: int = 138  ## the default 2.3 s intro at 60 Hz

var _host: NetSession
var _client: NetSession
var _vp: SubViewport
var _host_match: Match = null
var _client_match: Match = null
var _walk_start: Vector3 = Vector3.ZERO
var _walk_end: Vector3 = Vector3.ZERO
var _sent_inputs: int = 0
var present: bool = false  ## build both matches with presentation (arena, blood, sound, HUD, camera)
var prefix: String = "net"
var time_limit_s: float = TIME_LIMIT_S
var port: int = PORT
var lag_ticks: int = LAG_TICKS
var jitter_ticks: int = JITTER_TICKS
var loss: float = LOSS
var client_speed_max: float = 0.0  ## fastest client-side pelvis speed seen while walking (kinematic velocity)
var cursor_seen: bool = false


func _client_input() -> FighterInput:
	var t: int = _sent_inputs
	_sent_inputs += 1
	var f := FighterInput.new()
	if t >= WALK_FROM and t < WALK_TO:
		f.move_y = 1000
	elif t >= WALK_TO:
		var phase: int = (t / 30) % 2
		f.aim_x = 900 if phase == 0 else -900
		f.aim_y = 300
		f.buttons = FighterInput.SWING
		f.move_y = 400
	return f


func _on_host_start(start: Dictionary) -> void:
	var m := Match.new()
	m.name = "HostMatch"
	world.add_child(m)
	m.setup(NetLobby.match_config(start, present))
	# Side 0 is a CPU here instead of the host's devices.
	var r: Variant = m.readers[0]
	if r != null:
		m.remove_child(r as Node)
		(r as Node).free()
	m.readers[0] = null
	m.brains[0] = FighterBrain.new(SEED, {})
	_host.attach_match(m)
	_host.host_driver.keep_history = true
	_host_match = m


func _on_client_start(start: Dictionary) -> void:
	var m := Match.new()
	m.name = "ClientMatch"
	_vp.add_child(m)
	m.setup(NetLobby.match_config(start, present))
	_client.attach_match(m)
	_client.client_driver.input_source = _client_input
	_client_match = m


func run() -> Array:
	var rows: Array = []
	await sandbox()
	rows.append(await _mismatch_row())
	_host = NetSession.new()
	_host.name = "HostSession"
	world.add_child(_host)
	_client = NetSession.new()
	_client.name = "ClientSession"
	world.add_child(_client)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.add_child(_vp)
	_host.set_link(lag_ticks, jitter_ticks, loss, 11)
	_client.set_link(lag_ticks, jitter_ticks, loss, 12)
	_host.set_local("Host", {"weapon": "gladius", "offhand": "", "armor": {}})
	_client.set_local("Client", {"weapon": "spear", "offhand": "", "armor": {"torso": "cuirass_iron", "head": "helm_iron"}})
	_host.match_requested.connect(_on_host_start)
	_client.match_requested.connect(_on_client_start)
	var err: Error = _host.host(port, "127.0.0.1")
	if err == OK:
		err = _client.join("127.0.0.1", port)
	var n: int = 0
	while err == OK and n < 300 and not (_host.remote_joined and _client.remote_joined):
		await host.get_tree().physics_frame
		n += 1
	var lobby_ok: bool = err == OK and _host.remote_joined and _client.remote_joined
	rows.append(row(prefix + "_lobby", lobby_ok, "joined after %d ticks, host sees %s with %s" % [n, _host.remote_name,
		str(_host.remote_loadout.get("weapon", "?"))]))
	if not lobby_ok:
		await _teardown()
		return rows
	_host.start_match(SEED, time_limit_s, FIGHT_TICK)
	n = 0
	var budget_ok: bool = true
	var peak_out: float = 0.0
	var peak_in: float = 0.0
	while n < CAP_TICKS:
		await host.get_tree().physics_frame
		n += 1
		if _host_match == null or _client_match == null:
			continue
		var f1: Fighter = _host_match.fighters[1]
		if _host_match.tick == DISLODGE_TICK:
			# Tear the client fighter's cuirass and helm off on the host (what a hard blow does).
			f1.call("_dislodge", "cuirass_iron", "torso", Vector3(1, 0, 0))
			f1.call("_dislodge", "helm_iron", "head", Vector3(0, 0, 1))
		var hp: Vector3 = (f1.parts["pelvis"] as RigidBody3D).global_position
		var applied: int = _host.host_driver.inputs.last_applied_tick
		if applied <= WALK_FROM:
			_walk_start = hp
		if applied <= WALK_TO:
			_walk_end = hp
		if n > NetConfig.TICK_HZ:
			peak_out = maxf(peak_out, _host.bw_out.per_second(_host.local_tick))
			peak_in = maxf(peak_in, _client.bw_out.per_second(_client.local_tick))
		var cf1: Fighter = _client_match.fighters[1]
		if _sent_inputs > WALK_FROM + 30 and _sent_inputs < WALK_TO:
			client_speed_max = maxf(client_speed_max, (cf1.parts["pelvis"] as RigidBody3D).linear_velocity.length())
		var cm: Variant = _client.client_driver.get("_cursor_mesh")
		if cm != null and (cm as Node3D).visible:
			cursor_seen = true
		if _host_match.over and _client_match.over:
			break
	budget_ok = peak_out <= NetConfig.BUDGET_BYTES_PER_S and peak_in <= NetConfig.BUDGET_BYTES_PER_S
	var hd: NetHostDriver = _host.host_driver
	var cd: NetClientDriver = _client.client_driver
	var ticks: int = maxi(_host_match.tick if _host_match != null else 1, 1)
	rows.append(row(prefix + "_snapshots_arrive", cd != null and cd.snapshots_received >= int(float(hd.snapshots_sent) * 0.85),
		"client got %d of %d snapshots, interp delay %.1f ticks (%.0f ms), extrapolated %d ticks, held %d, resyncs %d" % [
		cd.snapshots_received, hd.snapshots_sent, cd.interp.delay, cd.interp.delay * 1000.0 / 60.0,
		cd.interp.extrapolated_ticks, cd.interp.held_ticks, cd.interp.resyncs]))
	rows.append(row(prefix + "_latency", null, "fake link %d+0..%d ticks each way, %.0f%% loss; input to screen %.1f ticks (%.0f ms; %.1f ticks counting the older snapshot's ack, as v1 did); cursor drawn from local aim the same tick" % [
		lag_ticks, jitter_ticks, loss * 100.0, cd.input_to_screen_ticks(), cd.input_to_screen_ticks() * 1000.0 / 60.0,
		cd.input_to_screen_older_ticks()]))
	var ib: NetInputBuffer = hd.inputs
	var moved: float = Vector2(_walk_end.x - _walk_start.x, _walk_end.z - _walk_start.z).length()
	rows.append(row(prefix + "_inputs_reach_host", ib.received >= int(float(_sent_inputs) * 0.9) and moved > 1.0,
		"host got %d of %d client ticks (dups %d, late %d, underruns %d, skipped %d), walking moved fighter 1 %.2f m" % [
		ib.received, _sent_inputs, ib.duplicates, ib.late, ib.underruns, ib.skipped, moved]))
	rows.append(row(prefix + "_bandwidth_budget", budget_ok,
		"host->client avg %.1f KB/s peak %.1f, client->host avg %.1f KB/s peak %.1f (budget %.0f KB/s, overhead incl.)" % [
		_host.bw_out.average(_host.local_tick) / 1000.0, peak_out / 1000.0, _client.bw_out.average(_client.local_tick) / 1000.0,
		peak_in / 1000.0, NetConfig.BUDGET_BYTES_PER_S / 1000.0]))
	var hr: Dictionary = _host_match.result if _host_match != null else {}
	var cr: Dictionary = _client_match.result if _client_match != null else {}
	var same: bool = _host_match != null and _host_match.over and _client_match != null and _client_match.over \
		and int(hr.get("winner", -9)) == int(cr.get("winner", -8)) and str(hr.get("reason", "a")) == str(cr.get("reason", "b")) \
		and int(hr.get("ticks", -1)) == int(cr.get("ticks", -2))
	rows.append(row(prefix + "_same_result", same, "host winner=%s reason=%s ticks=%s, client winner=%s reason=%s ticks=%s" % [
		hr.get("winner"), hr.get("reason"), hr.get("ticks"), cr.get("winner"), cr.get("reason"), cr.get("ticks")]))
	rows.append(_fight_clock_row(hr, cr))
	# The client's newest snapshot against the host's state at that tick (quantisation only).
	var worst: float = -1.0
	var newest: int = -1
	if cd != null and cd.shown != null:
		newest = cd.interp.newest_tick()
		var hs: NetSnapshot = hd.history.get(newest)
		if hs != null:
			var hq: NetSnapshot = NetSnapshot.decode(hs.encode())
			var cs: NetSnapshot = _snapshot_at(cd, newest)
			if cs != null:
				worst = 0.0
				for side: int in 2:
					for i: int in range(hs.fighters[side].body_count()):
						worst = maxf(worst, hs.fighters[side].pos[i].distance_to(cs.fighters[side].pos[i]))
						worst = maxf(worst, hq.fighters[side].pos[i].distance_to(cs.fighters[side].pos[i]))
	rows.append(row(prefix + "_final_state_matches", worst >= 0.0 and worst < 0.002, "tick %d: worst body offset %.4f m" % [newest, worst]))
	var played: int = cd.events_played if cd != null else -1
	rows.append(row(prefix + "_events_arrive", hd.events_at_over >= 0 and played >= hd.events_at_over,
		"host sent %d hit/gore events by the end of the match (%d in all), client played %d; %d ticks, %s" % [
		hd.events_at_over, hd.events_sent, played, ticks, _client.stats_line()]))
	rows.append(_armor_props_row())
	rows.append(await _end_pause_row())
	await _teardown()
	return rows


## A client whose game data differs is refused, and both sides say "version mismatch".
func _mismatch_row() -> Array:
	var h := NetSession.new()
	h.name = "MismatchHost"
	world.add_child(h)
	var c := NetSession.new()
	c.name = "MismatchClient"
	world.add_child(c)
	c.set("_content_hash", "deadbeefdeadbeef")
	var host_said: Array = []
	h.status_changed.connect(func(t: String) -> void: host_said.append(t))
	var err: Error = h.host(port + 20, "127.0.0.1")
	if err == OK:
		err = c.join("127.0.0.1", port + 20)
	var n: int = 0
	while err == OK and n < 300 and c.close_reason == "":
		await host.get_tree().physics_frame
		n += 1
	var host_line: String = ""
	for t: String in host_said:
		if t.contains("version mismatch"):
			host_line = t
	var ok: bool = c.close_reason.begins_with("version mismatch") and host_line != "" and not h.remote_joined
	var line: String = "client: \"%s\"; host: \"%s\"" % [c.close_reason, host_line]
	c.queue_free()
	h.queue_free()
	await host.get_tree().physics_frame
	return row(prefix + "_version_mismatch", ok, line)


## Host and client count the same fight ticks from START's fight tick, and a time-limit end comes time_limit_s after
## the release, not after the match start.
func _fight_clock_row(hr: Dictionary, cr: Dictionary) -> Array:
	if _host_match == null or _client_match == null:
		return row(prefix + "_fight_clock", false, "no match on one side")
	var hf: int = int(hr.get("fight_ticks", -1))
	var cf: int = int(cr.get("fight_ticks", -2))
	var starts: bool = _host_match.fight_start_tick == FIGHT_TICK and _client_match.fight_start_tick == FIGHT_TICK
	var span_ok: bool = int(hr.get("ticks", 0)) - hf == FIGHT_TICK
	var limit_ok: bool = str(hr.get("reason", "")) != "time" or hf == roundi(time_limit_s * float(NetConfig.TICK_HZ))
	return row(prefix + "_fight_clock", hf == cf and hf > 0 and starts and span_ok and limit_ok,
		"fight ticks host %d client %d (match ticks %s, fight start host %d client %d, reason %s, limit %.0f s = %d ticks)" % [
		hf, cf, hr.get("ticks"), _host_match.fight_start_tick, _client_match.fight_start_tick, hr.get("reason"),
		time_limit_s, roundi(time_limit_s * float(NetConfig.TICK_HZ))])


## Knocked-off armor flies as props on the client too: same count, same place (both have come to rest by now).
func _armor_props_row() -> Array:
	var hp: Array[RigidBody3D] = NetWorld.armor_props(_host_match.fighters[1] as Fighter)
	var cp: Array[RigidBody3D] = NetWorld.armor_props(_client_match.fighters[1] as Fighter)
	var worst: float = 0.0
	for i: int in range(mini(hp.size(), cp.size())):
		worst = maxf(worst, hp[i].global_position.distance_to(cp[i].global_position))
	var visible_ok: bool = true
	for c: RigidBody3D in cp:
		for ch: Node in c.get_children():
			if ch is MeshInstance3D:
				visible_ok = visible_ok and (ch as MeshInstance3D).is_visible_in_tree()
	return row(prefix + "_armor_props", hp.size() == 2 and cp.size() == hp.size() and worst < 0.15 and visible_ok,
		"host props %d, client props %d, worst distance %.3f m, visible %s" % [hp.size(), cp.size(), worst, str(visible_ok)])


## Hits in the host's end pause are not sent: after the result the host sends no more events and the client plays none.
func _end_pause_row() -> Array:
	var hd: NetHostDriver = _host.host_driver
	var cd: NetClientDriver = _client.client_driver
	var sent_at_over: int = hd.events_sent
	var played_at_over: int = cd.events_played
	for _i: int in range(120):
		await host.get_tree().physics_frame
	return row(prefix + "_no_events_after_result", hd.events_sent == sent_at_over and cd.events_played == played_at_over \
		and hd.events_sent == hd.events_at_over,
		"events sent %d -> %d, played %d -> %d over the 120 ticks after the result (sent at over: %d)" % [
		sent_at_over, hd.events_sent, played_at_over, cd.events_played, hd.events_at_over])


## The client's held snapshot with exactly `tick` (re-sampled at that tick), or null.
func _snapshot_at(cd: NetClientDriver, tick: int) -> NetSnapshot:
	var keep: float = cd.interp.render_tick
	cd.interp.render_tick = float(tick)
	var s: NetSnapshot = cd.interp.sample()
	cd.interp.render_tick = keep
	return s if s != null and s.tick == tick else null


func _teardown() -> void:
	if _client != null:
		_client.leave("done")
	if _host != null:
		_host.leave("done")
	Engine.time_scale = 1.0
	await clear()
