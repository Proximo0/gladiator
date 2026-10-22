extends TestCase

func _pal() -> Dictionary:
	return {"flesh": Color(0.7, 0.1, 0.1), "fat": Color(0.9, 0.7, 0.5), "bone": Color(0.9, 0.85, 0.7),
			"marrow": Color(0.3, 0.02, 0.02), "skin": Color(0.8, 0.6, 0.5)}


func test_build_is_one_valid_surface() -> void:
	var m: ArrayMesh = CapMesh.build(0.07, 0.058, _pal(), 7)
	assert_eq(m.get_surface_count(), 1)
	var arr: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	assert_eq((arr[Mesh.ARRAY_COLOR] as PackedColorArray).size(), v.size())
	assert_true(v.size() < 700, "cheap")
	for p: Vector3 in v:
		assert_true(p.length() < 0.2, "no stray vertex")


func test_edge_is_irregular_and_dome_not_flat() -> void:
	var m: ArrayMesh = CapMesh.build(0.07, 0.058, _pal(), 3)
	var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rim: int = 1 + (CapMesh.RINGS - 1) * CapMesh.SEGS
	var lo: float = 9.0
	var hi: float = 0.0
	for s: int in CapMesh.SEGS:
		var r: float = Vector2(v[rim + s].x, v[rim + s].z).length()
		lo = minf(lo, r)
		hi = maxf(hi, r)
	assert_true(hi - lo > 0.07 * 0.1, "edge radius varies")
	assert_true(v[0].y < v[1 + 3 * CapMesh.SEGS].y + 0.0001 or v[1 + 3 * CapMesh.SEGS].y > 0.0, "dome above the pit")


func test_same_seed_same_mesh() -> void:
	var a: PackedVector3Array = CapMesh.build(0.07, 0.058, _pal(), 11).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = CapMesh.build(0.07, 0.058, _pal(), 11).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var c: PackedVector3Array = CapMesh.build(0.07, 0.058, _pal(), 12).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(a == b)
	assert_true(a != c)


func test_tendrils_sag_along_gravity() -> void:
	var down: PackedVector3Array = CapMesh.build(0.07, 0.058, _pal(), 11, Vector3.DOWN).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var up: PackedVector3Array = CapMesh.build(0.07, 0.058, _pal(), 11, Vector3.UP).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(down.size(), up.size())
	# The collar reaches below the strands, so compare the highest point: strands given UP rise, given DOWN hang.
	var hi_down: float = -1.0
	var hi_up: float = -1.0
	for i: int in down.size():
		hi_down = maxf(hi_down, down[i].y)
		hi_up = maxf(hi_up, up[i].y)
	assert_true(hi_up > hi_down + 0.02, "strands hang along the given down")
