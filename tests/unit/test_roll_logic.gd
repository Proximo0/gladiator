extends TestCase
## RollLogic: press edge, stamina and cooldown gating, direction, the motion curves and the limited guard.


func test_press_edge_only() -> void:
	var r := RollLogic.new()
	assert_true(r.press(true, true, 1.0, 0.2))
	r.start(Vector2(1, 0))
	assert_false(r.press(true, true, 1.0, 0.2), "holding does not start another")
	r.t = -1.0
	assert_false(r.press(true, true, 1.0, 0.2), "still held")
	assert_false(r.press(false, true, 1.0, 0.2))
	assert_true(r.press(true, true, 1.0, 0.2))


func test_gates() -> void:
	var r := RollLogic.new()
	assert_false(r.can_start(false, 1.0, 0.2), "not standing")
	assert_false(r.can_start(true, 0.1, 0.2), "no stamina")
	r.cooldown = 0.5
	assert_false(r.can_start(true, 1.0, 0.2), "cooling down")
	r.cooldown = 0.0
	assert_true(r.can_start(true, 0.2, 0.2))


func test_direction_defaults_back() -> void:
	var r := RollLogic.new()
	r.start(Vector2.ZERO)
	assert_eq(r.dir, Vector2(0, -1))
	r.start(Vector2(0.0, 0.5))
	assert_eq(r.dir, Vector2(0, 1))


func test_tick_ends_and_cools_down() -> void:
	var r := RollLogic.new()
	r.start(Vector2(1, 0))
	var ended: int = 0
	for _k: int in range(60):
		if r.tick(1.0 / 60.0, 0.8, 1.0):
			ended += 1
	assert_eq(ended, 1)
	assert_false(r.active())
	assert_near(r.cooldown, 1.0 - (60 - 48) / 60.0, 0.03)
	for _k: int in range(80):
		r.tick(1.0 / 60.0, 0.8, 1.0)
	assert_near(r.cooldown, 0.0, 0.0001)


func test_curves() -> void:
	assert_near(RollLogic.spin(0.0), 0.0, 0.0001)
	assert_near(RollLogic.spin(RollLogic.TUCK_END), 0.0, 0.0001)
	assert_near(RollLogic.spin(RollLogic.OPEN_START), TAU, 0.0001)
	assert_near(RollLogic.spin(1.0), TAU, 0.0001)
	assert_near(RollLogic.tuck(0.5), 1.0, 0.0001)
	assert_near(RollLogic.tuck(1.0), 0.0, 0.0001)
	assert_true(RollLogic.drive(0.05) > 0.5 and RollLogic.drive(0.99) < 0.1)
	# The rate integrates to one full turn.
	var a: float = 0.0
	for k: int in range(800):
		a += RollLogic.spin_rate((k + 0.5) / 800.0, 0.8) * 0.8 / 800.0
	assert_near(a, TAU, 0.01)


func test_guard_is_limited_and_brief() -> void:
	assert_near(RollLogic.guard_scale(true, 0.3, 0.6, 0.1, 0.55), 0.6, 0.0001)
	assert_near(RollLogic.guard_scale(true, 0.8, 0.6, 0.1, 0.55), 1.0, 0.0001)
	assert_near(RollLogic.guard_scale(false, 0.3, 0.6, 0.1, 0.55), 1.0, 0.0001)
	assert_true(RollLogic.guard_scale(true, 0.3, 0.0, 0.1, 0.55) >= 0.0)


func test_axis_tips_top_toward_direction() -> void:
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-0.6, 0, 0.8)]:
		var up: Vector3 = Basis(RollLogic.axis(d), 0.5) * Vector3.UP
		assert_true(up.dot(d) > 0.4)


func test_round_trip() -> void:
	var r := RollLogic.new()
	r.press(true, true, 1.0, 0.2)
	r.start(Vector2(-1, 0))
	r.tick(0.1, 0.8, 1.0)
	var q := RollLogic.new()
	q.from_array(r.to_array())
	assert_eq(q.to_array(), r.to_array())
