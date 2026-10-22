class_name OnlineScreen
extends Control
## Online 1v1 lobby: your name, host (listen on a port, shows this machine's LAN addresses) or join by address
## (ip or ip:port), then your loadout picked as usual while the other player's shows beside it. The host starts the
## fight once someone has joined. Talks to the NetSession MenuFlow owns; emits start_pressed (host) and back.
## Quick Match mode (open_quick): the same screen without the address controls. It asks the OnlineService for an
## opponent (spinner, Cancel), shows who was found with their rating, connects the NetSession as the service says
## (host listens, client joins after a beat) and starts the fight by itself. It also builds and signs this side's
## result report for the service (report_finished / report_abandoned).

signal back
signal start_pressed

var state: MenuState
var session: NetSession = null
var player_name: String = "Gladiator"
var service: OnlineService = null

enum Phase { IDLE, SEARCHING, FOUND, CONNECTING, STARTED }

const FOUND_DELAY_S: float = 1.6  ## the opponent card stays up this long before the connection is made (host listens at once)
const SPIN_RATE: float = 5.0

var _title: Label
var _body: BoxContainer
var _left: VBoxContainer
var _name_edit: LineEdit
var _port_edit: LineEdit
var _addr_edit: LineEdit
var _host_btn: Button
var _join_btn: Button
var _status: Label
var _addresses: Label
var _opponent: Label
var _panel: LoadoutPanel
var _start: Button
var _back: Button
var _status_text: String = ""
var _quick: bool = false
var _phase: Phase = Phase.IDLE
var _info: Dictionary = {}
var _found_s: float = 0.0
var _spin: float = 0.0
var _match_open: bool = false
var _adv: Array[Control] = []
var _quick_box: VBoxContainer
var _headline: Label
var _spinner: Control
var _card: Label


func _init(p_state: MenuState) -> void:
	state = p_state
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.012, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28.0
	root.offset_right = -28.0
	root.offset_top = 14.0
	root.offset_bottom = -16.0
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	_title = MenuTheme.label("ARENA REMOTA / Online 1v1", 52, MenuTheme.PARCHMENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = BoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 20)
	scroll.add_child(_body)

	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(left_panel)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 10)
	left_panel.add_child(_left)
	_left.add_child(MenuTheme.label("Name", MenuTheme.FONT_SMALL, MenuTheme.OCHRE))
	_name_edit = _edit(player_name, "Your name")
	_name_edit.max_length = NetLobby.MAX_NAME
	_name_edit.text_changed.connect(func(t: String) -> void:
		player_name = NetLobby.clean_name(t)
		_push_local())
	_name_edit.text_submitted.connect(func(_t: String) -> void:
		if _quick and service != null and _phase == Phase.SEARCHING:
			_begin_search())
	_left.add_child(_name_edit)
	_left.add_child(MenuTheme.label("Host a fight on port", MenuTheme.FONT_SMALL, MenuTheme.OCHRE))
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	_port_edit = _edit(str(NetConfig.DEFAULT_PORT), "Port")
	_port_edit.custom_minimum_size = Vector2(180.0, MenuTheme.ROW_H)
	hrow.add_child(_port_edit)
	_host_btn = MenuTheme.button("Host", 220.0)
	_host_btn.pressed.connect(_on_host)
	hrow.add_child(_host_btn)
	_left.add_child(hrow)
	_addresses = MenuTheme.label("", 24, MenuTheme.DIM_TEXT)
	_addresses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left.add_child(_addresses)
	_left.add_child(MenuTheme.label("Join by address (ip or ip:port)", MenuTheme.FONT_SMALL, MenuTheme.OCHRE))
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 10)
	_addr_edit = _edit("", "192.168.1.20")
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	jrow.add_child(_addr_edit)
	_join_btn = MenuTheme.button("Join", 220.0)
	_join_btn.pressed.connect(_on_join)
	jrow.add_child(_join_btn)
	_left.add_child(jrow)
	_status = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left.add_child(_status)
	_opponent = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_opponent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left.add_child(_opponent)
	for c: Node in _left.get_children():
		if c != _left.get_child(0) and c != _name_edit and c != _status and c != _opponent:
			_adv.append(c as Control)
	_build_quick_box()

	_panel = LoadoutPanel.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.set_header("YOUR ARMS")
	_panel.loadout_changed.connect(_on_loadout)
	_body.add_child(_panel)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 40)
	root.add_child(foot)
	_back = MenuTheme.button("Back", 300.0)
	_back.pressed.connect(_on_back)
	foot.add_child(_back)
	_start = MenuTheme.button("FIGHT!", 420.0)
	_start.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.RED, MenuTheme.OCHRE, 4))
	_start.pressed.connect(_on_start_pressed)
	foot.add_child(_start)
	resized.connect(_relayout)


