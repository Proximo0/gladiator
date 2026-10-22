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
	assert_eq(union, 4095, "all twelve button bits covered")


func test_every_button_action_has_a_device_binding() -> void:
	for action: String in InputBindings.BUTTON_ACTIONS:
		var bound: bool = InputBindings.KEYS.has(action) or InputBindings.MOUSE.has(action) \
			or InputBindings.PAD_BUTTONS.has(action) or InputBindings.PAD_TRIGGERS.has(action)
		assert_true(bound, "no binding for %s" % action)


func test_default_device_is_auto_everywhere() -> void:
	# A Windows touch laptop reports a touchscreen; keyboard and mouse must still drive the fighter.
	assert_eq(InputReader.default_device(false, {}), "auto")
	assert_eq(InputReader.default_device(true, {}), "auto")


func test_merge_inputs_first_active_device_wins() -> void:
	var pad := FighterInput.new()
	var kbm := FighterInput.new()
	kbm.move_y = 1000
	kbm.aim_x = 300
	kbm.buttons = 1
	pad.buttons = 2
	var m: FighterInput = InputReader.merge_inputs([pad, kbm] as Array[FighterInput])
	assert_eq(m.move_y, 1000, "keyboard moves when the stick is idle")
	assert_eq(m.aim_x, 300)
	assert_eq(m.buttons, 3, "buttons from every device")
	pad.move_x = -500
	m = InputReader.merge_inputs([pad, kbm] as Array[FighterInput])
	assert_eq(m.move_x, -500, "a moved stick overrides the keys")
	assert_eq(m.move_y, 0)


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
	assert_eq(layout.size(), 10)
	var bits: int = 0
	for b: Dictionary in layout:
		var c: Vector2 = b["center"]
		assert_true(c.x > AREA.x * 0.5, "button %s on right half" % b["label"])
		assert_true(c.y > 0.0 and c.y < AREA.y, "button %s on screen" % b["label"])
		bits |= int(b["bit"])
	assert_eq(bits, FighterInput.OFFHAND | FighterInput.THRUST | FighterInput.HALF_SWORD \
		| FighterInput.SPRINT | FighterInput.GRAB | FighterInput.ROLL | FighterInput.CROUCH | FighterInput.SHOVE \
		| FighterInput.KICK | FighterInput.CLINCH)


func test_touch_button_hit_test() -> void:
	var layout: Array = TouchControls.button_layout(AREA)
	for b: Dictionary in layout:
		assert_eq(TouchControls.button_at(b["center"], layout), int(b["bit"]), str(b["label"]))
	assert_eq(TouchControls.button_at(Vector2(10.0, 10.0), layout), 0, "top-left corner is no button")


func test_touch_buttons_are_thumb_sized_and_apart_on_a_phone() -> void:
	var area: Vector2 = Vector2(1920.0, 4160.0)  # a 540x1170 phone under the 1920-wide expand stretch
	var k: float = 540.0 / 1920.0
	var layout: Array = TouchControls.button_layout(area, k, Vector4(0.0, 0.0, 0.0, 40.0) / k)
	for b: Dictionary in layout:
		assert_true(float(b["radius"]) * k >= 28.0, "%s is at least 56 px across" % b["label"])
		var c: Vector2 = b["center"]
		assert_true(c.x * k > 540.0 * 0.5 and c.x * k + float(b["radius"]) * k <= 540.0, "%s on the right, on screen" % b["label"])
		assert_true((c.y + float(b["radius"])) * k <= 1170.0 - 40.0, "%s clear of the bottom inset" % b["label"])
	for i: int in layout.size():
		for j: int in range(i + 1, layout.size()):
			var d: float = (layout[i]["center"] as Vector2).distance_to(layout[j]["center"])
			assert_true(d >= float(layout[i]["radius"]) + float(layout[j]["radius"]), "%s and %s do not overlap" % [layout[i]["label"], layout[j]["label"]])


func test_touch_buttons_leave_the_aim_area_free() -> void:
	for area: Vector2 in [Vector2(2340.0, 1080.0), Vector2(1920.0, 4160.0), Vector2(1280.0, 720.0)]:
		var k: float = 540.0 / minf(area.x, area.y) if area.x != 1280.0 else 1.0
		var width_px: float = 0.0
		var height_px: float = 0.0
		for b: Dictionary in TouchControls.button_layout(area, k):
			var c: Vector2 = b["center"]
			width_px = maxf(width_px, (area.x - c.x + float(b["radius"])) * k)
			height_px = maxf(height_px, (area.y - c.y + float(b["radius"])) * k)
		assert_true(width_px < area.x * k * 0.42, "buttons use under 42%% of the width at %s" % area)
		assert_true(height_px < area.y * k * 0.55, "buttons use under 55%% of the height at %s" % area)


func test_emulated_mouse_buttons_do_not_count() -> void:
	# A phone's first finger is also a left mouse button; it must not read as SWING.
	assert_false(InputReader.mouse_button_counts(true))
	assert_true(InputReader.mouse_button_counts(false))


func test_touch_buttons_fit_a_real_phone_by_dpi() -> void:
	# 2400x1080 at 420 dpi: 9 to 14 mm across; a tablet's big short side no longer makes huge buttons.
	var phone: float = TouchControls.button_radius_px(1080.0, 420.0)
	assert_true(phone * 2.0 / 420.0 * 25.4 >= 9.0, "phone button %.0f px" % phone)
	var tablet: float = TouchControls.button_radius_px(1600.0, 280.0)
	assert_true(tablet * 2.0 / 280.0 * 25.4 <= 14.01, "tablet button %.0f px" % tablet)
	assert_near(TouchControls.button_radius_px(540.0), 540.0 * TouchControls.BUTTON_RADIUS_FRAC, 0.01, "no dpi: share of the short side")


func test_touch_toggles_are_offhand_half_sword_and_crouch() -> void:
	assert_eq(TouchControls.TOGGLE_BITS, FighterInput.OFFHAND | FighterInput.HALF_SWORD | FighterInput.CROUCH)
