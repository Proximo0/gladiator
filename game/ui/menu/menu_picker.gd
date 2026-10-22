class_name MenuPicker
extends Control
## One option row: a label on the left and "< value >" on the right. Left/right (keys, d-pad, stick) change it,
## Accept or a click on the right half goes forward, a click on the left half goes back. Works with touch (emulated
## mouse). `items` is [[id, label], ...]; an optional third element `true` marks a locked item, drawn dimmed with a
## padlock (it can still be browsed; the owner of the picker decides what a locked pick means).

signal changed(id: String)

var title: String = ""
var items: Array = []
var index: int = 0
var enabled: bool = true:
	set(v):
		enabled = v
		focus_mode = Control.FOCUS_ALL if v else Control.FOCUS_NONE
		queue_redraw()
var _hover: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0.0, MenuTheme.ROW_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func setup(p_title: String, p_items: Array, selected_id: String = "") -> void:
	title = p_title
	items = p_items
	select(selected_id, false)


## True when the item at `i` (default: the current one) is marked locked.
func is_locked(i: int = -1) -> bool:
	var k: int = index if i < 0 else i
	if k < 0 or k >= items.size():
		return false
	var it: Array = items[k]
	return it.size() > 2 and bool(it[2])


func current_id() -> String:
	return str((items[index] as Array)[0]) if not items.is_empty() else ""


func select(id: String, emit: bool = true) -> void:
	for i: int in items.size():
		if str((items[i] as Array)[0]) == id:
			index = i
			break
	queue_redraw()
	if emit:
		changed.emit(current_id())


func step(dir: int) -> void:
	if items.is_empty() or not enabled:
		return
	index = posmod(index + dir, items.size())
	queue_redraw()
	changed.emit(current_id())


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		step(-1 if (event as InputEventMouseButton).position.x < size.x * 0.68 else 1)
		accept_event()


func _draw() -> void:
	var focused: bool = has_focus() and enabled
	var bg: Color = MenuTheme.BUTTON_HOT if (focused or (_hover and enabled)) else MenuTheme.BUTTON_BG
	if not enabled:
		bg = bg.darkened(0.3)
	var border: Color = MenuTheme.OCHRE if (focused or _hover) else MenuTheme.BRONZE.darkened(0.4)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	draw_rect(Rect2(Vector2.ZERO, size), border, false, 5.0 if focused else 3.0)
	var font: Font = MenuTheme.caps_font()
	var fs: int = clampi(int(size.y * 0.36), MenuTheme.FONT_SMALL, 40)  # finger-sized rows on a phone get larger text
	var col: Color = MenuTheme.PARCHMENT if enabled else MenuTheme.DIM_TEXT
	var ty: float = size.y * 0.5 + float(fs) * 0.36
	draw_string(font, Vector2(16.0, ty), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.34, fs, MenuTheme.OCHRE if enabled else MenuTheme.DIM_TEXT)
	var vx: float = size.x * 0.36
	var vw: float = size.x - vx - 8.0
	var value: String = str((items[index] as Array)[1]) if not items.is_empty() else ""
	if enabled:
		draw_string(font, Vector2(vx, ty), "<", HORIZONTAL_ALIGNMENT_LEFT, 40.0, fs, MenuTheme.OCHRE)
		draw_string(font, Vector2(vx + vw - 28.0, ty), ">", HORIZONTAL_ALIGNMENT_LEFT, 40.0, fs, MenuTheme.OCHRE)
	if is_locked():
		col = MenuTheme.DIM_TEXT
		_draw_lock(Vector2(vx + 40.0, size.y * 0.5), float(fs) * 0.62)
		draw_string(font, Vector2(vx + 34.0 + float(fs) * 0.7, ty), value, HORIZONTAL_ALIGNMENT_CENTER, vw - 68.0 - float(fs) * 0.7, fs, col)
		return
	draw_string(font, Vector2(vx + 34.0, ty), value, HORIZONTAL_ALIGNMENT_CENTER, vw - 68.0, fs, col)


## A small padlock centred at `c`, `h` tall (drawn, so it needs no font glyph).
func _draw_lock(c: Vector2, h: float) -> void:
	var w: float = h * 0.8
	var col: Color = MenuTheme.OCHRE
	draw_arc(Vector2(c.x, c.y - h * 0.1), w * 0.3, PI, TAU, 10, col, 2.0, true)
	draw_line(Vector2(c.x - w * 0.3, c.y - h * 0.1), Vector2(c.x - w * 0.3, c.y), col, 2.0)
	draw_line(Vector2(c.x + w * 0.3, c.y - h * 0.1), Vector2(c.x + w * 0.3, c.y), col, 2.0)
	draw_rect(Rect2(c.x - w * 0.45, c.y, w * 0.9, h * 0.45), col)
