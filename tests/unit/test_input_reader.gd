extends TestCase

const AREA: Vector2 = Vector2(1280.0, 720.0)


func test_keys_move_cardinal_and_diagonal() -> void:
	assert_eq(InputReader.keys_move(true, false, false, false), Vector2i(1000, 0))
	assert_eq(InputReader.keys_move(false, false, false, true), Vector2i(0, -1000))
	assert_eq(InputReader.keys_move(false, false, false, false), Vector2i.ZERO)
	assert_eq(InputReader.keys_move(true, true, false, false), Vector2i.ZERO, "opposite keys cancel")
	assert_eq(InputReader.keys_move(true, false, true, false), Vector2i(707, 707), "diagonal scaled to unit length")


func test_stick_deadzone_and_scaling() -> void:
	assert_eq(InputReader.stick_units(Vector2(0.1, 0.1), 0.15), Vector2i.ZERO, "inside the deadzone")
	assert_eq(InputReader.stick_units(Vector2(1.0, 0.0), 0.15), Vector2i(1000, 0))
	assert_eq(InputReader.stick_units(Vector2(0.575, 0.0), 0.15), Vector2i(500, 0), "rescaled past the deadzone")


func test_stick_y_is_flipped_to_forward_positive() -> void:
	# Engine stick y is positive when pushed down, so pushing up (negative y) is forward.
	assert_eq(InputReader.stick_units(Vector2(0.0, -1.0), 0.15), Vector2i(0, 1000))
	assert_eq(InputReader.stick_units(Vector2(0.0, 1.0), 0.15), Vector2i(0, -1000))


func test_stick_clamps_beyond_unit_circle() -> void:
	var v: Vector2i = InputReader.stick_units(Vector2(3.0, 4.0), 0.15)
	assert_true(Vector2(v).length() <= 1000.5, "length %s" % str(v))
	assert_true(v.x > 0 and v.y < 0, "direction kept, y flipped")


func test_aim_step_accumulates_with_sensitivity() -> void:
	var a: Vector2 = InputReader.aim_step(Vector2.ZERO, Vector2(10.0, 10.0), 2.0)
	assert_near(a.x, 20.0)
	assert_near(a.y, -20.0, 0.0001, "mouse down is aim down")


func test_aim_step_clamps() -> void:
	var a: Vector2 = InputReader.aim_step(Vector2(995.0, 0.0), Vector2(100.0, 0.0), 1.0)
	assert_near(a.x, 1000.0)
	var b: Vector2 = InputReader.aim_step(Vector2(0.0, -995.0), Vector2(0.0, 100.0), 1.0)
	assert_near(b.y, -1000.0)


func test_recentre_pulls_toward_zero_without_overshoot() -> void:
	var a: Vector2 = InputReader.recentre(Vector2(10.0, -3.0), 20.0)
	assert_near(a.x, 0.0)
	assert_near(a.y, 0.0)
	var b: Vector2 = InputReader.recentre(Vector2(1000.0, 0.0), 6.0)
	assert_near(b.x, 994.0)


func test_to_units_rounds() -> void:
	assert_eq(InputReader.to_units(Vector2(10.4, -10.6)), Vector2i(10, -11))


func test_pad_index() -> void:
	assert_eq(InputReader.pad_index("pad0"), 0)
	assert_eq(InputReader.pad_index("pad1"), 1)
	assert_eq(InputReader.pad_index("kbm"), -1)
	assert_eq(InputReader.pad_index("touch"), -1)
	assert_eq(InputReader.pad_index("pad"), -1)


func test_trigger_threshold() -> void:
	assert_true(InputReader.trigger_pressed(0.6))
	assert_false(InputReader.trigger_pressed(0.4))


func test_button_mask_ors_known_actions_only() -> void:
	var mask: int = InputBindings.button_mask(PackedStringArray(["swing", "sprint", "nope"]))
	assert_eq(mask, FighterInput.SWING | FighterInput.SPRINT)
	assert_eq(InputBindings.button_mask(PackedStringArray()), 0)


func test_every_button_action_has_a_unique_bit() -> void:
	var union: int = 0
	var seen: int = 0
	for action: String in InputBindings.BUTTON_ACTIONS:
		var bit: int = InputBindings.bit_for_action(action)
		assert_true(bit != 0, action)
		assert_eq(seen & bit, 0, "duplicate bit for %s" % action)
		seen |= bit
		union |= bit
	assert_eq(union, 255, "all eight button bits covered")


func test_every_button_action_has_a_device_binding() -> void:
	for action: String in InputBindings.BUTTON_ACTIONS:
		var bound: bool = InputBindings.KEYS.has(action) or InputBindings.MOUSE.has(action) \
			or InputBindings.PAD_BUTTONS.has(action) or InputBindings.PAD_TRIGGERS.has(action)
		assert_true(bound, "no binding for %s" % action)


func test_default_device_follows_touch_availability() -> void:
	assert_eq(InputReader.default_device(false, {}), "kbm")
	assert_eq(InputReader.default_device(true, {}), "touch")
	assert_eq(InputReader.default_device(false, {"touch": "1"}), "touch", "--touch forces the overlay")


func test_touch_should_show() -> void:
	assert_false(TouchControls.should_show(false, {}))
	assert_true(TouchControls.should_show(true, {}))
	assert_true(TouchControls.should_show(false, {"touch": "1"}))


func test_touch_offset_units() -> void:
	assert_eq(InputReader.offset_units(Vector2(0.0, -100.0), 100.0), Vector2i(0, 1000), "drag up is forward")
	assert_eq(InputReader.offset_units(Vector2(0.0, 100.0), 100.0), Vector2i(0, -1000))
	assert_eq(InputReader.offset_units(Vector2(300.0, 0.0), 100.0), Vector2i(1000, 0), "clamped to the radius")
	assert_eq(InputReader.offset_units(Vector2(50.0, 0.0), 100.0), Vector2i(500, 0))
	assert_eq(InputReader.offset_units(Vector2(50.0, 0.0), 0.0), Vector2i.ZERO, "no radius, no motion")


func test_touch_left_half_split() -> void:
	assert_true(TouchControls.in_left_half(10.0, 100.0))
	assert_false(TouchControls.in_left_half(50.0, 100.0))
	assert_false(TouchControls.in_left_half(100.0, 100.0))


func test_touch_clamp_offset() -> void:
	assert_eq(TouchControls.clamp_offset(Vector2(300.0, 0.0), 100.0), Vector2(100.0, 0.0))
	assert_eq(TouchControls.clamp_offset(Vector2(30.0, 0.0), 100.0), Vector2(30.0, 0.0))


func test_touch_button_layout_lives_on_the_right() -> void:
	var layout: Array = TouchControls.button_layout(AREA)
	assert_eq(layout.size(), 5)
	var bits: int = 0
	for b: Dictionary in layout:
		var c: Vector2 = b["center"]
		assert_true(c.x > AREA.x * 0.5, "button %s on right half" % b["label"])
		assert_true(c.y > 0.0 and c.y < AREA.y, "button %s on screen" % b["label"])
		bits |= int(b["bit"])
	assert_eq(bits, FighterInput.OFFHAND | FighterInput.THRUST | FighterInput.HALF_SWORD \
		| FighterInput.SPRINT | FighterInput.GRAB)


func test_touch_button_hit_test() -> void:
	var layout: Array = TouchControls.button_layout(AREA)
	for b: Dictionary in layout:
		assert_eq(TouchControls.button_at(b["center"], layout), int(b["bit"]), str(b["label"]))
	assert_eq(TouchControls.button_at(Vector2(10.0, 10.0), layout), 0, "top-left corner is no button")
