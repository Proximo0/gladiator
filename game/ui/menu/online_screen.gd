class_name OnlineScreen
extends Control
## Online 1v1 lobby: your name, host (listen on a port, shows this machine's LAN addresses) or join by address
## (ip or ip:port), then your loadout picked as usual while the other player's shows beside it. The host starts the
## fight once someone has joined. Talks to the NetSession MenuFlow owns; emits start_pressed (host) and back.
## Quick Match mode (open_quick): the same screen without the address controls, driven by a QuickMatchFlow. It asks
## the OnlineService for an opponent (spinner with the search time, the usual wait and the rating range, Cancel),
## shows who was found, connects the NetSession as the service says (host listens at once, the client joins after
## the card's beat), runs a short loadout confirm (READY, or a countdown; a ready note each way) and the host starts
## the fight. A connection that fails before the fight puts the player back in the queue with a plain-language line.
## After the fight it owns the online part of the result panel: the rating change (RatingChangeView), the rematch
## handshake (RematchHandshake over NetSession notes) and the panel's entries (result_entries / result_body). It also
## builds and signs this side's result report for the service (report_finished / report_abandoned).

signal back
signal start_pressed
signal result_changed  ## the online part of the result panel changed (rematch answer, rating verdict): redraw it

var state: MenuState
var session: NetSession = null
var player_name: String = "Gladiator"
var service: OnlineService = null

const SPIN_RATE: float = 5.0
const TOUCH_H_PORTRAIT: float = 124.0  ## main buttons on a phone held upright: about 48 dp at ~1000 units across
const TOUCH_H_WIDE: float = 84.0
const NOTE_READY: String = "ready"

var flow: QuickMatchFlow = QuickMatchFlow.new()
var rematch: RematchHandshake = RematchHandshake.new()
var last_summary: Dictionary = {}  ## the service's verdict on the last fight (with this player's streak)

var _title: ScreenHeader
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
var _info: Dictionary = {}
var _spin: float = 0.0
var _match_open: bool = false
var _rated_next: bool = true  ## the next fight with this opponent is rated (a rematch may be a friendly)
var _rated_now: bool = true
var _summary_played: String = ""  ## the match id whose rating change already counted up
var _opponent_name: String = ""
var _portrait: bool = false
var _shown_second: int = -1
var _panel_locked: bool = false
var _adv: Array[Control] = []
var _quick_box: VBoxContainer
var _headline: Label
var _spinner: Control
var _wait_line: Label
var _range_line: Label
var _card: Label
var _banner: Label
var _confirm_box: VBoxContainer
var _arms: Label
var _ready_btn: Button
var _remote_line: Label
var _link_queued: bool = false


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
	_title = ScreenHeader.new("ARENA REMOTA / Online 1v1")
	root.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
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
		if _quick and service != null and flow.phase == QuickMatchFlow.Phase.SEARCHING:
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
		session.note_received.connect(_on_note)


# --- Quick Match -------------------------------------------------------------------------------------------------

func _build_quick_box() -> void:
	_quick_box = VBoxContainer.new()
	_quick_box.add_theme_constant_override("separation", 10)
	_quick_box.visible = false
	_left.add_child(_quick_box)
	_left.move_child(_quick_box, 0)  # above the name field
	_headline = MenuTheme.label("", 46, MenuTheme.PARCHMENT)
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quick_box.add_child(_headline)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(0.0, 170.0)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_draw_spinner)
	_quick_box.add_child(_spinner)
	_wait_line = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_wait_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_box.add_child(_wait_line)
	_range_line = MenuTheme.label("", 24, MenuTheme.DIM_TEXT)
	_range_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_box.add_child(_range_line)
	_card = MenuTheme.label("", 36, MenuTheme.OCHRE)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quick_box.add_child(_card)
	_banner = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quick_box.add_child(_banner)
	_confirm_box = VBoxContainer.new()
	_confirm_box.add_theme_constant_override("separation", 10)
	_quick_box.add_child(_confirm_box)
	_arms = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_arms.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_box.add_child(_arms)
	_ready_btn = MenuTheme.button("READY", 420.0)
	_ready_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ready_btn.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.RED, MenuTheme.OCHRE, 4))
	_ready_btn.add_theme_font_size_override("font_size", 44)
	_ready_btn.pressed.connect(press_ready)
	_confirm_box.add_child(_ready_btn)
	_remote_line = MenuTheme.label("", 26, MenuTheme.DIM_TEXT)
	_remote_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_box.add_child(_remote_line)