func _edit(text: String, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = hint
	e.custom_minimum_size = Vector2(0.0, MenuTheme.ROW_H)
	e.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	return e


## Shows the screen for `p_session` (a fresh one: connect controls; an open one: back in its lobby).
func open(p_session: NetSession) -> void:
	_set_mode(false)
	_bind_session(p_session)
	_apply_weapon_access()
	_panel.set_loadout(state.loadout_with_outfit(0))
	_name_edit.text = player_name
	_push_local()
	refresh()
	_relayout()
	(_host_btn if not session.is_open() else _panel.first_focus()).grab_focus()


func _bind_session(p_session: NetSession) -> void:
	if session != p_session:
		session = p_session
		session.status_changed.connect(show_status)
		session.lobby_changed.connect(refresh)


# --- Quick Match -------------------------------------------------------------------------------------------------

func _build_quick_box() -> void:
	_quick_box = VBoxContainer.new()
	_quick_box.add_theme_constant_override("separation", 14)
	_quick_box.visible = false
	_left.add_child(_quick_box)
	_headline = MenuTheme.label("", 44, MenuTheme.PARCHMENT)
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_box.add_child(_headline)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(0.0, 150.0)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_draw_spinner)
	_quick_box.add_child(_spinner)
	_card = MenuTheme.label("", 40, MenuTheme.OCHRE)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quick_box.add_child(_card)


func _set_mode(quick: bool) -> void:
	_quick = quick
	for c: Control in _adv:
		c.visible = not quick
	_quick_box.visible = quick
	_opponent.visible = not quick
	_title.text = "ARENA REMOTA / Quick Match" if quick else "ARENA REMOTA / Online 1v1"
	_back.text = "Cancel" if quick else "Back"
	_start.text = "Search again" if quick else "FIGHT!"
	set_process(quick)


## Quick Match: look for an opponent through `p_service` and play whoever is found. `p_session` is a fresh NetSession.
func open_quick(p_session: NetSession, p_service: OnlineService) -> void:
	_set_mode(true)
	_bind_session(p_session)
	if service != p_service:
		service = p_service
		service.logged_in.connect(_on_logged_in)
		service.login_failed.connect(_on_login_failed)
		service.matched.connect(_on_matched)
		service.match_failed.connect(_on_match_failed)
		service.status_changed.connect(show_status)
	_apply_weapon_access()
	_panel.set_loadout(state.loadout_with_outfit(0))
	_name_edit.text = player_name
	_status_text = ""
	_relayout()
	_begin_search()
	_panel.first_focus().grab_focus()


func _begin_search() -> void:
	service.cancel()
	_phase = Phase.SEARCHING
	_info = {}
	_found_s = 0.0
	_push_local()
	service.build_id = session.content_hash()
	service.login(player_name)  # signs in the first time, renames afterwards; logged_in starts the search
	refresh()


func _on_logged_in(profile: Dictionary) -> void:
	if _quick and PlayerProgress.shared().sync_ranked(int(profile.get("games", 0)), int(profile.get("wins", 0))).size() > 0:
		_apply_weapon_access()  # the service's own record unlocked something (a reinstall, another device)
	if _quick and _phase == Phase.SEARCHING and not service.is_searching():
		service.quick_match(my_loadout())


## The `owned` list this screen's weapons are checked against: store products plus earned weapons. A ranked Quick
## Match only takes what was earned; --unlock-all works in a direct (unrated) lobby only.
func weapon_access() -> Array:
	return WeaponUnlocks.access(state.store.owned(), PlayerProgress.shared().counters, Flags.unlock_all() and not _quick)


func _apply_weapon_access() -> void:
	_panel.set_weapon_access(weapon_access(), PlayerProgress.shared().counters)


## The loadout this player brings: the menu pick with its outfit, gated by `weapon_access()` (a weapon picked with
## --unlock-all off-line, or not yet earned, becomes the longsword here).
func my_loadout() -> Dictionary:
	return LoadoutRules.sanitize(state.loadout_with_outfit(0), weapon_access())


func _on_login_failed(reason: String) -> void:
	if _quick:
		_phase = Phase.IDLE
		show_status("Could not sign in: %s" % reason)


