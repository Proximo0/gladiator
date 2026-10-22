extends TestCase


func test_dead_zone_swallows_a_resting_thumb() -> void:
	assert_eq(TouchFeel.stick_units(Vector2(5.0, 5.0), 100.0), Vector2i.ZERO, "inside the stick dead zone")
	assert_eq(TouchFeel.aim_units(Vector2(2.0, 0.0), 100.0), Vector2i.ZERO, "inside the aim dead zone")
	assert_eq(TouchFeel.stick_units(Vector2(50.0, 0.0), 0.0), Vector2i.ZERO, "no radius, no motion")


func test_output_starts_from_zero_past_the_dead_zone() -> void:
	var just: Vector2i = TouchFeel.stick_units(Vector2(100.0 * TouchFeel.STICK_DEAD + 1.0, 0.0), 100.0)
	assert_true(just.x > 0 and just.x < 30, "no jump at the edge: %s" % just)


func test_stick_reaches_full_before_the_ring() -> void:
	assert_eq(TouchFeel.stick_units(Vector2(0.0, -100.0 * TouchFeel.STICK_FULL), 100.0), Vector2i(0, 1000), "drag up is forward")
	assert_eq(TouchFeel.stick_units(Vector2(300.0, 0.0), 100.0), Vector2i(1000, 0), "clamped")


func test_aim_is_linear_and_y_up() -> void:
	var half: Vector2i = TouchFeel.aim_units(Vector2(0.0, 51.5), 100.0)
	assert_eq(half.x, 0)
	assert_true(half.y < -490 and half.y > -510, "half a radius down is about -500: %s" % half)
	assert_eq(TouchFeel.aim_units(Vector2(-100.0, 0.0), 100.0), Vector2i(-1000, 0))


func test_expo_softens_the_centre() -> void:
	var lin: Vector2 = TouchFeel.shape(Vector2(50.0, 0.0), 100.0, 0.0, 1.0, 0.0)
	var cub: Vector2 = TouchFeel.shape(Vector2(50.0, 0.0), 100.0, 0.0, 1.0, 1.0)
	assert_near(lin.x, 0.5)
	assert_near(cub.x, 0.125)


func test_anchor_follows_a_finger_past_the_ring() -> void:
	assert_eq(TouchFeel.follow_anchor(Vector2.ZERO, Vector2(50.0, 0.0), 100.0), Vector2.ZERO, "inside: anchor stays")
	var a: Vector2 = TouchFeel.follow_anchor(Vector2.ZERO, Vector2(250.0, 0.0), 100.0)
	assert_near(a.x, 150.0)
	assert_near((Vector2(250.0, 0.0) - a).length(), 100.0, 0.001, "finger sits on the ring")


func test_size_by_share_or_millimetres() -> void:
	assert_near(TouchFeel.size_px(1000.0, 0.1, 0.0, 5.0, 10.0, 0.0), 100.0)
	assert_near(TouchFeel.size_px(100.0, 0.1, 0.0, 5.0, 10.0, 32.0), 32.0, 0.001, "pixel floor without dpi")
	assert_near(TouchFeel.size_px(4000.0, 0.1, 254.0, 5.0, 10.0, 0.0), 100.0, 0.001, "capped at 10 mm by dpi")
	assert_near(TouchFeel.size_px(100.0, 0.1, 254.0, 5.0, 10.0, 0.0), 50.0, 0.001, "raised to 5 mm by dpi")


func test_hold_grab_crouches_and_repeats() -> void:
	var g: int = FighterInput.GRAB
	var c: int = FighterInput.CROUCH
	assert_eq(TouchFeel.tick_buttons(0, 0, 0), 0)
	assert_eq(TouchFeel.tick_buttons(g, 0, 1), g | c, "first tick grabs")
	assert_eq(TouchFeel.tick_buttons(g, 0, TouchFeel.GRAB_PULSE_TICKS + 1), c, "then lets go, still crouched")
	assert_eq(TouchFeel.tick_buttons(g, 0, 2 * TouchFeel.GRAB_PULSE_TICKS + 1), g | c, "and grabs again")
	assert_eq(TouchFeel.tick_buttons(g, 0, 0), 0, "GRAB bit alone never passes without the counter")


func test_toggles_and_held_buttons_add_up() -> void:
	var t: int = FighterInput.OFFHAND
	var h: int = FighterInput.SWING | FighterInput.THRUST
	assert_eq(TouchFeel.tick_buttons(h, t, 0), h | t)
