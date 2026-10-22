class_name TitleScreen
extends Control
## SANDBLOOD title and main menu over the live arena backdrop (TitleBackdrop). Quick Match (online, the main mode) is
## first, larger and focused; "Online 1v1 (direct IP)" stays further down as the advanced entry.
## Landscape: the carved wordmark and a list of entries down the left side over a dark scrim, the gladiators in view
## on the right. Portrait, or any screen where a list of finger-sized entries will not fit: the mark on top and the
## entries as stone tiles at the bottom, Quick Match across the full width and the rest two to a row
## (MenuMetrics.title_grid). Focus wraps round the menu in every direction.

signal chosen(id: String)  ## "quick", "practice", "fight", "local_2p", "leaderboard", "online", "bots", "options", "quit"

const EDGE: float = 18.0  ## Clear space kept at the top and bottom.
const HINT_MIN_PX: float = 15.0  ## Smallest hint text on screen.
const HINT_MIN_UNITS: float = 24.0
const HINT_MAX_UNITS: float = 64.0
const LOGO_MAX: float = 172.0
const LOGO_MIN: float = 70.0
const LIST_H: float = 62.0  ## desktop list entry height
const LIST_MAX_H: float = 74.0
const TOUCH_MAX_H: float = 150.0
const GAP: float = 8.0
const TILE_GAP: float = 14.0
const RULE_MIN_PX: float = 12.0  ## Smallest meander cell on screen.

var _logo: TitleLogo
var _rule: Control
var _sub: Label
var _sub_en: Label
var _items: Array[TitleMenuItem] = []
var _hint: Label
var _hint_font: int = 0
var _px: float = 1.0  ## on-screen pixels per layout unit
var _touch: bool = false
var _portrait: bool = false
var _grid: Dictionary = {}
var _rule_cell: float = 14.0


func _init() -> void:
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_logo = TitleLogo.new()
	add_child(_logo)
	_rule = Control.new()
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.draw.connect(func() -> void: MenuTheme.draw_meander(_rule, 0.0, 4.0, _rule.size.x, _rule_cell, maxf(3.0, _rule_cell * 0.22)))
	add_child(_rule)
	_sub = MenuTheme.label("MORS AVT VICTORIA", 40, MenuTheme.OCHRE)
	_outline(_sub, 6)
	add_child(_sub)
	_sub_en = MenuTheme.label("Death or victory", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT.darkened(0.12))
	_outline(_sub_en, 5)
	add_child(_sub_en)
	var first_time: bool = PracticeSave.shared().should_offer()
	var entries: Array = [["quick", "Quick Match", "Ranked, online"], ["practice", "Training", "Start here" if first_time else ""],
			["fight", "Fight vs CPU", ""], ["local_2p", "Local 2 players", ""], ["leaderboard", "Leaderboard", ""],
			["shop", "Shop", ""], ["online", "Online 1v1", "Direct IP"], ["bots", "Watch bots", ""], ["options", "Options", ""]]
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		entries.append(["quit", "Quit", ""])
	for e: Array in entries:
		var b := TitleMenuItem.new(str(e[1]).to_upper(), str(e[2]))
		b.name = "Item_%s" % str(e[0])
		b.primary = _items.is_empty()
		b.pressed.connect(func() -> void: chosen.emit(str(e[0])))
		add_child(b)
		_items.append(b)
	_hint = MenuTheme.label("", int(HINT_MIN_UNITS), MenuTheme.PARCHMENT)
	_hint.name = "Hint"
	_outline(_hint, 4)
	_hint.text = "\n".join(hint_lines(not Input.get_connected_joypads().is_empty(), DisplayServer.is_touchscreen_available() or Flags.args.has("touch")))
	add_child(_hint)
	resized.connect(_relayout)


## Dark outline so text stays readable over the bright arena backdrop.
static func _outline(l: Label, px: int) -> void:
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.03, 0.9))
	l.add_theme_constant_override("outline_size", px)