func _on_match_failed(reason: String) -> void:
	if _quick and _phase == Phase.SEARCHING:
		_phase = Phase.IDLE
		show_status(reason)


func _on_matched(info: Dictionary) -> void:
	if not _quick or _phase != Phase.SEARCHING:
		return
	_info = info
	_phase = Phase.FOUND
	_found_s = 0.0
	if str(info.get("role", "")) == OnlineService.ROLE_HOST:
		_connect_now()  # the host listens at once so the client's join cannot beat it
	refresh()


func _connect_now() -> void:
	_phase = Phase.CONNECTING
	var role: String = str(_info.get("role", ""))
	var peer: Variant = _info.get("peer")
	if peer != null:
		if session.has_method("adopt_peer"):
			session.call("adopt_peer", peer, role)
		else:
			show_status("This build cannot use relay connections yet")
			_phase = Phase.IDLE
	elif role == OnlineService.ROLE_HOST:
		session.host(int(_info.get("port", NetConfig.DEFAULT_PORT)))
	else:
		session.join(str(_info.get("address", "")), int(_info.get("port", NetConfig.DEFAULT_PORT)))


func _process(delta: float) -> void:
	if not visible or not _quick:
		return
	_spin += delta * SPIN_RATE
	_spinner.queue_redraw()
	if _phase == Phase.FOUND:
		_found_s += delta
		if _found_s >= FOUND_DELAY_S:
			_connect_now()
			refresh()
	elif _phase == Phase.CONNECTING:
		_found_s += delta
		_try_start()


## The host starts the fight as soon as the client is in and the opponent card has been up for a moment.
func _try_start() -> void:
	if _phase == Phase.CONNECTING and str(_info.get("role", "")) == OnlineService.ROLE_HOST and session.remote_joined \
			and _found_s >= FOUND_DELAY_S:
		_phase = Phase.STARTED
		start_pressed.emit()


func _draw_spinner() -> void:
	var c: Vector2 = _spinner.size * 0.5
	var r: float = minf(_spinner.size.y * 0.4, 56.0)
	if _phase == Phase.IDLE:
		return
	if _phase != Phase.SEARCHING:
		_spinner.draw_arc(c, r, 0.0, TAU, 48, MenuTheme.OCHRE, 6.0, true)
		return
	_spinner.draw_arc(c, r, 0.0, TAU, 48, MenuTheme.BRONZE.darkened(0.55), 6.0, true)
	for i: int in 5:  # a comet: a bright head with a fading tail
		var a0: float = _spin - float(i) * 0.32
		_spinner.draw_arc(c, r, a0 - 0.3, a0, 8, MenuTheme.OCHRE.lerp(MenuTheme.RED, float(i) / 5.0), 8.0 - float(i), true)


func _refresh_quick() -> void:
	var rated: Dictionary = service.my_rating() if service != null else {}
	match _phase:
		Phase.SEARCHING:
			_headline.text = "Searching for an opponent"
			_card.text = "You: %s %s" % [Rating.tier(int(rated.get("rating", 0))), Rating.rating_text(int(rated.get("rating", 0)), int(rated.get("games", 0)))]
		Phase.IDLE:
			_headline.text = "No match"
			_card.text = ""
		_:
			var o: Dictionary = _info.get("opponent", {})
			_headline.text = "Opponent found" if _phase == Phase.FOUND else "Entering the arena"
			_card.text = "%s\n%s  %s" % [str(o.get("name", "?")), Rating.tier(int(o.get("rating", 0))),
				Rating.rating_text(int(o.get("rating", 0)), int(o.get("games", 0)))]
	_status.text = _status_text
	_start.visible = _phase == Phase.IDLE
	_start.disabled = false
	_name_edit.editable = _phase == Phase.SEARCHING or _phase == Phase.IDLE
	_spinner.queue_redraw()
	_try_start()


func _on_back() -> void:
	if _quick and service != null:
		service.cancel()
	back.emit()


func _on_start_pressed() -> void:
	if _quick:
		_begin_search()
	else:
		start_pressed.emit()


# --- reporting the result ----------------------------------------------------------------------------------------

func is_quick() -> bool:
	return _quick and not _info.is_empty()


## MenuFlow calls this when the match is built: from now on leaving counts as a loss.
func match_started() -> void:
	_match_open = true


func has_open_match() -> bool:
	return _quick and _match_open


