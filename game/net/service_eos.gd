class_name ServiceEos
extends OnlineService
## Epic Online Services backend (docs/online_service.md "EOS", setup in docs/eos_setup.md), written against the
## EOSG GDExtension 2.3.1 (github.com/3ddelano/epic-online-services-godot): its IEOS singleton, the eos.gd option
## classes, the HPlatform / HAuth / HLobbies autoloads and EOSGMultiplayerPeer.
##
## Nothing here names a plugin class: the plugin is optional (its binaries are only on the owner's PC), so the
## script must parse without it. Everything goes through Engine.get_singleton("IEOS"), load(eos.gd), the autoload
## nodes and ClassDB.instantiate, and MenuFlow only builds this service when available() says the plugin is there
## (and EosConfig found credentials); otherwise it falls back to ServiceLocal.
##
## Flow:
##   login     platform from EosConfig (once per process), Connect device id (created on first run), Connect login
##             with the display name; a new device gets a ProductUserId (create_user) on its first login. Then the
##             stats sb_rating / sb_games / sb_wins / sb_losses fill the profile.
##   quick     lobby search in bucket "sb_quick:<build>" sorted by rating distance; the closest lobby inside the
##             widening Rating window is joined (client). With none, this player creates one (2 slots, not in
##             presence, no invites, no host migration) and hosts. Two hosts that see each other: the larger id
##             gives up its lobby and joins the smaller one's. The lobby owner opens an EOSGMultiplayerPeer server
##             on socket "sb<lobby id>"; the joiner connects a client to the owner. NetSession.adopt_peer() runs
##             the fight over it, through Epic's relays when a direct path fails.
##   result    Tier 0 (no server): each player writes its signed report as the lobby member attribute "rep",
##             reads the other's, runs Rating.reconcile on both and ingests its own stats.
##   board     leaderboard sb_rating_all (ranks), plus games / wins / losses of the rows shown (user scores).
##
## Dev flag: --eos-profile=<name> keeps a second identity on one PC (own EOS cache folder and local profile file),
## for two game instances quick-matching each other.

signal platform_settled  ## the platform start finished (ready or failed)

const ADDON_DIR: String = "res://addons/epic-online-services-godot/"
const EOS_SCRIPT: String = ADDON_DIR + "eos.gd"
const CREDENTIALS_SCRIPT: String = ADDON_DIR + "heos/hcredentials.gd"
const AUTOLOADS: PackedStringArray = ["EOSGRuntime", "HPlatform", "HAuth", "HLobbies"]
const PEER_CLASS: StringName = &"EOSGMultiplayerPeer"
const IEOS_NAME: StringName = &"IEOS"

const BUCKET_PREFIX: String = "sb_quick"
const LEADERBOARD_ID: String = "sb_rating_all"
const STAT_RATING: String = "sb_rating"
const STAT_GAMES: String = "sb_games"
const STAT_WINS: String = "sb_wins"
const STAT_LOSSES: String = "sb_losses"
const STAT_NAMES: PackedStringArray = [STAT_RATING, STAT_GAMES, STAT_WINS, STAT_LOSSES]
const ATTR_BUILD: String = "build"
const ATTR_RATING: String = "rating"
const ATTR_GAMES: String = "games"
const ATTR_NAME: String = "name"
const ATTR_KEY: String = "key"
const ATTR_VERSION: String = "ver"
const ATTR_REPORT: String = "rep"

const SEARCH_INTERVAL: float = 3.0  ## seconds between lobby searches
const SEARCH_TIMEOUT: float = 120.0
const SEARCH_RESULTS: int = 10
const POLL_STEP: float = 0.25
const MEMBER_INFO_WAIT: float = 4.0  ## host: how long to wait for the joiner's name and rating attributes
const REPORT_WAIT: float = 20.0  ## how long to wait for the other player's report
const REPORT_LINGER: float = 3.0  ## stay in the lobby this long after reading theirs, so they can read ours
const CALL_TIMEOUT: float = 15.0  ## any single EOS call
const PLATFORM_TIMEOUT: float = 20.0
const TIMED_OUT: int = -10001  ## our own result code for a call that never called back
const MAX_EOS_NAME: int = 32  ## EOS_CONNECT_USERLOGININFO_DISPLAYNAME_MAX_LENGTH
const MAX_SOCKET: int = 32  ## EOSG socket ids: 1..32 alphanumeric characters
const MAX_BUCKET_BUILD: int = 16

enum PlatformState { NONE, STARTING, READY, FAILED }

var config: EosConfig = null
var profile_name: String = ""  ## --eos-profile: "" = the default identity

var _E: Variant = null  ## eos.gd (GDScript): option classes and enums
var _ieos: Object = null
var _plat: Variant = null  ## HPlatform
var _auth: Variant = null  ## HAuth
var _lobbies: Variant = null  ## HLobbies
var _platform_state: PlatformState = PlatformState.NONE
var _platform_error: String = ""
var _logging_in: bool = false
var _pending_name: String = ""
var _last_error: String = ""

var _gen: int = 0  ## bumped by cancel() / a new search: older coroutines see it and stop
var _searching: bool = false
var _search_s: float = 0.0
var _own_lobby: Variant = null  ## HLobby we host and wait in
var _own_peer: Object = null  ## its EOSGMultiplayerPeer server, until a match hands it over
var _match_lobby: Variant = null  ## the lobby of the match in progress
var _handed_peer: Object = null  ## the peer given to the game with matched()
var _current: Dictionary = {}  ## {mid, key, opp_id, opp_name, opp_rating, opp_games}
var _reported: Dictionary = {}
var _board: ServiceBoard = ServiceBoard.new()  ## me plus the opponents met: the repeat-pair damper
var _lb_busy: bool = false
var _lb_want: Array = []  ## [top_n, around_me, offset] of the newest leaderboard request not yet answered
var _settling: bool = false


