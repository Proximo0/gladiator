class_name TitleMenuItem
extends Button
## One title menu entry, drawn by hand. Focus (pad, keys, or the mouse over it) sweeps a blood-red bar in from the
## left behind the text, brings in a bronze marker, and nudges the text right; a press flashes it. `tile` frames it
## as a stone tile (touch layouts); otherwise it is bare text over the scrim (desktop list). `primary` is the main
## mode: larger, always faintly lit. `note` is a small line under the label ("start here").

const SWEEP_RATE: float = 14.0  ## 1/s, how fast the focus amount follows (about 160 ms to settle)
const PRESS_DECAY: float = 6.0
const NUDGE: float = 16.0

var label_text: String = ""
var note: String = ""
var tile: bool = false
var primary: bool = false
var font_px: int = 40
var _f: float = 0.0  ## 0 unfocused .. 1 focused, eased
var _press: float = 0.0


## `p_plain` is the Button's own text (what tests, logs and screen readers see) when the drawn label is styled
## differently (upper case); the Button never draws it.
func _init(p_text: String = "", p_note: String = "", p_plain: String = "") -> void:
	label_text = p_text
	note = p_note
	text = p_plain if p_plain != "" else p_text
	clip_text = true
	for fc: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color", "font_outline_color"]:
		add_theme_color_override(fc, Color(0.0, 0.0, 0.0, 0.0))
	focus_mode = Control.FOCUS_ALL
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, empty)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	pressed.connect(func() -> void: _press = 1.0)


func _process(delta: float) -> void:
	var want: float = 1.0 if has_focus() else 0.0
	var f: float = _f + (want - _f) * (1.0 - exp(-SWEEP_RATE * delta))
	if absf(f - want) < 0.004:
		f = want
	var p: float = maxf(0.0, _press - delta * PRESS_DECAY)
	if f != _f or p != _press:
		_f = f
		_press = p
		queue_redraw()


## Settles the focus look at once (screen just opened: no sweep for the first focus).
func snap() -> void:
	_f = 1.0 if has_focus() else 0.0
	_press = 0.0
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	var f: float = _f * _f * (3.0 - 2.0 * _f)  # smoothstep
	var red: Color = MenuTheme.RED
	if tile:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.1, 0.075, 0.055, 0.82))
	# The sweep: a red bar from the left, fading out toward the right edge.
	var w: float = s.x * (0.08 + 0.92 * f) if f > 0.0 else 0.0
	if primary and f < 0.35:
		w = maxf(w, s.x * 0.35)
	if w > 0.0:
		var a0: float = (0.9 if tile else 0.82) * maxf(f, 0.45 if primary else 0.0)
		var a1: float = a0 * (0.55 if tile else 0.0)
		var c0: Color = Color(red.r, red.g, red.b, a0)
		var c1: Color = Color(red.r, red.g, red.b, a1)
		draw_polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, s.y), Vector2(0.0, s.y)]),
				PackedColorArray([c0, c1, c1, c0]))
	if _press > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.85, 0.6, 0.35 * _press))
	if tile or f > 0.0:
		var edge: Color = MenuTheme.BRONZE.darkened(0.35).lerp(MenuTheme.OCHRE, f)
		if tile:
			draw_rect(Rect2(Vector2(1.0, 1.0), s - Vector2(2.0, 2.0)), edge, false, 2.0 + 2.0 * f)
		else:
			# Thin bronze rules above and below the lit item.
			var rw: float = s.x * f
			draw_line(Vector2(0.0, 1.0), Vector2(rw, 1.0), Color(edge, f), 2.0)
			draw_line(Vector2(0.0, s.y - 1.0), Vector2(rw * 0.7, s.y - 1.0), Color(edge, f * 0.8), 2.0)
	# Bronze marker: a small lozenge left of the text.
	var font: Font = MenuTheme.caps_font()
	var fs: int = font_px
	var room: float = s.x - (22.0 if tile else 30.0) - NUDGE - 14.0
	while fs > 14 and font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1  # a long label in a narrow tile shrinks rather than being cut off
	var nfs: int = maxi(22, int(float(fs) * 0.56))
	var has_note: bool = note != ""
	var block: float = float(fs) * 0.72 + (float(nfs) * 1.05 if has_note else 0.0)
	var base_y: float = (s.y - block) * 0.5 + float(fs) * 0.72
	var x0: float = (22.0 if tile else 30.0) + NUDGE * f
	if f > 0.01:
		var m: Vector2 = Vector2(x0 - 16.0, base_y - float(fs) * 0.36)
		var r: float = float(fs) * 0.16 * f
		draw_colored_polygon(PackedVector2Array([m + Vector2(0.0, -r), m + Vector2(r, 0.0), m + Vector2(0.0, r), m + Vector2(-r, 0.0)]), MenuTheme.OCHRE)
	var col: Color = MenuTheme.PARCHMENT.lerp(Color(1.0, 0.97, 0.9), f)
	if disabled:
		col = MenuTheme.DIM_TEXT
	var outline: int = maxi(4, int(float(fs) * 0.16))
	var max_w: float = s.x - x0 - 10.0
	draw_string_outline(font, Vector2(x0, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, outline, Color(0.07, 0.035, 0.02, 0.9))
	draw_string(font, Vector2(x0, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, col)
	if has_note:
		var ny: float = base_y + float(nfs) * 1.15
		draw_string_outline(font, Vector2(x0, ny), note, HORIZONTAL_ALIGNMENT_LEFT, max_w, nfs, maxi(3, outline / 2), Color(0.07, 0.035, 0.02, 0.9))
		draw_string(font, Vector2(x0, ny), note, HORIZONTAL_ALIGNMENT_LEFT, max_w, nfs, MenuTheme.OCHRE.lightened(0.15 * f))
