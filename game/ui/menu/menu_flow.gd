class_name MenuFlow
extends Node
## The menu layer: title, loadout, options, pause and end-of-match screens, plus the arena backdrop behind them and
## the Match lifecycle. Add it as a child of the main scene and call setup(host). It builds each Match under `host`
## and announces them with match_started so the host can hang debug tools on it. `adopt()` takes over a match the
## host started itself (command-line --mode) so Esc pause and the end-of-match menu still work.
## Online 1v1: the Online screen owns nothing itself; MenuFlow keeps the NetSession (alive from host/join until
## the player leaves) and builds each online Match from the host's START like any other, then hangs the session's
## host or client driver on it. Online matches never pause the tree (the other side keeps playing).
## Everything is laid out in units: on a landscape screen a unit is a 1920x1080 design pixel, on a portrait phone the
## layer is scaled up so the columns stay readable.

signal match_started(match_node: Match)
signal match_closed

enum Screen { TITLE, LOADOUT, OPTIONS, FIGHT, PAUSED, RESULT, ONLINE, LEADERBOARD }

const LAYER: int = 60
const RESULT_DELAY_S: float = 3.4
const PORTRAIT_UNITS: float = 1000.0  ## layout width on a portrait screen
const ORBIT_RATE: float = 0.1
const ORBIT_RADIUS: float = 9.0
const ORBIT_HEIGHT: float = 3.4
const ONLINE_MODE: String = "online"

var state: MenuState = MenuState.new()
var settings: MenuSettings = MenuSettings.new()
var screen: Screen = Screen.TITLE
var current_match: Match = null

var _host: Node = null
var _layer: CanvasLayer
var _root: Control
var _title: TitleScreen
var _loadout: LoadoutScreen
var _options: OptionsScreen
var _online: OnlineScreen
var _net: NetSession = null
var _leaderboard: LeaderboardScreen
var _service: OnlineService = null  ## the matchmaking / rating backend (ServiceLocal until another is wired in)
var _quick: bool = false  ## the online screen / match in progress is a Quick Match (rated), not direct IP
var _rating_line: String = ""
var _pause: MenuPanel = null
var _pause_dim: ColorRect
var _hint: ControlsHint
var _pause_btn: Button
var _backdrop: Node3D = null
var _cam: Camera3D = null
var _orbit: float = 0.6
var _next_seed: int = 0
var _fight_token: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(p_host: Node) -> void:
	_host = p_host
	settings.load_file()
	settings.apply()
	_build_ui()
	for c: Node in _host.get_children():
		if c is MeshInstance3D:  # placeholder floor and box of the bare main scene
			(c as MeshInstance3D).visible = false
	_show_title()


## The host already started `m` itself (for example from --mode); wire pause and the end menu to it.
func adopt(m: Match, mode: String) -> void:
	_host = m.get_parent()
	settings.load_file()
	settings.apply()
	_build_ui()
	state.last_mode = mode
	current_match = m
	_hook_match(m)
	_enter_fight()


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	_title = TitleScreen.new()
	_title.chosen.connect(_on_title)
	_root.add_child(_title)
	_loadout = LoadoutScreen.new(state)
	_loadout.start.connect(_begin_fight)
	_loadout.back.connect(_show_title)
	_root.add_child(_loadout)
	_options = OptionsScreen.new(settings)
	_options.back.connect(_show_title)
	_root.add_child(_options)
	_online = OnlineScreen.new(state)
	_online.back.connect(_show_title)
	_online.start_pressed.connect(_on_online_start)
	_root.add_child(_online)
	_leaderboard = LeaderboardScreen.new()
	_leaderboard.back.connect(_show_title)
	_root.add_child(_leaderboard)
	_pause_dim = MenuTheme.dim_rect()
	_pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_dim.visible = false
	_root.add_child(_pause_dim)
	_hint = ControlsHint.new()
	_root.add_child(_hint)
	_pause_btn = MenuTheme.button("II", 96.0)
	_pause_btn.pressed.connect(_pause_game)
	_pause_btn.visible = false
	_root.add_child(_pause_btn)
	_hide_screens()
	_layout()


func _process(delta: float) -> void:
	_layout()
	if _cam != null and is_instance_valid(_cam):
		_orbit += delta * ORBIT_RATE
		_cam.position = Vector3(cos(_orbit) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_orbit) * ORBIT_RADIUS)
		_cam.look_at(Vector3(0.0, 1.6, 0.0))


