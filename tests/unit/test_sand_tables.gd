extends TestCase
## SandTables: cached static sand tables, built on a worker or synchronously, identical either way.


## The disc loop as SandSurface.build_disc_mesh had it before the cache (reference for the faster rewrite).
func _reference_disc(r: float, cell: float) -> Dictionary:
	var gn: int = int(ceil(2.0 * r / cell)) + 1
	var idx: PackedInt32Array = PackedInt32Array()
	idx.resize(gn * gn)
	idx.fill(-1)
	var verts: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var r2: float = r * r
	for cz: int in range(gn - 1):
		for cx: int in range(gn - 1):
			var keep: bool = false
			for k: int in range(4):
				var px: float = -r + float(cx + (k & 1)) * cell
				var pz: float = -r + float(cz + (k >> 1)) * cell
				if px * px + pz * pz <= r2:
					keep = true
			if not keep:
				continue
			var q: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
			for k: int in range(4):
				var gi: int = (cz + (k >> 1)) * gn + cx + (k & 1)
				if idx[gi] < 0:
					idx[gi] = verts.size()
					verts.append(Vector3(-r + float(cx + (k & 1)) * cell, 0.0, -r + float(cz + (k >> 1)) * cell))
				q[k] = idx[gi]
			indices.append_array(PackedInt32Array([q[0], q[1], q[2], q[1], q[3], q[2]]))
	return {"verts": verts, "indices": indices}


func test_disc_matches_reference() -> void:
	for rc: Vector2 in [Vector2(2.0, 0.5), Vector2(3.35, 0.22), Vector2(1.0, 0.15)]:
		var a: Dictionary = SandTables.build_disc(rc.x, rc.y)
		var b: Dictionary = _reference_disc(rc.x, rc.y)
		assert_eq((a["verts"] as PackedVector3Array).size(), (b["verts"] as PackedVector3Array).size())
		assert_true(a["verts"] == b["verts"], "same vertices in the same order")
		assert_true(a["indices"] == b["indices"], "same indices")


func test_background_equals_sync_and_sets_ready() -> void:
	SandTables.clear()
	var e: float = SandMap.map_extent(4.0)
	assert_false(SandTables.is_ready(4.0, e, 7, 4.35, 0.22))
	SandTables.prewarm(4.0, e, 7, 4.35, 0.22)
	var base_t: Dictionary = SandTables.base(4.0, e, 7)  # waits for the worker
	var disc_t: Dictionary = SandTables.disc(4.35, 0.22)
	var noise_t: Dictionary = SandTables.noise()
	assert_true(SandTables.is_ready(4.0, e, 7, 4.35, 0.22))
	assert_true(base_t["base"] == SandMap.build_base(4.0, e, 7), "worker base grid equals a direct build")
	assert_true((base_t["image"] as Image).get_data() == (SandTables.build_base(4.0, e, 7)["image"] as Image).get_data())
	assert_true(disc_t["indices"] == SandTables.build_disc(4.35, 0.22)["indices"])
	var img: Image = noise_t["image"]
	assert_eq(img.get_width(), SandTables.NOISE_SIZE)
	assert_true(img.has_mipmaps())
	assert_true(img.get_data() == (SandTables.build_noise()["image"] as Image).get_data(), "noise is deterministic")
	SandTables.clear()


func test_cache_returns_same_tables_without_prewarm() -> void:
	SandTables.clear()
	var a: Dictionary = SandTables.disc(1.0, 0.25)
	assert_true(SandTables.disc(1.0, 0.25) == a)
	assert_false(SandTables.is_ready(1.0, 1.0, 7, 1.0, 0.25), "only the disc is cached")
	SandTables.clear()


func test_arena_prewarm_keys_match_sand_setup() -> void:
	assert_eq(Arena.SAND_BASE_SEED, SandSurface.BASE_SEED)
	assert_near(Arena.SAND_DISC_MARGIN, SandSurface.DISC_MARGIN, 1e-6)
