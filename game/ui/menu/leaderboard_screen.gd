class_name LeaderboardScreen
extends Control
## The ranking: the top 100 in pages of 20 (Prev / Next, "My page"), your own row highlighted on its page and pinned
## under the list wherever you rank, the Roman tier names in their colours, win - loss and the current streak. While
## the service answers it shows a spinner; when it cannot (offline, not signed in, no answer) it says so in plain
## words with a Retry button. Asks the OnlineService for the data and draws whatever comes back, so it looks the same
## for every backend. Emits back.

signal back

const PAGE_ROWS: int = 20
const MAX_RANK: int = 100  ## the pages go this deep; anyone below sees their own pinned row
const AROUND_ROWS: int = 3
const LOAD_TIMEOUT_S: float = 12.0  ## no answer this long: show the offline state
const SPIN_RATE: float = 5.0
const HEADERS: PackedStringArray = ["#", "Gladiator", "Rank", "Rating", "W - L", "Streak"]
## [width, alignment] per column; width 0 = takes the rest (the name), -1 = as wide as the longest tier name.
const COLS_WIDE: Array = [[90.0, 0], [0.0, 0], [-1.0, 0], [150.0, 2], [170.0, 2], [140.0, 2]]
const COLS_PORTRAIT: Array = [[58.0, 0], [0.0, 0], [-1.0, 0], [92.0, 2], [106.0, 2], [108.0, 2]]  ## ~1000 units across (MenuFlow)
const BODY_WIDE: int = 30
const BODY_PORTRAIT: int = 25
const SEP_WIDE: int = 18
const SEP_PORTRAIT: int = 10
const NAME_MIN: float = 150.0  ## the name column never gets less than this; the tier column gives way first
const TOUCH_H_PORTRAIT: float = 124.0
const TOUCH_H_WIDE: float = 80.0
## Tier colours, lowest to highest (Rating.tier_names order): bronze to purple-gold.
const TIER_COLOURS: Array[Color] = [Color(0.66, 0.55, 0.42), Color(0.86, 0.78, 0.62), Color(0.62, 0.78, 0.6),
	Color(0.55, 0.72, 0.92), Color(0.93, 0.74, 0.3), Color(0.9, 0.55, 0.95)]

enum View { LOADING, BOARD, OFFLINE }

var service: OnlineService = null
var offset: int = 0  ## the first rank of the page asked for, minus one
var view: View = View.LOADING

var _title: ScreenHeader
var _rows: VBoxContainer
var _inner: VBoxContainer
var _header: HBoxContainer
var _portrait: bool = false
var _data: Dictionary = {}  ## the last data shown, redrawn when the orientation flips
var _pin: PanelContainer
var _pin_row: HBoxContainer
var _me_line: Label
var _source: Label
var _back: Button
var _prev: Button
var _next: Button
var _mine: Button
var _retry: Button
var _page_label: Label
var _spinner: Control
var _state_box: VBoxContainer
var _state_title: Label
var _state_body: Label
var _wait_s: float = 0.0
var _spin: float = 0.0


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
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	_build_state_box(inner)

	_pin = PanelContainer.new()
	_pin.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.3, 0.1, 0.07, 0.92), MenuTheme.OCHRE, 3, 12.0))
	root.add_child(_pin)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	_pin.add_child(pv)
	_pin_row = HBoxContainer.new()
	pv.add_child(_pin_row)
	_me_line = MenuTheme.label("", 24, MenuTheme.PARCHMENT)
	_me_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_me_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_me_line)

	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 12)
	root.add_child(pager)
	_prev = MenuTheme.button("< Prev", 200.0)
	_prev.pressed.connect(func() -> void: show_page(offset - PAGE_ROWS))
	pager.add_child(_prev)
	_page_label = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(150.0, 0.0)
	pager.add_child(_page_label)
	_next = MenuTheme.button("Next >", 200.0)
	_next.pressed.connect(func() -> void: show_page(offset + PAGE_ROWS))
	pager.add_child(_next)
	_mine = MenuTheme.button("My page", 220.0)
	_mine.pressed.connect(show_my_page)
	pager.add_child(_mine)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 30)
	root.add_child(foot)
	_back = MenuTheme.button("Back", 300.0)
	_back.pressed.connect(func() -> void: back.emit())
	foot.add_child(_back)
	_source = MenuTheme.label("", 22, MenuTheme.DIM_TEXT)
	_source.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_source)
	resized.connect(_relayout)
	set_process(false)


func _build_state_box(parent: Control) -> void:
	_state_box = VBoxContainer.new()
	_state_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_state_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_state_box.add_theme_constant_override("separation", 12)
	parent.add_child(_state_box)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(0.0, 150.0)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_draw_spinner)
	_state_box.add_child(_spinner)
	_state_title = MenuTheme.label("", MenuTheme.FONT_HEAD, MenuTheme.PARCHMENT)
	_state_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_box.add_child(_state_title)
	_state_body = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.DIM_TEXT)
	_state_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_box.add_child(_state_body)
	_retry = MenuTheme.button("Retry", 320.0)
	_retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_retry.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.RED, MenuTheme.OCHRE, 4))
	_retry.pressed.connect(func() -> void: show_page(offset))
	_state_box.add_child(_retry)