## Scales the layer so a landscape screen keeps design units and a portrait one gets ~1000 units across.
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var s: float = 1.0 if vp.x / vp.y >= 1.2 else vp.x / PORTRAIT_UNITS
	_layer.scale = Vector2(s, s)
	_root.position = Vector2.ZERO
	_root.size = vp / s
	if _hint.visible:
		_hint.position = Vector2((_root.size.x - _hint.size.x) * 0.5, 18.0)
	_pause_btn.position = Vector2(_root.size.x - 96.0 - 18.0, 18.0)


# --- screens -----------------------------------------------------------------------------------------------------

func _hide_screens() -> void:
	_title.visible = false
	_loadout.visible = false
	_options.visible = false
	_online.visible = false
	_leaderboard.visible = false
	_pause_dim.visible = false
	_hint.hide_now()
	_pause_btn.visible = false
	if _pause != null:
		_pause.queue_free()
		_pause = null


func _show_title() -> void:
	_close_match()
	_end_session()
	_hide_screens()
	_ensure_backdrop()
	screen = Screen.TITLE
	_title.visible = true
	_title.focus_first.call_deferred()


func _open_loadout(mode: String) -> void:
	_close_match()
	_hide_screens()
	_ensure_backdrop()
	screen = Screen.LOADOUT
	_loadout.visible = true
	_loadout.open(mode)


func _on_title(id: String) -> void:
	match id:
		"fight":
			_open_loadout("player_vs_cpu")
		"local_2p":
			_open_loadout("local_2p")
		"quick":
			_open_online(true)
		"leaderboard":
			_open_leaderboard()
		"online":
			_open_online()
		"bots":
			_begin_fight("bot_vs_bot")
		"options":
			_hide_screens()
			screen = Screen.OPTIONS
			_options.visible = true
			_options.open()
		"quit":
			get_tree().quit()


func _ensure_backdrop() -> void:
	if _backdrop != null or _host == null:
		return
	_backdrop = Node3D.new()
	_backdrop.name = "MenuBackdrop"
	var arena := Arena.new()
	arena.name = "Arena"
	_backdrop.add_child(arena)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_backdrop.add_child(_cam)
	_host.add_child(_backdrop)
	_cam.current = true


func _free_backdrop() -> void:
	if _backdrop == null:
		return
	_host.remove_child(_backdrop)
	_backdrop.free()
	_backdrop = null
	_cam = null


# --- the match ---------------------------------------------------------------------------------------------------

func _new_seed() -> int:
	if _next_seed == 0:
		_next_seed = Flags.seed_value() if Flags.args.has("seed") else int(Time.get_ticks_usec() & 0x7fffffff)
	else:
		_next_seed = (_next_seed * 1103515245 + 12345) & 0x7fffffff
	return _next_seed


func _begin_fight(mode: String) -> void:
	_close_match()
	_hide_screens()
	_free_backdrop()
	var cfg: Dictionary = state.to_config(mode, _new_seed())
	settings.apply_quality()  # before Match.new(): the arena, sand and blood read GfxQuality when built
	var m := Match.new()
	m.name = "Match"
	_host.add_child(m)
	m.setup(cfg)
	if m.presenter != null and m.presenter.blood != null:
		m.presenter.blood.set_quality(GfxQuality.blood_level())
	current_match = m
	_hook_match(m)
	match_started.emit(m)
	_enter_fight()


func _hook_match(m: Match) -> void:
	_fight_token += 1
	m.match_over.connect(_on_match_over.bind(_fight_token))


func _enter_fight() -> void:
	screen = Screen.FIGHT
	_hide_screens()
	var mode: String = str(current_match.config.get("mode", "bot_vs_bot")) if current_match != null else "bot_vs_bot"
	if mode != "bot_vs_bot":
		var touch: bool = DisplayServer.is_touchscreen_available() or Flags.args.has("touch")
		var pad: bool = not Input.get_connected_joypads().is_empty()
		_hint.show_lines(ControlsText.hint_lines(mode, pad, touch), minf(_root.size.x - 120.0, 1500.0))
		_pause_btn.visible = touch
	else:
		_pause_btn.visible = DisplayServer.is_touchscreen_available()


func _close_match() -> void:
	if _net != null:
		_net.detach_match()
	get_tree().paused = false
	Engine.time_scale = 1.0
	_fight_token += 1
	if current_match != null and is_instance_valid(current_match):
		var p: Node = current_match.get_parent()
		if p != null:
			p.remove_child(current_match)
		current_match.free()
		match_closed.emit()
	current_match = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- online ------------------------------------------------------------------------------------------------------

