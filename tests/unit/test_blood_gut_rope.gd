extends TestCase

const DT: float = 1.0 / 60.0


func _flat(_p: Vector3) -> float:
	return 0.0


func _rope(anchor: Vector3 = Vector3(0, 1.2, 0)) -> GutRope:
	var r: GutRope = GutRope.new()
	r.setup(9, 0.1, 0.04, 0.9, anchor, Vector3(1, -0.4, 0).normalized(), 2.5, 7.0, 1, 0.3)
	return r


func _run(r: GutRope, seconds: float, anchor: Vector3) -> void:
	var ground: Callable = Callable(self, "_flat")
	for i: int in int(seconds / DT):
		r.step(DT, 9.8, anchor, ground, 0.99, 0.8, 0.06, 0.6)


func test_grow_goes_from_a_stub_to_full_length() -> void:
	assert_near(GutRope.grow(0.0, 1.0), GutRope.MIN_GROW)
	assert_near(GutRope.grow(1.0, 1.0), 1.0)
	assert_near(GutRope.grow(5.0, 1.0), 1.0)
	assert_true(GutRope.grow(0.3, 1.0) < GutRope.grow(0.6, 1.0))


func test_rope_stays_pinned_to_the_wound_and_keeps_its_link_lengths() -> void:
	var r: GutRope = _rope()
	var a: Vector3 = Vector3(0, 1.2, 0)
	_run(r, 1.5, a)
	assert_near(r.pos[0].distance_to(a), 0.0, 0.0001)
	for i: int in r.n - 1:
		var d: float = r.pos[i].distance_to(r.pos[i + 1])
		assert_true(d < r.seg_full * 1.15, "link %d is %f" % [i, d])


func test_rope_hangs_down_from_the_wound_and_lies_on_the_sand() -> void:
	var r: GutRope = _rope(Vector3(0, 0.5, 0))
	_run(r, 4.0, Vector3(0, 0.5, 0))
	assert_true(r.asleep, "calm rope falls asleep")
	for i: int in r.n:
		assert_true(r.pos[i].y >= -0.0001, "above the sand")
	assert_true(r.pos[r.n - 1].y < 0.1, "the tip lies on the sand")
	assert_true(r.grounded_count() > 0)


func test_short_rope_dangles_from_a_high_wound() -> void:
	var r: GutRope = _rope()
	_run(r, 4.0, Vector3(0, 1.2, 0))
	assert_true(r.pos[r.n - 1].y > 0.2, "too short to reach the sand")
	assert_true(r.pos[r.n - 1].y < 1.2 - 0.5, "hangs below the wound")


func test_rope_never_sinks_below_the_ground() -> void:
	var r: GutRope = _rope(Vector3(0, 0.3, 0))
	_run(r, 3.0, Vector3(0, 0.3, 0))
	for i: int in range(1, r.n):
		assert_true(r.pos[i].y >= r.radius * 0.9 - 0.001)


func test_sleeping_rope_wakes_when_the_wound_moves() -> void:
	var r: GutRope = _rope(Vector3(0, 0.5, 0))
	_run(r, 4.0, Vector3(0, 0.5, 0))
	assert_true(r.asleep)
	var before: Vector3 = r.pos[r.n - 1]
	_run(r, 1.0, Vector3(0.6, 0.5, 0))
	assert_false(r.asleep and r.pos[r.n - 1].is_equal_approx(before), "dragged along")
	assert_near(r.pos[0].x, 0.6, 0.0001)


func test_touches_report_the_first_landing_once_per_point() -> void:
	var r: GutRope = _rope(Vector3(0, 0.5, 0))
	var seen: int = 0
	var ground: Callable = Callable(self, "_flat")
	for i: int in 240:
		r.step(DT, 9.8, Vector3(0, 0.5, 0), ground, 0.99, 0.8, 0.06, 0.6)
		seen += r.touches.size()
	assert_true(seen > 0)
	assert_true(seen <= r.n, "never more touches than points")


func test_rope_is_deterministic() -> void:
	var a: GutRope = _rope()
	var b: GutRope = _rope()
	_run(a, 1.0, Vector3(0, 1.2, 0))
	_run(b, 1.0, Vector3(0, 1.2, 0))
	for i: int in a.n:
		assert_eq(a.pos[i], b.pos[i])
