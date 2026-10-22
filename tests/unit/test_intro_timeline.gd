extends TestCase


func test_phases_in_order() -> void:
	var tl := IntroTimeline.new(2.0, 0.8, true)
	assert_eq(tl.phase(), IntroTimeline.PLATES)
	assert_true(tl.holding())
	tl.advance(1.99)
	assert_eq(tl.phase(), IntroTimeline.PLATES)
	tl.advance(0.02)
	assert_eq(tl.phase(), IntroTimeline.FIGHT)
	assert_false(tl.holding(), "the fighters are free from FIGHT!'s first frame")
	tl.advance(0.8)
	assert_true(tl.done())
	assert_eq(tl.phase(), "")


func test_skip_goes_to_fight_then_ends() -> void:
	var tl := IntroTimeline.new(2.0, 0.8, true)
	tl.advance(0.3)
	assert_true(tl.skip())
	assert_eq(tl.phase(), IntroTimeline.FIGHT)
	assert_true(tl.skip())
	assert_true(tl.done())
	assert_false(tl.skip(), "nothing left to skip")


func test_online_cannot_skip_and_never_runs_back() -> void:
	var tl := IntroTimeline.new(2.0, 0.8, false)
	assert_false(tl.skip())
	tl.set_time(1.0)
	tl.set_time(0.5)  # a late snapshot
	assert_near(tl.t, 1.0)
	tl.set_time(2.5)
	assert_eq(tl.phase(), IntroTimeline.FIGHT)


func test_plates_slide_in_and_out() -> void:
	var tl := IntroTimeline.new(2.0, 0.8, true)
	assert_near(tl.plate_in(), 0.0)
	tl.advance(1.0)
	assert_near(tl.plate_in(), 1.0)
	tl.advance(1.0 + IntroTimeline.OUT_S)
	assert_near(tl.plate_in(), 0.0)


func test_stinger_punches_then_fades() -> void:
	var tl := IntroTimeline.new(2.0, 0.8, true)
	assert_eq(tl.stinger(), Vector2.ZERO)
	tl.advance(2.0)
	assert_near(tl.stinger().x, 1.8, 0.01)
	assert_near(tl.stinger().y, 1.0)
	tl.advance(IntroTimeline.PUNCH_S)
	assert_near(tl.stinger().x, 1.0, 0.01)
	tl.advance(0.8 - IntroTimeline.PUNCH_S - 0.01)
	assert_true(tl.stinger().y < 0.1, "faded at the end")


func test_zero_plates_is_just_the_stinger() -> void:
	var tl := IntroTimeline.new(0.0, 0.8, true)
	assert_eq(tl.phase(), IntroTimeline.FIGHT)
	assert_false(tl.holding())