func _is_online() -> bool:
	return state.last_mode == ONLINE_MODE and _net != null


func _open_online(quick: bool = false) -> void:
	_close_match()
	_hide_screens()
	_ensure_backdrop()
	_quick = quick
	if quick and _net != null:
		_end_session()  # a Quick Match always starts from a fresh connection
	if _net == null:
		_net = NetSession.new()
		_net.name = "NetSession"
		add_child(_net)
		_net.match_requested.connect(_begin_online)
		_net.closed.connect(_on_net_closed)
	screen = Screen.ONLINE
	_online.visible = true
	if quick:
		_ensure_service()
		_online.open_quick(_net, _service)
	else:
		_online.open(_net)


func _ensure_service() -> void:
	if _service != null:
		return
	if Flags.get_arg("online-service", "local") == "stub":
		var st := ServiceStub.new()
		st.auto_match = false
		for i: int in 14:
			st.add_fake_player("fake%02d" % i, ["Verus", "Cato", "Brutus", "Livia", "Marcus", "Titus", "Aurelia", "Gaius", "Nero", "Crispus", "Julia", "Felix", "Sabina", "Lucan"][i],
				1620 - i * 38, 60 - i * 3, 40 - i * 2)
		_service = st
	else:
		var loc := ServiceLocal.new()
		loc.entropy = int(Time.get_ticks_usec() & 0x7fffffff) ^ (OS.get_process_id() << 8)
		loc.device_id = Flags.get_arg("device-id", "")
		_service = loc
	_service.name = "OnlineService"
	_service.result_recorded.connect(_on_recorded)
	add_child(_service)


func _open_leaderboard() -> void:
	_close_match()
	_hide_screens()
	_ensure_backdrop()
	_ensure_service()
	if not _service.is_logged_in():
		_service.login(_online.player_name)
	screen = Screen.LEADERBOARD
	_leaderboard.visible = true
	_leaderboard.open(_service)


func _on_recorded(summary: Dictionary) -> void:
	_rating_line = OnlineScreen.summary_text(summary)
	if screen == Screen.RESULT and _is_online() and _quick and current_match != null:
		_show_online_result(int(current_match.result.get("winner", -1)), current_match.names)  # the verdict came after the panel


func _end_session() -> void:
	if _quick and _online.has_open_match():
		_online.report_abandoned(Rating.KIND_LEFT)  # leaving a rated fight before the end is a loss
	if _service != null:
		_service.cancel()
	if _net == null:
		return
	_net.closed.disconnect(_on_net_closed)
	_net.leave("left")
	_net.queue_free()
	_net = null


func _on_online_start() -> void:
	if _net != null:
		_net.start_match(_new_seed())


## Both sides: the host pressed FIGHT (or Rematch). Build the match from the START message.
func _begin_online(start: Dictionary) -> void:
	_close_match()
	_hide_screens()
	_free_backdrop()
	state.last_mode = ONLINE_MODE
	_rating_line = ""
	if _quick:
		_online.match_started()
	settings.apply_quality()  # each peer builds with its own setting; presentation only, the sim is unaffected
	var m := Match.new()
	m.name = "Match"
	_host.add_child(m)
	m.setup(NetLobby.match_config(start, true))
	if m.presenter != null and m.presenter.blood != null:
		m.presenter.blood.set_quality(GfxQuality.blood_level())
	_net.attach_match(m)
	current_match = m
	_hook_match(m)
	match_started.emit(m)
	_enter_fight()


func _on_net_closed(reason: String) -> void:
	if _net != null:
		_net.queue_free()
		_net = null
	if _quick and _online.has_open_match():
		_online.report_abandoned(Rating.KIND_DROPPED)
	if screen == Screen.ONLINE:
		_open_online(_quick)
		_online.show_status(reason)
		return
	if screen == Screen.FIGHT or screen == Screen.PAUSED or screen == Screen.RESULT:
		get_tree().paused = false
		Engine.time_scale = 1.0
		screen = Screen.RESULT
		_hint.hide_now()
		_pause_btn.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause_dim.visible = true
		_show_panel("VALE", "Connection closed", reason, [["online", "Online"], ["title", "Title"]])


func _on_match_over(result: Dictionary, token: int) -> void:
	if _quick and _is_online() and _online.has_open_match():
		_online.report_finished(int(result.get("winner", -1)), int(result.get("ticks", 0)), str(result.get("reason", "")))
	if current_match == null or bool(current_match.config.get("loop", false)):
		return
	var t: SceneTreeTimer = get_tree().create_timer(RESULT_DELAY_S, true, false, true)
	t.timeout.connect(_show_result.bind(result, token))


