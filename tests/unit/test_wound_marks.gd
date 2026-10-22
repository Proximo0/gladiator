extends TestCase


func test_kind_follows_the_contact_and_damage() -> void:
	assert_eq(WoundMarks.kind_for("edge", 12.0, 0.0, 2.0, false), WoundMarks.Kind.GASH)
	assert_eq(WoundMarks.kind_for("point", 2.0, 14.0, 0.0, false), WoundMarks.Kind.PUNCTURE)
	assert_eq(WoundMarks.kind_for("point", 6.0, 6.0, 0.0, false), WoundMarks.Kind.PUNCTURE)
	assert_eq(WoundMarks.kind_for("blunt", 0.0, 0.0, 20.0, false), WoundMarks.Kind.BRUISE)
	assert_eq(WoundMarks.kind_for("edge", 0.5, 0.0, 1.0, false), -1, "a tap leaves nothing")
	assert_eq(WoundMarks.kind_for("edge", 2.0, 0.0, 0.0, true), -1, "a weak glancing cut leaves nothing")
	assert_eq(WoundMarks.kind_for("flat", 1.0, 0.0, 30.0, false), WoundMarks.Kind.BRUISE, "a flat blow bruises")


func test_severity_grows_with_damage_and_is_clamped() -> void:
	var lo: float = WoundMarks.severity(WoundMarks.Kind.GASH, 3.0, 0.0, 0.0)
	var hi: float = WoundMarks.severity(WoundMarks.Kind.GASH, 30.0, 0.0, 0.0)
	assert_true(hi > lo)
	assert_near(WoundMarks.severity(WoundMarks.Kind.BRUISE, 0.0, 0.0, 999.0), 1.0)
	assert_true(WoundMarks.severity(WoundMarks.Kind.PUNCTURE, 0.0, 0.1, 0.0) >= 0.15)


func test_capsule_normal_is_radial_from_the_bone() -> void:
	var size: Vector3 = Vector3(0.05, 0.3, 0.05)
	var n: Vector3 = WoundMarks.surface_normal("capsule", size, Vector3(0.0, 0.05, 0.05))
	assert_near(n.dot(Vector3.BACK), 1.0, 0.001)
	var cap_n: Vector3 = WoundMarks.surface_normal("capsule", size, Vector3(0.0, 0.2, 0.0))
	assert_near(cap_n.dot(Vector3.UP), 1.0, 0.001, "past the segment end the normal points out of the cap")


func test_snap_pulls_points_onto_the_surface_band() -> void:
	var size: Vector3 = Vector3(0.05, 0.3, 0.05)
	var deep: Vector3 = WoundMarks.snap_to_surface("capsule", size, Vector3(0.0, 0.0, 0.005))
	assert_near(deep.z, 0.05 - WoundMarks.SNAP_IN, 0.0001)
	var far: Vector3 = WoundMarks.snap_to_surface("capsule", size, Vector3(0.2, 0.0, 0.0))
	assert_near(far.x, 0.05 + WoundMarks.SNAP_OUT, 0.0001)
	var on: Vector3 = WoundMarks.snap_to_surface("capsule", size, Vector3(0.0, 0.0, 0.05))
	assert_near(on.z, 0.05, 0.0001, "a point on the skin stays put")
	var box_far: Vector3 = WoundMarks.snap_to_surface("box", Vector3(0.36, 0.48, 0.22), Vector3(0.0, 0.0, 0.4))
	assert_true(box_far.z < 0.4 and box_far.z > 0.11)


func test_tangent_lies_in_the_surface_plane() -> void:
	var n: Vector3 = Vector3(0, 0, 1)
	var t: Vector3 = WoundMarks.tangent(Vector3(1, 0, 3), n, Vector3.UP)
	assert_near(t.dot(n), 0.0, 0.0001)
	assert_near(t.length(), 1.0, 0.0001)
	var fb: Vector3 = WoundMarks.tangent(Vector3(0, 0, 2), n, Vector3.UP)
	assert_near(fb.dot(Vector3.UP), 1.0, 0.0001, "motion along the normal falls back")


