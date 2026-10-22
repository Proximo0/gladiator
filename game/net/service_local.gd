class_name ServiceLocal
extends OnlineService
## LAN / dev backend. Quick match finds another searching player on the local network with UDP broadcast and picks
## the host deterministically: of two players the one with the smaller device id hosts and makes the offer; the
## other accepts. The leaderboard is a table of every player this device has met, kept in user://online_local.json
## (never written in scripted runs). No server, so ratings are trust-based here: each device rates its own games.
##
## Wire (JSON in UDP datagrams, port discovery_port..+PORT_SPAN-1, whichever is free):
##   seek   {m, t:"seek",  v, h, id, name, rating, games, age, port}     broadcast every SEEK_INTERVAL while searching
##   offer  {m, t:"offer", v, h, id, to, name, rating, games, port, mid}  host -> chosen client (unicast)
##   accept {m, t:"accept", id, to, mid, name, rating, games}             client -> host (sent 3 times)
## Two instances on one machine find each other too: seeks also go to 127.0.0.1 on every port of the span.

const MAGIC: String = "sandblood-lan"
const DISCOVERY_PORT: int = 17780
const PORT_SPAN: int = 8
const SEEK_INTERVAL: float = 0.4
const OFFER_TIMEOUT: float = 1.5
const OFFER_COOL: float = 1.0
const CANDIDATE_STALE: float = 2.0
const SEARCH_TIMEOUT: float = 120.0
const MAX_PACKET: int = 1024
const ACCEPT_REPEATS: int = 3

var store_path: String = "user://online_local.json"
var device_id: String = ""  ## empty: generated from `entropy` (and stored) on login
var entropy: int = 0  ## the menu feeds a clock value here; logic stays clock-free
var game_port: int = NetConfig.DEFAULT_PORT  ## the port the host listens on for the fight
var discovery_port: int = DISCOVERY_PORT
var board: ServiceBoard = ServiceBoard.new()

var _udp: PacketPeerUDP = null
var _bound: int = 0
var _clock: float = 0.0
var _searching: bool = false
var _search_started: float = 0.0
var _next_seek: float = 0.0
var _loadout: Dictionary = {}
var _cands: Dictionary = {}  ## id -> {name, rating, games, age, port, ip, udp, seen}
var _cool: Dictionary = {}  ## id -> clock until which we do not offer to them again
var _pending: Dictionary = {}  ## the outstanding offer: {id, mid, deadline}
var _offers_made: int = 0
var _current: Dictionary = {}  ## the match in progress: {mid, key, opp_id, opp_name}
var _reported: Dictionary = {}


func backend_name() -> String:
	return "LAN"


func features() -> PackedStringArray:
	return PackedStringArray(["lan_only"])


func login(display_name: String) -> void:
	if profile.is_empty():
		_load()
	if device_id == "":
		var rng := RandomNumberGenerator.new()
		rng.seed = entropy
		device_id = "%08x%08x" % [rng.randi(), rng.randi()]
	var e: Dictionary = board.ensure(device_id, display_name)
	profile = {"id": device_id, "name": str(e["name"])}
	_refresh_profile()
	_save()
	logged_in.emit(profile)


func is_searching() -> bool:
	return _searching


func quick_match(loadout: Dictionary) -> void:
	if not is_logged_in():
		match_failed.emit("Sign in first")
		return
	_close_socket()
	_loadout = loadout
	_cands.clear()
	_cool.clear()
	_pending = {}
	if not _open_socket():
		match_failed.emit("Could not open the LAN search port")
		return
	_searching = true
	_search_started = _clock
	_next_seek = _clock
	status_changed.emit("Searching the local network")


func cancel() -> void:
	_searching = false
	_pending = {}
	_close_socket()


func _open_socket() -> bool:
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	for p: int in range(discovery_port, discovery_port + PORT_SPAN):
		if _udp.bind(p, "*") == OK:
			_bound = p
			return true
	_udp = null
	return false


func _close_socket() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	_bound = 0


func _exit_tree() -> void:
	_close_socket()


