extends "res://tests/sim/sim_net_soak.gd"
## Connection loss during a match, over real ENet on localhost with the bot on both ends. Cases:
##   leave: the client sends LEAVE; the host says who left.
##   vanish: the client's packets stop without a word (a pulled cable): both sides close with "Connection lost" within
##     DISCONNECT_TICKS plus a margin, and the host's fighter 1 does not keep acting on the last input meanwhile.
##   stall: a 0.5 s hiccup of the client's packets; nothing closes, the stream resumes.
## Prints SOAK lines (readable by tools/net_soak.sh) and returns PASS/FAIL rows.

var _host_closed: String = ""
var _client_closed: String = ""
var _host_closed_tick: int = -1
var _client_closed_tick: int = -1


func _start(mi: int, seed_value: int, lag: int = 2) -> bool:
	_host_closed = ""
	_client_closed = ""
	_host_closed_tick = -1
	_client_closed_tick = -1
	var ok: bool = await _setup(mi, lag, 0 if lag == 0 else 1, seed_value)
	if not ok:
		return false
	_host.closed.connect(func(r: String) -> void:
		_host_closed = r
		_host_closed_tick = _host.local_tick)
	_client.closed.connect(func(r: String) -> void:
		_client_closed = r
		_client_closed_tick = _client.local_tick)
	return true


func _wait_match(ticks: int) -> void:
	var n: int = 0
	while n < ticks:
		await host.get_tree().physics_frame
		n += 1


## Peak speed of the host's fighter 1 over the next `ticks` ticks.
func _fighter1_speed(ticks: int) -> float:
	var peak: float = 0.0
	var f1: Fighter = _hm.fighters[1]
	for _i: int in range(ticks):
		await host.get_tree().physics_frame
		peak = maxf(peak, (f1.parts["pelvis"] as RigidBody3D).linear_velocity.length())
	return peak


func run() -> Array:
	var rows: Array = []
	time_limit_s = 60.0
	await sandbox()
	# leave
	loss = 0.0
	if await _start(0, 9300, 0):  ## clean link: leave() closes at once, so a fake link's delayed LEAVE would never go out
		await _wait_match(180)
		_client.leave("left")
		await _wait_match(30)
		rows.append(row("net_drop_leave", _host_closed.ends_with("left") and _host_closed != "" and _client_closed != "",
			"host: \"%s\" client: \"%s\"" % [_host_closed, _client_closed]))
	else:
		rows.append(row("net_drop_leave", false, "no lobby"))
	await _teardown()
	loss = 0.03
	# vanish: every packet from the client stops
	if await _start(1, 9301):
		await _wait_match(240)
		_client.link = NetLinkSim.new(0, 0, 1.0, 5)
		_client.link.loss = 1.0
		_client.link.latency_ticks = 1  ## active() so send() goes through the sim, which drops unreliable ones
		var t0: int = _host.local_tick
		var speed_after: float = await _fighter1_speed(60)  ## the first second of silence
		var late_speed: float = await _fighter1_speed(150)
		await _wait_match(200)
		var det: int = _host_closed_tick - t0
		rows.append(row("net_drop_vanish_host_closes", _host_closed.begins_with("Connection lost") and det > 0 and det <= NetConfig.DISCONNECT_TICKS + 30,
			"host closed after %d ticks (%.1f s): \"%s\"" % [det, float(det) / 60.0, _host_closed]))
		rows.append(row("net_drop_vanish_stops_acting", late_speed < 1.0, "fighter 1 peak speed with no input: %.2f m/s in the first second, %.2f m/s after" % [speed_after, late_speed]))
	else:
		rows.append(row("net_drop_vanish_host_closes", false, "no lobby"))
	await _teardown()
	# stall
	if await _start(2, 9302):
		await _wait_match(240)
		var saved: NetLinkSim = _client.link
		_client.link = NetLinkSim.new(1, 0, 1.0, 5)
		await _wait_match(30)
		_client.link = saved
		await _wait_match(240)
		rows.append(row("net_drop_stall_survives", _host_closed == "" and _client_closed == "" and not _hm.over,
			"0.5 s of silence: host \"%s\" client \"%s\" received %d inputs" % [_host_closed, _client_closed, _host.host_driver.inputs.received]))
	else:
		rows.append(row("net_drop_stall_survives", false, "no lobby"))
	await _teardown()
	rows.append(await _protocol_rows())
	rows.append(await _old_host_row())
	return rows


## A protocol-1 client (raw ENet peer sending a v1 HELLO) is refused with a readable line and never joins.
func _protocol_rows() -> Array:
	var h := NetSession.new()
	world.add_child(h)
	var said: Array = []
	h.status_changed.connect(func(t: String) -> void: said.append(t))
	h.host(net_port(40), "127.0.0.1")
	var raw := ENetMultiplayerPeer.new()
	raw.create_client("127.0.0.1", net_port(40))
	var reply: Dictionary = {}
	var sent: bool = false
	for _i: int in range(300):
		await host.get_tree().physics_frame
		raw.poll()
		if not sent and raw.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			raw.set_target_peer(1)
			raw.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
			raw.put_packet(NetLobby.encode(NetConfig.MSG_HELLO, {"v": 1, "h": h.content_hash(), "name": "Old", "loadout": {}}))
			sent = true
		while raw.get_available_packet_count() > 0:
			var d: Dictionary = NetLobby.decode(raw.get_packet())
			if int(d.get("_type", 0)) == NetConfig.MSG_LOBBY:
				reply = d
		if not reply.is_empty():
			break
	var line: String = ""
	for t: String in said:
		if t.contains("version mismatch"):
			line = t
	var ok: bool = not reply.is_empty() and not bool(reply.get("accepted", true)) and str(reply.get("reason", "")).begins_with("version mismatch: different protocol") \
		and line != "" and not h.remote_joined
	var r: Array = row("net_version_protocol1_refused", ok, "client sees \"%s\"; host shows \"%s\"" % [str(reply.get("reason", "")), line])
	raw.close()
	h.queue_free()
	await host.get_tree().physics_frame
	return r


## A client that joins a protocol-1 host (raw peer answering with an accepted v1 LOBBY) leaves with the same readable line.
func _old_host_row() -> Array:
	var raw := ENetMultiplayerPeer.new()
	raw.create_server(net_port(41), 1)
	var c := NetSession.new()
	world.add_child(c)
	c.join("127.0.0.1", net_port(41))
	var answered: bool = false
	for _i: int in range(300):
		await host.get_tree().physics_frame
		raw.poll()
		while raw.get_available_packet_count() > 0:
			var pid: int = raw.get_packet_peer()
			var d: Dictionary = NetLobby.decode(raw.get_packet())
			if int(d.get("_type", 0)) == NetConfig.MSG_HELLO and not answered:
				raw.set_target_peer(pid)
				raw.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
				raw.put_packet(NetLobby.encode(NetConfig.MSG_LOBBY, {"v": 1, "h": c.content_hash(), "name": "OldHost", "loadout": {}, "accepted": true, "reason": ""}))
				answered = true
		if c.close_reason != "":
			break
	var r: Array = row("net_version_old_host_refused", c.close_reason.begins_with("version mismatch: different protocol") and not c.remote_joined,
		"client shows \"%s\"" % c.close_reason)
	raw.close()
	c.queue_free()
	await host.get_tree().physics_frame
	return r