## The hint under the menu for the device in use: touch (reusing the fight hint), gamepad, or keyboard.
static func hint_lines(has_pad: bool, has_touch: bool) -> Array:
	if has_touch and not has_pad:
		return ["Tap a button to choose"] + ControlsText.compact_lines("player_vs_cpu", false, true)
	if has_pad:
		return ["Stick / D-pad: move    A: select    B: back"]
	return ["Arrows / stick: move    Enter / A: select    Esc / B: back"]


## Hint font in layout units: about HINT_MIN_PX on screen, never below the desktop size.
static func hint_font_units(px_per_unit: float) -> int:
	return int(clampf(ceilf(HINT_MIN_PX / maxf(px_per_unit, 0.01)), HINT_MIN_UNITS, HINT_MAX_UNITS))


## Where the gladiators should sit across the screen (TitleBackdrop.frame_x) for this layout.
func backdrop_frame_x() -> float:
	return 0.0 if (_portrait or _grid.get("columns", 1) == 2) else 0.36


func items() -> Array[TitleMenuItem]:
	return _items


## The menu grid in use ({"columns", "rows", "item_h"}, see MenuMetrics.title_grid).
func grid() -> Dictionary:
	return _grid


## Lays the screen out as if shown at `px_per_unit` on-screen pixels per unit, on a touch screen or not (tests).
func layout_for(px_per_unit: float, touch: bool) -> void:
	_px = px_per_unit
	_touch = touch
	_relayout()


func focus_first() -> void:
	_items[0].grab_focus()
	for b: TitleMenuItem in _items:
		b.snap()


## The opening flourish: the mark drops in, the entries slide in from the left one after another.
func play_intro() -> void:
	MenuFx.reveal(_logo, Vector2(0.0, -22.0))
	MenuFx.reveal(_sub, Vector2(0.0, -12.0))
	MenuFx.reveal(_sub_en, Vector2(0.0, -12.0))
	MenuFx.reveal_items(_items, Vector2(-34.0 if not _portrait else 0.0, 0.0 if not _portrait else 26.0))


func _process(_delta: float) -> void:
	if visible:
		_fit_scale()  # the layer's scale is set after this screen's first layout


func _fit_scale() -> void:
	if not is_inside_tree():
		return
	var px: float = maxf(get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x, 0.01)
	var touch: bool = TouchControls.active() or DisplayServer.is_touchscreen_available() or Flags.args.has("touch")
	if not is_equal_approx(px, _px) or touch != _touch:
		_px = px
		_touch = touch
		_relayout()


func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_portrait = size.y > size.x * 1.05
	var hint_font: int = hint_font_units(_px)
	if hint_font != _hint_font:
		_hint_font = hint_font
		_hint.add_theme_font_size_override("font_size", hint_font)
	_rule_cell = maxf(14.0, RULE_MIN_PX / _px)
	var min_h: float = LIST_H
	var max_h: float = LIST_MAX_H
	if _touch or _portrait:
		min_h = maxf(LIST_H, MenuMetrics.touch_units(DisplayServer.screen_get_dpi() if _touch else 0.0, _px))
		max_h = maxf(min_h * 1.25, minf(TOUCH_MAX_H, min_h * 1.6))
	if _portrait:
		_layout_portrait(min_h, max_h)
	else:
		_layout_landscape(min_h, max_h)
	_link_focus()
	_rule.queue_redraw()
	queue_redraw()


func _hint_h() -> float:
	return _hint.get_combined_minimum_size().y


## Mark, rule and motto stacked at `x`, `y` within `w` (centred when `centre`); returns the y under them.
func _place_head(x: float, y: float, w: float, logo_px: float, centre: bool) -> float:
	_logo.px = logo_px
	var lw: float = _logo.custom_minimum_size.x
	_logo.size = _logo.custom_minimum_size
	_logo.position = Vector2(x + ((w - lw) * 0.5 if centre else 0.0), y)
	var ly: float = y + _logo.size.y - logo_px * 0.1
	var rw: float = minf(lw, w)
	_rule.size = Vector2(rw, _rule_cell + 14.0)
	_rule.position = Vector2(_logo.position.x + (lw - rw) * 0.5 if centre else _logo.position.x, ly)
	var sub_px: int = int(clampf(logo_px * 0.26, 28.0, 46.0))
	_sub.add_theme_font_size_override("font_size", sub_px)
	_sub_en.add_theme_font_size_override("font_size", maxi(int(HINT_MIN_UNITS), int(float(sub_px) * 0.72)))
	var sy: float = _rule.position.y + _rule.size.y + 2.0
	for l: Label in [_sub, _sub_en]:
		l.size = l.get_combined_minimum_size()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centre else HORIZONTAL_ALIGNMENT_LEFT
		if centre:
			l.size.x = w
			l.position = Vector2(x, sy)
		else:
			l.position = Vector2(_logo.position.x + 4.0, sy)
		sy += l.size.y - 4.0
	return sy + 4.0