func _physics_process(delta: float) -> void:
	_clock += delta
	if not _searching or _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var bytes: PackedByteArray = _udp.get_packet()
		if _udp.get_packet_error() != OK or bytes.size() > MAX_PACKET:
			continue
		_on_packet(bytes, _udp.get_packet_ip(), _udp.get_packet_port())
		if not _searching:
			return
	if _clock - _search_started > SEARCH_TIMEOUT:
		cancel()
		match_failed.emit("Nobody else is searching on this network")
		return
	if _clock >= _next_seek:
		_next_seek = _clock + SEEK_INTERVAL
		_broadcast_seek()
	_maybe_offer()


func _me() -> Dictionary:
	return board.entry(device_id)


func _msg(t: String) -> Dictionary:
	var e: Dictionary = _me()
	return {"m": MAGIC, "t": t, "v": NetConfig.PROTOCOL_VERSION, "h": build_id, "id": device_id, "name": str(e.get("name", "")),
		"rating": int(e.get("rating", Rating.START_RATING)), "games": int(e.get("games", 0)),
		"age": _clock - _search_started, "port": game_port}


func _broadcast_seek() -> void:
	var bytes: PackedByteArray = JSON.stringify(_msg("seek")).to_utf8_buffer()
	for p: int in range(discovery_port, discovery_port + PORT_SPAN):
		_udp.set_dest_address("255.255.255.255", p)
		_udp.put_packet(bytes)
		if p != _bound:
			_udp.set_dest_address("127.0.0.1", p)
			_udp.put_packet(bytes)


func _send(d: Dictionary, ip: String, port: int) -> void:
	_udp.set_dest_address(ip, port)
	_udp.put_packet(JSON.stringify(d).to_utf8_buffer())


func _on_packet(bytes: PackedByteArray, ip: String, udp_port: int) -> void:
	var v: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not (v is Dictionary):
		return
	var d: Dictionary = v
	if str(d.get("m", "")) != MAGIC or str(d.get("id", "")) == device_id or str(d.get("id", "")) == "":
		return
	if int(d.get("v", -1)) != NetConfig.PROTOCOL_VERSION or str(d.get("h", "")) != build_id:
		return  # another game version: not an opponent for us
	var id: String = str(d["id"])
	match str(d.get("t", "")):
		"seek":
			_cands[id] = {"name": NetLobby.clean_name(str(d.get("name", ""))), "rating": int(d.get("rating", Rating.START_RATING)),
				"games": int(d.get("games", 0)), "age": float(d.get("age", 0.0)), "port": int(d.get("port", NetConfig.DEFAULT_PORT)),
				"ip": ip, "udp": udp_port, "seen": _clock}
		"offer":
			if str(d.get("to", "")) == device_id and _pending.is_empty() and id < device_id:
				_accept(d, ip, udp_port)
		"accept":
			if not _pending.is_empty() and str(d.get("to", "")) == device_id and str(d.get("mid", "")) == str(_pending["mid"]) \
					and id == str(_pending["id"]):
				_host_confirmed(d, ip)


## Host side: pick the closest-rated fresh candidate that has a larger id and fits the widening window.
func _maybe_offer() -> void:
	if not _pending.is_empty():
		if _clock > float(_pending["deadline"]):
			_cool[str(_pending["id"])] = _clock + OFFER_COOL
			_pending = {}
		else:
			return
	var mine: int = int(_me().get("rating", Rating.START_RATING))
	var best: String = ""
	var best_diff: int = 1 << 30
	for id: String in _cands:
		var c: Dictionary = _cands[id]
		if id < device_id or _clock - float(c["seen"]) > CANDIDATE_STALE or float(_cool.get(id, 0.0)) > _clock:
			continue
		var waited: float = maxf(_clock - _search_started, float(c["age"]))
		if not Rating.in_window(mine, int(c["rating"]), waited):
			continue
		var diff: int = absi(mine - int(c["rating"]))
		if diff < best_diff or (diff == best_diff and id < best):
			best = id
			best_diff = diff
	if best == "":
		return
	_offers_made += 1
	var mid: String = _match_id(device_id, best, _offers_made)
	var c2: Dictionary = _cands[best]
	var offer: Dictionary = _msg("offer")
	offer["to"] = best
	offer["mid"] = mid
	_send(offer, str(c2["ip"]), int(c2["udp"]))
	_pending = {"id": best, "mid": mid, "deadline": _clock + OFFER_TIMEOUT}


