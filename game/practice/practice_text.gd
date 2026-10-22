class_name PracticeText
extends RefCounted
## Prompt text for the Practice steps: a Roman heading (Latin / English) and one or two instruction lines per device.
## Pure strings. Devices: "kbm", "pad", "touch" (see device_for()).

const HEADINGS: Dictionary = {
	"move": ["AMBVLA", "Walk"],
	"aim": ["MIRA", "Steer your weapon hand"],
	"swing": ["FERI", "Swing fast"],
	"thrust": ["PVNGE", "Thrust"],
	"strike": ["PERCVTE", "Hit the dummy"],
	"roll": ["VOLVE", "Roll away"],
	"grab": ["CAPE", "Pick up a weapon"],
	"finish": ["CONFICE", "Finish him"],
}

## [device] -> line, per step.
const BODY: Dictionary = {
	"move": {
		"kbm": "Hold W A S D to walk around the sand.",
		"pad": "Push the left stick to walk around the sand.",
		"touch": "Hold your left thumb on the screen and drag to walk.",
	},
	"aim": {
		"kbm": "Move the mouse. Your weapon hand follows it, it is not a cursor. Sweep left, right, up and down.",
		"pad": "Push the right stick. Your weapon hand follows it. Sweep left, right, up and down.",
		"touch": "Drag a finger on the right half of the screen. Your hand follows the offset. Sweep it around.",
	},
	"swing": {
		"kbm": "Hold left click and whip the mouse across. Only a tip speed over %s m/s hurts anyone.",
		"pad": "Hold the right trigger and flick the right stick across. Only a tip speed over %s m/s hurts anyone.",
		"touch": "Drag fast on the right side while it is held. Only a tip speed over %s m/s hurts anyone.",
	},
	"thrust": {
		"kbm": "Press Space while you aim at the dummy: the hand drives forward. Speed matters here too.",
		"pad": "Press the right bumper while you aim at the dummy: the hand drives forward.",
		"touch": "Tap THRUST while you aim at the dummy: the hand drives forward.",
	},
	"strike": {
		"kbm": "Walk up to the dummy and cut it with a fast swing or a thrust. Slow touches do nothing.",
		"pad": "Walk up to the dummy and cut it with a fast swing or a thrust. Slow touches do nothing.",
		"touch": "Walk up to the dummy and cut it with a fast swing or a thrust. Slow touches do nothing.",
	},
	"roll": {
		"kbm": "Hold a direction and press C. You tumble that way (backward when still).",
		"pad": "Hold a direction and press X. You tumble that way (backward when still).",
		"touch": "Hold a direction and tap ROLL. You tumble that way (backward when still).",
	},
	"grab": {
		"kbm": "Your weapon has been dropped at your feet. Walk so it lies just ahead of you, hold Ctrl and tap E to bend down and take it.",
		"pad": "Your weapon has been dropped at your feet. Walk so it lies just ahead of you, hold B and press A to bend down and take it.",
		"touch": "Your weapon has been dropped at your feet. Walk onto it and hold GRAB to bend down and take it.",
	},
	"finish": {
		"kbm": "The dummy is nearly drained. A strong hit now kills outright: swing hard at the neck, gut or head.",
		"pad": "The dummy is nearly drained. A strong hit now kills outright: swing hard at the neck, gut or head.",
		"touch": "The dummy is nearly drained. A strong hit now kills outright: swing hard at the neck, gut or head.",
	},
}

const SKIP_HINT: Dictionary = {
	"kbm": "N: skip step     Esc: menu",
	"pad": "Back: skip step     Start: menu",
	"touch": "Tap SKIP to skip a step",
}
const FREE_HINT: Dictionary = {
	"kbm": "R: reset dummy     T: next weapon     Esc: menu",
	"pad": "Y: reset dummy     D-pad right: next weapon     Start: menu",
	"touch": "Use the buttons below",
}


## "touch" when only touch is present, "pad" when a gamepad is connected, else "kbm".
static func device_for(has_pad: bool, has_touch: bool) -> String:
	if has_pad:
		return "pad"
	if has_touch:
		return "touch"
	return "kbm"


static func heading(step_id: String) -> Array:
	return HEADINGS.get(step_id, ["", ""])


static func body(step_id: String, device: String, min_speed: float = 3.0) -> String:
	var per: Dictionary = BODY.get(step_id, {})
	var s: String = str(per.get(device, per.get("kbm", "")))
	if s.contains("%s"):
		s = s % ("%.0f" % min_speed)
	return s


static func skip_hint(device: String) -> String:
	return str(SKIP_HINT.get(device, SKIP_HINT["kbm"]))


static func free_hint(device: String) -> String:
	return str(FREE_HINT.get(device, FREE_HINT["kbm"]))


## "STEP 3 OF 8" style line.
static func step_line(index: int, total: int) -> String:
	return "Step %d of %d" % [index + 1, total]