func _set_mode(quick: bool) -> void:
	_quick = quick
	for c: Control in _adv:
		c.visible = not quick
	_quick_box.visible = quick
	_opponent.visible = not quick
	_status.visible = not quick
	_title.set_text("ARENA REMOTA / Quick Match" if quick else "ARENA REMOTA / Online 1v1")
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
	_banner.text = ""
	_relayout()
	_begin_search()
	_back.grab_focus()


func _begin_search() -> void:
	service.cancel()
	flow.begin_search()
	_info = {}
	_match_open = false
	_rated_next = true
	_rated_now = true
	last_summary = {}
	rematch.reset()
	_push_local()
	service.build_id = session.content_hash()
	service.login(player_name)  # signs in the first time, renames afterwards; logged_in starts the search
	refresh()


## The connection to the last opponent failed before the fight (MenuFlow reopened the screen with a fresh session):
## say what happened in plain words and keep searching, or stop when it is not about that opponent.
func requeue(reason: String) -> void:
	var said: Dictionary = OnlineText.plain(reason, _opponent_name)
	if [OnlineText.KIND_VERSION, OnlineText.KIND_OFFLINE, OnlineText.KIND_BLOCKED].has(str(said["kind"])):
		service.cancel()
		flow.fail(reason, _opponent_name)
		refresh()
		return
	_banner.text = "%s. Back in the queue." % str(said["title"])
	refresh()


func _on_logged_in(profile: Dictionary) -> void:
	if _quick and PlayerProgress.shared().sync_ranked(int(profile.get("games", 0)), int(profile.get("wins", 0))).size() > 0:
		_apply_weapon_access()  # the service's own record unlocked something (a reinstall, another device)
	if _quick and flow.phase == QuickMatchFlow.Phase.SEARCHING and not service.is_searching():
		service.quick_match(my_loadout())
	refresh()


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
	if _quick and flow.phase == QuickMatchFlow.Phase.SEARCHING:
		flow.fail("Could not sign in: %s" % reason)
		refresh()


func _on_match_failed(reason: String) -> void:
	if _quick and flow.phase == QuickMatchFlow.Phase.SEARCHING:
		flow.fail(reason)
		refresh()


func _on_matched(info: Dictionary) -> void:
	if not _quick or not flow.found(str(info.get("role", "")) == OnlineService.ROLE_HOST):
		return
	_info = info
	_opponent_name = str((info.get("opponent", {}) as Dictionary).get("name", ""))
	_banner.text = ""
	if flow.is_host:
		_connect_now()  # the host listens at once so the client's join cannot beat it
	refresh()
	_ready_btn.grab_focus()


func _connect_now() -> void:
	var role: String = str(_info.get("role", ""))
	var peer: Variant = _info.get("peer")
	if peer != null:
		if session.has_method("adopt_peer"):
			session.call("adopt_peer", peer, role)
		else:
			flow.fail("This build cannot use relay connections yet")
	elif role == OnlineService.ROLE_HOST:
		session.host(int(_info.get("port", NetConfig.DEFAULT_PORT)))
	else:
		session.join(str(_info.get("address", "")), int(_info.get("port", NetConfig.DEFAULT_PORT)))


## READY on the confirm: lock the arms in (the client's LOADOUT goes out before its ready note).
func press_ready() -> void:
	if flow.press_ready():
		_push_local()
		_send_ready()
		refresh()


func _send_ready() -> void:
	if flow.take_ready_note(session.remote_joined):
		session.send_note({"t": NOTE_READY})


func _on_note(note: Dictionary) -> void:
	if not _quick:
		return
	match str(note.get("t", "")):
		NOTE_READY:
			flow.on_remote_ready()
			refresh()
		RematchHandshake.NOTE_ASK, RematchHandshake.NOTE_DECLINE:
			rematch.on_note(str(note["t"]))
			if rematch.state == RematchHandshake.State.AGREED:
				_on_rematch_agreed()
			result_changed.emit()


