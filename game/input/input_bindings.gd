class_name InputBindings
extends RefCounted
## Default device bindings, the one table. Controls registers these as InputMap actions; InputReader reads the raw
## devices with the same table, so a device only ever drives its own player. Keys are physical (layout independent).

## action -> physical keys (keyboard)
const KEYS: Dictionary = {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"half_sword": [KEY_Q],
	"thrust": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"grab": [KEY_E],
	"turn_lock": [KEY_ALT],
}

## action -> mouse buttons
const MOUSE: Dictionary = {
	"swing": [MOUSE_BUTTON_LEFT],
	"offhand": [MOUSE_BUTTON_RIGHT],
}

## action -> gamepad buttons
const PAD_BUTTONS: Dictionary = {
	"thrust": [JOY_BUTTON_RIGHT_SHOULDER],
	"half_sword": [JOY_BUTTON_LEFT_SHOULDER],
	"sprint": [JOY_BUTTON_LEFT_STICK],
	"crouch": [JOY_BUTTON_B],
	"grab": [JOY_BUTTON_A],
	"turn_lock": [JOY_BUTTON_RIGHT_STICK],
}

## action -> gamepad trigger axis (read as pressed past 0.5)
const PAD_TRIGGERS: Dictionary = {
	"swing": JOY_AXIS_TRIGGER_RIGHT,
	"offhand": JOY_AXIS_TRIGGER_LEFT,
}

## action -> [stick axis, sign]: the stick pushed toward that side presses the action
const PAD_STICKS: Dictionary = {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"aim_left": [JOY_AXIS_RIGHT_X, -1.0],
	"aim_right": [JOY_AXIS_RIGHT_X, 1.0],
	"aim_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
}

## Actions that set a FighterInput.buttons bit.
const BUTTON_ACTIONS: PackedStringArray = [
	"swing", "offhand", "half_sword", "thrust", "sprint", "crouch", "grab", "turn_lock",
]


static func bit_for_action(action: String) -> int:
	match action:
		"swing":
			return FighterInput.SWING
		"offhand":
			return FighterInput.OFFHAND
		"half_sword":
			return FighterInput.HALF_SWORD
		"thrust":
			return FighterInput.THRUST
		"sprint":
			return FighterInput.SPRINT
		"crouch":
			return FighterInput.CROUCH
		"grab":
			return FighterInput.GRAB
		"turn_lock":
			return FighterInput.TURN_LOCK
	return 0


## OR of the bits for the given button actions. Unknown names contribute nothing.
static func button_mask(pressed: PackedStringArray) -> int:
	var mask: int = 0
	for action: String in pressed:
		mask |= bit_for_action(action)
	return mask
