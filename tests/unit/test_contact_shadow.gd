extends TestCase


func _t() -> Tuning:
	return Tuning.new()


func test_planted_foot_full_strength() -> void:
	var t: Tuning = _t()
	var b: Vector4 = ContactShadow.blob(Vector3(1.0, 0.05, 2.0), 0.0, 0.16, 0.3, 0.5, 0.8)
	assert_near(b.x, 1.0)
	assert_near(b.y, 2.0)
	assert_near(b.z, 0.16)
	assert_near(b.w, 0.5)
	var fb: Array[Vector4] = ContactShadow.fighter_blobs([Vector3(0.0, t.sand_contact_foot_rest, 0.0)] as Array[Vector3],
			Vector3(0.0, 0.95, 0.0), t)
	assert_eq(fb.size(), 2)
	assert_near(fb[0].w, t.sand_contact_dark)


func test_lifted_part_fades_and_widens() -> void:
	var low: Vector4 = ContactShadow.blob(Vector3.ZERO, 0.05, 0.16, 0.3, 0.5, 0.8)
	var high: Vector4 = ContactShadow.blob(Vector3.ZERO, 0.2, 0.16, 0.3, 0.5, 0.8)
	var gone: Vector4 = ContactShadow.blob(Vector3.ZERO, 0.3, 0.16, 0.3, 0.5, 0.8)
	assert_true(high.w < low.w and low.w < 0.5, "strength falls with height")
	assert_true(high.z > low.z and low.z > 0.16, "radius grows with height")
	assert_near(gone.w, 0.0)
	# Below its rest height (sunk in the sand) a part counts as planted.
	assert_near(ContactShadow.blob(Vector3.ZERO, -0.1, 0.16, 0.3, 0.5, 0.8).w, 0.5)


func test_standing_body_pool_is_faint_lying_is_dark() -> void:
	var t: Tuning = _t()
	var stand: Array[Vector4] = ContactShadow.fighter_blobs([] as Array[Vector3], Vector3(0.0, 0.95, 0.0), t)
	var lying: Array[Vector4] = ContactShadow.fighter_blobs([] as Array[Vector3], Vector3(0.0, 0.17, 0.0), t)
	assert_true(stand[0].w > 0.05 and stand[0].w < t.sand_contact_body_dark * 0.5, "standing pool %f" % stand[0].w)
	assert_true(lying[0].w > t.sand_contact_body_dark * 0.9, "lying blob %f" % lying[0].w)


func test_pack_drops_faded_and_caps() -> void:
	var blobs: Array[Vector4] = [Vector4(0, 0, 0.2, 0.0), Vector4(1, 0, 0.2, 0.3)]
	var p: PackedVector4Array = ContactShadow.pack(blobs)
	assert_eq(p.size(), ContactShadow.MAX_BLOBS)
	assert_eq(ContactShadow.live_count(p), 1)
	assert_near(p[0].x, 1.0)
	var many: Array[Vector4] = []
	for i: int in 12:
		many.append(Vector4(float(i), 0.0, 0.2, 0.01 * float(i + 1)))
	p = ContactShadow.pack(many)
	assert_eq(ContactShadow.live_count(p), ContactShadow.MAX_BLOBS)
	assert_near(p[0].w, 0.12, 0.0001, "strongest kept first")
	assert_eq(ContactShadow.live_count(ContactShadow.pack([] as Array[Vector4])), 0)


func test_shade_at_matches_falloff() -> void:
	var p: PackedVector4Array = ContactShadow.pack([Vector4(0, 0, 0.2, 0.5), Vector4(0, 0, 0.4, 0.2)] as Array[Vector4])
	assert_near(ContactShadow.shade_at(p, 0.0, 0.0), 0.5 * 0.8)
	assert_near(ContactShadow.shade_at(p, 0.2, 0.0), 1.0 - 0.2 * 0.75 * 0.75)
	assert_near(ContactShadow.shade_at(p, 1.0, 0.0), 1.0)
	assert_near(ContactShadow.shade_at(ContactShadow.pack([] as Array[Vector4]), 0.0, 0.0), 1.0)


