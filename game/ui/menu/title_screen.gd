class_name TitleScreen
extends Control
## SANDBLOOD title and main menu over the arena backdrop. Quick Match (online, the main mode) is first and focused;
## "Online 1v1 (direct IP)" stays further down as the advanced entry.

signal chosen(id: String)  ## "quick", "fight", "local_2p", "leaderboard", "online", "bots", "options", "quit"

const TITLE_MIN: float = 56.0
const EDGE: float = 14.0  ## Clear space kept at the top and bottom.
const RULE_MIN_PX: float = 12.0  ## Smallest meander cell on screen.
const SCRIM_TOP: float = 0.22  ## Backdrop darkening, a vertical gradient so there is no seam across the arena.
const SCRIM_BOTTOM: float = 0.4
const HINT_MIN_PX: float = 15.0  ## Smallest hint text on screen.
const HINT_MIN_UNITS: float = 24.0
const HINT_MAX_UNITS: float = 64.0

var _title: Label
var _sub: Label
var _rule: Control
var _col: VBoxContainer
var _first: Button
var _buttons: Array[Button] = []
var _gap: Control
var _rule_cell: float = 14.0
var _hint: Label
var _hint_font: int = 0


func _init() -> void:
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.add_theme_constant_override("separation", 8)
	add_child(_col)
	_title = MenuTheme.label("SANDBLOOD", 190, MenuTheme.PARCHMENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.03, 0.95))
	_title.add_theme_constant_override("outline_size", 22)
	_col.add_child(_title)
	_rule = Control.new()
	_rule.custom_minimum_size = Vector2(0.0, 40.0)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.draw.connect(func() -> void: MenuTheme.draw_meander(_rule, _rule.size.x * 0.1, 6.0, _rule.size.x * 0.8, _rule_cell, maxf(3.0, _rule_cell * 0.22)))
	_col.add_child(_rule)
	_sub = MenuTheme.label("MORS AVT VICTORIA", 56, MenuTheme.OCHRE)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_sub, 6)
	_col.add_child(_sub)
	var eng := MenuTheme.label("Death or victory", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT.darkened(0.2))
	eng.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(eng)
	_gap = Control.new()
	_gap.custom_minimum_size = Vector2(0.0, 30.0)
	_col.add_child(_gap)
	var entries: Array = [["quick", "Quick Match"], ["fight", "Fight  (vs CPU)"], ["local_2p", "Local 2 players"],
			["leaderboard", "Leaderboard"], ["shop", "Shop"], ["online", "Online 1v1 (direct IP)"], ["bots", "Watch bots"], ["options", "Options"]]
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		entries.append(["quit", "Quit"])
	for e: Array in entries:
		var b: Button = MenuTheme.button(str(e[1]), 640.0)
		b.custom_minimum_size.y = 58.0
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: chosen.emit(str(e[0])))
		_col.add_child(b)
		_buttons.append(b)
		if _first == null:
			_first = b
	_hint = MenuTheme.label("", int(HINT_MIN_UNITS), MenuTheme.PARCHMENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.name = "Hint"
	_hint.text = "\n".join(hint_lines(not Input.get_connected_joypads().is_empty(), DisplayServer.is_touchscreen_available() or Flags.args.has("touch")))
	_col.add_child(_hint)
	resized.connect(_relayout)
	_relayout()


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


func focus_first() -> void:
	_first.grab_focus()


## Fits the whole column to the viewport: the wordmark and the buttons shrink together until it all fits (short
## landscape windows), and the meander rule's cell grows so it keeps at least RULE_MIN_PX on screen (phones).
func _relayout() -> void:
	_col.position = Vector2.ZERO
	_col.size = size
	var title_px: float = clampf(minf(size.x / 7.2, size.y / 6.5), TITLE_MIN, 190.0)
	var btn_h: float = 58.0
	var gap_h: float = 30.0
	var sep: int = 8
	if size.y > size.x * 1.3:  # portrait: roomy buttons so the column fills the screen
		btn_h = 92.0
		gap_h = 56.0
		sep = 14
	_col.add_theme_constant_override("separation", sep)
	var avail: float = size.y - 2.0 * EDGE
	for _pass: int in 24:
		_title.add_theme_font_size_override("font_size", int(title_px))
		for b: Button in _buttons:
			b.custom_minimum_size.y = btn_h
		_gap.custom_minimum_size.y = gap_h
		_col.reset_size()
		if _col.get_combined_minimum_size().y <= avail:
			break
		title_px = maxf(title_px * 0.92, TITLE_MIN)
		btn_h = maxf(btn_h - 3.0, 38.0)
		gap_h = maxf(gap_h - 4.0, 4.0)
	_col.position = Vector2.ZERO
	_col.size = size
	_title.add_theme_constant_override("outline_size", int(clampf(title_px / 8.5, 6.0, 22.0)))
	_fit_rule()


func _process(_delta: float) -> void:
	if visible:
		_fit_rule()  # the layer's scale is set after this screen's first layout


func _fit_rule() -> void:
	if not is_inside_tree():
		return
	var px: float = maxf(get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x, 0.01)
	var hint_font: int = hint_font_units(px)
	if hint_font != _hint_font:
		_hint_font = hint_font
		_hint.add_theme_font_size_override("font_size", hint_font)
		_relayout()
	var cell: float = maxf(14.0, RULE_MIN_PX / px)
	if not is_equal_approx(cell, _rule_cell):
		_rule_cell = cell
		_rule.custom_minimum_size.y = cell + 26.0
		_rule.queue_redraw()


func _draw() -> void:
	var top: Color = Color(0.02, 0.012, 0.008, SCRIM_TOP)
	var bottom: Color = Color(0.02, 0.012, 0.008, SCRIM_BOTTOM)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]), PackedColorArray([top, top, bottom, bottom]))
