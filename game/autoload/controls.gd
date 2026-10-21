extends Node
## Input actions, registered in code so they live in one readable place. Gameplay device bindings (keys, mouse,
## gamepad) come from InputBindings, which InputReader reads too. `debug_stamp` is required by game/debug/frame_stamp.gd.

## action -> [physical keys]: pause and debug keys
const DEBUG_KEYS: Dictionary = {
	"debug_stamp": [KEY_F10],
	"debug_overlay": [KEY_F1],
	"debug_slowmo": [KEY_F2],
	"debug_freeze": [KEY_F3],
	"debug_step": [KEY_PERIOD],
	"debug_save_recording": [KEY_F12],
	"debug_tuning": [KEY_QUOTELEFT],
	"pause": [KEY_ESCAPE],
}


func _ready() -> void:
	for action: String in DEBUG_KEYS:
		_ensure(action)
		for k: Key in DEBUG_KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action: String in InputBindings.KEYS:
		_ensure(action)
		for k: int in InputBindings.KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k as Key
			InputMap.action_add_event(action, e)
	for action: String in InputBindings.MOUSE:
		_ensure(action)
		for b: int in InputBindings.MOUSE[action]:
			var e := InputEventMouseButton.new()
			e.button_index = b as MouseButton
			InputMap.action_add_event(action, e)
	for action: String in InputBindings.PAD_BUTTONS:
		_ensure(action)
		for b: int in InputBindings.PAD_BUTTONS[action]:
			var e := InputEventJoypadButton.new()
			e.button_index = b as JoyButton
			InputMap.action_add_event(action, e)
	for action: String in InputBindings.PAD_TRIGGERS:
		_ensure(action)
		var t := InputEventJoypadMotion.new()
		t.axis = InputBindings.PAD_TRIGGERS[action] as JoyAxis
		t.axis_value = 1.0
		InputMap.action_add_event(action, t)
	for action: String in InputBindings.PAD_STICKS:
		_ensure(action)
		var data: Array = InputBindings.PAD_STICKS[action]
		var s := InputEventJoypadMotion.new()
		s.axis = data[0] as JoyAxis
		s.axis_value = float(data[1])
		InputMap.action_add_event(action, s)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