## The fight ended: `winner_side` 0 = host, 1 = client, -1 = draw.
func report_finished(winner_side: int, ticks: int, reason: String) -> void:
	var me_side: int = 0 if str(_info.get("role", "")) == OnlineService.ROLE_HOST else 1
	var winner: String = ""
	if winner_side >= 0:
		winner = str(service.profile.get("id", "")) if winner_side == me_side else str((_info["opponent"] as Dictionary).get("id", ""))
	_report(Rating.KIND_RESULT, winner, reason, ticks)


## The match ended without a result: Rating.KIND_LEFT (this player left) or KIND_DROPPED (the connection died).
func report_abandoned(kind: String, ticks: int = 0) -> void:
	_report(kind, "", kind, ticks)


func _report(kind: String, winner_id: String, reason: String, ticks: int) -> void:
	if not has_open_match():
		return
	_match_open = false
	var rep: Dictionary = Rating.make_report(str(_info.get("match_id", "")), str(service.profile.get("id", "")), kind, winner_id, reason, ticks)
	service.report_result(str(_info.get("match_id", "")), rep, Rating.sign_report(str(_info.get("match_key", "")), rep))


## One line for the result panel.
static func summary_text(s: Dictionary) -> String:
	match str(s.get("status", "")):
		"agree", "single", "forfeit":
			return "Rating %d -> %d  (%+d)" % [int(s.get("before", 0)), int(s.get("after", 0)), int(s.get("delta", 0))]
		"pending":
			return "Rating pending"
		_:
			return "Not rated: %s" % str(s.get("why", ""))


func show_status(text: String) -> void:
	_status_text = text
	refresh()


func refresh() -> void:
	if session == null:
		return
	if _quick and service != null:
		_refresh_quick()
		return
	var open_now: bool = session.is_open()
	_host_btn.disabled = open_now
	_join_btn.disabled = open_now
	_port_edit.editable = not open_now
	_addr_edit.editable = not open_now
	_name_edit.editable = not open_now
	_status.text = _status_text if _status_text != "" else ("Not connected" if not open_now else "")
	if session.role == NetSession.ROLE_HOST and open_now:
		_addresses.text = "Others join at: %s" % ", ".join(PackedStringArray(_lan_addresses(int(_port_edit.text))))
	else:
		_addresses.text = ""
	if session.remote_joined:
		_opponent.text = "Opponent: %s  -  %s" % [session.remote_name, _describe(session.remote_loadout)]
	else:
		_opponent.text = ""
	_start.visible = session.role == NetSession.ROLE_HOST
	_start.disabled = not (session.role == NetSession.ROLE_HOST and session.remote_joined)
	if session.role == NetSession.ROLE_CLIENT and session.remote_joined:
		_status.text = "%s\nWaiting for %s to start the fight" % [_status.text, session.remote_name]


func _describe(l: Dictionary) -> String:
	var parts: PackedStringArray = [LoadoutRules.display_name(str(l.get("weapon", "fists")))]
	var off: String = str(l.get("offhand", ""))
	if off != "":
		parts.append(LoadoutRules.display_name(off))
	var armor: Dictionary = l.get("armor", {})
	parts.append("%d armor" % armor.size())
	return ", ".join(parts)


static func _lan_addresses(port: int) -> Array:
	var out: Array = []
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append("%s:%d" % [a, port])
	if out.is_empty():
		out.append("this machine's address, port %d" % port)
	return out


func _push_local() -> void:
	if session != null:
		session.set_local(player_name, LoadoutRules.sanitize(_panel.loadout(), weapon_access()))


func _on_loadout(l: Dictionary) -> void:
	state.set_loadout(0, l)
	_push_local()
	if _quick and _phase == Phase.SEARCHING and service != null:
		service.quick_match(LoadoutRules.sanitize(l, weapon_access()))  # same search, new arms


func _on_host() -> void:
	_push_local()
	var port: int = int(_port_edit.text) if _port_edit.text.is_valid_int() else NetConfig.DEFAULT_PORT
	session.host(clampi(port, 1, 65535))
	refresh()


func _on_join() -> void:
	_push_local()
	var addr: Array = NetLobby.parse_address(_addr_edit.text)
	if addr.is_empty():
		show_status("Type the host's address, for example 192.168.1.20 or 192.168.1.20:7777")
		return
	session.join(str(addr[0]), int(addr[1]))
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


## Landscape: connect column and loadout side by side. Portrait: stacked.
func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_body.vertical = portrait
	_title.add_theme_font_size_override("font_size", 40 if portrait else 52)
