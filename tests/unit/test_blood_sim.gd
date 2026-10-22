extends TestCase


func _flat() -> Callable:
	return Callable()


func test_emit_fills_pool_and_refuses_when_full() -> void:
	var s: BloodSim = BloodSim.new(3)
	for i: int in 3:
		assert_true(s.emit(Vector3(0, 1, 0), Vector3.ZERO, 0.004, 1.0, 5.0, 0.5))
	assert_false(s.emit(Vector3(0, 1, 0), Vector3.ZERO, 0.004, 1.0, 5.0, 0.5))
	assert_eq(s.count, 3)
	assert_eq(s.free_slots(), 0)


func test_step_matches_math_helper() -> void:
	var s: BloodSim = BloodSim.new(4)
	s.emit(Vector3(0, 5, 0), Vector3(3, 2, -1), 0.003, 1.0, 5.0, 0.0)
	var v: Vector3 = BloodMath.step_velocity(Vector3(3, 2, -1), 0.016, 9.8, 0.003)
	s.step(0.016, 9.8, _flat(), PackedVector3Array(), 0.0, 0.0)
	var got: Vector3 = s.vel_of(0)
	assert_near(got.x, v.x, 0.0001)
	assert_near(got.y, v.y, 0.0001)
	assert_near(got.z, v.z, 0.0001)
	assert_near(s.pos_of(0).x, 3.0 * 0.016 * 0.99, 0.01)


func test_ballistic_arc_lands_near_vacuum_range() -> void:
	var s: BloodSim = BloodSim.new(2)
	s.emit(Vector3(0, 0.5, 0), Vector3(4, 0, 0), 0.01, 1.0, 5.0, 0.0)
	var t: float = 0.0
	while s.count > 0 and t < 3.0:
		s.step(0.01, 9.8, _flat(), PackedVector3Array(), 0.0, 0.0)
		if s.imp_pos.size() > 0:
			break
		t += 0.01
	assert_eq(s.imp_pos.size(), 1)
	var fall: float = sqrt(2.0 * 0.5 / 9.8)
	assert_near(t, fall, 0.04)
	assert_true(s.imp_pos[0].x < 4.0 * fall and s.imp_pos[0].x > 4.0 * fall * 0.9, "drag shortens the range")


func test_small_drops_fall_shorter_than_big_ones() -> void:
	var rng_x: Array[float] = []
	for r: float in [0.0015, 0.008]:
		var s: BloodSim = BloodSim.new(2)
		s.emit(Vector3(0, 1.0, 0), Vector3(6, 0, 0), r, 1.0, 5.0, 0.0)
		for i: int in 300:
			s.step(0.01, 9.8, _flat(), PackedVector3Array(), 0.0, 0.0)
			if s.imp_pos.size() > 0:
				rng_x.append(s.imp_pos[0].x)
				break
	assert_eq(rng_x.size(), 2)
	assert_true(rng_x[0] < rng_x[1])


func test_ground_uses_height_function() -> void:
	var s: BloodSim = BloodSim.new(2)
	var hf: Callable = func(_p: Vector3) -> float: return 0.05
	s.emit(Vector3(0, 0.07, 0), Vector3(0, -2, 0), 0.004, 1.0, 5.0, 0.0)
	s.step(0.02, 9.8, hf, PackedVector3Array(), 0.0, 0.0)
	assert_eq(s.imp_pos.size(), 1)
	assert_near(s.imp_pos[0].y, 0.05, 0.0001)


func test_compact_removes_dead_and_keeps_live() -> void:
	var s: BloodSim = BloodSim.new(8)
	for i: int in 5:
		s.emit(Vector3(float(i), 3, 0), Vector3.ZERO, 0.004, 1.0, 5.0, 0.0)
	s.kill(1)
	s.kill(4)
	s.compact()
	assert_eq(s.count, 3)
	var xs: Array[int] = []
	for i: int in s.count:
		xs.append(roundi(s.pos_of(i).x))
	xs.sort()
	assert_eq(xs, [0, 2, 3])
	s.kill(0)
	s.kill(1)
	s.kill(2)
	s.compact()
	assert_eq(s.count, 0)


func test_lifetime_expires() -> void:
	var s: BloodSim = BloodSim.new(2)
	s.emit(Vector3(0, 50, 0), Vector3.ZERO, 0.004, 1.0, 0.05, 0.0)
	for i: int in 10:
		s.step(0.01, 0.0, _flat(), PackedVector3Array(), 0.0, 0.0)
	s.compact()
	assert_eq(s.count, 0)


func test_near_list_respects_grace_and_reach() -> void:
	var s: BloodSim = BloodSim.new(4)
	s.emit(Vector3(0, 1, 0), Vector3(1, 0, 0), 0.004, 1.0, 5.0, 0.0)
	s.emit(Vector3(20, 1, 0), Vector3.ZERO, 0.004, 1.0, 5.0, 0.0)
	var reach: PackedVector3Array = PackedVector3Array([Vector3(0, 1, 0)])
	s.step(0.01, 9.8, _flat(), reach, 4.0, 0.5)
	assert_eq(s.near_idx.size(), 0, "grace period")
	s.step(0.6, 0.0, _flat(), reach, 4.0, 0.5)
	assert_eq(s.near_idx.size(), 1)
	assert_eq(s.near_idx[0], 0)


func test_mist_fades_and_expires() -> void:
	var m: BloodMist = BloodMist.new(4)
	assert_true(m.emit(Vector3.ZERO, Vector3(0, 1, 0), 0.05, 0.2, 0.5, 0.4, 0.0))
	m.step(0.25)
	assert_eq(m.count, 1)
	assert_true(m.buf[13] > 0.0 and m.buf[13] < 0.4)
	assert_true(m.buf[12] > 0.05)
	m.step(0.3)
	assert_eq(m.count, 0)
	assert_near(BloodMist.alpha_at(1.0, 0.4), 0.0)


func test_droplet_keeps_its_palette_slot_through_impact_and_compaction() -> void:
	var s: BloodSim = BloodSim.new(4)
	s.emit(Vector3(0, 5, 0), Vector3.ZERO, 0.004, 1.0, 5.0, 0.0, 0)
	s.emit(Vector3(1, 0.05, 0), Vector3(0, -3, 0), 0.004, 1.0, 5.0, 0.0, 1)
	assert_eq(s.slot_of(0), 0)
	assert_eq(s.slot_of(1), 1)
	s.step(0.05, 9.8, Callable(), PackedVector3Array(), 1.0, 0.05)
	assert_eq(s.imp_slot.size(), 1)
	assert_eq(s.imp_slot[0], 1)
	s.compact()
	assert_eq(s.count, 1)
	assert_eq(s.slot_of(0), 0)