func test_bound_holds_every_blob() -> void:
	var p: PackedVector4Array = ContactShadow.pack([Vector4(-1, 0, 0.2, 0.5), Vector4(1.5, 0.5, 0.4, 0.2), Vector4(0, -0.3, 0.1, 0.3)] as Array[Vector4])
	var b: Vector4 = ContactShadow.bound(p)
	for i: int in ContactShadow.live_count(p):
		var q: Vector4 = p[i]
		assert_true(Vector2(q.x - b.x, q.y - b.y).length() + q.z <= b.z + 0.0001, "blob %d inside" % i)
	assert_true(b.z < 1.8, "bound stays tight: %f" % b.z)
	assert_eq(ContactShadow.bound(ContactShadow.pack([] as Array[Vector4])), Vector4.ZERO)


func test_foot_blobs_are_ovals_along_the_foot() -> void:
	var t: Tuning = _t()
	var feet: Array[Vector3] = [Vector3(0.0, t.sand_contact_foot_rest, 0.0)]
	var toes: Array[Vector3] = [Vector3(0.0, -0.1, -1.0)]
	var blobs: Array[Vector4] = ContactShadow.fighter_blobs(feet, Vector3(0.0, 0.95, 0.0), t)
	var axes: Array[Vector4] = ContactShadow.fighter_axes(toes, t)
	assert_eq(axes.size(), blobs.size())
	assert_near(axes[0].y, -1.0, 0.0001, "along the flat toe direction")
	assert_near(axes[0].z, t.sand_contact_foot_aspect)
	assert_eq(axes[1], ContactShadow.ROUND, "the pelvis pool is round")
	var p: PackedVector4Array = ContactShadow.pack([blobs[0]] as Array[Vector4])
	var a: PackedVector4Array = ContactShadow.pack_axes([blobs[0]] as Array[Vector4], [axes[0]] as Array[Vector4])
	var along: float = ContactShadow.shade_at(p, 0.0, -0.15, a)
	var across: float = ContactShadow.shade_at(p, 0.15, 0.0, a)
	assert_true(along < across - 0.1, "darker ahead of the toes than beside the foot: %f vs %f" % [along, across])
	assert_near(ContactShadow.shade_at(p, 0.0, 0.0, a), ContactShadow.shade_at(p, 0.0, 0.0), 0.0001, "same core")
	var e: Vector2 = ContactShadow.half_extents(blobs[0], axes[0])
	assert_near(e.x * e.y, blobs[0].z * blobs[0].z, 0.0001, "same area as the round blob")
	assert_eq(ContactShadow.axis(Vector3.UP, 2.0), ContactShadow.ROUND, "a foot pointing down at the sand is round")


func test_axes_follow_the_blobs_pack_keeps() -> void:
	var blobs: Array[Vector4] = [Vector4(0, 0, 0.2, 0.0), Vector4(1, 0, 0.2, 0.3), Vector4(2, 0, 0.2, 0.5)]
	var axes: Array[Vector4] = [Vector4(1, 0, 3, 0), Vector4(0, 1, 2, 0), Vector4(1, 0, 1.5, 0)]
	var a: PackedVector4Array = ContactShadow.pack_axes(blobs, axes)
	assert_eq(a.size(), ContactShadow.MAX_BLOBS)
	assert_eq(a[0], axes[1], "the faded first blob is dropped with its axis")
	assert_eq(a[1], axes[2])
	assert_eq(a[2], Vector4.ZERO)
	var p: PackedVector4Array = ContactShadow.pack(blobs)
	var b: Vector4 = ContactShadow.bound(p, a)
	for i: int in ContactShadow.live_count(p):
		var reach: float = ContactShadow.half_extents(p[i], a[i]).x
		assert_true(Vector2(p[i].x - b.x, p[i].y - b.y).length() + reach <= b.z + 0.0001, "oval %d inside" % i)
