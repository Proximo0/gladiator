What happened: On a phone the first finger is also Godot's emulated left mouse button, so "auto" input read it as SWING: walking with the left thumb swung the sword (sim_touch, 210 of 210 ticks)
Rule: Ignore mouse events with `device == InputEvent.DEVICE_ID_EMULATION` wherever mouse buttons are read; prove touch with synthetic `InputEventScreenTouch` through `Input.parse_input_event`
