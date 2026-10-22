class_name TouchControls
extends Control
## On-screen controls for touch, drawn over the game. A floating thumbstick anywhere on the left half moves. A drag
## on the right half aims: the offset from where the drag started, springing back to centre on release, and SWING is
## held while that finger is down. Both rings float: a finger that runs past the ring drags it along. Buttons:
## THRUST, SPRINT and ROLL hold; GRAB held bends down and picks up (CROUCH plus a repeating GRAB); OFF, HALF and
## CROUCH are toggles (tap on, tap off) so both thumbs stay free to move and swing. Every finger is dropped when the
## app loses focus or is paused, and releases are tracked while the tree is paused, so nothing stays held. The mouse
## stands in for a finger on a machine without a touchscreen (for --touch testing). Pure mapping is in TouchFeel and
## the static functions here; sims drive it with synthetic touch events (tests/sim/sim_touch.gd).

const UNIT_FRACTION: float = 0.1  ## one layout unit u = min(width, height) * UNIT_FRACTION
const STICK_RADIUS_U: float = 2.0
const AIM_RADIUS_U: float = 2.5
const STICK_MAX_MM: float = 18.0  ## ring radii stop growing on a tablet (when the dpi is known)
const AIM_MAX_MM: float = 22.0
const BUTTON_RADIUS_FRAC: float = 0.062  ## of the screen's short side, in pixels
const BUTTON_RADIUS_MIN_PX: float = 32.0  ## 64 px buttons at the least
const BUTTON_RADIUS_MIN_MM: float = 4.5  ## 9 mm across at the least on a real phone
const BUTTON_RADIUS_MAX_MM: float = 7.0  ## 14 mm across at the most (tablets)
const TOGGLE_BITS: int = FighterInput.OFFHAND | FighterInput.HALF_SWORD | FighterInput.CROUCH
const EDGE_PX: float = 14.0  ## gap from the screen edge to the corner button
const LABEL_PX: float = 15.0  ## button label size on screen
const MOUSE_POINTER: int = -1  ## pointer id for the mouse fallback; touch indices are >= 0

var move: Vector2i = Vector2i.ZERO  ## -1000..1000, y up (read by InputReader)
var aim: Vector2i = Vector2i.ZERO  ## -1000..1000, y up
var buttons: int = 0  ## FighterInput bits held by buttons, toggles and the aim finger (SWING), before tick shaping
var toggled: int = 0  ## TOGGLE_BITS that are on

var _stick_finger: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _aim_finger: int = -1
var _aim_start: Vector2 = Vector2.ZERO
var _aim_pos: Vector2 = Vector2.ZERO
var _button_fingers: Dictionary = {}  ## pointer id -> FighterInput bit
var _grab_ticks: int = 0


## Shown when the device has a touchscreen, or when the run asks for it with --touch.
static func should_show(touch_ok: bool, args: Dictionary) -> bool:
	return touch_ok or args.has("touch")


static func in_left_half(x: float, width: float) -> bool:
	return x < width * 0.5


## True when the touch overlay is drawn (a phone, or --touch). The HUD and menus lay themselves out around it.
static func active() -> bool:
	return should_show(OS.has_feature("mobile"), Flags.args)


## Button radius in on-screen pixels for a screen whose short side is `short_px`: big enough for a thumb. With the
## screen's dpi (phones) it is also kept between 9 and 14 mm across, whatever the resolution.
static func button_radius_px(short_px: float, dpi: float = 0.0) -> float:
	return TouchFeel.size_px(short_px, BUTTON_RADIUS_FRAC, dpi, BUTTON_RADIUS_MIN_MM, BUTTON_RADIUS_MAX_MM, BUTTON_RADIUS_MIN_PX)