func _accept(offer: Dictionary, ip: String, udp_port: int) -> void:
	var reply: Dictionary = _msg("accept")
	reply["to"] = str(offer["id"])
	reply["mid"] = str(offer["mid"])
	for _i: int in range(ACCEPT_REPEATS):
		_send(reply, ip, udp_port)
	var opp := {"id": str(offer["id"]), "name": NetLobby.clean_name(str(offer.get("name", ""))),
		"rating": int(offer.get("rating", Rating.START_RATING)), "games": int(offer.get("games", 0))}
	_finish(ROLE_CLIENT, ip, int(offer.get("port", NetConfig.DEFAULT_PORT)), str(offer["mid"]), opp)


func _host_confirmed(accept: Dictionary, ip: String) -> void:
	var opp := {"id": str(accept["id"]), "name": NetLobby.clean_name(str(accept.get("name", ""))),
		"rating": int(accept.get("rating", Rating.START_RATING)), "games": int(accept.get("games", 0))}
	_finish(ROLE_HOST, ip, game_port, str(_pending["mid"]), opp)


func _finish(role: String, address: String, port: int, mid: String, opp: Dictionary) -> void:
	_searching = false
	_pending = {}
	_close_socket()
	board.note_opponent(str(opp["id"]), str(opp["name"]), int(opp["rating"]), int(opp["games"]))
	_current = {"mid": mid, "key": match_key(mid), "opp_id": str(opp["id"]), "opp_name": str(opp["name"])}
	status_changed.emit("Found %s" % str(opp["name"]))
	matched.emit(OnlineService.match_info(role, address, port, null, mid, str(_current["key"]), opp))


## Both sides compute the same id from the host's offer.
static func _match_id(host_id: String, client_id: String, n: int) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%s|%s|%d" % [host_id, client_id, n]).to_utf8_buffer())
	return ctx.finish().hex_encode().left(16)


## LAN has no server to keep a secret, so the key only binds a report to its match.
static func match_key(mid: String) -> String:
	return "lan-" + mid


func report_result(match_id: String, report: Dictionary, signature: String) -> void:
	if _current.is_empty() or match_id != str(_current["mid"]) or _reported.has(match_id):
		return
	var me: String = device_id
	if not Rating.verify_report(str(_current["key"]), report, signature) or str(report.get("player", "")) != me:
		result_recorded.emit(OnlineService.result_summary(match_id, "voided", "", int(_me()["rating"]), int(_me()["rating"]), "bad signature"))
		return
	_reported[match_id] = true
	var opp: String = str(_current["opp_id"])
	# Trust mode: this device rates its own game from its own report. A dropped connection is not rated here.
	var v: Dictionary = Rating.reconcile(me, report, opp, {}, str(report.get("kind", "")) != Rating.KIND_DROPPED)
	var before: int = int(_me()["rating"])
	if bool(v["rated"]):
		board.apply(me, opp, float(v["score_a"]))
		_refresh_profile()
		_save()
	result_recorded.emit(OnlineService.result_summary(match_id, str(v["status"]), str(v["winner"]), before, int(_me()["rating"]), str(v["why"])))


func request_leaderboard(top_n: int = 20, around_me: int = 3) -> void:
	var data: Dictionary = board.leaderboard(device_id, top_n, around_me)
	data["source"] = "LAN: players met on this device"
	leaderboard_ready.emit(data)


func _refresh_profile() -> void:
	var e: Dictionary = _me()
	profile["rating"] = int(e.get("rating", Rating.START_RATING))
	profile["games"] = int(e.get("games", 0))
	profile["wins"] = int(e.get("wins", 0))
	profile["losses"] = int(e.get("losses", 0))
	profile["name"] = str(e.get("name", profile.get("name", "")))


func _can_persist() -> bool:
	return not Flags.is_scripted_run()


func _load() -> void:
	if not _can_persist() or not FileAccess.file_exists(store_path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(store_path))
	if v is Dictionary:
		if device_id == "":
			device_id = str((v as Dictionary).get("device_id", ""))
		var b: Variant = (v as Dictionary).get("board", {})
		if b is Dictionary:
			board.from_dict(b)


func _save() -> void:
	if not _can_persist():
		return
	var f := FileAccess.open(store_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"device_id": device_id, "board": board.to_dict()}))
