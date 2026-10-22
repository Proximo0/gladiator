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


func test_base_relief_banks_the_wall_and_leaves_spawns_flat() -> void:
	var e: float = SandMap.map_extent(11.0)
	var heaps: Array[Dictionary] = SandMap.make_heaps(11.0, 7)
	assert_true(heaps.size() >= 4, "heaps %d" % heaps.size())
	var wall_max: float = 0.0
	var wall_min: float = 1.0
	for k in range(72):
		var a: float = TAU * float(k) / 72.0
		var h: float = SandMap.base_height(cos(a) * 11.1, sin(a) * 11.1, 11.0, 7, heaps)
		wall_max = maxf(wall_max, h)
		wall_min = minf(wall_min, h)
	assert_true(wall_max > 0.08 and wall_max <= SandMap.DRIFT_MAX_H + SandMap.HEAP_MAX_H, "wall max %f" % wall_max)
	assert_true(wall_min > 0.008, "a thin bank everywhere, min %f" % wall_min)
	assert_near(SandMap.base_height(0.0, 0.0, 11.0, 7, heaps), 0.0, 0.0001)
	assert_near(SandMap.base_height(0.0, 4.0, 11.0, 7, heaps), 0.0, 0.0001)
	assert_near(SandMap.base_height(0.0, -4.0, 11.0, 7, heaps), 0.0, 0.0001)
	for hp: Dictionary in heaps:
		assert_true(float(hp["h"]) <= SandMap.HEAP_MAX_H + 0.0001)


func test_base_grid_samples_and_is_deterministic() -> void:
	var e: float = SandMap.map_extent(4.0)
	var a: PackedFloat32Array = SandMap.build_base(4.0, e, 3)
	var b: PackedFloat32Array = SandMap.build_base(4.0, e, 3)
	assert_eq(a, b)
	var n: int = SandMap.base_size(e)
	assert_eq(a.size(), n * n)
	var heaps: Array[Dictionary] = SandMap.make_heaps(4.0, 3)
	var x: float = 3.5
	var z: float = 0.7
	assert_near(SandMap.sample_base(a, e, x, z), SandMap.base_height(x, z, 4.0, 3, heaps), 0.01)
	var bytes: PackedByteArray = SandMap.base_to_rgba_bytes(a, e)
	assert_eq(bytes.size(), n * n * 16)


func test_drift_profile_falls_off_inward() -> void:
	assert_near(SandMap.drift_profile(-0.5, 1.0), 1.0)
	assert_true(SandMap.drift_profile(0.2, 1.0) > SandMap.drift_profile(0.6, 1.0))
	assert_near(SandMap.drift_profile(1.0, 1.0), 0.0)


func test_apply_blood_palette_slots_coexist() -> void:
	var n: int = 64
	var b: PackedFloat32Array = _flat(n)
	var w: PackedFloat32Array = _flat(n)
	var d: PackedFloat32Array = _flat(n)
	var pal: PackedByteArray = PackedByteArray()
	pal.resize(n * n)
	SandMap.apply_blood(b, w, d, n, Vector2(20.0, 32.0), 6.0, 0.8, 1.0, true, pal, 0)
	SandMap.apply_blood(b, w, d, n, Vector2(44.0, 32.0), 6.0, 0.8, 2.0, true, pal, 1)
	assert_eq(pal[32 * n + 20], 0)
	assert_eq(pal[32 * n + 44], 1)
	assert_true(b[32 * n + 20] > 0.5 and b[32 * n + 44] > 0.5)
	# Wet halo texels with no blood take the colour too (no stray red rim around ichor).
	assert_eq(pal[32 * n + 51], 1)
	# A weaker spread pass of the other colour does not repaint a stronger pool.
	SandMap.apply_blood(b, w, d, n, Vector2(20.0, 32.0), 6.0, 0.3, 3.0, false, pal, 1)
	assert_eq(pal[32 * n + 20], 0)
	# No pal array: unchanged behaviour.
	SandMap.apply_blood(b, w, d, n, Vector2(32.0, 10.0), 4.0, 0.8, 1.0, true)


