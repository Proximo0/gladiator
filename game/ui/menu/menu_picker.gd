class_name MenuPicker
extends Control
## One option row: a label on the left and "< value >" on the right. Left/right (keys, d-pad, stick) change it,
## Accept or a click on the right half goes forward, a click on the left half goes back. Works with touch (emulated
## mouse). `items` is [[id, label], ...].

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
	var fs: int = MenuTheme.FONT_SMALL
	var col: Color = MenuTheme.PARCHMENT if enabled else MenuTheme.DIM_TEXT
	var ty: float = size.y * 0.5 + float(fs) * 0.36
	draw_string(font, Vector2(16.0, ty), title, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.34, fs, MenuTheme.OCHRE if enabled else MenuTheme.DIM_TEXT)
	var vx: float = size.x * 0.36
	var vw: float = size.x - vx - 8.0
	var value: String = str((items[index] as Array)[1]) if not items.is_empty() else ""
	if enabled:
		draw_string(font, Vector2(vx, ty), "<", HORIZONTAL_ALIGNMENT_LEFT, 40.0, fs, MenuTheme.OCHRE)
		draw_string(font, Vector2(vx + vw - 28.0, ty), ">", HORIZONTAL_ALIGNMENT_LEFT, 40.0, fs, MenuTheme.OCHRE)
	draw_string(font, Vector2(vx + 34.0, ty), value, HORIZONTAL_ALIGNMENT_CENTER, vw - 68.0, fs, col)
