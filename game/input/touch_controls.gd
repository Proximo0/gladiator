class_name TouchControls
extends Control
## On-screen controls for touch, drawn over the game. A floating thumbstick anywhere on the left half moves. A drag
## on the right half aims: the offset from where the drag started, springing back to centre on release, and SWING is
## held while that finger is down. Nine buttons hold OFFHAND, THRUST, HALF_SWORD, SPRINT,
## GRAB, ROLL, KICK, SHOVE and CLINCH (HOLD). The mouse stands in
## for a finger on a machine without a touchscreen (for --touch testing). Pure mapping is in static functions.

const UNIT_FRACTION: float = 0.1  ## one layout unit u = min(width, height) * UNIT_FRACTION
const STICK_RADIUS_U: float = 2.0
const AIM_RADIUS_U: float = 2.5
const BUTTON_RADIUS_FRAC: float = 0.068  ## of the screen's short side, in pixels
const BUTTON_RADIUS_MIN_PX: float = 32.0  ## 64 px buttons at the least
const BUTTON_RADIUS_MAX_PX: float = 46.0
const EDGE_PX: float = 14.0  ## gap from the screen edge to the corner button
const LABEL_PX: float = 15.0  ## button label size on screen
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


## True when the touch overlay is drawn (a phone, or --touch). The HUD and menus lay themselves out around it.
static func active() -> bool:
	return should_show(OS.has_feature("mobile"), Flags.args)


## Button radius in on-screen pixels for a screen whose short side is `short_px`: big enough for a thumb.
static func button_radius_px(short_px: float) -> float:
	return clampf(short_px * BUTTON_RADIUS_FRAC, BUTTON_RADIUS_MIN_PX, BUTTON_RADIUS_MAX_PX)


## Button centres in a thumb arc in the bottom-right corner; each entry is {bit, center, radius, label}.
## `area` is the layout size, `k` the on-screen pixels per layout unit (sizes are set in real pixels, so a phone that
## squeezes a 1920-unit design still gets thumb-sized buttons), `insets` the safe-area insets in layout units
## (left, top, right, bottom). Offsets are in button radii from the corner: x to the left, y up.
static func button_layout(area: Vector2, k: float = 1.0, insets: Vector4 = Vector4.ZERO) -> Array:
	var kk: float = maxf(k, 0.0001)
	var r: float = button_radius_px(minf(area.x, area.y) * kk) / kk
	var corner: Vector2 = Vector2(area.x - insets.z, area.y - insets.w) - Vector2.ONE * (EDGE_PX / kk)
	var defs: Array = [
		[FighterInput.THRUST, 1.3, 1.3, 1.2, "THRUST"],
		[FighterInput.OFFHAND, 1.2, 3.9, 1.0, "OFF"],
		[FighterInput.HALF_SWORD, 2.2, 6.4, 1.0, "HALF"],
		[FighterInput.ROLL, 3.9, 1.2, 1.0, "ROLL"],
		[FighterInput.GRAB, 4.1, 3.6, 1.0, "GRAB"],
		[FighterInput.SPRINT, 4.5, 5.9, 1.0, "SPRINT"],
	]
	# The close-range buttons: a fourth column in landscape, stacked above the arc on a tall (portrait) screen.
	if area.y > area.x:
		defs.append_array([[FighterInput.KICK, 1.3, 8.6, 1.0, "KICK"], [FighterInput.SHOVE, 3.6, 8.2, 1.0, "SHOVE"],
			[FighterInput.CLINCH, 2.4, 10.5, 1.0, "HOLD"]])
	else:
		defs.append_array([[FighterInput.KICK, 6.1, 1.2, 1.0, "KICK"], [FighterInput.SHOVE, 6.3, 3.4, 1.0, "SHOVE"],
			[FighterInput.CLINCH, 6.6, 5.6, 1.0, "HOLD"]])
	var out: Array = []
	for d: Array in defs:
		out.append({
			"bit": d[0],
			"center": corner - Vector2(d[1], d[2]) * r,
			"radius": float(d[3]) * r,
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
	var bit: int = button_at(local, _layout())
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


## Pixels per layout unit (the project stretches a 1920x1080 design, so a phone squeezes it).
func _px_per_unit() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(get_viewport().get_final_transform().get_scale().x, 0.01)


func _layout() -> Array:
	var k: float = _px_per_unit()
	return button_layout(size, k, SafeArea.window_insets() / k)


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
	var k: float = _px_per_unit()
	var font_size: int = ceili(LABEL_PX / k)
	var line: float = 2.5 / k
	for b: Dictionary in _layout():
		var center: Vector2 = b["center"]
		var held: bool = (buttons & int(b["bit"])) != 0
		var radius: float = float(b["radius"]) * (1.08 if held else 1.0)
		draw_circle(center, radius, Color(1.0, 0.82, 0.45, 0.62) if held else Color(0.06, 0.04, 0.03, 0.42))
		draw_arc(center, radius, 0.0, TAU, 40, Color(1.0, 0.95, 0.8, 1.0) if held else Color(1.0, 1.0, 1.0, 0.7), line * (1.6 if held else 1.0), true)
		var text: String = b["label"]
		var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var at: Vector2 = center + Vector2(-text_w * 0.5, font_size * 0.35)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, maxi(int(3.0 / k), 3), Color(0.0, 0.0, 0.0, 0.85))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(1.0, 1.0, 1.0, 1.0))
