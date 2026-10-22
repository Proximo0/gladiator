class_name LeaderboardScreen
extends Control
## The ranking: the best players, and the rows around you when you are not among them. Asks the OnlineService for
## the data and draws whatever comes back, so it looks the same for every backend. Emits back.

signal back

const TOP_ROWS: int = 12
const AROUND_ROWS: int = 3
const COLS: Array = [["#", 90.0, 0], ["Gladiator", 0.0, 0], ["Rank", 280.0, 0], ["Rating", 170.0, 2], ["W - L", 170.0, 2]]

var service: OnlineService = null

var _title: Label
var _rows: VBoxContainer
var _me_line: Label
var _source: Label
var _back: Button


func _init() -> void:
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.012, 0.66)
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
	_title = MenuTheme.label("ALBVM / Leaderboard", 52, MenuTheme.PARCHMENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	inner.add_child(_line(["#", "Gladiator", "Rank", "Rating", "W - L"], MenuTheme.OCHRE, false))
	var rule := ColorRect.new()
	rule.color = MenuTheme.BRONZE
	rule.custom_minimum_size = Vector2(0.0, 3.0)
	inner.add_child(rule)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)
	_me_line = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_me_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_me_line)
	_source = MenuTheme.label("", 22, MenuTheme.DIM_TEXT)
	_source.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_source)
	_back = MenuTheme.button("Back", 300.0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(func() -> void: back.emit())
	root.add_child(_back)
	resized.connect(_relayout)


func open(p_service: OnlineService) -> void:
	if service != p_service:
		service = p_service
		service.leaderboard_ready.connect(show_data)
	_clear()
	_rows.add_child(MenuTheme.label("Counting the wins...", MenuTheme.FONT_SMALL, MenuTheme.DIM_TEXT))
	_me_line.text = ""
	_source.text = service.backend_name()
	_back.grab_focus()
	_relayout()
	service.request_leaderboard(TOP_ROWS, AROUND_ROWS)


## Draws {top, around, me, total, source}.
func show_data(data: Dictionary) -> void:
	_clear()
	var top: Array = data.get("top", [])
	var around: Array = data.get("around", [])
	var me: Dictionary = data.get("me", {})
	var my_id: String = str(me.get("id", ""))
	if top.is_empty():
		var empty := MenuTheme.label("No rated fights yet.\nWin a Quick Match to take a place here.", MenuTheme.FONT_BODY, MenuTheme.DIM_TEXT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(empty)
	for r: Dictionary in top:
		_rows.add_child(_player_row(r, str(r.get("id", "")) == my_id))
	if not around.is_empty():
		var gap := MenuTheme.label("...", MenuTheme.FONT_SMALL, MenuTheme.DIM_TEXT)
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(gap)
		for r2: Dictionary in around:
			_rows.add_child(_player_row(r2, str(r2.get("id", "")) == my_id))
	if me.is_empty():
		_me_line.text = "You are not ranked yet: play a Quick Match."
	else:
		_me_line.text = "You: #%d of %d   %s   %s" % [int(me["rank"]), int(data.get("total", 0)), str(me["tier"]),
			Rating.rating_text(int(me["rating"]), int(me["games"]))]
	_source.text = str(data.get("source", ""))
	_relayout()


func _clear() -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()


func _player_row(r: Dictionary, mine: bool) -> Control:
	var cells: Array = ["%d" % int(r.get("rank", 0)), str(r.get("name", "")), str(r.get("tier", "")),
		Rating.rating_text(int(r.get("rating", 0)), int(r.get("games", 0))), "%d - %d" % [int(r.get("wins", 0)), int(r.get("losses", 0))]]
	var line: Control = _line(cells, MenuTheme.OCHRE if mine else MenuTheme.PARCHMENT, true)
	if not mine:
		return line
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.3, 0.1, 0.07, 0.8), MenuTheme.OCHRE, 2, 6.0))
	p.add_child(line)
	return p


func _line(cells: Array, colour: Color, body: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for i: int in COLS.size():
		var col: Array = COLS[i]
		var l := MenuTheme.label(str(cells[i]), 30 if body else MenuTheme.FONT_SMALL, colour)
		l.clip_text = true
		l.custom_minimum_size = Vector2(float(col[1]), 0.0)
		if float(col[1]) == 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if int(col[2]) == 2 else HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(l)
	return h


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back.emit()
		get_viewport().set_input_as_handled()


func _relayout() -> void:
	_title.add_theme_font_size_override("font_size", 40 if size.x < size.y * 1.05 else 52)