func _process(delta: float) -> void:
	if not _quick:
		return
	var asked: RematchHandshake.State = rematch.state
	rematch.tick(delta)
	if rematch.state != asked:
		result_changed.emit()  # the question expired
	if not visible:
		return
	_spin += delta * SPIN_RATE
	_spinner.queue_redraw()
	var was_ready: bool = flow.local_ready
	if flow.tick(delta) and not flow.is_host:
		_connect_now()  # the card had its beat: the client joins now
	if flow.local_ready and not was_ready:
		_push_local()  # the countdown ran out: these arms go to the fight
	_send_ready()
	if flow.join_timed_out(session.remote_joined):
		session.leave("No answer from the host")  # MenuFlow puts us back in the queue with the words for it
		return
	_try_start()
	var sec: int = int(flow.search_s) if flow.phase == QuickMatchFlow.Phase.SEARCHING else int(flow.phase_s * 4.0)
	if sec != _shown_second:
		_shown_second = sec
		refresh()


## The host starts the fight once both are ready (or the other side's note is late) and the client is in.
func _try_start() -> void:
	if flow.can_start(session.remote_joined):
		flow.start()
		start_pressed.emit()


func _draw_spinner() -> void:
	var c: Vector2 = _spinner.size * 0.5
	var r: float = minf(_spinner.size.y * 0.42, 70.0)
	var f: Font = MenuTheme.caps_font()
	match flow.phase:
		QuickMatchFlow.Phase.IDLE:
			return
		QuickMatchFlow.Phase.SEARCHING:
			_spinner.draw_arc(c, r, 0.0, TAU, 64, MenuTheme.BRONZE.darkened(0.55), 6.0, true)
			for i: int in 6:  # a comet: a bright head with a fading tail
				var a0: float = _spin - float(i) * 0.3
				_spinner.draw_arc(c, r, a0 - 0.28, a0, 10, MenuTheme.OCHRE.lerp(MenuTheme.RED, float(i) / 6.0), 9.0 - float(i), true)
			var t: String = OnlineText.clock(flow.search_s)
			var ts: Vector2 = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
			_spinner.draw_string(f, c + Vector2(-ts.x * 0.5, 14.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, MenuTheme.PARCHMENT)
		_:
			# Found: a full ring that drains as the confirm counts down, the seconds left inside.
			var left: float = 1.0
			if flow.phase == QuickMatchFlow.Phase.CONFIRM and not flow.local_ready:
				left = clampf(1.0 - flow.phase_s / QuickMatchFlow.CONFIRM_S, 0.0, 1.0)
			_spinner.draw_arc(c, r, 0.0, TAU, 64, MenuTheme.BRONZE.darkened(0.55), 6.0, true)
			_spinner.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * left, 64, MenuTheme.OCHRE, 9.0, true)
			var mid: String = "VS" if flow.local_ready or flow.phase != QuickMatchFlow.Phase.CONFIRM else str(flow.confirm_left())
			var ms: Vector2 = f.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 44)
			_spinner.draw_string(f, c + Vector2(-ms.x * 0.5, 15.0), mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, MenuTheme.PARCHMENT)