## Waits for one thing that may never happen: finish() or expire(), whichever comes first.
class EosWaitLatch extends RefCounted:
	signal fired
	var done: bool = false
	var timed_out: bool = false
	var value: Variant = null

	func finish(v: Variant) -> void:
		if done:
			return
		done = true
		value = v
		fired.emit()

	func expire() -> void:
		if done:
			return
		done = true
		timed_out = true
		fired.emit()


# --- availability (static: MenuFlow asks before building the service) ------------------------------------------

## What is missing for EOS: the GDExtension binaries, the IEOS singleton, the addon scripts, the plugin's
## autoloads (enabling the plugin adds them). Empty = the plugin is usable.
static func missing_parts(tree: SceneTree) -> PackedStringArray:
	var out := PackedStringArray()
	if not ClassDB.class_exists(PEER_CLASS):
		out.append("EOSGMultiplayerPeer (EOSG binaries in addons/epic-online-services-godot/bin)")
	if not Engine.has_singleton(IEOS_NAME):
		out.append("IEOS singleton")
	if not ResourceLoader.exists(EOS_SCRIPT):
		out.append(EOS_SCRIPT)
	if tree == null or tree.root == null:
		out.append("scene tree")
	else:
		for n: String in AUTOLOADS:
			if tree.root.get_node_or_null(NodePath(n)) == null:
				out.append("autoload %s (enable the EOSG plugin)" % n)
	return out


static func available(tree: SceneTree) -> bool:
	return missing_parts(tree).is_empty()


## Why MenuFlow should not use EOS for `--online-service=<which>` ("auto", "eos" or "local"); "" = use it.
## "auto" never picks EOS in scripted runs (tests, captures and sims stay on the LAN backend).
static func unavailable_reason(tree: SceneTree, which: String, scripted: bool, cfg: EosConfig) -> String:
	if which == "local" or which == "stub":
		return "--online-service=%s" % which
	if which == "auto" and scripted:
		return "scripted run"
	var missing: PackedStringArray = missing_parts(tree)
	if not missing.is_empty():
		return "EOS plugin not installed: %s" % ", ".join(missing)
	if cfg == null or not cfg.is_complete():
		return "EOS credentials: %s" % (cfg.error if cfg != null else "none")
	return ""


## A ready ServiceEos for MenuFlow, or null (use ServiceLocal); a refused explicit "--online-service=eos" warns.
static func create_for(tree: SceneTree, which: String, eos_profile: String, scripted: bool) -> ServiceEos:
	var cfg: EosConfig = EosConfig.find() if which != "local" and which != "stub" else null
	var why: String = unavailable_reason(tree, which, scripted, cfg)
	if why != "":
		if which == "eos":
			push_warning("ServiceEos: not used (%s); falling back to the LAN service" % why)
		return null
	var s := ServiceEos.new()
	s.config = cfg
	s.profile_name = clean_profile(eos_profile)
	return s


# --- pure helpers (unit tested in tests/unit/test_net_service_eos.gd) -------------------------------------------

## A --eos-profile value made safe for file names: lower-case letters, digits, '-' and '_', at most 24.
static func clean_profile(p: String) -> String:
	var out: String = ""
	for ch: String in p.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_":
			out += ch
	return out.left(24)


static func cache_dir_for(p: String) -> String:
	return "user://eosg-cache" + ("" if p == "" else "-" + p)


static func store_path_for(p: String) -> String:
	return "user://eos_profile%s.json" % ("" if p == "" else "_" + p)


## Only lobbies of the same build meet (the build id is the NetLobby content hash).
static func bucket_for(build: String) -> String:
	return "%s:%s" % [BUCKET_PREFIX, build.left(MAX_BUCKET_BUILD) if build != "" else "dev"]


## The P2P socket both lobby members derive from the lobby id: "sb" + its letters and digits, 32 at most.
static func socket_name(lobby_id: String) -> String:
	var out: String = "sb"
	for ch: String in lobby_id:
		if out.length() >= MAX_SOCKET:
			break
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## A lobby as the matchmaker sees it: {id, owner, slots, members, build, rating, games, name, key}.
static func summarize(lobby_id: String, owner: String, slots: int, members: int, attrs: Array) -> Dictionary:
	var a: Dictionary = attr_map(attrs)
	return {"id": lobby_id, "owner": owner, "slots": slots, "members": members, "build": str(a.get(ATTR_BUILD, "")),
		"rating": int(a.get(ATTR_RATING, Rating.START_RATING)), "games": int(a.get(ATTR_GAMES, 0)),
		"name": NetLobby.clean_name(str(a.get(ATTR_NAME, ""))), "key": str(a.get(ATTR_KEY, "")),
		"version": int(a.get(ATTR_VERSION, -1))}


## EOSG attribute lists ([{key, value, visibility}]) as key -> value. EOS upper-cases nothing, but keys are
## compared lower-case to be safe.
static func attr_map(attrs: Array) -> Dictionary:
	var out: Dictionary = {}
	for a: Variant in attrs:
		if a is Dictionary and (a as Dictionary).has("key"):
			out[str((a as Dictionary)["key"]).to_lower()] = (a as Dictionary).get("value")
	return out


## Index of the lobby to join in `cands` (summaries), or -1: same build and protocol, a free slot, a key, not
## mine, inside the widening rating window after `waited` seconds; the closest rating wins, then the smaller id.
static func pick_lobby(cands: Array, my_id: String, my_rating: int, build: String, waited: float) -> int:
	var best: int = -1
	var best_diff: int = 1 << 30
	for i: int in cands.size():
		var c: Dictionary = cands[i]
		if str(c["owner"]) == my_id or str(c["owner"]) == "" or int(c["slots"]) < 1 or str(c["key"]) == "":
			continue
		if str(c["build"]) != build or int(c["version"]) != NetConfig.PROTOCOL_VERSION:
			continue
		if not Rating.in_window(my_rating, int(c["rating"]), waited):
			continue
		var diff: int = absi(my_rating - int(c["rating"]))
		if diff < best_diff or (diff == best_diff and str(c["owner"]) < str(cands[best]["owner"])):
			best = i
			best_diff = diff
	return best


