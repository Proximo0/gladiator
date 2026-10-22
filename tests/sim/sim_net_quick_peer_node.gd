extends Node
## The body of sim_net_quick_peer.gd (loaded after the autoloads exist).

const SEED: int = 4242
const TIME_LIMIT_S: float = 40.0  ## the client stands still, so the host's CPU brain should win well before this
const CAP_TICKS: int = 60 * 70

var _svc: ServiceLocal
var _session: NetSession
var _match: Match = null
var _info: Dictionary = {}
var _summary: Dictionary = {}
var _my_id: String = ""


func _ready() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return fallback


func _client_input() -> FighterInput:
	return FighterInput.new()  # neutral: a decisive match so the rating has to move


func _on_start(start: Dictionary) -> void:
	var host_side: bool = str(_info["role"]) == OnlineService.ROLE_HOST
	var m := Match.new()
	get_tree().root.add_child(m)
	m.setup(NetLobby.match_config(start, false))
	if host_side:
		var r: Variant = m.readers[0]
		if r != null:
			m.remove_child(r as Node)
			(r as Node).free()
		m.readers[0] = null
		m.brains[0] = FighterBrain.new(SEED, {})
	_session.attach_match(m)
	if not host_side:
		_session.client_driver.input_source = _client_input
	_match = m


func _run() -> void:
	_my_id = _arg("id", "aaaa")
	_svc = ServiceLocal.new()
	_svc.device_id = _my_id
	_svc.game_port = int(_arg("gport", "17961"))
	_svc.discovery_port = int(_arg("dport", "17790"))
	_svc.build_id = "sim"
	add_child(_svc)
	_session = NetSession.new()
	add_child(_session)
	_session.match_requested.connect(_on_start)
	_svc.matched.connect(func(i: Dictionary) -> void: _info = i)
	_svc.result_recorded.connect(func(s: Dictionary) -> void: _summary = s)
	_svc.login(_arg("name", "Peer"))
	_session.set_local(_arg("name", "Peer"), {"weapon": _arg("weapon", "gladius")})
	_svc.quick_match({"weapon": _arg("weapon", "gladius")})
	var n: int = 0
	while n < CAP_TICKS and _info.is_empty():
		await get_tree().physics_frame
		n += 1
	if _info.is_empty():
		_fail("no match found")
		return
	var host_side: bool = str(_info["role"]) == OnlineService.ROLE_HOST
	var err: Error = OK
	if host_side:
		err = _session.host(int(_info["port"]), "127.0.0.1")
	else:
		for _i: int in range(20):  # the opponent card stays up a moment in the real menu too
			await get_tree().physics_frame
		err = _session.join(str(_info["address"]), int(_info["port"]))
	while err == OK and n < CAP_TICKS and (_match == null or not _match.over):
		await get_tree().physics_frame
		n += 1
		if host_side and _session.remote_joined and _match == null:
			_session.start_match(SEED, TIME_LIMIT_S)
	if _match == null or not _match.over:
		_fail("no finished match (err %d, %s)" % [err, _session.close_reason])
		return
	var r: Dictionary = _match.result
	var w: int = int(r.get("winner", -1))
	var me_side: int = 0 if host_side else 1
	var winner_id: String = ""
	if w >= 0:
		winner_id = _my_id if w == me_side else str((_info["opponent"] as Dictionary)["id"])
	var rep: Dictionary = Rating.make_report(str(_info["match_id"]), _my_id, Rating.KIND_RESULT, winner_id, str(r.get("reason", "")),
		int(r.get("ticks", 0)))
	_svc.report_result(str(_info["match_id"]), rep, Rating.sign_report(str(_info["match_key"]), rep))
	for _i: int in range(30):  # let the last reliable packets go out
		await get_tree().physics_frame
	var mine: Dictionary = _svc.my_rating()
	print("QPEER id=%s role=%s opp=%s oppname=%s mid=%s winner=%s status=%s before=%d after=%d games=%d wins=%d" % [_my_id,
		str(_info["role"]), str((_info["opponent"] as Dictionary)["id"]), str((_info["opponent"] as Dictionary)["name"]),
		str(_info["match_id"]), winner_id, str(_summary.get("status", "none")), int(_summary.get("before", 0)),
		int(_summary.get("after", 0)), int(mine["games"]), int(mine["wins"])])
	_session.leave("done")
	get_tree().quit(0)


func _fail(why: String) -> void:
	print("QPEER id=%s FAIL %s" % [_my_id, why])
	get_tree().quit(1)