func _refresh_quick() -> void:
	var rated: Dictionary = service.my_rating() if service != null else {}
	var my_r: int = int(rated.get("rating", Rating.START_RATING))
	var searching: bool = flow.phase == QuickMatchFlow.Phase.SEARCHING
	var matched: bool = flow.phase == QuickMatchFlow.Phase.FOUND or flow.phase == QuickMatchFlow.Phase.CONFIRM \
		or flow.phase == QuickMatchFlow.Phase.STARTED
	_spinner.visible = flow.phase != QuickMatchFlow.Phase.IDLE
	_wait_line.visible = searching
	_range_line.visible = searching
	_confirm_box.visible = matched
	match flow.phase:
		QuickMatchFlow.Phase.SEARCHING:
			_headline.text = "Finding an opponent"
			var est: float = flow.estimate_s(service.expected_wait_s() if service != null else -1.0)
			_wait_line.text = OnlineText.wait_line(flow.search_s, est)
			_range_line.text = OnlineText.range_line(my_r, flow.search_s)
			_card.text = "You: %s  %s\n%s" % [Rating.tier(my_r), Rating.rating_text(my_r, int(rated.get("games", 0))),
				record_line(rated)]
			_card.add_theme_color_override("font_color", MenuTheme.OCHRE)
		QuickMatchFlow.Phase.IDLE:
			var why: Dictionary = flow.failure
			_headline.text = str(why.get("title", "Search stopped"))
			_card.text = str(why.get("body", "Press Search again to look for an opponent."))
			_card.add_theme_color_override("font_color", MenuTheme.PARCHMENT)
		_:
			var o: Dictionary = _info.get("opponent", {})
			var o_r: int = int(o.get("rating", Rating.START_RATING))
			_headline.text = "Opponent found!" if flow.phase == QuickMatchFlow.Phase.FOUND else (
				"Entering the arena" if flow.phase == QuickMatchFlow.Phase.STARTED else "Ready your arms")
			_card.text = "%s\n%s  %s" % [str(o.get("name", "?")), Rating.tier(o_r), Rating.rating_text(o_r, int(o.get("games", 0)))]
			_card.add_theme_color_override("font_color", MenuTheme.OCHRE)
			_arms.text = "Your arms: %s" % _describe(_panel.loadout())
			if flow.local_ready:
				_ready_btn.text = "Ready!" if not flow.auto_ready else "Locked in"
			else:
				_ready_btn.text = "READY  %d" % flow.confirm_left()
			_ready_btn.disabled = flow.local_ready
			if flow.remote_ready:
				_remote_line.text = "%s is ready" % _opponent_name
			elif not session.remote_joined:
				_remote_line.text = "Connecting to %s..." % _opponent_name
			else:
				_remote_line.text = "%s is choosing arms..." % _opponent_name
	_banner.visible = _banner.text != "" and searching
	_start.visible = flow.phase == QuickMatchFlow.Phase.IDLE
	_start.disabled = false
	_back.text = "Cancel" if searching else ("Leave" if matched else "Back")
	_name_edit.editable = searching or flow.phase == QuickMatchFlow.Phase.IDLE
	var lock: bool = flow.local_ready and matched
	if lock != _panel_locked:
		_panel_locked = lock
		_panel.set_locked(lock)  # ready: the arms are what the opponent already got
	_spinner.queue_redraw()
	_queue_link()


## "12 W - 7 L   W3" for the search card ("" before the first rated fight).
static func record_line(r: Dictionary) -> String:
	var g: int = int(r.get("games", 0))
	if g <= 0:
		return "First rated fight"
	var line: String = "%d W - %d L" % [int(r.get("wins", 0)), int(r.get("losses", 0))]
	var st: String = ServiceBoard.streak_text(int(r.get("streak", 0)))
	return line if st == "" else "%s   %s" % [line, st]


func _on_back() -> void:
	if _quick and service != null:
		service.cancel()
		flow.cancel()
	back.emit()


func _on_start_pressed() -> void:
	if _quick:
		_banner.text = ""
		_begin_search()
	else:
		start_pressed.emit()


# --- after the fight: rematch and rating -----------------------------------------------------------------------

## This player pressed Rematch on the result panel.
func ask_rematch() -> void:
	if session == null or not session.remote_joined:
		rematch.on_gone()
	elif rematch.ask():
		session.send_note({"t": RematchHandshake.NOTE_ASK})
		if rematch.state == RematchHandshake.State.AGREED:
			_on_rematch_agreed()
	result_changed.emit()


## Both want it: the next fight's id and key (rated if the backend can), and the host starts it.
func _on_rematch_agreed() -> void:
	var next: Dictionary = service.rematch_info(_info, rematch.count) if service != null else {}
	_rated_next = not next.is_empty()
	if _rated_next:
		_info = next
	if session != null and session.role == NetSession.ROLE_HOST:
		start_pressed.emit.call_deferred()  # after the result panel has drawn the agreement


## MenuFlow: the session closed while the result panel is up.
func on_session_closed(_reason: String) -> void:
	rematch.on_gone()
	result_changed.emit()


## MenuFlow: the service's verdict on the last fight arrived.
func on_summary(summary: Dictionary) -> void:
	last_summary = summary.duplicate()
	if service != null:
		last_summary["streak"] = int(service.my_rating().get("streak", 0))
	result_changed.emit()


## The lines of the online result panel under the heading.
func result_body() -> String:
	var lines: PackedStringArray = []
	if not _rated_now:
		lines.append(OnlineText.unrated_line("friendly"))
	elif last_summary.is_empty() and has_info():
		lines.append("Waiting for the result...")
	var rt: String = rematch.text(_opponent_name)
	if rt != "":
		lines.append(rt)
	return "\n".join(lines)