## Two players both waiting in their own lobby: the larger id gives its lobby up and joins the smaller one's.
static func should_yield(my_id: String, other_owner: String) -> bool:
	return other_owner != "" and other_owner < my_id


## Profile numbers from the stats query (stat name -> value); missing stats are a new player.
static func profile_from_stats(vals: Dictionary) -> Dictionary:
	var r: int = int(vals.get(STAT_RATING, 0))
	return {"rating": r if r >= Rating.MIN_RATING else Rating.START_RATING, "games": maxi(0, int(vals.get(STAT_GAMES, 0))),
		"wins": maxi(0, int(vals.get(STAT_WINS, 0))), "losses": maxi(0, int(vals.get(STAT_LOSSES, 0)))}


## The IngestStat list for one rated game: the new rating ("Latest" stat) and the counters that moved.
static func stats_for_result(after_rating: int, score_me: float) -> Array:
	var out: Array = [{"stat_name": STAT_RATING, "ingest_amount": after_rating}, {"stat_name": STAT_GAMES, "ingest_amount": 1}]
	if score_me > 0.5:
		out.append({"stat_name": STAT_WINS, "ingest_amount": 1})
	elif score_me < 0.5:
		out.append({"stat_name": STAT_LOSSES, "ingest_amount": 1})
	return out


static func encode_report(report: Dictionary, signature: String) -> String:
	return JSON.stringify({"r": report, "s": signature})


## The other player's report from its lobby attribute, or {} when it is missing, garbled, for another match or
## another player, or the signature does not match the match key.
static func decode_report(raw: String, key: String, player_id: String, match_id: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(raw) != OK:
		return {}  # (JSON.parse_string would print an engine error for a garbled attribute)
	var v: Variant = j.data
	if not (v is Dictionary) or not ((v as Dictionary).get("r") is Dictionary):
		return {}
	var rep: Dictionary = (v as Dictionary)["r"]
	rep["ticks"] = int(rep.get("ticks", 0))  # JSON numbers come back as floats
	if str(rep.get("player", "")) != player_id or str(rep.get("match_id", "")) != match_id:
		return {}
	if not Rating.verify_report(key, rep, str((v as Dictionary).get("s", ""))):
		return {}
	return rep


static func fallback_name(id: String) -> String:
	return "Player %s" % (id.right(4).to_upper() if id != "" else "????")


## Leaderboard rows from EOS records ([{user_id, rank, score, user_display_name}]) and the per-user counters
## (`extra`: id -> {games, wins, losses}); `mine` fills my own row. Same shape as ServiceBoard.leaderboard.
static func leaderboard_view(records: Array, extra: Dictionary, my_id: String, mine: Dictionary, top_n: int,
		around_me: int, offset: int = 0) -> Dictionary:
	var rows: Array = []
	for rec: Variant in records:
		if not (rec is Dictionary):
			continue
		var r: Dictionary = rec
		var id: String = str(r.get("user_id", ""))
		if id == "":
			continue
		var counts: Dictionary = mine if id == my_id else extra.get(id, {})
		var games: int = int(counts.get("games", 0))
		var rating: int = int(r.get("score", Rating.START_RATING))
		var nm: String = str(r.get("user_display_name", ""))
		if id == my_id and str(mine.get("name", "")) != "":
			nm = str(mine["name"])
		rows.append({"id": id, "name": NetLobby.clean_name(nm) if nm != "" else fallback_name(id), "rating": rating,
			"games": games, "wins": int(counts.get("wins", 0)), "losses": int(counts.get("losses", 0)),
			"streak": int(counts.get("streak", 0)), "provisional": Rating.is_provisional(games), "tier": Rating.tier(rating),
			"rank": int(r.get("rank", 0))})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["rank"]) < int(y["rank"]))
	var data: Dictionary = ServiceBoard.page_view(rows, my_id, top_n, around_me, offset)
	data["source"] = ""
	return data


## The user ids whose games / wins / losses the screen will show (top rows and my window).
static func ids_to_detail(records: Array, my_id: String, top_n: int, around_me: int, offset: int = 0) -> PackedStringArray:
	var view: Dictionary = leaderboard_view(records, {}, my_id, {}, top_n, around_me, offset)
	var out := PackedStringArray()
	for r: Dictionary in (view["top"] as Array) + (view["around"] as Array):
		if str(r["id"]) != my_id:
			out.append(str(r["id"]))
	return out


# --- OnlineService ----------------------------------------------------------------------------------------------

func backend_name() -> String:
	return "EOS" if profile_name == "" else "EOS (%s)" % profile_name


func features() -> PackedStringArray:
	return PackedStringArray(["relay", "global_leaderboard"])


func is_searching() -> bool:
	return _searching


func login(display_name: String) -> void:
	var nm: String = _pick_name(display_name)
	if is_logged_in():
		if nm != str(profile.get("name", "")):
			profile["name"] = nm  # EOS keeps the name from the next sign-in; opponents see this one in the lobby
			_board.ensure(str(profile["id"]), nm)
			_save_local()
		logged_in.emit(profile)
		return
	if _logging_in:
		_pending_name = nm
		return
	_logging_in = true
	var err: String = await _login_async(nm)
	_logging_in = false
	if err != "":
		_last_error = err
		login_failed.emit(err)
		return
	if _pending_name != "" and _pending_name != nm:
		profile["name"] = _pending_name
	_pending_name = ""
	logged_in.emit(profile)


func logout() -> void:
	cancel()
	_close_match(true, true)
	profile = {}


## EOS matches on rating and build only; the loadout travels in the NetSession lobby once connected.
func quick_match(_loadout: Dictionary) -> void:
	if not is_logged_in():
		match_failed.emit("Sign in first")
		return
	cancel()
	_close_match(not _settling, true)  # a report still settling keeps its lobby until it is done
	_gen += 1
	_searching = true
	_search_s = 0.0
	status_changed.emit("Searching Epic Online Services")
	_search_loop(_gen)


