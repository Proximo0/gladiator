extends TestCase


func _count(items: Array[Dictionary], id: String) -> int:
	var n: int = 0
	for it: Dictionary in items:
		if it["id"] == id:
			n += 1
	return n


func test_counts_follow_the_requested_numbers() -> void:
	var items: Array[Dictionary] = DecorLayout.pieces(11.0, 4, 1, 2)
	assert_eq(_count(items, "column"), 4)
	assert_eq(_count(items, "column_stump"), 1)
	assert_eq(_count(items, "banner"), 2)
	assert_eq(_count(items, "portcullis"), 2)
	assert_eq(_count(items, "weapon_rack"), 2)
	assert_eq(_count(items, "barrier"), 2)
	assert_eq(_count(DecorLayout.pieces(11.0, 99, 99, 99), "column"), DecorLayout.COLUMNS.size(), "capped by the list")


func test_gfx_levels_only_change_visual_pieces() -> void:
	var lo: Array[Dictionary] = DecorLayout.pieces(11.0, GfxQuality.pick_i(GfxQuality.DECOR_COLUMNS, GfxQuality.LOW),
			GfxQuality.pick_i(GfxQuality.DECOR_STUMPS, GfxQuality.LOW), GfxQuality.pick_i(GfxQuality.DECOR_BANNERS, GfxQuality.LOW))
	var hi: Array[Dictionary] = DecorLayout.pieces(11.0, GfxQuality.pick_i(GfxQuality.DECOR_COLUMNS, GfxQuality.HIGH),
			GfxQuality.pick_i(GfxQuality.DECOR_STUMPS, GfxQuality.HIGH), GfxQuality.pick_i(GfxQuality.DECOR_BANNERS, GfxQuality.HIGH))
	assert_true(lo.size() < hi.size(), "low shows fewer pieces")
	for id: String in ["portcullis", "weapon_rack", "barrier"]:
		assert_eq(_count(lo, id), _count(hi, id), id + " has a collider: same on every level")


func test_pieces_face_the_centre_at_the_wall() -> void:
	for it: Dictionary in DecorLayout.pieces(11.0, 8, 4, 4):
		var xf: Transform3D = it["xf"]
		var flat := Vector3(xf.origin.x, 0.0, xf.origin.z)
		assert_near(xf.origin.y, 0.0, 0.0001, "%s stands on the floor" % it["id"])
		assert_true(flat.length() > 10.6 and flat.length() <= 11.0 + 0.001, "%s sits at the wall (%.2f m)" % [it["id"], flat.length()])
		if it["id"] == "column_stump":
			continue  # turned for variety
		var front: Vector3 = xf.basis.z.normalized()
		assert_true(front.dot(-flat.normalized()) > 0.99, "%s faces the centre" % it["id"])


func test_pieces_do_not_overlap_along_the_wall() -> void:
	var items: Array[Dictionary] = DecorLayout.pieces(11.0, 8, 4, 4)
	for i: int in items.size():
		for j: int in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var gap: float = absf(wrapf(deg_to_rad(float(a["angle"]) - float(b["angle"])), -PI, PI)) * 11.0
			var need: float = float(DecorLayout.HALF_WIDTH[a["id"]]) + float(DecorLayout.HALF_WIDTH[b["id"]])
			assert_true(gap >= need, "%s at %.1f and %s at %.1f overlap" % [a["id"], a["angle"], b["id"], b["angle"]])


func test_nothing_in_the_gate_openings() -> void:
	for it: Dictionary in DecorLayout.pieces(11.0, 8, 4, 4):
		var deg: float = float(it["angle"])
		if it["id"] != "portcullis":
			for gate: float in [0.0, 180.0, 360.0]:
				assert_true(absf(deg - gate) > 9.0, "%s at %.1f blocks a gate" % [it["id"], deg])


func test_colliders_are_flat_against_the_wall() -> void:
	var boxes: Array[Dictionary] = DecorLayout.colliders(11.0)
	assert_eq(boxes.size(), DecorLayout.GATES.size() + DecorLayout.RACKS.size() + DecorLayout.BARRIERS.size())
	for b: Dictionary in boxes:
		var xf: Transform3D = b["xf"]
		var size: Vector3 = b["size"]
		var r: float = Vector2(xf.origin.x, xf.origin.z).length()
		assert_true(r - size.z * 0.5 > 10.3, "a collider stands at most 0.7 m into the arena")
		assert_near(xf.origin.y, size.y * 0.5, 0.0001, "standing on the floor")
