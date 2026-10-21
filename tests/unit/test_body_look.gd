extends TestCase


func test_deterministic_and_sides_differ() -> void:
	for s: int in 40:
		assert_eq(BodyLook.skin_index(s, 0), BodyLook.skin_index(s, 0))
		assert_true(BodyLook.skin_index(s, 0) != BodyLook.skin_index(s, 1), "sides differ for seed %d" % s)
		assert_eq(BodyLook.bearded(s, 1), BodyLook.bearded(s, 1))


func test_tones_vary_over_seeds() -> void:
	var seen: Dictionary = {}
	var beards: int = 0
	for s: int in 200:
		seen[BodyLook.skin_index(s, 0)] = true
		if BodyLook.bearded(s, 0):
			beards += 1
	assert_eq(seen.size(), BodyLook.SKIN_TONES.size())
	assert_true(beards > 40 and beards < 160, "beards mixed: %d" % beards)


func test_caps() -> void:
	assert_eq(BodyLook.cap_for("head"), "cap_neck")
	assert_eq(BodyLook.cap_for("shin_r"), "cap_knee")
	assert_eq(BodyLook.cap_for("torso"), "")