func open(p_service: OnlineService) -> void:
	if service != p_service:
		service = p_service
		service.leaderboard_ready.connect(show_data)
		service.login_failed.connect(_on_login_failed)
	_data = {}
	_pin.visible = false
	_source.text = service.backend_name()
	_relayout()
	show_page(0)
	_back.grab_focus()


## Ask for the page that starts after rank `p_offset` (clamped to the top MAX_RANK) and show the spinner meanwhile.
func show_page(p_offset: int) -> void:
	offset = clampi(p_offset, 0, MAX_RANK - PAGE_ROWS)
	_set_view(View.LOADING)
	if service != null:
		service.request_leaderboard(PAGE_ROWS, AROUND_ROWS, offset)


## Jump to the page with your own row (when you are in the top MAX_RANK).
func show_my_page() -> void:
	var page: int = my_page_offset(_data.get("me", {}))
	if page >= 0:
		show_page(page)


## The offset of the page holding `me` (a row with a rank), or -1 when unranked or below the top MAX_RANK.
static func my_page_offset(me: Dictionary) -> int:
	var rank: int = int(me.get("rank", 0))
	if rank <= 0 or rank > MAX_RANK:
		return -1
	return ((rank - 1) / PAGE_ROWS) * PAGE_ROWS


## "Ranks 21-40 of 57" for the pager.
static func page_text(p_offset: int, shown: int, total: int) -> String:
	if total <= 0 or shown <= 0:
		return ""
	return "%d-%d of %d" % [p_offset + 1, p_offset + shown, total]


func _on_login_failed(reason: String) -> void:
	if visible and view == View.LOADING:
		_show_offline(OnlineText.plain("Could not sign in: %s" % reason))


func _process(delta: float) -> void:
	_spin += delta * SPIN_RATE
	_spinner.queue_redraw()
	if view == View.LOADING:
		_wait_s += delta
		if _wait_s >= LOAD_TIMEOUT_S:
			_show_offline(OnlineText.plain("unavailable"))


func _set_view(v: View) -> void:
	view = v
	_wait_s = 0.0
	set_process(v == View.LOADING)
	_state_box.visible = v != View.BOARD
	_spinner.visible = v == View.LOADING
	_retry.visible = v == View.OFFLINE
	_rows.get_parent().visible = v == View.BOARD
	if v == View.LOADING:
		_state_title.text = "Counting the wins..."
		_state_body.text = ""
	_refresh_pager()


func _show_offline(said: Dictionary) -> void:
	_set_view(View.OFFLINE)
	_state_title.text = str(said.get("title", "Can't reach the arena servers"))
	_state_body.text = str(said.get("body", ""))
	_pin.visible = false
	_retry.grab_focus()


