extends TestCase
## ThrustPlan: THRUST press timing, closing speed, square-on, the end of a drive, reach and the closing plan.


func test_press_waits_for_the_body() -> void:
	assert_false(ThrustPlan.press_now(1.0, 3.0, 0.15, 0.2), "0.33 s out: too early")
	assert_true(ThrustPlan.press_now(0.4, 3.0, 0.15, 0.2), "0.13 s out")
	assert_true(ThrustPlan.press_now(0.15, 0.0, 0.15, 0.2), "already at the target")
	assert_false(ThrustPlan.press_now(0.5, 0.0, 0.15, 0.2), "not closing: the press would fall short")
	assert_false(ThrustPlan.press_now(0.5, -2.0, 0.15, 0.2), "parting")


func test_closing_speed() -> void:
	var dir := Vector3(0, 0, -1)
	assert_near(ThrustPlan.closing_speed(Vector3(0, 0, -3), Vector3.ZERO, dir), 3.0, 0.001)
	assert_near(ThrustPlan.closing_speed(Vector3(0, 0, -3), Vector3(0, 0, 2), dir), 5.0, 0.001, "the foe steps in too")
	assert_near(ThrustPlan.closing_speed(Vector3(2, 5, 0), Vector3.ZERO, dir), 0.0, 0.001, "sideways and up do not count")
	assert_true(ThrustPlan.closing_speed(Vector3(0, 0, 1), Vector3.ZERO, dir) < 0.0)


func test_square_on() -> void:
	# Foe at the origin facing -Z (yaw 0); I stand 2 m in front of him, then beside him, then behind.
	assert_true(ThrustPlan.square_on(0.0, Vector3.ZERO, Vector3(0, 0, -2), 0.8))
	assert_true(ThrustPlan.square_on(0.0, Vector3.ZERO, Vector3(0.5, 0, -2), 0.8), "a little off line")
	assert_false(ThrustPlan.square_on(0.0, Vector3.ZERO, Vector3(2, 0, 0), 0.8), "side on")
	assert_false(ThrustPlan.square_on(0.0, Vector3.ZERO, Vector3(0, 0, 2), 0.8), "behind him")
	assert_true(ThrustPlan.square_on(PI * 0.5, Vector3.ZERO, Vector3(-2, 0, 0), 0.8), "turned: yaw 90 faces -X")
	assert_false(ThrustPlan.square_on(0.0, Vector3.ZERO, Vector3.ZERO, 0.8), "same spot")


func test_drive_done() -> void:
	assert_false(ThrustPlan.drive_done(0.6, 0.6, 5, 30, 0.12, 0.2))
	assert_true(ThrustPlan.drive_done(0.1, 0.3, 5, 30, 0.12, 0.2), "arrived")
	assert_true(ThrustPlan.drive_done(0.55, 0.3, 5, 30, 0.12, 0.2), "went past")
	assert_true(ThrustPlan.drive_done(0.6, 0.6, 30, 30, 0.12, 0.2), "out of time")


func test_reach_of() -> void:
	assert_near(ThrustPlan.reach_of(0.7), 1.53, 0.001)
	assert_true(ThrustPlan.reach_of(2.2) > ThrustPlan.reach_of(1.05))


func test_close_step() -> void:
	var g: float = ThrustPlan.reach_of(0.7)  # gladius
	var l: float = ThrustPlan.reach_of(1.05)  # longsword
	assert_eq(ThrustPlan.close_step(2.0, l, g, false, 0.25, 0.5), ThrustPlan.CLOSE_NONE, "the longer weapon has no plan")
	assert_eq(ThrustPlan.close_step(2.0, g, g, false, 0.25, 0.5), ThrustPlan.CLOSE_NONE, "same reach")
	assert_eq(ThrustPlan.close_step(5.0, g, l, false, 0.25, 0.5), ThrustPlan.CLOSE_NONE, "far out: walk up")
	assert_eq(ThrustPlan.close_step(1.9, g, l, false, 0.25, 0.5), ThrustPlan.CLOSE_WAIT)
	assert_eq(ThrustPlan.close_step(1.9, g, l, true, 0.25, 0.5), ThrustPlan.CLOSE_RUSH, "he just swung")
	assert_eq(ThrustPlan.close_step(1.4, g, l, false, 0.25, 0.5), ThrustPlan.CLOSE_INSIDE)
