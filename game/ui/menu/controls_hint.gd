class_name ControlsHint
extends PanelContainer
## A short controls reminder at the top of the screen for the first seconds of a fight, then it fades out.

const HOLD_S: float = 4.5
const FADE_S: float = 0.9
const MIN_FONT: int = 18
const MAX_FONT: int = 40

var _box: VBoxContainer
var _tween: Tween = null


func _init() -> void:
	theme = MenuTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", MenuTheme.box(Color(0.06, 0.045, 0.03, 0.62), MenuTheme.BRONZE.darkened(0.2), 2, 10.0))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	visible = false


## `font_px` is the text size in layout units (the caller picks about 15 on-screen px); lines wrap within `max_width`.
func show_lines(lines: Array, max_width: float, font_px: int = 26) -> void:
	for c: Node in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for line: Variant in lines:
		var l := MenuTheme.label(str(line), clampi(font_px, MIN_FONT, MAX_FONT), MenuTheme.PARCHMENT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var fit: float = MenuTheme.caps_font().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, clampi(font_px, MIN_FONT, MAX_FONT)).x + 4.0
		l.custom_minimum_size = Vector2(minf(max_width, fit), 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(l)
	size = Vector2.ZERO
	modulate.a = 1.0
	visible = not lines.is_empty()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_interval(HOLD_S)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_S)
	_tween.tween_callback(func() -> void: visible = false)


func hide_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
