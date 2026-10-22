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
	["Crouch / kneel", "Ctrl", "B", "CROUCH button (tap on, tap off)"],
	["Grab / pick up", "E", "A", "Hold GRAB (bends down and picks up)"],
	["Dodge roll (move direction)", "C", "X", "ROLL button"],
	["Shove (free hand, shield or shoulder)", "F", "D-pad up", "SHOVE button"],
	["Front kick", "V", "D-pad down", "KICK button"],
	["Grab the foe's weapon arm (aim high: head), hold to keep", "G", "D-pad left", "HOLD button"],
	["Lock turning", "Alt", "Right stick press", "-"],
	["Pause", "Esc", "Start", "Menu key"],
]


## Hint lines for the first seconds of a fight, for the devices in use. Always starts with the keyboard and mouse
## line unless the match is touch-only.
static func hint_lines(mode: String, has_pad: bool, has_touch: bool) -> Array:
	var out: Array = []
	if mode == "local_2p":
		out.append("PLAYER 1  -  keyboard and mouse: WASD move, mouse steers the weapon hand, left click swing, Space thrust")
		out.append("right click off hand / shield, E grab, Ctrl crouch, Shift sprint, C roll, F shove, V kick, G hold")
		out.append("PLAYER 2  -  gamepad: left stick move, right stick steers, right trigger swing, left trigger shield")
		return out
	if not has_touch or has_pad or not _touch_only(has_pad, has_touch):
		out.append("WASD move  |  mouse steers your weapon hand  |  left click swing  |  Space thrust")
		out.append("right click off hand / shield  |  E grab  |  Ctrl crouch / kneel  |  Shift sprint  |  C roll")
		out.append("F shove  |  V front kick  |  G grab the foe's weapon arm (aim high for the head), hold to keep")
	if has_pad:
		out.append("Gamepad: left stick move, right stick steers, right trigger swing, right bumper thrust, left trigger shield, X roll, D-pad up shove, down kick, left grab foe")
	if has_touch:
		out.append("Touch: left thumb moves, drag on the right to aim and swing, buttons for thrust, off hand, roll, shove, kick and hold")
		out.append("CROUCH and OFF toggle (tap on, tap off); hold GRAB to bend down and pick up a weapon")
	return out


static func _touch_only(has_pad: bool, has_touch: bool) -> bool:
	return has_touch and not has_pad


## Short hint for the first seconds of a fight: one or two brief lines for the device in use (touch, gamepad, or
## keyboard and mouse), so it can sit small at the top edge without covering the fight. Each lists the close-range
## moves (shove, kick, hold).
static func compact_lines(mode: String, has_pad: bool, has_touch: bool) -> Array:
	if mode == "local_2p":
		return ["P1: WASD, mouse steers, click swing, Space thrust", "P2 pad: left stick move, right stick steers, RT swing, LT shield"]
	if has_touch and not has_pad:
		return ["Left thumb: move   Right drag: aim   SHOVE  KICK  HOLD up close",
			"CROUCH toggles   hold GRAB to pick up a weapon"]
	var out: Array = []
	if has_pad:
		out.append("L stick move  R stick aim  RT swing  RB thrust  LT shield  X roll  D-pad shove/kick/hold")
	if not has_pad or not has_touch:
		out.append("WASD  Mouse aim  Click swing  Space thrust  RMB shield  E grab  C roll")
	if not has_pad:
		out.append("Up close:  F shove   V kick   hold G to grab the foe")
	return out