## Button centres in a thumb arc in the bottom-right corner; each entry is {bit, center, radius, label}.
## `area` is the layout size, `k` the on-screen pixels per layout unit (sizes are set in real pixels, so a phone that
## squeezes a 1920-unit design still gets thumb-sized buttons), `insets` the safe-area insets in layout units
## (left, top, right, bottom), `dpi` the screen's (0 = unknown). Offsets are in button radii from the corner: x to the
## left, y up. The most used (THRUST, ROLL, GRAB) sit nearest the thumb's pivot in the corner.
static func button_layout(area: Vector2, k: float = 1.0, insets: Vector4 = Vector4.ZERO, dpi: float = 0.0) -> Array:
	var kk: float = maxf(k, 0.0001)
	var r: float = button_radius_px(minf(area.x, area.y) * kk, dpi) / kk
	var corner: Vector2 = Vector2(area.x - insets.z, area.y - insets.w) - Vector2.ONE * (EDGE_PX / kk)
	var defs: Array = [
		[FighterInput.THRUST, 1.3, 1.3, 1.2, "THRUST"],
		[FighterInput.ROLL, 3.6, 1.1, 1.0, "ROLL"],
		[FighterInput.CROUCH, 5.15, 2.45, 1.0, "CROUCH"],
		[FighterInput.OFFHAND, 1.25, 3.8, 1.0, "OFF"],
		[FighterInput.GRAB, 3.2, 3.25, 1.0, "GRAB"],
		[FighterInput.HALF_SWORD, 1.6, 5.9, 1.0, "HALF"],
		[FighterInput.SPRINT, 3.65, 5.35, 1.0, "SPRINT"],
	]
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
	process_mode = Node.PROCESS_MODE_ALWAYS  # see releases while the pause menu is up


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			release_all()  # the releases of fingers down now never arrive


## Drops every finger, held button and toggle (app paused or backgrounded).
func release_all() -> void:
	_stick_finger = -1
	_aim_finger = -1
	_button_fingers.clear()
	toggled = 0
	_grab_ticks = 0
	_refresh()


## Buttons for this physics tick (InputReader calls it once per tick): held bits, toggles and the hold-GRAB repeat.
func tick_buttons() -> int:
	_grab_ticks = _grab_ticks + 1 if (buttons & FighterInput.GRAB) != 0 else 0
	return TouchFeel.tick_buttons(buttons, toggled, _grab_ticks)


## Ring radii in layout units.
func stick_radius() -> float:
	return _ring_radius(STICK_RADIUS_U, STICK_MAX_MM)


func aim_radius() -> float:
	return _ring_radius(AIM_RADIUS_U, AIM_MAX_MM)


func _ring_radius(units: float, max_mm: float) -> float:
	var k: float = _px_per_unit()
	var short_px: float = minf(size.x, size.y) * k
	return TouchFeel.size_px(short_px, UNIT_FRACTION * units, _dpi(), 0.0, max_mm, 1.0) / k


func _dpi() -> float:
	return float(DisplayServer.screen_get_dpi()) if OS.has_feature("mobile") else 0.0


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
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return  # Godot's mouse made from a touch: the touch itself was handled
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
	_forget(pointer)  # a finger index pressed again (its release was lost) starts fresh
	if is_inside_tree() and get_tree().paused:
		_refresh()
		return
	var local: Vector2 = _to_local_pos(screen_pos)
	var bit: int = button_at(local, _layout())
	if bit != 0 and (bit & TOGGLE_BITS) != 0:
		toggled ^= bit
	elif bit != 0:
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
		_stick_origin = TouchFeel.follow_anchor(_stick_origin, local, stick_radius())
	elif pointer == _aim_finger:
		_aim_pos = local
		_aim_start = TouchFeel.follow_anchor(_aim_start, local, aim_radius())
	_refresh()


func _release(pointer: int) -> void:
	_forget(pointer)
	_refresh()


func _forget(pointer: int) -> void:
	if pointer == _stick_finger:
		_stick_finger = -1
	if pointer == _aim_finger:
		_aim_finger = -1
	_button_fingers.erase(pointer)


func _refresh() -> void:
	move = Vector2i.ZERO
	if _stick_finger >= 0:
		move = TouchFeel.stick_units(_stick_pos - _stick_origin, stick_radius())
	aim = Vector2i.ZERO
	if _aim_finger >= 0:
		aim = TouchFeel.aim_units(_aim_pos - _aim_start, aim_radius())
	var mask: int = toggled
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
	return button_layout(size, k, SafeArea.window_insets() / k, _dpi())


func _to_local_pos(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _draw() -> void:
	var ink: Color = Color(1.0, 1.0, 1.0, 0.45)
	if _stick_finger >= 0:
		var r: float = stick_radius()
		draw_circle(_stick_origin, r, Color(1.0, 1.0, 1.0, 0.1))
		draw_arc(_stick_origin, r, 0.0, TAU, 48, ink, 2.0)
		draw_circle(_stick_origin + clamp_offset(_stick_pos - _stick_origin, r), r * 0.4, Color(1.0, 1.0, 1.0, 0.4))
	if _aim_finger >= 0:
		var ra: float = aim_radius()
		draw_arc(_aim_start, ra, 0.0, TAU, 48, Color(1.0, 0.85, 0.5, 0.5), 2.0)
		draw_circle(_aim_start + clamp_offset(_aim_pos - _aim_start, ra), ra * 0.2, Color(1.0, 0.85, 0.5, 0.6))
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
