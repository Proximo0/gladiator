class_name LeaderboardScreen
extends Control
## The ranking: the best players, and the rows around you when you are not among them. Asks the OnlineService for
## the data and draws whatever comes back, so it looks the same for every backend. Emits back.

signal back

const TOP_ROWS: int = 12
const AROUND_ROWS: int = 3
const HEADERS: PackedStringArray = ["#", "Gladiator", "Rank", "Rating", "W - L"]
## [width, alignment] per column; width 0 = takes the rest (the name), -1 = as wide as the longest tier name.
const COLS_WIDE: Array = [[90.0, 0], [0.0, 0], [-1.0, 0], [170.0, 2], [170.0, 2]]
const COLS_PORTRAIT: Array = [[52.0, 0], [0.0, 0], [-1.0, 0], [104.0, 2], [118.0, 2]]  ## ~1000 units across (MenuFlow)
const BODY_WIDE: int = 30
const BODY_PORTRAIT: int = 26
const SEP_WIDE: int = 18
const SEP_PORTRAIT: int = 12
const SCROLL_STEP: float = 64.0  ## units the table scrolls per up/down press
const NAME_MIN: float = 160.0  ## the name column never gets less than this; the tier column gives way first

var service: OnlineService = null

var _title: ScreenHeader
var _rows: VBoxContainer
var _inner: VBoxContainer
var _header: HBoxContainer
var _portrait: bool = false
var _data: Dictionary = {}  ## the last data shown, redrawn when the orientation flips
var _me_line: Label
var _source: Label
var _back: Button
var _scroll: ScrollContainer


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
	_title = ScreenHeader.new("ALBVM / Leaderboard")
	root.add_child(_title)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	_inner = inner
	_header = _line(Array(HEADERS), MenuTheme.OCHRE, false)
	inner.add_child(_header)
	var rule := ColorRect.new()
	rule.color = MenuTheme.BRONZE
	rule.custom_minimum_size = Vector2(0.0, 3.0)
	inner.add_child(rule)
	var scroll := ScrollContainer.new()
	_scroll = scroll
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
	_data = data
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
	h.add_theme_constant_override("separation", SEP_PORTRAIT if _portrait else SEP_WIDE)
	var size_px: int = (BODY_PORTRAIT if _portrait else BODY_WIDE) if body else MenuTheme.FONT_SMALL - (4 if _portrait else 0)
	var widths: Array = column_widths(_portrait, _tier_width(BODY_PORTRAIT if _portrait else BODY_WIDE))
	var cols: Array = COLS_PORTRAIT if _portrait else COLS_WIDE
	for i: int in cols.size():
		var l := MenuTheme.label(str(cells[i]), size_px, colour)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long name ends in "..." instead of running on
		l.custom_minimum_size = Vector2(float(widths[i]), 0.0)
		if float(widths[i]) == 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size = Vector2(NAME_MIN, 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if int(cols[i][1]) == 2 else HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(l)
	return h


## Fixed widths per column (0 = the name column, which takes the rest). The tier column is as wide as the longest
## tier name at the body size (`tier_px`), so "Primus Palus" never runs into the rating.
static func column_widths(portrait: bool, tier_px: float) -> Array:
	var out: Array = []
	for col: Array in (COLS_PORTRAIT if portrait else COLS_WIDE):
		out.append(ceilf(tier_px) + 4.0 if float(col[0]) < 0.0 else float(col[0]))
	return out


func _tier_width(size_px: int) -> float:
	var f: Font = MenuTheme.caps_font()
	var w: float = 0.0
	var names: PackedStringArray = [Rating.TOP_TIER, HEADERS[2]]
	for t: Array in Rating.TIERS:
		names.append(str(t[1]))
	for n: String in names:
		w = maxf(w, f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	return w


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back.emit()
		get_viewport().set_input_as_handled()
	elif _back.has_focus() and (event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true)):
		# Back is the only button: up and down scroll the table instead (pad and keys reach every row).
		_scroll.scroll_vertical += int(SCROLL_STEP) * (-1 if event.is_action_pressed("ui_up", true) else 1)
		get_viewport().set_input_as_handled()


func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_title.set_compact(portrait)
	if portrait == _portrait:
		return
	_portrait = portrait
	# Widths and sizes are set per line: rebuild the header and the rows for the new orientation.
	var fresh: HBoxContainer = _line(Array(HEADERS), MenuTheme.OCHRE, false)
	_inner.add_child(fresh)
	_inner.move_child(fresh, _header.get_index())
	_inner.remove_child(_header)
	_header.queue_free()
	_header = fresh
	if not _data.is_empty():
		show_data(_data)