## The online result panel's buttons: [id, label]; MenuFlow handles "net_rematch", "online", "title".
func result_entries() -> Array:
	var out: Array = []
	if session != null and session.is_open() and session.remote_joined and rematch.state != RematchHandshake.State.GONE \
			and rematch.state != RematchHandshake.State.DECLINED and rematch.state != RematchHandshake.State.AGREED:
		out.append(["net_rematch", rematch.button_text(_opponent_name)])
	out.append(["online", "Find another opponent"])
	out.append(["title", "Leave"])
	return out


## The rating change for the result panel (null when there is no verdict for a rated fight yet). It counts up the
## first time it is shown for a match and stands still when the panel is redrawn.
func make_result_view() -> RatingChangeView:
	if last_summary.is_empty() or not _rated_now:
		return null
	var v := RatingChangeView.new()
	var mid: String = str(last_summary.get("match_id", ""))
	v.play(last_summary, _summary_played != mid)
	_summary_played = mid
	return v


func has_info() -> bool:
	return not _info.is_empty()


## The name the service gave the current opponent ("" before a match).
func opponent_name() -> String:
	return _opponent_name


## 0 when this side hosts (simulates side 0), 1 for the client.
func my_side() -> int:
	return 0 if str(_info.get("role", "")) == OnlineService.ROLE_HOST else 1


# --- reporting the result ----------------------------------------------------------------------------------------

func is_quick() -> bool:
	return _quick and not _info.is_empty()


## MenuFlow calls this when the match is built: from now on leaving a rated fight counts as a loss.
func match_started() -> void:
	_rated_now = _rated_next
	_match_open = _rated_now
	last_summary = {}
	rematch.fight_started()
	if flow.phase != QuickMatchFlow.Phase.STARTED and flow.phase != QuickMatchFlow.Phase.IDLE:
		flow.start()  # the client: the host's START arrived


func has_open_match() -> bool:
	return _quick and _match_open


## The fight ended: `winner_side` 0 = host, 1 = client, -1 = draw.
func report_finished(winner_side: int, ticks: int, reason: String) -> void:
	_report(Rating.KIND_RESULT, _side_id(winner_side), reason, ticks)


## The player id of match side `side` (0 = host, 1 = client), "" for -1.
func _side_id(side: int) -> String:
	if side < 0:
		return ""
	var me_side: int = 0 if str(_info.get("role", "")) == OnlineService.ROLE_HOST else 1
	return str(service.profile.get("id", "")) if side == me_side else str((_info["opponent"] as Dictionary).get("id", ""))


## The match ended without a result: Rating.KIND_LEFT (this player left) or KIND_DROPPED (the connection died).
## A dropped report names who was ahead on points when it died (`leader_side`, MatchJudge.leader) as its winner.
func report_abandoned(kind: String, ticks: int = 0, leader_side: int = -1) -> void:
	_report(kind, _side_id(leader_side) if kind == Rating.KIND_DROPPED else "", kind, ticks)


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
			return OnlineText.unrated_line(str(s.get("why", "")))


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
	_queue_link()


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
	if _quick and flow.phase == QuickMatchFlow.Phase.SEARCHING and service != null:
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


## Landscape: connect column and loadout side by side. Portrait: stacked, with thumb-sized main buttons.
func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_portrait = portrait
	_body.vertical = portrait
	_title.set_compact(portrait)
	var h: float = TOUCH_H_PORTRAIT if portrait else TOUCH_H_WIDE
	for b: Button in [_back, _start, _ready_btn]:
		b.custom_minimum_size.y = h
	_back.custom_minimum_size.x = 380.0 if portrait else 300.0
	_start.custom_minimum_size.x = 440.0 if portrait else 420.0
	_ready_btn.custom_minimum_size.x = 560.0 if portrait else 420.0
	_spinner.custom_minimum_size.y = 190.0 if portrait else 170.0
	_queue_link()


## Pad and keyboard routes by hand (the columns scroll, which Godot's own search sees through): the connection column
## wraps through Back, your arms through FIGHT; portrait runs them as one column. Re-linked as rows come and go.
func _link_focus() -> void:
	_link_queued = false
	var left: Array[Control] = MenuNav.focusables(_left)
	var arms: Array[Control] = MenuNav.focusables(_panel)
	MenuNav.link_screen([left, arms], _back, _start, _body.vertical)


func _queue_link() -> void:
	if not _link_queued:
		_link_queued = true
		_link_focus.call_deferred()
