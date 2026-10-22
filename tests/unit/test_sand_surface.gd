extends TestCase


func _make() -> SandSurface:
	var s: SandSurface = SandSurface.new()
	s.setup(4.0, 20.0, 0.5)
	return s


func test_stamp_changes_height_and_drag_digs() -> void:
	var s: SandSurface = _make()
	var lift: float = Tuning.shared().sand_lift
	assert_near(s.height_at(Vector3(1, 0, 1)), lift)
	s.stamp(Vector3(1, 0, 1), 0.2, 0.04)
	assert_true(s.height_at(Vector3(1, 0, 1)) < lift - 0.07, "a 4 cm press digs several cm")
	s.drag(Vector3(-2, 0, 0), Vector3(-1, 0, 0), 0.1, 0.03)
	assert_true(s.height_at(Vector3(-1.5, 0, 0)) < lift - 0.04)
	s.free()


func test_blood_and_clear() -> void:
	var s: SandSurface = _make()
	s.add_blood(Vector3(0.5, 0, 0.5), 0.1, 0.1)
	assert_true(s.blood_at(Vector3(0.5, 0, 0.5)) > 0.1)
	s.flush()
	s.clear()
	assert_near(s.blood_at(Vector3(0.5, 0, 0.5)), 0.0)
	s.free()


func test_disc_mesh_is_clockwise_up() -> void:
	var m: ArrayMesh = SandSurface.build_disc_mesh(2.0, 0.5)
	var arrays: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_true(idx.size() > 0 and idx.size() % 3 == 0)
	var nrm: Vector3 = (v[idx[1]] - v[idx[0]]).cross(v[idx[2]] - v[idx[0]])
	assert_true(nrm.y < 0.0, "clockwise from above means cross points down")


func test_piles_are_part_of_height_and_survive_clear() -> void:
	var s: SandSurface = _make()
	var wall: Vector3 = Vector3(3.8, 0, 0)
	var base: float = s.base_height_at(wall)
	assert_true(base > 0.01, "wall drift %f" % base)
	var lifted: float = base + SandMap.lift_at(wall.x, wall.z, 4.0, Tuning.shared().sand_lift)
	assert_near(s.height_at(wall), lifted, 0.0001)
	s.stamp(wall, 0.2, 0.04)
	assert_true(s.height_at(wall) < lifted - 0.02, "stamp digs into the pile")
	s.clear()
	assert_near(s.height_at(wall), lifted, 0.0001)
	s.free()


func test_effects_throw_grains() -> void:
	var s: SandSurface = _make()
	s.spray(Vector3(0, 0, 0), Vector3(2, 1, 0), 0.8)
	assert_true(s._fx.count > 10, "spray throws grains")
	s.clear()
	assert_eq(s._fx.count, 0)
	s.drag(Vector3(0, 0, 0), Vector3(0.1, 0, 0), 0.025, 0.012)
	assert_true(s._fx.count > 0, "a fast tip drag throws sand")
	s.free()


func test_pool_spreading_is_throttled_but_keeps_time() -> void:
	var s: SandSurface = _make()
	s.add_blood(Vector3(0.5, 0, 0.5), 0.3, 0.5)
	assert_eq(s._pools.size(), 1)
	s._spread_pools(0.001)
	assert_near(float(s._pools[0]["t"]), 0.0, 0.0001, "a tiny step waits")
	s._spread_pools(0.2)
	assert_near(float(s._pools[0]["t"]), 0.201, 0.0001, "the waiting time is not lost")
	s.free()


func test_quality_sizes_the_grain_pool() -> void:
	var old: int = GfxQuality.level
	GfxQuality.set_level(GfxQuality.LOW)
	var s: SandSurface = SandSurface.new()
	s.setup(4.0, 20.0, 0.5)
	assert_eq(s._fx.capacity, GfxQuality.SAND_GRAINS[0])
	s.free()
	GfxQuality.set_level(old)


func test_red_and_ichor_share_the_sand() -> void:
	var s: SandSurface = _make()
	s.add_blood(Vector3(-1.0, 0, 0.5), 0.15, 0.2, 0)
	s.add_blood(Vector3(1.0, 0, 0.5), 0.15, 0.2, 1)
	assert_eq(s.blood_slot_at(Vector3(-1.0, 0, 0.5)), 0)
	assert_eq(s.blood_slot_at(Vector3(1.0, 0, 0.5)), 1)
	s.flush()
	s.set_blood_palette(1, Color(0.1, 0.5, 0.4), Color(0.03, 0.2, 0.15), 0.3)
	s.clear()
	assert_eq(s.blood_slot_at(Vector3(1.0, 0, 0.5)), 0, "clear resets the colour map")
	s.free()


func test_fall_digs_a_crater_with_berms_and_dust() -> void:
	var s: SandSurface = _make()
	var lift: float = Tuning.shared().sand_lift
	s.stamp_capsule(Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0), 0.2, 0.062)
	assert_true(s.height_at(Vector3.ZERO) < lift - 0.12, "deep crater %f" % s.height_at(Vector3.ZERO))
	var berm: float = 0.0
	for k in range(30):
		berm = maxf(berm, s.height_at(Vector3(0.0, 0, 0.2 + 0.01 * k)))
	assert_true(berm > lift + 0.02, "berm beside the crater %f" % berm)
	assert_true(s._fx.count > 40, "a fall throws many grains")
	assert_true(s._dust.count > 5, "and dust")
	assert_true(s.height_at(Vector3.ZERO) > lift - SandMap.H_MAX - 0.3, "bounded")
	s.free()


func test_footstep_kicks_grains_and_dust() -> void:
	var s: SandSurface = _make()
	s.stamp_ellipse(Vector3(1, 0, 0), 0.06, 0.14, 0.0, 0.018, Vector3(0.5, 0, 0))
	assert_true(s._fx.count >= 4, "step grains %d" % s._fx.count)
	assert_true(s._dust.count >= 1, "step dust")
	s.free()


func test_low_quality_caps_grains_and_dust() -> void:
	var old: int = GfxQuality.level
	GfxQuality.set_level(GfxQuality.LOW)
	var s: SandSurface = SandSurface.new()
	s.setup(4.0, 20.0, 0.5)
	for i in range(30):
		s.stamp_capsule(Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0), 0.15, 0.062)
	assert_true(s._fx.count <= GfxQuality.SAND_GRAINS[0])
	assert_true(s._dust.count <= GfxQuality.SAND_DUST[0])
	s.free()
	GfxQuality.set_level(old)