func test_capsule_is_body_shaped_and_conserves_mass() -> void:
	var n: int = 120
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(n * n)
	h.fill(0.0)
	SandMap.apply_capsule(h, n, Vector2(40, 60), Vector2(80, 60), 8.0, 0.15, Vector2.ZERO, 1.0)
	assert_near(h[60 * n + 60], -0.15, 0.001, "flat deep middle")
	assert_near(h[60 * n + 42], -0.15, 0.001, "deep along the whole body")
	assert_true(h[30 * n + 60] == 0.0, "far side untouched")
	assert_near(SandMap.total_height(h), 0.0, 0.05, "volume conserved")
	var berm: float = 0.0
	for y in range(40, 80):
		berm = maxf(berm, h[y * n + 60])
	assert_true(berm > 0.02, "berm %f" % berm)


## A fallen body is ~11 part contacts on one spot, then flicker re-contacts. Returns [max height, max texel step].
func _corpse_pile(gain: float, repeats: int) -> Array[float]:
	var n: int = 160
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(n * n)
	h.fill(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for rep: int in repeats:
		for k: int in 11:
			var c: Vector2 = Vector2(80.0 + rng.randf_range(-14.0, 14.0), 80.0 + rng.randf_range(-14.0, 14.0))
			if k % 3 == 0:
				var d: Vector2 = Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
				SandMap.apply_capsule(h, n, c - d, c + d, 10.0, 0.05, Vector2(0.3, 0.1), gain)
			else:
				SandMap.apply_stamp(h, n, c, 9.0, 9.0, 0.0, 0.04, Vector2(0.2, 0.0), gain)
	var hi: float = -1.0
	var step: float = 0.0
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			hi = maxf(hi, h[y * n + x])
			step = maxf(step, maxf(absf(h[y * n + x] - h[y * n + x + 1]), absf(h[y * n + x] - h[(y + 1) * n + x])))
	return [hi, step]


func test_repeated_body_contacts_stay_smooth() -> void:
	# Before the fix: berm 0.24 m, texel step 0.076 m after three passes.
	var one: Array[float] = _corpse_pile(1.3, 1)
	var many: Array[float] = _corpse_pile(1.3, 3)
	assert_true(many[0] < 0.065, "berm height %f" % many[0])
	assert_true(many[1] < 0.03 and many[1] < one[1] * 1.15, "texel step %f" % many[1])


func test_apply_blood_matches_exact_edge_and_stays_in_rect() -> void:
	var n: int = 64
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n * n)
	var w: PackedFloat32Array = b.duplicate()
	var d: PackedFloat32Array = b.duplicate()
	var r: Rect2i = SandMap.apply_blood(b, w, d, n, Vector2(32.0, 32.0), 7.0, 0.9, 2.0, true)
	var wet_edge: float = 7.0 * SandMap.EDGE_MAX * 1.6
	for y: int in n:
		for x: int in n:
			var dist: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(Vector2(32.0, 32.0))
			if dist >= wet_edge:
				assert_eq(w[y * n + x], 0.0)
			elif w[y * n + x] > 0.0:
				assert_true(r.has_point(Vector2i(x, y)))
	assert_near(b[32 * n + 32], 0.9, 0.05)


func test_edge_table_is_cached_per_seed_bucket() -> void:
	var a: PackedFloat32Array = SandMap.edge_table(1.0)
	assert_eq(a.size(), SandMap.EDGE_BINS)
	var w: float = TAU / float(SandMap.EDGE_SEED_BUCKETS)
	var centre: float = (floorf(1.0 / w) + 0.5) * w
	assert_near(a[0], SandMap.blood_edge(-PI, centre), 0.0001)
	assert_near(a[64], SandMap.blood_edge(64.0 / SandMap.EDGE_BINS * TAU - PI, centre), 0.0001)
	assert_eq(SandMap.edge_table(centre + w * 0.3), a, "same bucket, same table")
	assert_eq(SandMap.edge_table(1.0 + TAU), a, "seeds wrap around TAU")
	assert_true(SandMap.edge_table(1.0 + w) != a, "the next bucket has its own shape")
	for v: float in a:
		assert_true(v > 0.6 and v <= SandMap.EDGE_MAX)
