class_name InputReader
extends Node
## Reads one fighter's device once per physics tick and returns a FighterInput. The mapping is in static functions
## (tests/unit/test_input_reader.gd); this node only touches devices. Devices: "kbm", "pad0", "pad1", "touch".

const MOUSE_SENSITIVITY: float = 2.0  ## aim units (of 1000) per mouse pixel
const AIM_RETURN_PER_TICK: float = 6.0  ## aim units pulled back to centre per tick while the mouse is still
const STICK_DEADZONE: float = 0.15  ## radial, fraction of full stick
const TOUCH_LAYER: int = 20

var device: String = "kbm"

var _aim: Vector2 = Vector2.ZERO
var _mouse_delta: Vector2 = Vector2.ZERO
var _touch: TouchControls = null


func _ready() -> void:
	if device == "kbm":
		set_captured(true)
	elif device == "touch":
		var layer := CanvasLayer.new()
		layer.layer = TOUCH_LAYER
		add_child(layer)
		_touch = TouchControls.new()
		_touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_touch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_touch)


func _exit_tree() -> void:
	if device == "kbm":
		set_captured(false)


## Default device for player 1: touch when the touch overlay is wanted, else keyboard and mouse.
static func default_device(touch_ok: bool, args: Dictionary) -> String:
	return "touch" if TouchControls.should_show(touch_ok, args) else "kbm"


## Keyboard and mouse capture while playing, so aim is not limited by the screen edge.
func set_captured(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if device != "kbm" or not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_mouse_delta += (event as InputEventMouseMotion).relative


## Called once per physics tick, before the fighter steps.
func read() -> FighterInput:
	match device:
		"kbm":
			return _read_kbm()
		"touch":
			return _read_touch()
	var pad: int = pad_index(device)
	if pad >= 0:
		return _read_pad(pad)
	return FighterInput.new()


func _read_kbm() -> FighterInput:
	var f := FighterInput.new()
	var move: Vector2i = keys_move(
		_kbm_down("move_right"), _kbm_down("move_left"), _kbm_down("move_forward"), _kbm_down("move_back"))
	f.move_x = move.x
	f.move_y = move.y
	if _mouse_delta != Vector2.ZERO:
		_aim = aim_step(_aim, _mouse_delta, MOUSE_SENSITIVITY)
	else:
		_aim = recentre(_aim, AIM_RETURN_PER_TICK)
	_mouse_delta = Vector2.ZERO
	var aim: Vector2i = to_units(_aim)
	f.aim_x = aim.x
	f.aim_y = aim.y
	var pressed: PackedStringArray = PackedStringArray()
	for action: String in InputBindings.BUTTON_ACTIONS:
		if _kbm_down(action):
			pressed.append(action)
	f.buttons = InputBindings.button_mask(pressed)
	return f


func _read_pad(id: int) -> FighterInput:
	var f := FighterInput.new()
	var move: Vector2i = stick_units(
		Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)), STICK_DEADZONE)
	f.move_x = move.x
	f.move_y = move.y
	var aim: Vector2i = stick_units(
		Vector2(Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)), STICK_DEADZONE)
	f.aim_x = aim.x
	f.aim_y = aim.y
	var pressed: PackedStringArray = PackedStringArray()
	for action: String in InputBindings.BUTTON_ACTIONS:
		if _pad_down(action, id):
			pressed.append(action)
	f.buttons = InputBindings.button_mask(pressed)
	return f


func _read_touch() -> FighterInput:
	var f := FighterInput.new()
	if _touch == null:
		return f
	f.move_x = _touch.move.x
	f.move_y = _touch.move.y
	f.aim_x = _touch.aim.x
	f.aim_y = _touch.aim.y
	f.buttons = _touch.buttons
	return f


func _kbm_down(action: String) -> bool:
	var keys: Array = InputBindings.KEYS.get(action, [])
	for k: int in keys:
		if Input.is_physical_key_pressed(k):
			return true
	var buttons: Array = InputBindings.MOUSE.get(action, [])
	for b: int in buttons:
		if Input.is_mouse_button_pressed(b):
			return true
	return false


func _pad_down(action: String, id: int) -> bool:
	var buttons: Array = InputBindings.PAD_BUTTONS.get(action, [])
	for b: int in buttons:
		if Input.is_joy_button_pressed(id, b):
			return true
	if InputBindings.PAD_TRIGGERS.has(action):
		return trigger_pressed(Input.get_joy_axis(id, InputBindings.PAD_TRIGGERS[action]))
	return false


## Pad index from a device name: "pad0" -> 0, "pad1" -> 1, anything else -> -1.
static func pad_index(dev: String) -> int:
	if not dev.begins_with("pad"):
		return -1
	var digits: String = dev.trim_prefix("pad")
	return digits.to_int() if digits.is_valid_int() else -1


## Keys to a move vector. Diagonals are scaled to unit length so WASD matches a full stick.
static func keys_move(right: bool, left: bool, forward: bool, back: bool) -> Vector2i:
	var x: int = int(right) - int(left)
	var y: int = int(forward) - int(back)
	var scale: float = 1.0
	if x != 0 and y != 0:
		scale = 0.70710678
	return Vector2i(roundi(x * FighterInput.AXIS_MAX * scale), roundi(y * FighterInput.AXIS_MAX * scale))


## Raw stick (x right, y down as the engine reports it) to units (y up), with a radial deadzone.
static func stick_units(raw: Vector2, deadzone: float) -> Vector2i:
	var n: float = raw.length()
	if n <= deadzone or deadzone >= 1.0:
		return Vector2i.ZERO
	var scaled: Vector2 = raw.normalized() * minf((n - deadzone) / (1.0 - deadzone), 1.0)
	return offset_units(scaled, 1.0)


## A screen-space offset (x right, y down) over a radius to units (y up), clamped to the unit circle.
static func offset_units(offset: Vector2, radius: float) -> Vector2i:
	if radius <= 0.0:
		return Vector2i.ZERO
	var v: Vector2 = offset / radius
	if v.length() > 1.0:
		v = v.normalized()
	return Vector2i(roundi(v.x * FighterInput.AXIS_MAX), roundi(-v.y * FighterInput.AXIS_MAX))


static func trigger_pressed(value: float) -> bool:
	return value > 0.5


## Mouse motion (pixels, y down) into aim (y up), clamped per axis to the aim range.
static func aim_step(aim: Vector2, motion: Vector2, sensitivity: float) -> Vector2:
	var limit: float = float(FighterInput.AXIS_MAX)
	var next: Vector2 = Vector2(aim.x + motion.x * sensitivity, aim.y - motion.y * sensitivity)
	return Vector2(clampf(next.x, -limit, limit), clampf(next.y, -limit, limit))


## Slow return to the centre: each axis moves toward 0 by step, never past it.
static func recentre(aim: Vector2, step: float) -> Vector2:
	return Vector2(move_toward(aim.x, 0.0, step), move_toward(aim.y, 0.0, step))


static func to_units(aim: Vector2) -> Vector2i:
	return Vector2i(roundi(aim.x), roundi(aim.y))
