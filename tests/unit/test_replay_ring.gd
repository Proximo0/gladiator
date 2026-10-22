extends TestCase
## ReplayRing: the pose ring buffer behind the instant replay (wrap-around, tick lookup, gaps, events, blending).


func _frame_at(x: float, n: int = 2) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	for i: int in n:
		ReplayRing.write_pose(f, i, Transform3D(Basis(), Vector3(x, float(i), 0.0)))
	return f


func test_keeps_only_the_newest_capacity_ticks() -> void:
	var r := ReplayRing.new(5)
	for t: int in range(0, 12):
		r.push(t, _frame_at(float(t)))
	assert_eq(r.size(), 5)
	assert_eq(r.oldest_tick(), 7)
	assert_eq(r.newest_tick(), 11)
	for t: int in range(7, 12):
		assert_near(ReplayRing.pose(r.frame(t), 0).origin.x, float(t), 0.0001, "tick %d" % t)
	assert_false(r.has_tick(6))
	assert_near(ReplayRing.pose(r.frame(2), 0).origin.x, 7.0, 0.0001, "clamped to the oldest")


func test_a_gap_starts_over() -> void:
	var r := ReplayRing.new(8)
	for t: int in 4:
		r.push(t, _frame_at(float(t)))
	r.push_event(2, 0, "hit", {}, 0)
	r.push(10, _frame_at(10.0))
	assert_eq(r.size(), 1)
	assert_eq(r.oldest_tick(), 10)
	assert_true(r.events.is_empty())


func test_events_older_than_the_buffer_are_dropped() -> void:
	var r := ReplayRing.new(3)
	for t: int in 3:
		r.push(t, _frame_at(float(t)))
		r.push_event(t, 1, "hit", {"t": t}, t * 10)
	r.push(3, _frame_at(3.0))
	assert_eq(r.events.size(), 2)
	assert_eq(int((r.events[0] as Array)[0]), 1)
	assert_eq(r.events_in(2, 2).size(), 1)
	assert_eq(int((r.events_in(2, 2)[0] as Array)[4]), 20)


func test_pose_round_trip_and_absent_bodies() -> void:
	var f := PackedFloat32Array()
	var xf := Transform3D(Basis(Vector3.UP, 0.7), Vector3(1, 2, 3))
	ReplayRing.write_pose(f, 2, xf)
	assert_eq(f.size(), 3 * ReplayRing.STRIDE)
	assert_false(ReplayRing.has_pose(f, 0), "gap before is absent")
	assert_true(ReplayRing.has_pose(f, 2))
	assert_false(ReplayRing.has_pose(f, 3), "past the end is absent")
	var back: Transform3D = ReplayRing.pose(f, 2)
	assert_true(back.origin.is_equal_approx(xf.origin))
	assert_true(back.basis.get_rotation_quaternion().is_equal_approx(xf.basis.get_rotation_quaternion()))
	ReplayRing.write_absent(f, 2)
	assert_false(ReplayRing.has_pose(f, 2))


func test_blend_lerps_and_falls_back() -> void:
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	ReplayRing.write_pose(a, 0, Transform3D(Basis(), Vector3.ZERO))
	ReplayRing.write_pose(b, 0, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(2, 0, 0)))
	var m: Dictionary = ReplayRing.blend(a, b, 0, 0.5)
	assert_true(bool(m["ok"]))
	assert_near((m["xf"] as Transform3D).origin.x, 1.0, 0.0001)
	assert_near((m["xf"] as Transform3D).basis.get_euler().y, PI * 0.25, 0.001)
	ReplayRing.write_pose(b, 1, Transform3D(Basis(), Vector3(5, 0, 0)))  # appears only in the later frame
	var n: Dictionary = ReplayRing.blend(a, b, 1, 0.3)
	assert_true(bool(n["ok"]))
	assert_near((n["xf"] as Transform3D).origin.x, 5.0, 0.0001)
	assert_false(bool(ReplayRing.blend(a, a, 1, 0.3)["ok"]))


func test_sample_between_ticks_and_byte_count() -> void:
	var r := ReplayRing.new(10)
	for t: int in 4:
		r.push(t, _frame_at(float(t) * 2.0, 3))
	var s: Dictionary = r.sample(1.25, 0)
	assert_near((s["xf"] as Transform3D).origin.x, 2.5, 0.0001)
	assert_eq(r.frame_bytes(), 4 * 3 * ReplayRing.STRIDE * 4)
