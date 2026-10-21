extends Node
## The body of sim_net_peer.gd (loaded after the autoloads exist). See that file for how to run it.

const SEED: int = 99
const TIME_LIMIT_S: float = 8.0
const CAP_TICKS: int = 60 * 20

var _session: NetSession
var _match: Match = null
var _role: String = "host"
var _sent: int = 0


func _ready() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return fallback


func _client_input() -> FighterInput:
	var f := FighterInput.new()
	_sent += 1
	if _sent > 60 and _sent < 240:
		f.move_y = 1000
	elif _sent >= 240:
		f.aim_x = 900 if (_sent / 30) % 2 == 0 else -900
		f.buttons = FighterInput.SWING
	return f


func _on_start(start: Dictionary) -> void:
	var m := Match.new()
	get_tree().root.add_child(m)
	m.setup(NetLobby.match_config(start, false))
	if _role == NetSession.ROLE_HOST:
		var r: Variant = m.readers[0]
		if r != null:
			m.remove_child(r as Node)
			(r as Node).free()
		m.readers[0] = null
		m.brains[0] = FighterBrain.new(SEED, {})
	_session.attach_match(m)
	if _role == NetSession.ROLE_CLIENT:
		_session.client_driver.input_source = _client_input
	_match = m


func _run() -> void:
	_role = _arg("role", "host")
	var port: int = int(_arg("port", "17951"))
	_session = NetSession.new()
	get_tree().root.add_child(_session)
	_session.set_local(_role, {"weapon": "gladius" if _role == "host" else "spear"})
	_session.match_requested.connect(_on_start)
	var err: Error = _session.host(port, "127.0.0.1") if _role == NetSession.ROLE_HOST else _session.join("127.0.0.1", port)
	var n: int = 0
	while err == OK and n < CAP_TICKS and (_match == null or not _match.over):
		await get_tree().physics_frame
		n += 1
		if _role == NetSession.ROLE_HOST and _session.remote_joined and _match == null:
			_session.start_match(SEED, TIME_LIMIT_S)
	if _match == null or not _match.over:
		print("NETPEER %s FAIL no finished match after %d ticks (err %d, %s)" % [_role, n, err, _session.close_reason])
		get_tree().quit(1)
		return
	var r: Dictionary = _match.result
	var extra: String = ""
	if _role == NetSession.ROLE_HOST:
		var hd: NetHostDriver = _session.host_driver
		extra = "snaps_sent=%d events=%d inputs_rx=%d underruns=%d skipped=%d out=%.1fKB/s" % [hd.snapshots_sent, hd.events_at_over,
			hd.inputs.received, hd.inputs.underruns, hd.inputs.skipped, _session.bw_out.average(_session.local_tick) / 1000.0]
	else:
		var cd: NetClientDriver = _session.client_driver
		extra = "snaps_rx=%d events=%d delay=%.1f extrap=%d input_to_screen=%.1f out=%.1fKB/s" % [cd.snapshots_received,
			cd.events_played, cd.interp.delay, cd.interp.extrapolated_ticks, cd.input_to_screen_ticks(),
			_session.bw_out.average(_session.local_tick) / 1000.0]
	print("NETPEER %s winner=%d reason=%s ticks=%d %s" % [_role, int(r.get("winner", -9)), str(r.get("reason", "")),
		int(r.get("ticks", -1)), extra])
	# Let the last reliable packets go out before closing.
	for _i: int in range(30):
		await get_tree().physics_frame
	_session.leave("done")
	get_tree().quit(0)
