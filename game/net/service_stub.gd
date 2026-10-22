class_name ServiceStub
extends OnlineService
## A scriptable fake backend for tests and screenshots, and a model of the server-side rules: it keeps its own
## ServiceBoard, pairs the two players' reports with Rating.reconcile, and rates only an agreed (or forfeited) match.
## Tests drive it: set `auto_match` false and call fulfil() when they want the match, feed the opponent's report
## through opponent_report(), read `calls` to see what the UI asked for.

var auto_match: bool = true  ## quick_match answers at once (else call fulfil())
var fail_login_with: String = ""  ## non-empty: login fails with this reason
var fail_match_with: String = ""  ## non-empty: quick_match ends with this reason
var opponent: Dictionary = {"id": "zzzz-stub-opponent", "name": "Verus", "rating": 1040, "games": 12}
var role: String = ROLE_HOST
var port: int = NetConfig.DEFAULT_PORT
var address: String = "127.0.0.1"
var board: ServiceBoard = ServiceBoard.new()
var calls: Array = []  ## names of the API calls received, in order
var summaries: Array = []

var _searching: bool = false
var _mid: String = ""
var _reports: Dictionary = {}  ## match_id -> {player id -> report}
var _done: Dictionary = {}
var _n: int = 0


func backend_name() -> String:
	return "stub"


func features() -> PackedStringArray:
	return PackedStringArray(["global_leaderboard"])


func login(display_name: String) -> void:
	calls.append("login")
	if fail_login_with != "":
		login_failed.emit(fail_login_with)
		return
	var id: String = str(profile.get("id", "stub-player-0001"))
	var e: Dictionary = board.ensure(id, display_name)
	profile = {"id": id, "name": str(e["name"])}
	_sync_profile()
	logged_in.emit(profile)


func is_searching() -> bool:
	return _searching


func quick_match(_loadout: Dictionary) -> void:
	calls.append("quick_match")
	if fail_match_with != "":
		match_failed.emit(fail_match_with)
		return
	_searching = true
	status_changed.emit("Searching (stub)")
	if auto_match:
		fulfil()


func cancel() -> void:
	calls.append("cancel")
	_searching = false


## Pair the searching player with `opponent` now.
func fulfil() -> void:
	if not _searching:
		return
	_searching = false
	_n += 1
	_mid = "stub-match-%d" % _n
	board.note_opponent(str(opponent["id"]), str(opponent["name"]), int(opponent["rating"]), int(opponent["games"]))
	matched.emit(OnlineService.match_info(role, address, port, null, _mid, "stub-key-" + _mid, opponent.duplicate()))


func key_for(match_id: String) -> String:
	return "stub-key-" + match_id


func report_result(match_id: String, report: Dictionary, signature: String) -> void:
	calls.append("report_result")
	if not Rating.verify_report(key_for(match_id), report, signature):
		_emit_summary(match_id, "voided", "", 0, 0, "bad signature")
		return
	var m: Dictionary = _reports.get(match_id, {})
	m[str(report.get("player", ""))] = report
	_reports[match_id] = m
	_try_settle(match_id, false)


## The other player's report for the match (a test plays the opponent). Signed here with the match key.
func opponent_report(match_id: String, report: Dictionary) -> void:
	var r: Dictionary = report.duplicate()
	r["player"] = str(opponent["id"])
	r["match_id"] = match_id
	var m: Dictionary = _reports.get(match_id, {})
	m[str(opponent["id"])] = r
	_reports[match_id] = m
	_try_settle(match_id, false)


## The grace period for a missing report is over.
func timeout_match(match_id: String) -> void:
	_try_settle(match_id, true)


func _try_settle(match_id: String, final: bool) -> void:
	if _done.has(match_id):
		return
	var me: String = str(profile.get("id", ""))
	var opp: String = str(opponent["id"])
	var m: Dictionary = _reports.get(match_id, {})
	var v: Dictionary = Rating.reconcile(me, m.get(me, {}), opp, m.get(opp, {}), final)
	if str(v["status"]) == "pending":
		return
	_done[match_id] = true
	var before: int = int(board.entry(me).get("rating", Rating.START_RATING))
	if bool(v["rated"]):
		board.apply(me, opp, float(v["score_a"]))
		_sync_profile()
	_emit_summary(match_id, str(v["status"]), str(v["winner"]), before, int(board.entry(me).get("rating", before)), str(v["why"]))


func _emit_summary(match_id: String, status: String, winner: String, before: int, after: int, why: String) -> void:
	var s: Dictionary = OnlineService.result_summary(match_id, status, winner, before, after, why)
	summaries.append(s)
	result_recorded.emit(s)


func add_fake_player(id: String, player_name: String, rating: int, games: int, wins: int) -> void:
	var e: Dictionary = board.ensure(id, player_name)
	e["rating"] = rating
	e["games"] = games
	e["wins"] = wins
	e["losses"] = games - wins


func request_leaderboard(top_n: int = 20, around_me: int = 3) -> void:
	calls.append("request_leaderboard")
	var data: Dictionary = board.leaderboard(str(profile.get("id", "")), top_n, around_me)
	data["source"] = "stub"
	leaderboard_ready.emit(data)


func _sync_profile() -> void:
	var e: Dictionary = board.entry(str(profile.get("id", "")))
	profile["rating"] = int(e.get("rating", Rating.START_RATING))
	profile["games"] = int(e.get("games", 0))
	profile["wins"] = int(e.get("wins", 0))
	profile["losses"] = int(e.get("losses", 0))
