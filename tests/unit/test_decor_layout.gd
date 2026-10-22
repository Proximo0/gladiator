extends TestCase


func _ids(pieces: Array[Dictionary]) -> Dictionary:
	var n: Dictionary = {}
	for p: Dictionary in pieces:
		n[p["id"]] = int(n.get(p["id"], 0)) + 1
	return n


func test_floor_pieces() -> void:
	var n: Dictionary = _ids(DecorLayout.pieces(11.0))
	assert_eq(n.get("portcullis", 0), 2, "a gate each side")
	assert_eq(n.get("column", 0), 4, "a column either side of each gate")
	assert_eq(n.get("weapon_rack", 0), 2)
	assert_eq(n.get("barrier", 0), 4, "barriers either side of each gate")
	assert_eq(n.get("column_stump", 0), 2)
	assert_eq(DecorLayout.transforms(11.0, "barrier").size(), 4)


func test_pieces_face_the_centre_from_the_wall() -> void:
	for p: Dictionary in DecorLayout.pieces(11.0):
		var xf: Transform3D = p["xf"]
		var flat := Vector3(xf.origin.x, 0.0, xf.origin.z)
		assert_near(xf.origin.y, 0.0, 0.0001, "%s stands on the floor" % p["id"])
		assert_true(flat.length() > 10.2 and flat.length() < 11.1, "%s stands at the wall (%.2f m)" % [p["id"], flat.length()])
		if p["id"] != "column_stump":
			assert_true(xf.basis.z.normalized().dot(-flat.normalized()) > 0.95, "%s faces the centre" % p["id"])


func test_pieces_do_not_overlap() -> void:
	var cs: Array[Dictionary] = DecorLayout.colliders(11.0)
	for i: int in cs.size():
		for j: int in range(i + 1, cs.size()):
			var a: Vector3 = (cs[i]["xf"] as Transform3D).origin
			var b: Vector3 = (cs[j]["xf"] as Transform3D).origin
			var gap: float = Vector2(a.x - b.x, a.z - b.z).length()
			assert_true(gap > _half_width(cs[i]) + _half_width(cs[j]) - 0.05, "colliders %d and %d overlap (%.2f m apart)" % [i, j, gap])


func _half_width(c: Dictionary) -> float:
	if c.has("box"):
		return (c["box"] as Vector3).x * 0.5
	return (c["cyl"] as Vector2).x


func test_colliders_match_the_pieces_and_stay_by_the_wall() -> void:
	var cs: Array[Dictionary] = DecorLayout.colliders(11.0)
	assert_eq(cs.size(), DecorLayout.pieces(11.0).size(), "every floor piece is solid")
	for c: Dictionary in cs:
		var xf: Transform3D = c["xf"]
		assert_near(xf.basis.x.length(), 1.0, 0.0001, "collider transforms are unscaled")
		var r: float = Vector2(xf.origin.x, xf.origin.z).length()
		var depth: float = (c["box"] as Vector3).z * 0.5 if c.has("box") else (c["cyl"] as Vector2).x
		assert_true(r - depth > 10.2, "a collider reaches at most 0.8 m into the arena (%.2f)" % (r - depth))
		var h: float = (c["box"] as Vector3).y if c.has("box") else (c["cyl"] as Vector2).y
		assert_near(xf.origin.y, h * 0.5, 0.01, "standing on the floor")


func test_spawns_and_centre_stay_clear() -> void:
	for c: Dictionary in DecorLayout.colliders(11.0):
		var o: Vector3 = (c["xf"] as Transform3D).origin
		for side: int in 2:
			var sp: Vector3 = Arena.spawn_transform(side, 11.0).origin
			assert_true(Vector2(o.x - sp.x, o.z - sp.z).length() > 5.0, "dressing far from the spawns")


func test_scale_carries_into_the_shape_sizes() -> void:
	var cs: Array[Dictionary] = DecorLayout.colliders(11.0)
	var gate: Dictionary = cs[0]
	assert_near((gate["box"] as Vector3).y, 3.9 * DecorLayout.PORTCULLIS_SCALE, 0.0001)