func test_marks_merge_nearby_and_respect_the_cap() -> void:
	var wm: WoundMarks = WoundMarks.new(0)
	assert_eq(wm.cap, WoundMarks.CAPS[0])
	var n: Vector3 = Vector3.BACK
	var a: WoundMarks.Mark = wm.add("torso", WoundMarks.Kind.GASH, Vector3(0, 0, 0.11), n, Vector3.RIGHT, Vector3.DOWN, 0.3, 0)
	var b: WoundMarks.Mark = wm.add("torso", WoundMarks.Kind.GASH, Vector3(0.01, 0, 0.11), n, Vector3.RIGHT, Vector3.DOWN, 0.3, 0)
	assert_true(a == b, "a cut on the same spot deepens the old one")
	assert_true(a.sev > 0.3)
	assert_eq(wm.count("torso"), 1)
	var other: WoundMarks.Mark = wm.add("torso", WoundMarks.Kind.GASH, Vector3(0.01, 0, 0.11), n, Vector3.RIGHT, Vector3.DOWN, 0.3, 1)
	assert_true(other != a, "the other fighter's blood does not merge")
	for i: int in 20:
		wm.add("torso", WoundMarks.Kind.SMEAR, Vector3(-0.15 + 0.1 * float(i % 4), -0.2 + 0.1 * float(i / 4), 0.11), n,
				Vector3.RIGHT, Vector3.DOWN, 0.5, 0)
	assert_eq(wm.count("torso"), wm.cap)
	var kinds: Array = []
	for m: WoundMarks.Mark in wm.marks["torso"]:
		kinds.append(m.kind)
	assert_true(kinds.has(WoundMarks.Kind.GASH), "smears are dropped before wounds")
	assert_true(wm.dirty.has("torso"))


func test_trickle_runs_down_while_fresh_and_stops_at_its_length() -> void:
	var wm: WoundMarks = WoundMarks.new(2)
	var g: WoundMarks.Mark = wm.add("thigh_l", WoundMarks.Kind.GASH, Vector3(0, 0, 0.07), Vector3.BACK, Vector3.RIGHT,
			Vector3.DOWN, 1.0, 0)
	var br: WoundMarks.Mark = wm.add("thigh_l", WoundMarks.Kind.BRUISE, Vector3(0, 0.15, 0.07), Vector3.BACK,
			Vector3.RIGHT, Vector3.DOWN, 1.0, 0)
	assert_near(WoundMarks.trickle_len(g), 0.0)
	wm.step(1.0)
	var one: float = WoundMarks.trickle_len(g)
	assert_true(one > 0.0)
	wm.step(100.0)
	assert_near(WoundMarks.trickle_len(g), WoundMarks.TRICKLE_MAX, 0.0001)
	assert_near(WoundMarks.trickle_len(br), 0.0, 0.0, "bruises do not bleed")
	assert_true(g.down.dot(Vector3.DOWN) > 0.99)


func test_marks_darken_with_age() -> void:
	assert_near(WoundMarks.dryness(0.0), 0.0)
	assert_true(WoundMarks.dryness(10.0) < WoundMarks.dryness(60.0))
	assert_true(WoundMarks.dryness(1.0e4) > 0.99)


func test_pack_fills_the_shader_arrays() -> void:
	var wm: WoundMarks = WoundMarks.new(2)
	wm.add("head", WoundMarks.Kind.PUNCTURE, Vector3(0, 0, 0.09), Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 0.6, 1)
	wm.step(5.0)
	var pk: Dictionary = wm.pack("head")
	assert_eq(int(pk["count"]), 1)
	for key: String in ["a", "b", "c", "d", "e"]:
		assert_eq((pk[key] as PackedVector4Array).size(), WoundMarks.MAX_CAP)
	var c: Vector4 = (pk["c"] as PackedVector4Array)[0]
	assert_near(c.w, float(WoundMarks.Kind.PUNCTURE))
	var e: Vector4 = (pk["e"] as PackedVector4Array)[0]
	assert_near(e.z, 1.0, 0.0, "palette slot")
	assert_true(e.x > 0.0, "dryness")
	assert_eq(int(wm.pack("torso")["count"]), 0)


func test_seed_is_stable_for_a_point() -> void:
	var p: Vector3 = Vector3(0.3, 1.2, -0.7)
	assert_near(WoundMarks.seed_of(p), WoundMarks.seed_of(p), 0.0)
	assert_true(WoundMarks.seed_of(p) >= 0.0 and WoundMarks.seed_of(p) < 1.0)


func test_open_wounds_draw_over_smears_and_bruises() -> void:
	var wm: WoundMarks = WoundMarks.new(2)
	wm.add("torso", WoundMarks.Kind.GASH, Vector3(0, 0, 0.11), Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 0.5, 0)
	wm.add("torso", WoundMarks.Kind.SMEAR, Vector3(0.1, 0, 0.11), Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 0.5, 0)
	wm.add("torso", WoundMarks.Kind.BRUISE, Vector3(-0.1, 0, 0.11), Vector3.BACK, Vector3.RIGHT, Vector3.DOWN, 0.5, 0)
	var c: PackedVector4Array = wm.pack("torso")["c"]
	assert_near(c[0].w, float(WoundMarks.Kind.SMEAR))
	assert_near(c[1].w, float(WoundMarks.Kind.BRUISE))
	assert_near(c[2].w, float(WoundMarks.Kind.GASH))