func _head_h(logo_px: float) -> float:
	var sub_px: float = clampf(logo_px * 0.26, 28.0, 46.0)
	return logo_px * (0.86 + TitleLogo.DEPTH_EM + 0.42) - logo_px * 0.1 + _rule_cell + 16.0 + sub_px * 1.2 + sub_px * 0.9 + 4.0


## Left column: mark, then the entries (a list, or tiles two to a row when a list of `min_h` entries won't fit).
func _layout_landscape(min_h: float, max_h: float) -> void:
	var margin: float = clampf(size.x * 0.055, 40.0, 120.0)
	var col_w: float = clampf(size.x * 0.4, 560.0, 820.0)
	var logo_px: float = TitleLogo.fit_px(col_w, LOGO_MAX)
	var gap: float = GAP if not _touch else TILE_GAP
	var hint_h: float = _hint_h()
	var avail: float = 0.0
	for _pass: int in 16:
		avail = size.y - EDGE * 2.0 - _head_h(logo_px) - 18.0 - hint_h - 8.0
		_grid = MenuMetrics.title_grid(_items.size(), avail, min_h, max_h, gap)
		var used: float = float(_grid["rows"]) * float(_grid["item_h"]) + gap * float(int(_grid["rows"]) - 1)
		if used <= avail + 0.5 or logo_px <= LOGO_MIN:
			break
		logo_px = maxf(LOGO_MIN, logo_px * 0.9)
	var two: bool = int(_grid["columns"]) == 2
	if two:
		col_w = clampf(size.x * 0.5, col_w, 1000.0)
	var y: float = _place_head(margin, EDGE, col_w, logo_px, false) + 18.0
	_place_items(margin - (0.0 if two or _touch else 30.0), y, col_w, gap, two or _touch)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.size = Vector2(col_w, hint_h)
	_hint.position = Vector2(margin, size.y - EDGE - hint_h)


## Portrait: the mark across the top, the gladiators in the middle, tiles at the bottom.
func _layout_portrait(min_h: float, max_h: float) -> void:
	var margin: float = 40.0
	var w: float = size.x - margin * 2.0
	var logo_px: float = TitleLogo.fit_px(w, LOGO_MAX * 1.1)
	var hint_h: float = _hint_h()
	var gap: float = TILE_GAP
	var head_y: float = EDGE + size.y * 0.04
	var avail: float = size.y - head_y - _head_h(logo_px) - EDGE * 2.0 - hint_h - 60.0
	_grid = MenuMetrics.title_grid(_items.size(), avail, min_h, max_h, gap)
	if int(_grid["columns"]) == 1 and float(_grid["item_h"]) * float(_items.size()) > avail * 0.6:
		# A column of every entry would bury the gladiators: two to a row leaves the middle of the screen open.
		var rows: int = 1 + ceili(float(_items.size() - 1) / 2.0)
		_grid = {"columns": 2, "rows": rows, "item_h": clampf((avail * 0.62 - gap * float(rows - 1)) / float(rows), min_h, max_h)}
	_place_head(margin, head_y, w, logo_px, true)
	var used: float = float(_grid["rows"]) * float(_grid["item_h"]) + gap * float(int(_grid["rows"]) - 1)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(w, hint_h)
	_hint.position = Vector2(margin, size.y - EDGE - hint_h)
	_place_items(margin, _hint.position.y - 14.0 - used, w, gap, true)


