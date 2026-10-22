extends TestCase

const DT: float = 1.0 / 60.0


func _flat(_p: Vector3) -> float:
	return 0.0


func _cols() -> Array:
	var pal: BloodPalette = BloodPalette.red()
	var rc: Array = []
	var bc: Array = []
	for i: int in 3:
		rc.append(pal.gut_color(float(i) / 2.0))
		bc.append(pal.organ_color(float(i) / 2.0))
	return [[rc, rc], [bc, bc]]


func _rope(at: Vector3, slot: int = 0) -> GutRope:
	var r: GutRope = GutRope.new()
	r.setup(6, 0.1, 0.04, 0.5, at, Vector3.DOWN, 1.0, 5.0, slot, 0.5)
	return r


func test_caps_drop_the_oldest_rope_and_chunk() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(3, 2)
	for i: int in 5:
		s.add_rope(_rope(Vector3(float(i), 1, 0)))
		s.add_blob(Vector3(float(i), 1, 0), Vector3.ZERO, 0.05, 0.0, 0, 0.1)
	assert_eq(s.rope_count(), 3)
	assert_eq(s.blob_count(), 2)
	assert_eq(s.ropes[0].order, 2, "the two oldest were dropped")
	assert_near(s.blob_pos[0].x, 3.0)
	s.set_caps(1, 1)
	assert_eq(s.rope_count(), 1)
	assert_eq(s.blob_count(), 1)
	s.set_caps(0, 0)
	assert_true(s.add_rope(_rope(Vector3.ZERO)) == null)


func test_chunks_fall_bounce_and_sleep_on_the_sand() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(2, 4)
	s.add_blob(Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 0), 0.06, 0.0, 1, 0.3)
	var landed: int = 0
	for i: int in 60 * 6:
		s.step(DT, 9.8, PackedVector3Array(), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.3)
		landed += s.touches.size()
	assert_true(landed >= 1, "reports the landing")
	assert_eq(s.blob_asleep[0], 1, "comes to rest")
	assert_true(s.blob_pos[0].y >= 0.0)
	assert_true(s.blob_pos[0].y < 0.1)
	assert_true(s.all_asleep())


func test_touches_carry_the_slot_and_are_capped() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(8, 8)
	for i: int in 8:
		s.add_blob(Vector3(float(i), 0.04, 0), Vector3(0, -3, 0), 0.06, 0.0, 1, 0.3)
	s.step(DT, 9.8, PackedVector3Array(), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.3)
	assert_true(s.touches.size() <= GutSim.MAX_TOUCHES)
	assert_true(s.touches.size() > 0)
	for sl: int in s.touch_slots:
		assert_eq(sl, 1)


func test_write_fills_one_instance_per_link_and_chunk_with_the_slots_colour() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(2, 2)
	s.reserve(s.max_instances(6))
	s.add_rope(_rope(Vector3(0, 1, 0), 1))
	s.add_blob(Vector3(0, 0.1, 0), Vector3.ZERO, 0.06, 0.0, 0, 0.3)
	s.step(DT, 9.8, PackedVector3Array([Vector3(0, 1, 0)]), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.3)
	var n: int = s.write(_cols()[0], _cols()[1])
	assert_eq(n, 5 + 1)
	assert_false(s.dirty)
	assert_eq(s.buf.size(), s.max_instances(6) * GutSim.STRIDE)
	for i: int in n:
		var o: int = i * GutSim.STRIDE
		assert_near(s.buf[o + 15], 1.0)
		# basis columns are finite and have a non-zero scale
		assert_true(Vector3(s.buf[o], s.buf[o + 4], s.buf[o + 8]).length() > 0.001)


func test_all_asleep_stops_marking_the_buffer_dirty() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(2, 2)
	s.reserve(s.max_instances(6))
	s.add_rope(_rope(Vector3(0, 0.2, 0)))
	for i: int in 60 * 6:
		s.step(DT, 9.8, PackedVector3Array([Vector3(0, 0.2, 0)]), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.3)
	assert_true(s.all_asleep())
	s.write([[Color.RED]], [[Color.RED]])
	s.step(DT, 9.8, PackedVector3Array([Vector3(0, 0.2, 0)]), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.3)
	assert_false(s.dirty)


func test_palette_gut_colours_follow_the_fighters_blood() -> void:
	var red: BloodPalette = BloodPalette.red()
	var alien: BloodPalette = OutfitRules.blood_palette("alien")
	var gr: Color = red.gut_color(0.5)
	var ga: Color = alien.gut_color(0.5)
	assert_true(gr.r > gr.g and gr.r > gr.b, "red guts are reddish pink")
	assert_true(_dist(gr, ga) > 0.05 or _dist(red.flesh, alien.flesh) < 0.05, "ichor guts differ from red ones")
	assert_true(red.organ_color(0.0).v < gr.v, "organs are darker than intestine")
	assert_eq(red.organ_color(0.3).a, 1.0)


func test_quality_scales_gut_budgets_in_order() -> void:
	assert_true(BloodMath.gut_mult(0) < BloodMath.gut_mult(1))
	assert_true(BloodMath.gut_mult(1) < BloodMath.gut_mult(2))
	assert_true(BloodMath.gut_cap(14.0, 0) < BloodMath.gut_cap(14.0, 2))
	assert_true(BloodMath.gut_segs(9.0, 0) < BloodMath.gut_segs(9.0, 2))
	assert_eq(BloodMath.gut_segs(1.0, 0), 4)


func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
