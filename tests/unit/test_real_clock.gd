extends TestCase


func test_uses_the_scale_the_frame_began_with() -> void:
	var c := RealClock.new()
	var dt: float = 1.0 / 60.0
	assert_near(c.step(dt, 1.0), dt)
	# Slow motion starts during this frame's physics: Godot already scaled this delta by 1.0.
	assert_near(c.step(dt, 0.2), dt)
	# The next frame's delta is scaled by 0.2.
	assert_near(c.step(dt * 0.2, 0.2), dt)
	# Back to full speed during this frame: its delta was still scaled by 0.2.
	assert_near(c.step(dt * 0.2, 1.0), dt)
	assert_near(c.step(dt, 1.0), dt)


func test_bad_values_are_harmless() -> void:
	var c := RealClock.new()
	assert_eq(c.step(NAN, 1.0), 0.0)
	c.step(0.01, 0.0)
	assert_near(c.prev_scale, 1.0, 0.0001, "a zero scale is ignored")
