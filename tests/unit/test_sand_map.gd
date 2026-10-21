extends TestCase


func _flat(n: int) -> PackedFloat32Array:
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(n * n)
	h.fill(0.0)
	return h


func test_world_texel_round_trip() -> void:
	var n: int = SandMap.map_size(11.0, 40.0)
	var e: float = SandMap.map_extent(11.0)
	var t: Vector2 = SandMap.world_to_texel(3.2, -4.7, e, n)
	var w: Vector2 = SandMap.texel_to_world(t, e, n)
	assert_near(w.x, 3.2, 0.0001)
	assert_near(w.y, -4.7, 0.0001)
	var c: Vector2 = SandMap.world_to_texel(0.0, 0.0, e, n)
	assert_near(c.x, float(n) * 0.5, 0.0001)


func test_map_resolution_is_two_to_three_cm() -> void:
	var n: int = SandMap.map_size(11.0, 40.0)
	var tm: float = SandMap.texel_metres(SandMap.map_extent(11.0), n)
	assert_true(tm > 0.02 and tm < 0.03, "texel %f" % tm)


func test_profiles() -> void:
	assert_near(SandMap.bowl_profile(0.0), 1.0)
	assert_near(SandMap.bowl_profile(1.0), 0.0)
	assert_true(SandMap.bowl_profile(0.8) < SandMap.bowl_profile(0.6))
	assert_near(SandMap.rim_profile(0.5), 0.0)
	assert_true(SandMap.rim_profile(1.2) > 0.9)
	assert_near(SandMap.rim_profile(2.0), 0.0)


func test_stamp_conserves_mass() -> void:
	var n: int = 128
	var h: PackedFloat32Array = _flat(n)
	var r: Rect2i = SandMap.apply_stamp(h, n, Vector2(64.3, 60.7), 5.0, 9.0, 0.7, 0.03, Vector2(0.5, 0.2), 1.0)
	assert_true(r.size.x > 0)
	assert_near(SandMap.total_height(h), 0.0, 0.0005)
	var mn: float = 0.0
	var mx: float = 0.0
	for v: float in h:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	assert_true(mn < -0.02, "dug")
	assert_true(mx > 0.003, "rim")


func test_stamp_does_not_dig_deeper_than_depth() -> void:
	var n: int = 64
	var h: PackedFloat32Array = _flat(n)
	for i in range(5):
		SandMap.apply_stamp(h, n, Vector2(32.0, 32.0), 4.0, 4.0, 0.0, 0.02, Vector2.ZERO, 1.0)
	var mn: float = 0.0
	for v: float in h:
		mn = minf(mn, v)
	assert_true(mn >= -0.0201, "min %f" % mn)


func test_push_biases_rim() -> void:
	var n: int = 96
	var h: PackedFloat32Array = _flat(n)
	SandMap.apply_stamp(h, n, Vector2(48.0, 48.0), 6.0, 6.0, 0.0, 0.04, Vector2(1.0, 0.0), 1.0)
	var ahead: float = 0.0
	var behind: float = 0.0
	for y in range(n):
		for x in range(n):
			var v: float = h[y * n + x]
			if v > 0.0:
				if x > 48:
					ahead += v
				else:
					behind += v
	assert_true(ahead > behind * 1.5, "ahead %f behind %f" % [ahead, behind])


func test_stamp_clips_at_map_edge() -> void:
	var n: int = 32
	var h: PackedFloat32Array = _flat(n)
	var r: Rect2i = SandMap.apply_stamp(h, n, Vector2(1.0, 1.0), 5.0, 5.0, 0.0, 0.03, Vector2.ZERO, 1.0)
	assert_true(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= n and r.end.y <= n)


func test_sample_height_bilinear() -> void:
	var n: int = 16
	var h: PackedFloat32Array = _flat(n)
	h[8 * n + 8] = 0.1
	var e: float = 8.0
	# Texel (8,8) centre in world: (8.5 / 16 * 16 - 8) = 0.5.
	assert_near(SandMap.sample_height(h, n, e, 0.5, 0.5), 0.1, 0.0001)
	assert_near(SandMap.sample_height(h, n, e, 1.0, 0.5), 0.05, 0.0001)
	assert_near(SandMap.sample_height(h, n, e, 100.0, 0.0), 0.0)


func test_drag_points() -> void:
	var pts: PackedVector2Array = SandMap.drag_points(Vector2(0, 0), Vector2(1, 0), 0.1, 80)
	assert_eq(pts.size(), 11)
	assert_near(pts[0].x, 0.0)
	assert_near(pts[10].x, 1.0)
	var capped: PackedVector2Array = SandMap.drag_points(Vector2(0, 0), Vector2(100, 0), 0.01, 80)
	assert_eq(capped.size(), 80)
	assert_eq(SandMap.drag_points(Vector2(1, 1), Vector2(1, 1), 0.1, 80).size(), 2)


func test_blood_spread_and_strength() -> void:
	assert_near(SandMap.blood_spread_radius(0.0005, 0.02), 0.02)
	assert_true(SandMap.blood_spread_radius(2.0, 0.1) > 0.35)
	assert_true(SandMap.blood_strength(0.0005, 0.02) < SandMap.blood_strength(0.3, 0.2) + 0.001)
	assert_true(SandMap.blood_strength(5.0, 0.1) <= 1.0)
	assert_true(SandMap.blood_strength(0.0, 1.0) >= 0.12)


func test_apply_blood_soaks_and_freshens() -> void:
	var n: int = 64
	var b: PackedFloat32Array = _flat(n)
	var w: PackedFloat32Array = _flat(n)
	var d: PackedFloat32Array = _flat(n)
	d.fill(1.0)
	var r: Rect2i = SandMap.apply_blood(b, w, d, n, Vector2(32.0, 32.0), 6.0, 0.8, 1.0, true)
	assert_true(r.size.x > 0)
	assert_true(b[32 * n + 32] > 0.7)
	assert_true(d[32 * n + 32] < 0.3, "fresh blood is wet")
	assert_true(w[32 * n + 32] > 0.7)
	assert_near(b[2 * n + 2], 0.0)
	# Spread mode takes the max instead of adding.
	var before: float = b[32 * n + 32]
	SandMap.apply_blood(b, w, d, n, Vector2(32.0, 32.0), 6.0, 0.8, 1.0, false)
	assert_near(b[32 * n + 32], before, 0.0001)


func test_blood_edge_is_wobbly_but_bounded() -> void:
	var lo: float = 9.0
	var hi: float = 0.0
	for i in range(64):
		var e: float = SandMap.blood_edge(float(i) * 0.1, 2.0)
		lo = minf(lo, e)
		hi = maxf(hi, e)
	assert_true(lo > 0.65 and hi < 1.35 and hi - lo > 0.1)
