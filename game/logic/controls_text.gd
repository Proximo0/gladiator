class_name ControlsText
extends RefCounted
## Plain-text control references: the short hint shown at the start of a fight and the full table for the options
## page. Pure strings; the bindings themselves live in InputBindings.

## [action, keyboard and mouse, gamepad, touch]
const TABLE: Array = [
	["Move", "W A S D", "Left stick", "Left thumb stick"],
	["Steer weapon hand", "Mouse", "Right stick", "Drag on the right side"],
	["Swing", "Left click", "Right trigger", "Hold the aim drag"],
	["Thrust", "Space", "Right bumper", "THRUST button"],
	["Off hand / shield", "Right click", "Left trigger", "OFF button"],
	["Half-sword grip", "Q", "Left bumper", "HALF button"],
	["Sprint", "Shift", "Left stick press", "SPRINT button"],
	["Crouch / kneel", "Ctrl", "B", "-"],
	["Grab / pick up", "E", "A", "GRAB button"],
	["Dodge roll (move direction)", "C", "X", "ROLL button"],
	["Lock turning", "Alt", "Right stick press", "-"],
	["Pause", "Esc", "Start", "Menu key"],
]


## Hint lines for the first seconds of a fight, for the devices in use. Always starts with the keyboard and mouse
## line unless the match is touch-only.
static func hint_lines(mode: String, has_pad: bool, has_touch: bool) -> Array:
	var out: Array = []
	if mode == "local_2p":
		out.append("PLAYER 1  -  keyboard and mouse: WASD move, mouse steers the weapon hand, left click swing, Space thrust")
		out.append("right click off hand / shield, E grab, Ctrl crouch, Shift sprint, C roll")
		out.append("PLAYER 2  -  gamepad: left stick move, right stick steers, right trigger swing, left trigger shield")
		return out
	if not has_touch or has_pad or not _touch_only(has_pad, has_touch):
		out.append("WASD move  |  mouse steers your weapon hand  |  left click swing  |  Space thrust")
		out.append("right click off hand / shield  |  E grab  |  Ctrl crouch / kneel  |  Shift sprint  |  C roll")
	if has_pad:
		out.append("Gamepad: left stick move, right stick steers, right trigger swing, right bumper thrust, left trigger shield, X roll")
	if has_touch:
		out.append("Touch: left thumb moves, drag on the right to aim and swing, buttons for thrust, off hand, grab and roll")
	return out


static func _touch_only(has_pad: bool, has_touch: bool) -> bool:
	return has_touch and not has_pad
