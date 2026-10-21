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
