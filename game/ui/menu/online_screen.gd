class_name OnlineScreen
extends Control
## Online 1v1 lobby: your name, host (listen on a port, shows this machine's LAN addresses) or join by address
## (ip or ip:port), then your loadout picked as usual while the other player's shows beside it. The host starts the
## fight once someone has joined. Talks to the NetSession MenuFlow owns; emits start_pressed (host) and back.

signal back
signal start_pressed

var state: MenuState
var session: NetSession = null
var player_name: String = "Gladiator"

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
	_back.pressed.connect(func() -> void: back.emit())
	foot.add_child(_back)
	_start = MenuTheme.button("FIGHT!", 420.0)
	_start.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.RED, MenuTheme.OCHRE, 4))
	_start.pressed.connect(func() -> void: start_pressed.emit())
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
	if session != p_session:
		session = p_session
		session.status_changed.connect(show_status)
		session.lobby_changed.connect(refresh)
	_panel.set_loadout(state.loadouts[0])
	_name_edit.text = player_name
	_push_local()
	refresh()
	_relayout()
	(_host_btn if not session.is_open() else _panel.first_focus()).grab_focus()


func show_status(text: String) -> void:
	_status_text = text
	refresh()


func refresh() -> void:
	if session == null:
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
		session.set_local(player_name, _panel.loadout())


func _on_loadout(l: Dictionary) -> void:
	state.set_loadout(0, l)
	_push_local()


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
		back.emit()
		get_viewport().set_input_as_handled()


## Landscape: connect column and loadout side by side. Portrait: stacked.
func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_body.vertical = portrait
	_title.add_theme_font_size_override("font_size", 40 if portrait else 52)