## Draws {top, around, me, total, offset, source, error?}.
func show_data(data: Dictionary) -> void:
	if str(data.get("error", "")) != "":
		_data = data
		_show_offline(OnlineText.plain(str(data["error"])))
		_source.text = str(data.get("source", ""))
		return
	_data = data
	offset = int(data.get("offset", offset))
	_set_view(View.BOARD)
	_clear()
	var top: Array = data.get("top", [])
	var me: Dictionary = data.get("me", {})
	var my_id: String = str(me.get("id", ""))
	if top.is_empty():
		var empty := MenuTheme.label("No rated fights yet.\nWin a Quick Match to take a place here.", MenuTheme.FONT_BODY, MenuTheme.DIM_TEXT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(empty)
	for i: int in top.size():
		var r: Dictionary = top[i]
		_rows.add_child(_player_row(r, str(r.get("id", "")) == my_id, i % 2 == 1))
	_fill_pin(me, int(data.get("total", 0)))
	_source.text = str(data.get("source", ""))
	_refresh_pager()


func _fill_pin(me: Dictionary, total: int) -> void:
	for c: Node in _pin_row.get_children():
		_pin_row.remove_child(c)
		c.queue_free()
	_pin.visible = true
	if me.is_empty():
		_me_line.text = "You are not ranked yet: win or lose a Quick Match to get a place."
		return
	var line: HBoxContainer = _line(_cells(me), MenuTheme.PARCHMENT, true, me)
	for c2: Node in line.get_children():
		line.remove_child(c2)
		_pin_row.add_child(c2)
	line.free()
	_pin_row.add_theme_constant_override("separation", SEP_PORTRAIT if _portrait else SEP_WIDE)
	var parts: PackedStringArray = ["You: #%d of %d" % [int(me.get("rank", 0)), total]]
	var nxt: Dictionary = Rating.next_tier(int(me.get("rating", 0)))
	if not nxt.is_empty():
		parts.append("%d to %s" % [int(nxt["need"]), str(nxt["name"])])
	var st: String = OnlineText.streak_line(int(me.get("streak", 0)))
	if st != "":
		parts.append(st)
	_me_line.text = "   ".join(parts)


func _refresh_pager() -> void:
	var total: int = mini(int(_data.get("total", 0)), MAX_RANK)
	var shown: int = (_data.get("top", []) as Array).size() if view == View.BOARD else 0
	_page_label.text = page_text(offset, shown, int(_data.get("total", 0))) if view == View.BOARD else ""
	_prev.disabled = view != View.BOARD or offset <= 0
	_next.disabled = view != View.BOARD or offset + PAGE_ROWS >= total
	var mine: int = my_page_offset(_data.get("me", {}))
	_mine.disabled = view != View.BOARD or mine < 0 or mine == offset


func _clear() -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()


func _cells(r: Dictionary) -> Array:
	return ["%d" % int(r.get("rank", 0)), str(r.get("name", "")), str(r.get("tier", Rating.tier(int(r.get("rating", 0))))),
		Rating.rating_text(int(r.get("rating", 0)), int(r.get("games", 0))), "%d - %d" % [int(r.get("wins", 0)), int(r.get("losses", 0))],
		ServiceBoard.streak_text(int(r.get("streak", 0)))]


func _player_row(r: Dictionary, mine: bool, odd: bool) -> Control:
	var line: Control = _line(_cells(r), MenuTheme.OCHRE if mine else MenuTheme.PARCHMENT, true, r)
	var p := PanelContainer.new()
	if mine:
		p.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.3, 0.1, 0.07, 0.85), MenuTheme.OCHRE, 2, 6.0))
	else:
		p.add_theme_stylebox_override("panel", MenuTheme.box(Color(1.0, 0.9, 0.7, 0.05 if odd else 0.0), Color(0, 0, 0, 0), 0, 6.0))
	p.add_child(line)
	return p


## Colour of a tier name.
static func tier_colour(rating: int) -> Color:
	return TIER_COLOURS[clampi(Rating.tier_index(rating), 0, TIER_COLOURS.size() - 1)]


func _line(cells: Array, colour: Color, body: bool, r: Dictionary = {}) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", SEP_PORTRAIT if _portrait else SEP_WIDE)
	var size_px: int = (BODY_PORTRAIT if _portrait else BODY_WIDE) if body else MenuTheme.FONT_SMALL - (6 if _portrait else 0)
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
		if body and i == 2 and not r.is_empty():
			l.add_theme_color_override("font_color", tier_colour(int(r.get("rating", 0))))
		if body and i == 5:
			var st: int = int(r.get("streak", 0))
			l.add_theme_color_override("font_color", RatingChangeView.UP if st > 0 else (RatingChangeView.DOWN if st < 0 else colour))
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
	var names: PackedStringArray = Rating.tier_names()
	names.append(HEADERS[2])
	for n: String in names:
		w = maxf(w, f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	return w


func _draw_spinner() -> void:
	var c: Vector2 = _spinner.size * 0.5
	var r: float = minf(_spinner.size.y * 0.4, 56.0)
	_spinner.draw_arc(c, r, 0.0, TAU, 48, MenuTheme.BRONZE.darkened(0.55), 6.0, true)
	for i: int in 5:
		var a0: float = _spin - float(i) * 0.32
		_spinner.draw_arc(c, r, a0 - 0.3, a0, 8, MenuTheme.OCHRE.lerp(MenuTheme.RED, float(i) / 5.0), 8.0 - float(i), true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down") and not _next.disabled:
		show_page(offset + PAGE_ROWS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up") and not _prev.disabled:
		show_page(offset - PAGE_ROWS)
		get_viewport().set_input_as_handled()


func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_title.set_compact(portrait)
	var h: float = TOUCH_H_PORTRAIT if portrait else TOUCH_H_WIDE
	for b: Button in [_prev, _next, _mine, _back, _retry]:
		b.custom_minimum_size.y = h
	_prev.custom_minimum_size.x = 190.0 if portrait else 200.0
	_next.custom_minimum_size.x = 190.0 if portrait else 200.0
	_mine.custom_minimum_size.x = 210.0 if portrait else 220.0
	_back.custom_minimum_size.x = 420.0 if portrait else 300.0
	if portrait == _portrait:
		return
	_portrait = portrait
	_rebuild_header()
	if view == View.BOARD and not _data.is_empty():
		show_data(_data)


## Widths and sizes are set per line: rebuild the header (and the rows) for the current orientation.
func _rebuild_header() -> void:
	var fresh: HBoxContainer = _line(Array(HEADERS), MenuTheme.OCHRE, false)
	_inner.add_child(fresh)
	_inner.move_child(fresh, _header.get_index())
	_inner.remove_child(_header)
	_header.queue_free()
	_header = fresh