## Stops searching and gives up a lobby nobody joined. A matched lobby stays while its result report is settling
## (MenuFlow reports a leave before it cancels); one with no report (backed out before the fight) is left.
func cancel() -> void:
	_gen += 1
	_searching = false
	_drop_own_lobby()
	if _match_lobby != null and not _settling and not _current.is_empty() and not _reported.has(str(_current["mid"])):
		_close_match(true, false)


func report_result(match_id: String, report: Dictionary, signature: String) -> void:
	if _current.is_empty() or match_id != str(_current["mid"]) or _reported.has(match_id):
		return
	var me: String = str(profile.get("id", ""))
	var r: int = int(profile.get("rating", Rating.START_RATING))
	if not Rating.verify_report(str(_current["key"]), report, signature) or str(report.get("player", "")) != me:
		result_recorded.emit(OnlineService.result_summary(match_id, "voided", "", r, r, "bad signature"))
		return
	_reported[match_id] = true
	_settling = true
	await _settle(_current.duplicate(), report, signature)
	_settling = false


func request_leaderboard(top_n: int = 20, around_me: int = 3, offset: int = 0) -> void:
	_lb_want = [top_n, around_me, offset]
	if _lb_busy:
		return  # the running request picks this one up when it is done (the newest page wins)
	_lb_busy = true
	while not _lb_want.is_empty():
		var w: Array = _lb_want
		_lb_want = []
		var data: Dictionary = await _leaderboard_async(int(w[0]), int(w[1]), int(w[2]))
		if _lb_want.is_empty():
			leaderboard_ready.emit(data)
	_lb_busy = false


func _process(delta: float) -> void:
	if _searching:
		_search_s += delta


func _exit_tree() -> void:
	_gen += 1
	_searching = false
	_drop_own_lobby()
	_close_match(true, true)


# --- plugin plumbing ----------------------------------------------------------------------------------------------

func _bind_plugin() -> String:
	var missing: PackedStringArray = missing_parts(get_tree())
	if not missing.is_empty():
		return "EOS plugin not installed: %s" % ", ".join(missing)
	_E = load(EOS_SCRIPT)
	_ieos = Engine.get_singleton(IEOS_NAME)
	_plat = get_tree().root.get_node(NodePath("HPlatform"))
	_auth = get_tree().root.get_node(NodePath("HAuth"))
	_lobbies = get_tree().root.get_node(NodePath("HLobbies"))
	if _E == null or _ieos == null:
		return "EOS plugin did not load"
	_lobbies.set("presence_enabled", false)  # device-id users have no presence
	return ""


## A new eos.gd option object, e.g. "Connect.LoginOptions". Its local_user_id fields default to the signed-in user.
func _new_opts(path: String) -> Object:
	var cur: Variant = _E
	for part: String in path.split("."):
		cur = (cur as Object).get(part) if cur is Object else null
		if cur == null:
			push_error("ServiceEos: EOSG has no %s" % path)
			return null
	return (cur as GDScript).new()


## An eos.gd enum value, e.g. "Lobby.LobbyPermissionLevel.InviteOnly" or "Result.Success".
func _enum(path: String) -> int:
	var cur: Variant = _E
	for part: String in path.split("."):
		if cur is Dictionary:
			cur = (cur as Dictionary).get(part)
		elif cur is Object:
			cur = (cur as Object).get(part)
		else:
			cur = null
		if cur == null:
			push_error("ServiceEos: EOSG has no %s" % path)
			return -1
	return int(cur)


func _code(d: Dictionary) -> int:
	return int(d.get("result_code", TIMED_OUT))


func _ok(d: Dictionary) -> bool:
	return _code(d) == _enum("Result.Success")


func _code_name(code: int) -> String:
	if code == TIMED_OUT:
		return "no answer"
	var res: Variant = (_E as Object).get("Result") if _E is Object else null
	if res is Dictionary:
		var k: Variant = (res as Dictionary).find_key(code)
		if k != null:
			return str(k)
	return str(code)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _latch(timeout_s: float) -> EosWaitLatch:
	var l := EosWaitLatch.new()
	get_tree().create_timer(timeout_s, true).timeout.connect(l.expire)
	return l


## Waits for one IEOS callback signal (call the IEOS method first; callbacks only arrive on the next SDK tick).
func _await_cb(sig: StringName, timeout_s: float = CALL_TIMEOUT) -> Dictionary:
	var l: EosWaitLatch = _latch(timeout_s)
	var cb := func(d: Variant) -> void: l.finish(d)
	_ieos.connect(sig, cb)
	if not l.done:
		await l.fired
	if _ieos.is_connected(sig, cb):
		_ieos.disconnect(sig, cb)
	if l.timed_out:
		return {"result_code": TIMED_OUT}
	return l.value if l.value is Dictionary else {"result_code": int(l.value)}


## Awaits a plugin helper coroutine (HAuth / HLobbies / HLobby), giving up after `timeout_s`: the helpers wait on
## SDK callbacks with no timeout of their own. null = timed out (or the helper's own null).
func _guard(c: Callable, timeout_s: float = CALL_TIMEOUT) -> Variant:
	var l: EosWaitLatch = _latch(timeout_s)
	var run := func() -> void:
		var r: Variant = await c.call()
		l.finish(r)
	run.call()
	if not l.done:
		await l.fired
	return null if l.timed_out else l.value


func _runtime() -> Object:
	return get_tree().root.get_node(NodePath("EOSGRuntime"))


func _alive(gen: int) -> bool:
	return gen == _gen and _searching and is_inside_tree()


# --- platform and sign-in -----------------------------------------------------------------------------------------

