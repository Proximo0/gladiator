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
	assert_near(RollLogic.spin(RollLogic.DIP_END), RollLogic.LEAN_IN, 0.0001)
	assert_near(RollLogic.spin(RollLogic.OPEN_START), TAU, 0.0001)
	assert_near(RollLogic.spin(1.0), TAU, 0.0001)
	assert_near(RollLogic.tuck(0.5), 1.0, 0.0001)
	assert_near(RollLogic.tuck(1.0), 0.0, 0.0001)
	assert_true(RollLogic.drive(0.99) < 0.1)
	# The rate integrates to one full turn, and its peak stays near 1.25x the turn's mean rate.
	var a: float = 0.0
	var peak: float = 0.0
	for k: int in range(800):
		var r: float = RollLogic.spin_rate((k + 0.5) / 800.0, 0.8)
		a += r * 0.8 / 800.0
		if (k + 0.5) / 800.0 > RollLogic.DIP_END:
			peak = maxf(peak, r)
	assert_near(a, TAU, 0.01)
	var mean: float = (TAU - RollLogic.LEAN_IN) / ((RollLogic.OPEN_START - RollLogic.DIP_END) * 0.8)
	assert_true(peak < mean * 1.3)


func test_dip_comes_before_tuck() -> void:
	# The dip stands on planted feet: no tuck and no drive yet; the tuck closes only after it.
	for u: float in [0.05, 0.15, RollLogic.DIP_END - 0.01]:
		assert_near(RollLogic.tuck(u), 0.0, 0.0001)
		assert_near(RollLogic.drive(u), 0.0, 0.0001)
		assert_true(RollLogic.dip(u) > 0.0)
	assert_near(RollLogic.dip(RollLogic.DIP_END), 1.0, 0.0001)
	assert_near(RollLogic.dip(0.5), 1.0, 0.0001)
	assert_near(RollLogic.dip(1.0), 0.0, 0.0001)
	assert_true(RollLogic.spin(RollLogic.DIP_END) < 0.6)


func test_crossed_fires_once() -> void:
	var n: int = 0
	var t: float = 0.0
	for k: int in range(80):
		t += 1.0 / 60.0
		if RollLogic.crossed(t, 1.0 / 60.0, 1.0, RollLogic.OPEN_START):
			n += 1
	assert_eq(n, 1)
	assert_false(RollLogic.crossed(-1.0, 1.0 / 60.0, 1.0, 0.5))


func test_leg_tuck_holds_then_opens() -> void:
	var r := RollLogic.new()
	assert_near(r.hold_leg_tuck(1.0, 0.5, 1.0), 0.0, 0.0001)  # not rolling
	r.start(Vector2(0, 1))
	assert_near(r.hold_leg_tuck(0.2, 0.35, 0.5), 0.2, 0.0001)
	assert_near(r.hold_leg_tuck(0.9, 0.45, 1.0), 0.9, 0.0001)
	assert_near(r.hold_leg_tuck(0.1, 0.6, 1.0), 0.9, 0.0001)  # the feet do not come back down mid-turn
	assert_near(r.hold_leg_tuck(1.0, 0.85, 0.4), 0.4, 0.0001)  # opening follows the body tuck out
	r.start(Vector2(0, 1))
	assert_near(r.leg_tuck, 0.0, 0.0001)


func test_shoulder_axis_mirrors() -> void:
	assert_near(RollLogic.shoulder_side(Vector2(1, 0)), -RollLogic.shoulder_side(Vector2(-1, 0)), 0.0001)
	var d := Vector3(0, 0, -1)
	var a: Vector3 = RollLogic.axis(d, 0.8)
	assert_near(a.length(), 1.0, 0.0001)
	assert_near(a.dot(d), 0.0, 0.0001)  # still across the roll
	assert_true(absf(a.y) > 0.5)  # tipped toward one shoulder


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
	r.hold_leg_tuck(0.7, 0.5, 1.0)
	var q := RollLogic.new()
	q.from_array(r.to_array())
	assert_eq(q.to_array(), r.to_array())
