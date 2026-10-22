class_name PracticePanel
extends PanelContainer
## The Practice prompt card: Roman heading, step counter, the instruction for the device in use, a tip-speed bar
## against the damage threshold, and the buttons (skip, or reset / weapon / quick match in free practice).
## Pure presentation: PracticeSession feeds it with show_step() / show_free() and listens to `action`.

signal action(id: String)  ## "skip", "skip_all", "reset", "weapon", "quick", "menu"

const BODY_PX: float = 17.0  ## on-screen text height of the instruction
const HEAD_PX: float = 26.0
const BAR_H: float = 16.0
const MARGIN: float = 14.0
const MAX_W: float = 1000.0

var _head: Label
var _count: Label
var _body: Label
var _bar: Control
var _bar_label: Label
var _hint: Label
var _buttons: HBoxContainer
var _prog: Control
var _tip: float = 0.0
var _min: float = 3.0
var _progress: float = 0.0
var _show_bar: bool = false
var _free: bool = false
var _flash: float = 0.0


func _init() -> void:
	theme = MenuTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", MenuTheme.box(Color(0.09, 0.07, 0.05, 0.86), MenuTheme.BRONZE, 3, 12.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_head = MenuTheme.label("", 36, MenuTheme.OCHRE)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_head)
	_count = MenuTheme.label("", 30, MenuTheme.PARCHMENT)
	top.add_child(_count)
	_body = MenuTheme.label("", 28, MenuTheme.PARCHMENT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 200.0
	v.add_child(_body)
	_prog = Control.new()
	_prog.custom_minimum_size = Vector2(0.0, 8.0)
	_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prog.draw.connect(_draw_progress)
	v.add_child(_prog)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0.0, BAR_H)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	v.add_child(_bar)
	_bar_label = MenuTheme.label("", 24, MenuTheme.DIM_TEXT)
	v.add_child(_bar_label)
	_hint = MenuTheme.label("", 22, MenuTheme.DIM_TEXT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 200.0
	v.add_child(_hint)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_buttons)
	visible = false


## The step card. `touch_buttons`: show Skip buttons (touch, or any run with a free mouse).
func show_step(heading: Array, step_line: String, counter: String, body: String, hint: String, bar: bool, touch_buttons: bool) -> void:
	_free = false
	_head.text = "%s  -  %s" % [str(heading[0]), str(heading[1])]
	_count.text = ("%s    %s" % [step_line, counter]) if counter != "" else step_line
	_body.text = body
	_hint.text = hint
	_show_bar = bar
	_bar.visible = bar
	_bar_label.visible = bar
	_set_buttons([["skip", "Skip step"], ["skip_all", "Skip training"]] if touch_buttons else [])
	visible = true
	_relayout_size()


## The free practice card.
func show_free(heading: Array, body: String, hint: String, weapon_name: String, touch_buttons: bool) -> void:
	_free = true
	_head.text = "%s  -  %s" % [str(heading[0]), str(heading[1])]
	_count.text = ""
	_body.text = body
	_hint.text = hint
	_show_bar = true
	_bar.visible = true
	_bar_label.visible = true
	_progress = 0.0
	_prog.queue_redraw()
	_set_buttons([["reset", "Reset dummy"], ["weapon", "Weapon: %s" % weapon_name], ["quick", "Quick Match"]] if touch_buttons else [["quick", "Quick Match"]])
	visible = true
	_relayout_size()


## Live numbers, every tick: tip speed, the damage threshold and the current step's 0..1 progress.
func update_live(tip: float, min_speed: float, progress: float, best: float) -> void:
	_tip = tip
	_min = maxf(min_speed, 0.01)
	_progress = progress
	if _show_bar:
		_bar_label.text = "Tip speed %.1f m/s   best %.1f   (damage starts at %.0f)" % [tip, best, min_speed]
	_bar.queue_redraw()
	_prog.queue_redraw()


## A green flash of the card when a step is done.
func flash() -> void:
	_flash = 1.0
	var tw: Tween = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "_flash", 0.0, 0.8)
	tw.parallel().tween_method(func(_x: float) -> void: queue_redraw(), 0.0, 1.0, 0.8)


func _set_buttons(entries: Array) -> void:
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	for e: Array in entries:
		var b: Button = MenuTheme.button(str(e[1]))
		b.custom_minimum_size.y = 52.0
		b.focus_mode = Control.FOCUS_NONE  # Space (thrust) must never press a focused button
		b.pressed.connect(func() -> void: action.emit(str(e[0])))
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		_buttons.add_child(b)
	_buttons.visible = not entries.is_empty()


## Sizes the fonts to ~BODY_PX on screen and the card to the layout width; places it at (centre x, y).
func fit(root_w: float, y: float, ppu: float) -> void:
	var p: float = maxf(ppu, 0.01)
	var body_f: int = clampi(int(ceilf(BODY_PX / p)), 22, 52)
	var head_f: int = clampi(int(ceilf(HEAD_PX / p)), 28, 64)
	var small_f: int = clampi(int(ceilf(13.0 / p)), 18, 40)
	_head.add_theme_font_size_override("font_size", head_f)
	_count.add_theme_font_size_override("font_size", body_f)
	_body.add_theme_font_size_override("font_size", body_f)
	_bar_label.add_theme_font_size_override("font_size", small_f)
	_hint.add_theme_font_size_override("font_size", small_f)
	var w: float = minf(root_w - 2.0 * MARGIN, MAX_W / p * 0.6 + 300.0)
	w = clampf(w, 280.0, root_w - 2.0 * MARGIN)
	_body.custom_minimum_size.x = w - 40.0
	_hint.custom_minimum_size.x = w - 40.0
	custom_minimum_size.x = w
	_bar.custom_minimum_size.y = maxf(BAR_H, 12.0 / p)
	_prog.custom_minimum_size.y = maxf(8.0, 6.0 / p)
	_relayout_size()
	position = Vector2((root_w - size.x) * 0.5, y)


func _relayout_size() -> void:
	size = Vector2(custom_minimum_size.x, 0.0)


func _draw_bar() -> void:
	var s: Vector2 = _bar.size
	_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.04, 0.03, 0.9))
	var full: float = _min * 2.0
	var f: float = clampf(_tip / full, 0.0, 1.0)
	var hot: bool = _tip >= _min
	_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * f, s.y)), Color(0.78, 0.16, 0.1) if hot else Color(0.55, 0.45, 0.3))
	var mx: float = s.x * 0.5
	_bar.draw_rect(Rect2(mx - 2.0, -3.0, 4.0, s.y + 6.0), MenuTheme.PARCHMENT)
	_bar.draw_rect(Rect2(Vector2.ZERO, s), MenuTheme.BRONZE, false, 2.0)


func _draw_progress() -> void:
	if _free:
		return
	var s: Vector2 = _prog.size
	_prog.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.04, 0.03, 0.9))
	_prog.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * _progress, s.y)), MenuTheme.OCHRE)


func _draw() -> void:
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.7, 0.25, 0.35 * _flash))
