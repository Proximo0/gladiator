extends TestCase


func test_threshold_has_back_row_bias_and_cap() -> void:
	var near: float = CrowdCull.threshold(100, 11.6, 11.6)
	var far: float = CrowdCull.threshold(100, 21.6, 11.6)
	assert_near(near, CrowdMood.threshold_for(100))
	assert_true(far > near, "back rows cheer later")
	assert_true(CrowdCull.threshold(100, 90.0, 11.6) <= CrowdCull.MAX_THRESHOLD)


func test_order_sorts_and_is_stable() -> void:
	var thr := PackedFloat32Array([0.5, 0.2, 0.5, 0.9])
	assert_eq(Array(CrowdCull.order(thr, true)), [1, 0, 2, 3])
	assert_eq(Array(CrowdCull.order(thr, false)), [3, 0, 2, 1])


func test_cheering_group_grows_with_excitement() -> void:
	var thr := PackedFloat32Array([0.2, 0.4, 0.4, 0.8])
	assert_eq(CrowdCull.shown_count(thr, true, 0.0), 0)
	assert_eq(CrowdCull.shown_count(thr, true, 0.21), 1)
	assert_eq(CrowdCull.shown_count(thr, true, 0.5), 3)
	assert_eq(CrowdCull.shown_count(thr, true, 1.0), 4)


func test_calm_group_shrinks_and_never_cheerers_stay() -> void:
	var thr := PackedFloat32Array([CrowdCull.NEVER, 0.8, 0.4, 0.2])
	assert_eq(CrowdCull.shown_count(thr, false, 0.0), 4)
	assert_eq(CrowdCull.shown_count(thr, false, 0.5), 2)
	assert_eq(CrowdCull.shown_count(thr, false, 1.0), 1, "the seat that never cheers is always drawn")


func test_twins_partition_every_seat() -> void:
	# At any excitement each seat shows exactly one twin: calm count + cheer count == seats.
	var seats: PackedFloat32Array = PackedFloat32Array()
	for s: int in 40:
		seats.append(CrowdCull.threshold(s * 37, 12.0 + float(s % 5), 11.6))
	var up: PackedFloat32Array = PackedFloat32Array()
	for i: int in CrowdCull.order(seats, true):
		up.append(seats[i])
	var down: PackedFloat32Array = PackedFloat32Array()
	for i: int in CrowdCull.order(seats, false):
		down.append(seats[i])
	for e: float in [0.0, 0.1, 0.3, 0.5, 0.7, 0.95, 1.0]:
		assert_eq(CrowdCull.shown_count(up, true, e) + CrowdCull.shown_count(down, false, e), seats.size(), "e=%f" % e)


func test_decimated_mesh_has_fewer_triangles() -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 32
	sphere.rings = 16
	var full_idx: PackedInt32Array = sphere.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var low: Mesh = Crowd.decimated(sphere, 1)
	var low_idx: PackedInt32Array = low.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	assert_true(low_idx.size() > 0 and low_idx.size() < full_idx.size(), "%d vs %d" % [low_idx.size(), full_idx.size()])