func _show_result(result: Dictionary, token: int) -> void:
	if token != _fight_token or screen != Screen.FIGHT or current_match == null:
		return
	screen = Screen.RESULT
	_hint.hide_now()
	_pause_btn.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var names: Array = current_match.names
	var w: int = int(result.get("winner", -1))
	var mode: String = str(current_match.config.get("mode", ""))
	if _is_online():
		_show_online_result(w, names)
		return
	var latin: String = "AEQVO MARTE"
	var english: String = "Evenly matched"
	if w >= 0:
		latin = "VICTORIA" if (mode != "player_vs_cpu" or w == 0) else "MORS"
		english = ("%s wins" % str(names[w])) if mode != "player_vs_cpu" else ("You won" if w == 0 else "%s wins" % str(names[w]))
	_pause_dim.visible = true
	_show_panel(latin, english, "", [["rematch", "Rematch"], ["loadout", "Change loadout"], ["title", "Title"]])


func _show_online_result(w: int, names: Array) -> void:
	var me: int = 0 if _net.role == NetSession.ROLE_HOST else 1
	var latin: String = "AEQVO MARTE"
	var english: String = "Evenly matched"
	if w >= 0:
		latin = "VICTORIA" if w == me else "MORS"
		english = "You won" if w == me else "%s wins" % str(names[w])
	_pause_dim.visible = true
	var entries: Array = [["online", "Find another opponent" if _quick else "Back to lobby"], ["title", "Leave"]]
	var body: String = "" if _net.role == NetSession.ROLE_HOST else "The host picks a rematch"
	if _quick:
		body = _rating_line  # ranked fights have no rematch
	elif _net.role == NetSession.ROLE_HOST:
		entries.push_front(["net_rematch", "Rematch"])
	_show_panel(latin, english, body, entries)


func _pause_game() -> void:
	if screen != Screen.FIGHT or current_match == null:
		return
	if _is_online():
		# The fight goes on for the other player: a menu over it, no pause.
		screen = Screen.PAUSED
		if _net != null:
			_net.input_blocked = true  # neutral input from this side while the menu is up
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_pause_btn.visible = false
		_show_panel("PAVSA", "Online: the fight goes on", "", [["resume", "Resume"], ["title", "Leave match"]])
		return
	screen = Screen.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_btn.visible = false
	_pause_dim.visible = true
	_show_panel("PAVSA", "Paused", "", [["resume", "Resume"], ["loadout", "Change loadout"], ["title", "Title"]])


func _resume() -> void:
	if screen != Screen.PAUSED:
		return
	screen = Screen.FIGHT
	if _net != null:
		_net.input_blocked = false
	_pause_dim.visible = false
	if _pause != null:
		_pause.queue_free()
		_pause = null
	get_tree().paused = false
	if current_match != null:
		for r: Variant in current_match.readers:
			if r != null and (str(r.device) == "kbm" or str(r.device) == "auto"):
				r.set_captured(true)
		_pause_btn.visible = DisplayServer.is_touchscreen_available() or Flags.args.has("touch")
		if _is_online() and current_match.over:
			# The fight ended behind the menu: show its result now.
			_show_result(current_match.result, _fight_token)


func _show_panel(latin: String, english: String, body: String, entries: Array) -> void:
	if _pause != null:
		_pause.queue_free()
	_pause = MenuPanel.new()
	_pause.build(latin, english, body, entries)
	_pause.chosen.connect(_on_panel)
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_pause)
	_pause.focus_first.call_deferred()


func _on_panel(id: String) -> void:
	var mode: String = state.last_mode if state.last_mode != "bot_vs_bot" else "player_vs_cpu"
	match id:
		"resume":
			_resume()
		"online":
			_open_online(_quick)
		"net_rematch":
			_on_online_start()
		"rematch":
			_begin_fight(state.last_mode if state.last_mode != ONLINE_MODE else "player_vs_cpu")
		"loadout":
			_open_loadout(mode)
		"title":
			_show_title()


func _unhandled_input(event: InputEvent) -> void:
	var pressed_pause: bool = event.is_action_pressed("pause") \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START)
	if not pressed_pause:
		return
	if screen == Screen.FIGHT:
		_pause_game()
		get_viewport().set_input_as_handled()
	elif screen == Screen.PAUSED:
		_resume()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Closing the window in the middle of a rated fight counts as leaving it.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _quick and _online != null and _online.has_open_match():
		_online.report_abandoned(Rating.KIND_LEFT)
