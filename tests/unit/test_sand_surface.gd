extends TestCase


func _make() -> SandSurface:
	var s: SandSurface = SandSurface.new()
	s.setup(4.0, 20.0, 0.5)
	return s


func test_stamp_changes_height_and_drag_digs() -> void:
	var s: SandSurface = _make()
	assert_near(s.height_at(Vector3(1, 0, 1)), 0.0)
	s.stamp(Vector3(1, 0, 1), 0.2, 0.04)
	assert_true(s.height_at(Vector3(1, 0, 1)) < -0.03)
	s.drag(Vector3(-2, 0, 0), Vector3(-1, 0, 0), 0.1, 0.03)
	assert_true(s.height_at(Vector3(-1.5, 0, 0)) < -0.02)
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
	assert_near(s.height_at(wall), base, 0.0001)
	s.stamp(wall, 0.2, 0.04)
	assert_true(s.height_at(wall) < base - 0.02, "stamp digs into the pile")
	s.clear()
	assert_near(s.height_at(wall), base, 0.0001)
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
