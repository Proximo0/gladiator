class_name TouchControls
extends Control
## On-screen controls for touch, drawn over the game. A floating thumbstick anywhere on the left half moves. A drag
## on the right half aims: the offset from where the drag started, springing back to centre on release, and SWING is
## held while that finger is down. Six buttons hold OFFHAND, THRUST, HALF_SWORD, SPRINT,
## GRAB and ROLL. The mouse stands in
## for a finger on a machine without a touchscreen (for --touch testing). Pure mapping is in static functions.

const UNIT_FRACTION: float = 0.1  ## one layout unit u = min(width, height) * UNIT_FRACTION
const STICK_RADIUS_U: float = 2.0
const AIM_RADIUS_U: float = 2.5
const MOUSE_POINTER: int = -1  ## pointer id for the mouse fallback; touch indices are >= 0

var move: Vector2i = Vector2i.ZERO  ## -1000..1000, y up (read by InputReader)
var aim: Vector2i = Vector2i.ZERO  ## -1000..1000, y up
var buttons: int = 0  ## FighterInput bits held by buttons and the aim finger (SWING)

var _stick_finger: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _aim_finger: int = -1
var _aim_start: Vector2 = Vector2.ZERO
var _aim_pos: Vector2 = Vector2.ZERO
var _button_fingers: Dictionary = {}  ## pointer id -> FighterInput bit


## Shown when the device has a touchscreen, or when the run asks for it with --touch.
static func should_show(touch_ok: bool, args: Dictionary) -> bool:
	return touch_ok or args.has("touch")


static func in_left_half(x: float, width: float) -> bool:
	return x < width * 0.5


## Button centres sit in the bottom-right corner; each entry is {bit, center, radius, label}.
static func button_layout(area: Vector2) -> Array:
	var u: float = minf(area.x, area.y) * UNIT_FRACTION
	var defs: Array = [
		[FighterInput.OFFHAND, -1.3, -1.3, 0.9, "OFF"],
		[FighterInput.THRUST, -3.0, -0.9, 0.8, "THRUST"],
		[FighterInput.HALF_SWORD, -1.3, -3.0, 0.8, "HALF"],
		[FighterInput.GRAB, -4.6, -2.2, 0.7, "GRAB"],
		[FighterInput.SPRINT, -3.0, -3.4, 0.7, "SPRINT"],
		[FighterInput.ROLL, -4.6, -0.7, 0.7, "ROLL"],
	]
	var out: Array = []
	for d: Array in defs:
		out.append({
			"bit": d[0],
			"center": area + Vector2(d[1], d[2]) * u,
			"radius": float(d[3]) * u,
			"label": d[4],
		})
	return out


## The button bit under pos, or 0.
static func button_at(pos: Vector2, layout: Array) -> int:
	for b: Dictionary in layout:
		if pos.distance_to(b["center"]) <= float(b["radius"]):
			return int(b["bit"])
	return 0


static func clamp_offset(offset: Vector2, radius: float) -> Vector2:
	if radius <= 0.0 or offset.length() <= radius:
		return offset
	return offset.normalized() * radius


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position)
	elif not DisplayServer.is_touchscreen_available():
		_mouse_fallback(event)


func _mouse_fallback(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press(MOUSE_POINTER, mb.position)
		else:
			_release(MOUSE_POINTER)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag(MOUSE_POINTER, mm.position)


func _press(pointer: int, screen_pos: Vector2) -> void:
	var local: Vector2 = _to_local_pos(screen_pos)
	var bit: int = button_at(local, button_layout(size))
	if bit != 0:
		_button_fingers[pointer] = bit
	elif _stick_finger < 0 and in_left_half(local.x, size.x):
		_stick_finger = pointer
		_stick_origin = local
		_stick_pos = local
	elif _aim_finger < 0 and not in_left_half(local.x, size.x):
		_aim_finger = pointer
		_aim_start = local
		_aim_pos = local
	_refresh()


func _drag(pointer: int, screen_pos: Vector2) -> void:
	var local: Vector2 = _to_local_pos(screen_pos)
	if pointer == _stick_finger:
		_stick_pos = local
	elif pointer == _aim_finger:
		_aim_pos = local
	_refresh()


func _release(pointer: int) -> void:
	if pointer == _stick_finger:
		_stick_finger = -1
	if pointer == _aim_finger:
		_aim_finger = -1
	_button_fingers.erase(pointer)
	_refresh()


func _refresh() -> void:
	var u: float = minf(size.x, size.y) * UNIT_FRACTION
	move = Vector2i.ZERO
	if _stick_finger >= 0:
		move = InputReader.offset_units(_stick_pos - _stick_origin, u * STICK_RADIUS_U)
	aim = Vector2i.ZERO
	if _aim_finger >= 0:
		aim = InputReader.offset_units(_aim_pos - _aim_start, u * AIM_RADIUS_U)
	var mask: int = 0
	for bit: int in _button_fingers.values():
		mask |= bit
	if _aim_finger >= 0:
		mask |= FighterInput.SWING
	buttons = mask
	queue_redraw()


func _to_local_pos(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _draw() -> void:
	var u: float = minf(size.x, size.y) * UNIT_FRACTION
	var ink: Color = Color(1.0, 1.0, 1.0, 0.45)
	if _stick_finger >= 0:
		var r: float = u * STICK_RADIUS_U
		draw_circle(_stick_origin, r, Color(1.0, 1.0, 1.0, 0.1))
		draw_arc(_stick_origin, r, 0.0, TAU, 48, ink, 2.0)
		draw_circle(_stick_origin + clamp_offset(_stick_pos - _stick_origin, r), u * 0.8, Color(1.0, 1.0, 1.0, 0.4))
	if _aim_finger >= 0:
		var ra: float = u * AIM_RADIUS_U
		draw_arc(_aim_start, ra, 0.0, TAU, 48, Color(1.0, 0.85, 0.5, 0.5), 2.0)
		draw_circle(_aim_start + clamp_offset(_aim_pos - _aim_start, ra), u * 0.5, Color(1.0, 0.85, 0.5, 0.6))
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(int(u * 0.22), 10)
	for b: Dictionary in button_layout(size):
		var center: Vector2 = b["center"]
		var radius: float = b["radius"]
		var held: bool = (buttons & int(b["bit"])) != 0
		draw_circle(center, radius, Color(1.0, 1.0, 1.0, 0.4 if held else 0.14))
		draw_arc(center, radius, 0.0, TAU, 40, ink, 2.0)
		draw_string(font, center + Vector2(-radius, font_size * 0.35), b["label"], HORIZONTAL_ALIGNMENT_CENTER,
			radius * 2.0, font_size, Color(1.0, 1.0, 1.0, 0.85))
