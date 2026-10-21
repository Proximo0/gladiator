class_name TitleScreen
extends Control
## SANDBLOOD title and main menu over the arena backdrop. Fight (vs CPU) is first and focused.

signal chosen(id: String)  ## "fight", "local_2p", "bots", "options", "quit"

var _title: Label
var _sub: Label
var _rule: Control
var _col: VBoxContainer
var _first: Button


func _init() -> void:
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.add_theme_constant_override("separation", 12)
	add_child(_col)
	_title = MenuTheme.label("SANDBLOOD", 190, MenuTheme.PARCHMENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.03, 0.95))
	_title.add_theme_constant_override("outline_size", 22)
	_col.add_child(_title)
	_rule = Control.new()
	_rule.custom_minimum_size = Vector2(0.0, 40.0)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.draw.connect(func() -> void: MenuTheme.draw_meander(_rule, _rule.size.x * 0.1, 6.0, _rule.size.x * 0.8))
	_col.add_child(_rule)
	_sub = MenuTheme.label("MORS AVT VICTORIA", 56, MenuTheme.OCHRE)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_sub)
	var eng := MenuTheme.label("Death or victory", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT.darkened(0.2))
	eng.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(eng)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 30.0)
	_col.add_child(gap)
	var entries: Array = [["fight", "Fight  (vs CPU)"], ["local_2p", "Local 2 players"], ["bots", "Watch bots"],
			["options", "Options"]]
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		entries.append(["quit", "Quit"])
	for e: Array in entries:
		var b: Button = MenuTheme.button(str(e[1]), 560.0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: chosen.emit(str(e[0])))
		_col.add_child(b)
		if _first == null:
			_first = b
	var hint := MenuTheme.label("Arrows / stick: move    Enter / A: select    Esc / B: back", 24, MenuTheme.DIM_TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.name = "Hint"
	_col.add_child(hint)
	resized.connect(_relayout)
	_relayout()


func focus_first() -> void:
	_first.grab_focus()


func _relayout() -> void:
	_col.position = Vector2.ZERO
	_col.size = size
	_title.add_theme_font_size_override("font_size", int(clampf(size.x / 7.2, 70.0, 190.0)))
	_title.add_theme_constant_override("outline_size", int(clampf(size.x / 70.0, 8.0, 22.0)))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.012, 0.008, 0.45))
	draw_rect(Rect2(0.0, size.y * 0.55, size.x, size.y * 0.45), Color(0.02, 0.012, 0.008, 0.35))
