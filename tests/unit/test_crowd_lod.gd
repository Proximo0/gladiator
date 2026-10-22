extends TestCase
## Crowd LOD proxies (Crowd.decimated levels 1 and 2): every body part survives, so far spectators keep their heads.


func _two_part_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: int in 2:
		var sphere := SphereMesh.new()
		sphere.radius = 0.1 if part == 0 else 0.2
		sphere.height = sphere.radius * 2.0
		var arr: Array = sphere.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var off := Vector3(0.0, 1.6 if part == 0 else 1.0, 0.0)
		for i: int in idx:
			st.set_color(Color(0, 1, 0) if part == 0 else Color(1, 0, 0))
			st.set_normal(norms[i])
			st.add_vertex(verts[i] + off)
	st.index()
	return st.commit()


func test_parts_are_found_across_seams() -> void:
	var m: ArrayMesh = _two_part_mesh()
	var arr: Array = m.surface_get_arrays(0)
	assert_eq(Crowd.mesh_parts(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX]).size(), 2)


func test_proxy_levels_keep_every_part_and_cut_triangles() -> void:
	var m: ArrayMesh = _two_part_mesh()
	var full: int = (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for lod: int in [1, 2]:
		var low: Mesh = Crowd.decimated(m, lod)
		var arr: Array = low.surface_get_arrays(0)
		var tris: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_true(tris < full, "lod %d: %d < %d" % [lod, tris, full])
		assert_eq(Crowd.mesh_parts(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX]).size(), 2, "lod %d keeps the head" % lod)
		var top: float = -INF
		for v: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			top = maxf(top, v.y)
		assert_true(top > 1.6, "head still on top at lod %d" % lod)


func test_proxy_faces_point_outward() -> void:
	var low: Mesh = Crowd.decimated(_two_part_mesh(), 1)
	var arr: Array = low.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var centre := Vector3(0.0, 1.6, 0.0)
	for t: int in range(0, idx.size(), 3):
		var a: Vector3 = verts[idx[t]]
		if a.y < 1.4:
			continue
		var n: Vector3 = (verts[idx[t + 1]] - a).cross(verts[idx[t + 2]] - a)
		assert_true(n.dot(a - centre) < 0.0, "clockwise from outside (Godot front face)")
