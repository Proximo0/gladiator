extends TestCase


func _tun() -> Tuning:
	return Tuning.new()


func test_strength_has_a_floor_and_finishers_are_full() -> void:
	var t: Tuning = _tun()
	assert_eq(ScreenPunchLogic.strength_for({}, t.feel_punch_min - 0.01, t), 0.0)
	var mid: float = ScreenPunchLogic.strength_for({}, 0.7, t)
	assert_true(mid > 0.0 and mid < 1.0)
	assert_near(ScreenPunchLogic.strength_for({}, 1.0, t), 1.0)
	assert_eq(ScreenPunchLogic.strength_for({"finisher": "behead"}, 0.1, t), 1.0)
	assert_true(ScreenPunchLogic.strength_for({"hit_on_weapon": true}, 1.0, t) < 1.0, "a clash punches less")


func test_kick_decays_to_nothing() -> void:
	var t: Tuning = _tun()
	var p := ScreenPunchLogic.new()
	assert_false(p.active())
	p.kick(1.0, false, Vector2(0.3, 0.6), false, t)
	assert_true(p.active())
	assert_near(p.blur(t), t.feel_punch_blur)
	assert_near(p.chroma(t), t.feel_punch_chroma)
	p.step(t.feel_punch_s * 0.5)
	assert_near(p.current(), 0.25, 0.001)
	p.step(t.feel_punch_s)
	assert_false(p.active())


func test_reduced_motion_keeps_only_a_soft_flash() -> void:
	var t: Tuning = _tun()
	var p := ScreenPunchLogic.new()
	p.kick(1.0, false, Vector2(0.5, 0.5), true, t)
	assert_eq(p.blur(t), 0.0)
	assert_eq(p.chroma(t), 0.0)
	assert_near(p.flash(t), t.feel_punch_flash * ScreenPunchLogic.REDUCED_FLASH_MULT)


func test_weaker_kick_does_not_cut_a_stronger_one() -> void:
	var t: Tuning = _tun()
	var p := ScreenPunchLogic.new()
	p.kick(1.0, false, Vector2(0.2, 0.2), false, t)
	p.kick(0.4, false, Vector2(0.8, 0.8), false, t)
	assert_near(p.center.x, 0.2)
	p.kick(0.5, true, Vector2(0.9, 0.1), false, t)
	assert_true(p.finisher, "a finisher always takes over")
	assert_true(p.length > t.feel_punch_s)


func test_grade_alone_keeps_it_active_and_taps_by_level() -> void:
	var p := ScreenPunchLogic.new()
	p.grade = 0.5
	assert_true(p.active())
	assert_eq(ScreenPunchLogic.taps_for(0), 0)
	assert_true(ScreenPunchLogic.taps_for(2) > ScreenPunchLogic.taps_for(1))
	assert_eq(ScreenPunchLogic.taps_for(9), ScreenPunchLogic.taps_for(2))