func _ensure_platform() -> bool:
	if _platform_state == PlatformState.READY:
		return true
	if _platform_state == PlatformState.FAILED:
		return false  # EOS cannot be initialized twice in one process: restart the game
	if _platform_state == PlatformState.STARTING:
		await platform_settled
		return _platform_state == PlatformState.READY
	_platform_state = PlatformState.STARTING
	var err: String = _bind_plugin()
	if err == "" and (config == null or not config.is_complete()):
		err = "EOS credentials: %s" % (config.error if config != null else "none")
	if err == "":
		var creds: Object = (load(CREDENTIALS_SCRIPT) as GDScript).new()
		creds.set("product_name", config.product_name)
		creds.set("product_version", config.version_or(str(ProjectSettings.get_setting("application/config/version", ""))))
		creds.set("product_id", config.product_id)
		creds.set("sandbox_id", config.sandbox_id)
		creds.set("deployment_id", config.deployment_id)
		creds.set("client_id", config.client_id)
		creds.set("client_secret", config.client_secret)
		creds.set("encryption_key", config.encryption_key)
		_plat.set("cache_directory", ProjectSettings.globalize_path(cache_dir_for(profile_name)))
		var ok: Variant = await _guard(Callable(_plat as Object, "setup_eos_async").bind(creds), PLATFORM_TIMEOUT)
		if ok != true:
			err = "Epic Online Services did not start (check the credentials; details in the log)"
	if err == "":
		var relay: int = int(_ieos.call("p2p_interface_set_relay_control", _enum("P2P.RelayControl.AllowRelays")))
		if relay != _enum("Result.Success"):
			push_warning("ServiceEos: set_relay_control returned %s" % _code_name(relay))
	_platform_state = PlatformState.READY if err == "" else PlatformState.FAILED
	_platform_error = err
	platform_settled.emit()
	return err == ""


func _login_async(nm: String) -> String:
	status_changed.emit("Connecting to Epic Online Services")
	if not await _ensure_platform():
		return _platform_error
	# The device id is created once per device and OS user (DuplicateNotAllowed = it already exists).
	var dev: Object = _new_opts("Connect.CreateDeviceIdOptions")
	dev.set("device_model", ("%s %s" % [OS.get_name(), OS.get_model_name()]).left(64))
	_ieos.call("connect_interface_create_device_id", dev)
	var made: Dictionary = await _await_cb(&"connect_interface_create_device_id_callback")
	if not _ok(made) and _code(made) != _enum("Result.DuplicateNotAllowed"):
		return "Could not create the EOS device id (%s)" % _code_name(_code(made))
	var cred: Object = _new_opts("Connect.Credentials")
	cred.set("type", _enum("ExternalCredentialType.DeviceidAccessToken"))
	cred.set("token", null)
	var info: Object = _new_opts("Connect.UserLoginInfo")
	info.set("display_name", nm.left(MAX_EOS_NAME))
	var opts: Object = _new_opts("Connect.LoginOptions")
	opts.set("credentials", cred)
	opts.set("user_login_info", info)
	# HAuth: Connect login, and on InvalidUser (a new device) create_user with the continuance token.
	var ok: Variant = await _guard(Callable(_auth as Object, "login_game_services_async").bind(opts))
	var puid: String = str(_auth.get("product_user_id"))
	if ok != true or puid == "":
		return "EOS sign-in failed (%s)" % ("no answer" if ok == null else "see the log")
	# A new device signs in through create_user, which fires no connect login callback: EOSGRuntime (the default
	# local_user_id of every option object) and the P2P peer's mediator never learn the user. Sign in once more.
	if str(_runtime().get("local_product_user_id")) != puid:
		ok = await _guard(Callable(_auth as Object, "login_game_services_async").bind(opts))
		if ok != true or str(_runtime().get("local_product_user_id")) != puid:
			return "EOS sign-in failed after creating the user (see the log)"
	var clash: String = _identity_clash(puid)
	if clash != "":
		return clash
	profile = {"id": puid, "name": nm}
	_board.ensure(puid, nm)
	_load_local()
	await _load_stats()
	_save_local()
	status_changed.emit("Signed in as %s" % nm)
	return ""


func _load_stats() -> void:
	var q: Object = _new_opts("Stats.QueryStatsOptions")
	q.set("stat_names", Array(STAT_NAMES))
	_ieos.call("stats_interface_query_stats", q)
	var r: Dictionary = await _await_cb(&"stats_interface_query_stats_callback")
	var vals: Dictionary = {}
	if _ok(r):
		for n: String in STAT_NAMES:
			var c: Object = _new_opts("Stats.CopyStatByNameOptions")
			c.set("name", n)
			var got: Variant = _ieos.call("stats_interface_copy_stat_by_name", c)
			if got is Dictionary and _ok(got) and (got as Dictionary).get("stat") is Dictionary:
				vals[n] = int(((got as Dictionary)["stat"] as Dictionary).get("value", 0))
	else:
		push_warning("ServiceEos: stats query failed (%s); using the cached rating" % _code_name(_code(r)))
	_apply_numbers(profile_from_stats(vals) if _ok(r) else {})


func _apply_numbers(d: Dictionary) -> void:
	for k: String in d:
		profile[k] = d[k]
	if is_logged_in():
		var e: Dictionary = _board.ensure(str(profile["id"]), str(profile.get("name", "")))
		for k2: String in ["rating", "games", "wins", "losses", "streak"]:
			e[k2] = int(profile.get(k2, Rating.START_RATING if k2 == "rating" else 0))


func _pick_name(display_name: String) -> String:
	if display_name.strip_edges() != "":
		return NetLobby.clean_name(display_name)
	var stored: Dictionary = _read_local(store_path_for(profile_name))
	return NetLobby.clean_name(str(stored.get("name", "")))


## A second --eos-profile that signs in as the default profile's user would match against itself.
func _identity_clash(puid: String) -> String:
	if profile_name == "":
		return ""
	var main: Dictionary = _read_local(store_path_for(""))
	if str(main.get("puid", "")) == puid:
		return "--eos-profile=%s signed in as the same EOS user as the default profile (the device id is shared); see docs/eos_setup.md" % profile_name
	return ""


# --- quick match ------------------------------------------------------------------------------------------------

