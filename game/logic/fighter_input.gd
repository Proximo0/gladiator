class_name FighterInput
extends RefCounted
## One fighter's input for one physics tick. Pure: ints only, so it records, hashes and networks exactly.
## Mouse, stick and touch all produce this, so nothing downstream knows the device.

const AXIS_MAX: int = 1000

const SWING: int = 1  ## right hand drives hard: full arm strength
const OFFHAND: int = 2  ## left hand / shield up
const HALF_SWORD: int = 4  ## alternate grip: left hand on the blade, short powerful thrusts
const THRUST: int = 8  ## push hand target forward to full reach
const SPRINT: int = 16
const CROUCH: int = 32
const GRAB: int = 64  ## pick up / grab
const TURN_LOCK: int = 128  ## hold facing; otherwise the body turns toward the opponent

var move_x: int = 0  ## strafe right, -1000..1000
var move_y: int = 0  ## forward, -1000..1000
var aim_x: int = 0  ## weapon-hand target in the guard plane, right, -1000..1000
var aim_y: int = 0  ## up, -1000..1000
var buttons: int = 0  ## bitmask of the button constants above


func to_array() -> Array:
	return [move_x, move_y, aim_x, aim_y, buttons]


## Missing entries read as 0; axes are clamped to -1000..1000.
static func from_array(a: Array) -> FighterInput:
	var f := FighterInput.new()
	f.move_x = clamp_axis(_int_at(a, 0))
	f.move_y = clamp_axis(_int_at(a, 1))
	f.aim_x = clamp_axis(_int_at(a, 2))
	f.aim_y = clamp_axis(_int_at(a, 3))
	f.buttons = _int_at(a, 4)
	return f


static func clamp_axis(v: int) -> int:
	return clampi(v, -AXIS_MAX, AXIS_MAX)


func move() -> Vector2:
	return Vector2(move_x, move_y) / float(AXIS_MAX)


func aim() -> Vector2:
	return Vector2(aim_x, aim_y) / float(AXIS_MAX)


## True when any bit of b is set.
func has(b: int) -> bool:
	return (buttons & b) != 0


static func _int_at(a: Array, i: int) -> int:
	return int(a[i]) if i < a.size() else 0
