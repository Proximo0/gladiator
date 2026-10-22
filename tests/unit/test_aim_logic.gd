extends TestCase

const VP: Vector2 = Vector2(1920.0, 1080.0)


func test_trail_ages_out_and_caps() -> void:
	var t := AimLogic.new()
	t.max_age = 0.2
	for i: int in 30:
		t.push(Vector3(float(i) * 0.01, 0.0, 0.0), 0.02)
	assert_true(t.count() <= 11, "only samples younger than max_age remain")
	assert_eq(t.age_frac(t.count() - 1), 0.0)
	assert_true(t.age_frac(0) > 0.5)


func test_trail_restarts_on_a_jump() -> void:
	var t := AimLogic.new()
	t.push(Vector3.ZERO, 0.016)
	t.push(Vector3(0.1, 0, 0), 0.016)
	t.push(Vector3(9.0, 0, 0), 0.016)
	assert_eq(t.count(), 1)


func test_edge_marker_on_screen_and_clamped() -> void:
	var on: Dictionary = AimLogic.edge_marker(Vector2(900, 500), false, VP, 40.0)
	assert_true(bool(on["on_screen"]))
	var off: Dictionary = AimLogic.edge_marker(Vector2(5000, 540), false, VP, 40.0)
	assert_false(bool(off["on_screen"]))
	assert_near((off["pos"] as Vector2).x, VP.x - 40.0, 0.01)
	assert_near((off["pos"] as Vector2).y, 540.0, 0.01)
	assert_near(float(off["angle"]), 0.0, 0.01)


func test_edge_marker_behind_camera_flips() -> void:
	# Mirrored projection left of centre means the real target is to the right; behind is always off-screen.
	var m: Dictionary = AimLogic.edge_marker(Vector2(800, 540), true, VP, 40.0)
	assert_false(bool(m["on_screen"]))
	assert_true((m["pos"] as Vector2).x > VP.x * 0.5)
	var straight: Dictionary = AimLogic.edge_marker(VP * 0.5, true, VP, 40.0)
	assert_near((straight["pos"] as Vector2).y, VP.y - 40.0, 0.01)


func test_nearest() -> void:
	assert_eq(AimLogic.nearest(Vector3.ZERO, []), -1)
	assert_eq(AimLogic.nearest(Vector3.ZERO, [Vector3(5, 0, 0), Vector3(0, 0, 2), Vector3(-3, 0, 0)]), 1)


func test_lost_timer_and_prompt() -> void:
	assert_eq(AimLogic.lost_time(0.0, false, false, 0.1), 0.0, "never armed: no prompt")
	assert_near(AimLogic.lost_time(0.0, true, false, 0.1), 0.1, 0.0001)
	assert_near(AimLogic.lost_time(0.1, false, false, 0.1), 0.2, 0.0001)
	assert_eq(AimLogic.lost_time(0.5, false, true, 0.1), 0.0)
	assert_false(AimLogic.prompt_due(0.2, 0.4, true))
	assert_true(AimLogic.prompt_due(0.5, 0.4, true))
	assert_false(AimLogic.prompt_due(0.5, 0.4, false))


func test_wording_per_device() -> void:
	assert_eq(AimLogic.grab_key("touch"), "GRAB")
	assert_eq(AimLogic.grab_key("pad"), "A")
	assert_eq(AimLogic.grab_key("kbm"), "E")
	assert_true(AimLogic.pickup_hint("kbm").contains("E"))
	assert_true(AimLogic.pickup_hint("touch").contains("GRAB"))