func _search_loop(gen: int) -> void:
	var me: String = str(profile["id"])
	while _alive(gen):
		if _search_s > SEARCH_TIMEOUT:
			_searching = false
			_drop_own_lobby()
			match_failed.emit("Nobody to fight right now. Try again in a while.")
			return
		var found: Array = await _search_once()
		if not _alive(gen):
			return
		if _own_lobby != null and _member_count(_own_lobby) >= 2:
			await _host_matched(gen)
			return
		var cands: Array = []
		for l: Variant in found:
			var c: Dictionary = _summary_of(l)
			if _own_lobby != null and not should_yield(me, str(c["owner"])):
				c["slots"] = 0  # while hosting, only a smaller id's lobby is worth leaving ours for
			cands.append(c)
		var i: int = pick_lobby(cands, me, int(profile.get("rating", Rating.START_RATING)), build_id, _search_s)
		if i >= 0:
			if _own_lobby != null:
				await _drop_own_lobby()
			if await _join(found[i], cands[i], gen):
				return
		elif _own_lobby == null:
			if not await _host_lobby(gen):
				if _alive(gen):
					status_changed.emit("Could not open a lobby; retrying")
		var t: float = 0.0
		while t < SEARCH_INTERVAL and _alive(gen):
			if _own_lobby != null and _member_count(_own_lobby) >= 2:
				await _host_matched(gen)
				return
			await _wait(POLL_STEP)
			t += POLL_STEP
		if _alive(gen):
			status_changed.emit("Searching (rating window ±%d)" % Rating.search_window(_search_s))


## One lobby search: same bucket, a free slot, closest rating first. Returns HLobby objects (not joined).
func _search_once() -> Array:
	var so: Object = _new_opts("Lobby.CreateLobbySearchOptions")
	so.set("max_results", SEARCH_RESULTS)
	var made: Variant = _ieos.call("lobby_interface_create_lobby_search", so)
	if not (made is Dictionary) or not _ok(made) or (made as Dictionary).get("lobby_search") == null:
		return []
	var search: Object = (made as Dictionary)["lobby_search"]
	var eq: int = _enum("ComparisonOp.Equal")
	search.call("set_parameter", str((_E as Object).get("Lobby").get("SEARCH_BUCKET_ID")), bucket_for(build_id), eq)
	search.call("set_parameter", str((_E as Object).get("Lobby").get("SEARCH_MINSLOTSAVAILABLE")), 1,
		_enum("ComparisonOp.GreaterThanOrEqual"))
	search.call("set_parameter", ATTR_RATING, int(profile.get("rating", Rating.START_RATING)), _enum("ComparisonOp.Distance"))
	var res: Variant = await _guard(Callable(_lobbies as Object, "search_async").bind(search))
	return (res as Array) if res is Array else []


func _summary_of(lobby: Variant) -> Dictionary:
	var o: Object = lobby
	return summarize(str(o.get("lobby_id")), str(o.get("owner_product_user_id")), int(o.get("available_slots")),
		(o.get("members") as Array).size(), o.get("attributes") as Array)


func _member_count(lobby: Variant) -> int:
	if lobby == null or not bool((lobby as Object).call("is_valid")):
		return 0
	return ((lobby as Object).get("members") as Array).size()


func _member_attr(lobby: Variant, puid: String, key: String) -> Variant:
	if lobby == null:
		return null
	for m: Variant in ((lobby as Object).get("members") as Array):
		if str((m as Object).get("product_user_id")) == puid:
			return attr_map((m as Object).get("attributes") as Array).get(key)
	return null


func _has_member(lobby: Variant, puid: String) -> bool:
	if lobby == null or not bool((lobby as Object).call("is_valid")):
		return false
	for m: Variant in ((lobby as Object).get("members") as Array):
		if str((m as Object).get("product_user_id")) == puid:
			return true
	return false


func _other_member(lobby: Variant) -> String:
	var me: String = str(profile.get("id", ""))
	for m: Variant in ((lobby as Object).get("members") as Array):
		var id: String = str((m as Object).get("product_user_id"))
		if id != me:
			return id
	return ""


## Create our lobby and listen on its socket. The key goes in last, so a lobby is only joinable (pick_lobby needs
## the key) once the server socket exists.
func _host_lobby(gen: int) -> bool:
	var o: Object = _new_opts("Lobby.CreateLobbyOptions")
	o.set("bucket_id", bucket_for(build_id))
	o.set("max_lobby_members", 2)
	o.set("permission_level", _enum("Lobby.LobbyPermissionLevel.PublicAdvertised"))
	o.set("presence_enabled", false)
	o.set("allow_invites", false)
	o.set("enable_join_by_id", false)
	o.set("disable_host_migration", true)
	o.set("enable_rtc_room", false)
	var lobby: Variant = await _guard(Callable(_lobbies as Object, "create_lobby_async").bind(o))
	if lobby == null:
		return false
	if not _alive(gen):
		_guard(Callable(lobby as Object, "destroy_async"))
		return false
	var lid: String = str((lobby as Object).get("lobby_id"))
	var peer: Object = ClassDB.instantiate(PEER_CLASS)
	var err: int = int(peer.call("create_server", socket_name(lid)))
	if err != OK:
		push_warning("ServiceEos: create_server failed (%s)" % error_string(err))
		_guard(Callable(lobby as Object, "destroy_async"))
		return false
	_own_lobby = lobby
	_own_peer = peer
	var key: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var lo: Object = lobby
	lo.call("add_attribute", ATTR_BUILD, build_id)
	lo.call("add_attribute", ATTR_VERSION, NetConfig.PROTOCOL_VERSION)
	lo.call("add_attribute", ATTR_RATING, int(profile.get("rating", Rating.START_RATING)))
	lo.call("add_attribute", ATTR_GAMES, int(profile.get("games", 0)))
	lo.call("add_attribute", ATTR_NAME, str(profile.get("name", "")))
	lo.call("add_attribute", ATTR_KEY, key)
	var ok: Variant = await _guard(Callable(lo, "update_async"))
	if ok != true:
		await _drop_own_lobby()
		return false
	if _alive(gen):
		status_changed.emit("Waiting for an opponent")
	return true


