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


func test_write_fills_links_a_torn_end_a_tangle_and_chunks_per_kind() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(2, 2)
	s.reserve(6)
	var r: GutRope = s.add_rope(_rope(Vector3(0, 1, 0), 1))
	r.cluster = true
	s.add_blob(Vector3(0, 0.1, 0), Vector3.ZERO, 0.06, 0.0, 0, 0.3)
	s.step(DT, 9.8, PackedVector3Array([Vector3(0, 1, 0)]), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.3)
	var n: int = s.write(_cols()[0], _cols()[1])
	assert_eq(n, 5 + 1 + 1 + 1)
	assert_eq(s.counts[GutSim.K_LINK], 5)
	assert_eq(s.counts[GutSim.K_TORN], 1)
	assert_eq(s.counts[GutSim.K_CLUSTER], 1)
	assert_eq(s.counts[GutSim.K_COIL], 1)
	assert_eq(s.counts[GutSim.K_LIVER], 0)
	assert_false(s.dirty)
	for i: int in n:
		var o: int = i * GutSim.STRIDE
		assert_near(s.all[o + 15], 1.0)
		# basis columns are finite and have a non-zero scale
		assert_true(Vector3(s.all[o], s.all[o + 4], s.all[o + 8]).length() > 0.001)
	var cap: int = s.max_instances_of(GutSim.K_LINK, 6)
	var kb: PackedFloat32Array = s.kind_buffer(GutSim.K_LINK, cap)
	assert_eq(kb.size(), cap * GutSim.STRIDE, "padded to the MultiMesh size")
	assert_near(kb[3], s.all[3])
	var tb: PackedFloat32Array = s.kind_buffer(GutSim.K_TORN, s.max_instances_of(GutSim.K_TORN, 6))
	var torn_at: Vector3 = Vector3(tb[3], tb[7], tb[11])
	assert_true(torn_at.distance_to(r.pos[r.n - 1]) < 0.1, "the torn end sits on the rope's free end")
	var cb: PackedFloat32Array = s.kind_buffer(GutSim.K_CLUSTER, 2)
	assert_true(Vector3(cb[3], cb[7], cb[11]).distance_to(r.pos[0]) < 0.001, "the tangle sits on the wound")


func test_organs_have_their_own_cap_and_slide_leaving_smears() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(2, 1, 2)
	s.add_blob(Vector3(0, 0.5, 0), Vector3.ZERO, 0.05, 0.0, 0, 0.1)
	for i: int in 3:
		s.add_blob(Vector3(float(i), 0.3, 0), Vector3(2.5, 0, 0), 0.12, 0.0, 1, 0.2, GutSim.K_LIVER + i)
	assert_eq(s.blob_count(), 1, "chunks and organs are capped apart")
	assert_eq(s.organ_count(), 2)
	assert_eq(s.blob_kind[1], GutSim.K_STOMACH, "the oldest organ went first")
	s.organ_friction = 0.97
	s.smear_step = 0.1
	var start: float = s.blob_pos[1].x
	var smears: int = 0
	for i: int in 60 * 6:
		s.step(DT, 9.8, PackedVector3Array(), Callable(self, "_flat"), 0.99, 0.8, 0.06, 0.6, 0.2)
		smears += s.touches.size()
	assert_true(s.blob_pos[1].x - start > 0.4, "slides along the sand")
	assert_true(smears >= 4, "leaves a streak of smears, got %d" % smears)
	assert_true(s.all_asleep())
	var n: int = s.write(_cols()[0], _cols()[1])
	assert_eq(n, 3)
	assert_eq(s.counts[GutSim.K_STOMACH], 1)
	assert_eq(s.counts[GutSim.K_HEART], 1)


func test_organ_tones_keep_the_authored_colours_for_red_and_turn_for_ichor() -> void:
	var red: BloodPalette = BloodPalette.red()
	var alien: BloodPalette = OutfitRules.blood_palette("alien")
	for i: int in BloodPalette.ORGAN_TONES.size():
		assert_true(_dist(red.organ_tone(i), BloodPalette.ORGAN_TONES[i]) < 0.03, "red organ %d as authored" % i)
		if _dist(red.flesh, alien.flesh) > 0.05:
			assert_true(_dist(alien.organ_tone(i), red.organ_tone(i)) > 0.05, "ichor organ %d differs" % i)


func test_gut_art_meshes_are_normalised_and_coloured() -> void:
	for k: int in GutSim.KINDS:
		var m: Mesh = GutArt.mesh(k)
		assert_true(m != null and m.get_surface_count() == 1, "one merged surface for kind %d" % k)
		var arr: Array = m.surface_get_arrays(0)
		assert_true((arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0, "vertex colours baked")
		var ab: AABB = m.get_aabb()
		match k:
			GutSim.K_LINK:
				assert_near(ab.size.z, 2.0, 0.01)
				assert_near(ab.size.x, 2.0, 0.05)
			GutSim.K_TORN:
				assert_near(ab.position.z, 0.0, 0.01)
				assert_near(ab.end.z, 1.0, 0.01)
			_:
				assert_near(maxf(ab.size.x, ab.size.z), 2.0, 0.01)
		assert_true(GutArt.authored_size(k) > 0.0)
		assert_true(GutArt.floor_share(k) > 0.0)
	assert_true(GutArt.authored_size(GutSim.K_LIVER) > 0.1, "a liver keeps its authored size (about 0.13 m half width)")


func test_all_asleep_stops_marking_the_buffer_dirty() -> void:
	var s: GutSim = GutSim.new()
	s.set_caps(2, 2)
	s.reserve(6)
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