## Lays the entries out from (x, y) in `w` per _grid; tiles frame each entry.
func _place_items(x: float, y: float, w: float, gap: float, tiles: bool) -> void:
	var h: float = float(_grid["item_h"])
	var two: bool = int(_grid["columns"]) == 2
	var fs: int = int(clampf(h * 0.46, 30.0, 46.0))
	for i: int in _items.size():
		var b: TitleMenuItem = _items[i]
		b.tile = tiles
		b.font_px = int(float(fs) * 1.18) if i == 0 else fs
		var r: Rect2
		if i == 0 or not two:
			var row: int = i
			r = Rect2(x, y + float(row) * (h + gap), w, h)
		else:
			var k: int = i - 1
			var row2: int = 1 + k / 2
			var cw: float = (w - gap) * 0.5
			r = Rect2(x + float(k % 2) * (cw + gap), y + float(row2) * (h + gap), cw, h)
			if k % 2 == 0 and i == _items.size() - 1:
				r.size.x = w  # an odd one out takes the whole last row
		b.position = r.position
		b.size = r.size
		b.custom_minimum_size = Vector2.ZERO
		b.queue_redraw()


## Explicit neighbours, so the pad and keys go where the eye expects and wrap round the ends.
func _link_focus() -> void:
	var n: int = _items.size()
	var two: bool = int(_grid.get("columns", 1)) == 2
	for i: int in n:
		var b: TitleMenuItem = _items[i]
		var up: int
		var down: int
		var left: int = i
		var right: int = i
		if not two:
			up = posmod(i - 1, n)
			down = posmod(i + 1, n)
		elif i == 0:
			down = 1
			up = n - 1 if (n - 1) % 2 == 1 else n - 2  # the last row's left (or only) entry
		else:
			var k: int = i - 1
			var col: int = k % 2
			up = 0 if k < 2 else i - 2
			if i + 2 < n:
				down = i + 2
			elif col == 1 and i + 1 < n:
				down = i + 1  # onto the odd one out under this row
			else:
				down = 0
			if col == 0 and i + 1 < n:
				right = i + 1
			if col == 1:
				left = i - 1
		b.focus_neighbor_top = b.get_path_to(_items[up])
		b.focus_neighbor_bottom = b.get_path_to(_items[down])
		b.focus_neighbor_left = b.get_path_to(_items[left])
		b.focus_neighbor_right = b.get_path_to(_items[right])
		b.focus_next = b.get_path_to(_items[posmod(i + 1, n)])
		b.focus_previous = b.get_path_to(_items[posmod(i - 1, n)])


## Scrims: a dark wash behind the menu so the text reads over the bright sand, leaving the gladiators lit.
func _draw() -> void:
	var dark: Color = Color(0.03, 0.016, 0.01, 0.82)
	var clear: Color = Color(0.03, 0.016, 0.01, 0.0)
	var mid: Color = Color(0.03, 0.016, 0.01, 0.5)
	if _portrait:
		var top_h: float = _sub_en.position.y + _sub_en.size.y + 60.0
		_band(0.0, top_h, Color(0.03, 0.016, 0.01, 0.62), clear)
		var menu_top: float = _items[0].position.y - 90.0 if not _items.is_empty() else size.y * 0.5
		_band(menu_top, size.y, clear, dark)
	else:
		var w: float = clampf(size.x * 0.62, 700.0, size.x)
		if int(_grid.get("columns", 1)) == 2:
			w = size.x * 0.78
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w * 0.55, 0.0), Vector2(w, 0.0), Vector2(w, size.y), Vector2(w * 0.55, size.y), Vector2(0.0, size.y)]),
				PackedColorArray([dark, mid, clear, clear, mid, dark]))
		_band(size.y * 0.7, size.y, clear, Color(0.03, 0.016, 0.01, 0.4))


func _band(y0: float, y1: float, c0: Color, c1: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(0.0, y0), Vector2(size.x, y0), Vector2(size.x, y1), Vector2(0.0, y1)]),
			PackedColorArray([c0, c0, c1, c1]))