## Someone joined our lobby: hide it, learn who it is, hand the server peer over.
func _host_matched(gen: int) -> void:
	var lobby: Variant = _own_lobby
	var peer: Object = _own_peer
	_own_lobby = null
	_own_peer = null
	_match_lobby = lobby
	var opp_id: String = _other_member(lobby)
	var waited: float = 0.0
	while waited < MEMBER_INFO_WAIT and _member_attr(lobby, opp_id, ATTR_NAME) == null and gen == _gen:
		await _wait(POLL_STEP)
		waited += POLL_STEP
	if gen != _gen:
		_close_match(true, true)
		return
	(lobby as Object).set("permission_level", _enum("Lobby.LobbyPermissionLevel.InviteOnly"))
	_guard(Callable(lobby as Object, "update_async"))  # locked: off the search results; no need to wait
	var nm: Variant = _member_attr(lobby, opp_id, ATTR_NAME)
	var opp: Dictionary = {"id": opp_id, "name": NetLobby.clean_name(str(nm)) if nm != null else fallback_name(opp_id),
		"rating": int(_member_attr(lobby, opp_id, ATTR_RATING) if _member_attr(lobby, opp_id, ATTR_RATING) != null else Rating.START_RATING),
		"games": int(_member_attr(lobby, opp_id, ATTR_GAMES) if _member_attr(lobby, opp_id, ATTR_GAMES) != null else 0)}
	var key: String = str(attr_map((lobby as Object).get("attributes") as Array).get(ATTR_KEY, ""))
	_finish(ROLE_HOST, peer, str((lobby as Object).get("lobby_id")), key, opp)


func _join(target: Variant, summary: Dictionary, gen: int) -> bool:
	status_changed.emit("Joining %s" % str(summary["name"]))
	var joined: Variant = await _guard(Callable(_lobbies as Object, "join_async").bind(target))
	if joined == null:
		return false
	var jo: Object = joined
	if not _alive(gen):
		_guard(Callable(jo, "leave_async"))
		return false
	jo.call("add_current_member_attribute", ATTR_NAME, str(profile.get("name", "")))
	jo.call("add_current_member_attribute", ATTR_RATING, int(profile.get("rating", Rating.START_RATING)))
	jo.call("add_current_member_attribute", ATTR_GAMES, int(profile.get("games", 0)))
	await _guard(Callable(jo, "update_async"))
	var s: Dictionary = _summary_of(joined)
	if not _alive(gen) or str(s["key"]) == "" or str(s["owner"]) == "" or str(s["owner"]) == str(profile["id"]):
		_guard(Callable(jo, "leave_async"))
		return false
	var peer: Object = ClassDB.instantiate(PEER_CLASS)
	var err: int = int(peer.call("create_client", socket_name(str(s["id"])), str(s["owner"])))
	if err != OK:
		push_warning("ServiceEos: create_client failed (%s)" % error_string(err))
		_guard(Callable(jo, "leave_async"))
		return false
	_match_lobby = joined
	var opp: Dictionary = {"id": str(s["owner"]), "name": str(s["name"]), "rating": int(s["rating"]), "games": int(s["games"])}
	_finish(ROLE_CLIENT, peer, str(s["id"]), str(s["key"]), opp)
	return true


func _finish(role: String, peer: Object, mid: String, key: String, opp: Dictionary) -> void:
	_searching = false
	_handed_peer = peer
	_board.note_opponent(str(opp["id"]), str(opp["name"]), int(opp["rating"]), int(opp["games"]))
	_current = {"mid": mid, "key": key, "opp_id": str(opp["id"]), "opp_name": str(opp["name"])}
	status_changed.emit("Found %s" % str(opp["name"]))
	matched.emit(OnlineService.match_info(role, "", 0, peer, mid, key, opp))


## Give up the lobby we wait in (nobody joined). Safe to call without awaiting.
func _drop_own_lobby() -> void:
	var lobby: Variant = _own_lobby
	var peer: Object = _own_peer
	_own_lobby = null
	_own_peer = null
	if peer != null:
		peer.call("close")
	if lobby != null:
		await _guard(Callable(lobby as Object, "destroy_async"))


## Leave the match lobby (`leave_lobby`) and close the peer handed to the game (`close_peer`: only when a new
## search starts or the service goes away; after a result the NetSession may still be showing the fight).
func _close_match(leave_lobby: bool, close_peer: bool) -> void:
	if close_peer and _handed_peer != null:
		var p: MultiplayerPeer = _handed_peer as MultiplayerPeer
		if p != null and p.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			p.close()
		_handed_peer = null
	if not leave_lobby:
		return
	var lobby: Variant = _match_lobby
	_match_lobby = null
	_current = {}
	if lobby != null and bool((lobby as Object).call("is_valid")):
		var lo: Object = lobby
		if bool(lo.call("is_owner", str(profile.get("id", "")))):
			_guard(Callable(lo, "destroy_async"))
		else:
			_guard(Callable(lo, "leave_async"))


# --- results ------------------------------------------------------------------------------------------------------

func _settle(cur: Dictionary, report: Dictionary, signature: String) -> void:
	var lobby: Variant = _match_lobby
	var me: String = str(profile.get("id", ""))
	var mid: String = str(cur["mid"])
	var opp_id: String = str(cur["opp_id"])
	var theirs: Dictionary = {}
	if lobby != null and bool((lobby as Object).call("is_valid")):
		(lobby as Object).call("add_current_member_attribute", ATTR_REPORT, encode_report(report, signature))
		await _guard(Callable(lobby as Object, "update_async"))
		status_changed.emit("Waiting for %s's report" % str(cur["opp_name"]))
		var t: float = 0.0
		while t < REPORT_WAIT:
			var raw: Variant = _member_attr(lobby, opp_id, ATTR_REPORT)
			if raw != null and str(raw) != "":
				theirs = decode_report(str(raw), str(cur["key"]), opp_id, mid)
				break
			if not _has_member(lobby, opp_id):
				break  # they left without a report: decide on ours
			await _wait(POLL_STEP)
			t += POLL_STEP
	var v: Dictionary = Rating.reconcile(me, report, opp_id, theirs, true)
	var before: int = int(profile.get("rating", Rating.START_RATING))
	var after: int = before
	if bool(v["rated"]):
		_board.ensure(me, str(profile.get("name", "")))
		_apply_numbers({})  # my board entry = the profile numbers
		_board.apply(me, opp_id, float(v["score_a"]))
		var e: Dictionary = _board.entry(me)
		_apply_numbers({"rating": int(e["rating"]), "games": int(e["games"]), "wins": int(e["wins"]), "losses": int(e["losses"]),
			"streak": int(e.get("streak", 0))})
		after = int(e["rating"])
		_save_local()
	result_recorded.emit(OnlineService.result_summary(mid, str(v["status"]), str(v["winner"]), before, after, str(v["why"])))
	if bool(v["rated"]):
		await _ingest(stats_for_result(after, float(v["score_a"])))
	if not theirs.is_empty():
		await _wait(REPORT_LINGER)  # they may still be reading ours
	if _match_lobby == lobby:
		_close_match(true, false)


func _ingest(list: Array) -> void:
	var o: Object = _new_opts("Stats.IngestStatOptions")
	o.set("stats", list)
	_ieos.call("stats_interface_ingest_stat", o)
	var r: Dictionary = await _await_cb(&"stats_interface_ingest_stat_callback")
	if not _ok(r):
		push_warning("ServiceEos: stat ingest failed (%s); the client policy must allow Stats ingest" % _code_name(_code(r)))


# --- leaderboard --------------------------------------------------------------------------------------------------

func _leaderboard_async(top_n: int, around_me: int, offset: int) -> Dictionary:
	var waited: float = 0.0
	while _logging_in and waited < CALL_TIMEOUT:
		await _wait(POLL_STEP)
		waited += POLL_STEP
	var empty: Dictionary = {"top": [], "around": [], "me": {}, "total": 0, "source": "EOS"}
	if not is_logged_in() or _platform_state != PlatformState.READY:
		empty["source"] = "EOS: not signed in%s" % (" (%s)" % _last_error if _last_error != "" else "")
		empty["error"] = "offline"
		return empty
	var q: Object = _new_opts("Leaderboards.QueryLeaderboardRanksOptions")
	q.set("leaderboard_id", LEADERBOARD_ID)
	_ieos.call("leaderboards_interface_query_leaderboard_ranks", q)
	var r: Dictionary = await _await_cb(&"leaderboards_interface_query_leaderboard_ranks_callback")
	if not _ok(r):
		empty["source"] = "EOS leaderboard unavailable (%s)" % _code_name(_code(r))
		empty["error"] = "unavailable"
		return empty
	var n: int = int(_ieos.call("leaderboards_interface_get_leaderboard_record_count", _new_opts("Leaderboards.GetLeaderboardRecordCountOptions")))
	var records: Array = []
	for i: int in n:
		var c: Object = _new_opts("Leaderboards.CopyLeaderboardRecordByIndexOptions")
		c.set("leaderboard_record_index", i)
		var got: Variant = _ieos.call("leaderboards_interface_copy_leaderboard_record_by_index", c)
		if got is Dictionary and _ok(got) and (got as Dictionary).get("record") is Dictionary:
			records.append((got as Dictionary)["record"])
	var me: String = str(profile.get("id", ""))
	var extra: Dictionary = await _user_counts(ids_to_detail(records, me, top_n, around_me, offset))
	var data: Dictionary = leaderboard_view(records, extra, me, profile, top_n, around_me, offset)
	data["source"] = "EOS: all players"
	return data


## id -> {games, wins, losses} from the leaderboard user scores of the counter stats. Best effort: {} on failure.
func _user_counts(ids: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	if ids.is_empty():
		return out
	var sum: int = _enum("Leaderboards.LeaderboardAggregation.Sum")
	var q: Object = _new_opts("Leaderboards.QueryLeaderboardUserScoresOptions")
	q.set("user_ids", Array(ids))
	var info: Array[Dictionary] = [{"stat_name": STAT_GAMES, "aggregation": sum}, {"stat_name": STAT_WINS, "aggregation": sum},
		{"stat_name": STAT_LOSSES, "aggregation": sum}]
	q.set("stat_info", info)
	q.set("start_time", -1)
	q.set("end_time", -1)
	_ieos.call("leaderboards_interface_query_leaderboard_user_scores", q)
	var r: Dictionary = await _await_cb(&"leaderboards_interface_query_leaderboard_user_scores_callback")
	if not _ok(r):
		return out
	var keys: Dictionary = {STAT_GAMES: "games", STAT_WINS: "wins", STAT_LOSSES: "losses"}
	for id: String in ids:
		var row: Dictionary = {}
		for stat: String in keys:
			var c: Object = _new_opts("Leaderboards.CopyLeaderboardUserScoreByUserIdOptions")
			c.set("user_id", id)
			c.set("stat_name", stat)
			var got: Variant = _ieos.call("leaderboards_interface_copy_leaderboard_user_score_by_user_id", c)
			if got is Dictionary and _ok(got) and (got as Dictionary).get("user_score") is Dictionary:
				row[keys[stat]] = int(((got as Dictionary)["user_score"] as Dictionary).get("score", 0))
		out[id] = row
	return out


# --- local profile file (name, ProductUserId, recent opponents); never in scripted runs ---------------------------

func _read_local(path: String) -> Dictionary:
	if Flags.is_scripted_run() or not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


func _load_local() -> void:
	var d: Dictionary = _read_local(store_path_for(profile_name))
	if str(d.get("puid", "")) == str(profile.get("id", "")) and d.get("recent") is Dictionary:
		_board.recent = d["recent"]
	if str(d.get("puid", "")) == str(profile.get("id", "")):
		profile["streak"] = int(d.get("streak", 0))  # EOS has no streak stat: this device remembers it


func _save_local() -> void:
	if Flags.is_scripted_run() or not is_logged_in():
		return
	var f := FileAccess.open(store_path_for(profile_name), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"name": str(profile.get("name", "")), "puid": str(profile["id"]),
			"recent": _board.recent, "streak": int(profile.get("streak", 0))}))
