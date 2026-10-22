extends TestCase


func test_every_kind_has_its_length_level_and_quiet_ends() -> void:
	for kind: String in UiTones.KINDS:
		var x: PackedFloat32Array = UiTones.samples(kind)
		assert_eq(x.size(), int(float(UiTones.LENGTHS[kind]) * float(UiTones.RATE)), kind)
		var top: float = 0.0
		for v: float in x:
			top = maxf(top, absf(v))
		assert_near(top, float(UiTones.PEAKS[kind]), 0.001, kind + " peak")
		assert_true(absf(x[0]) < 0.01 and absf(x[x.size() - 1]) < 0.01, kind + " starts and ends silent (no click)")


func test_same_kind_same_samples_and_kinds_differ() -> void:
	assert_eq(UiTones.samples("select"), UiTones.samples("select"))
	assert_true(UiTones.samples("focus") != UiTones.samples("back"))
	assert_eq(UiTones.samples("nope").size(), 0)


func test_pcm16_is_two_bytes_a_sample_and_clamps() -> void:
	var b: PackedByteArray = UiTones.pcm16(PackedFloat32Array([0.0, 1.0, -2.0]))
	assert_eq(b.size(), 6)
	assert_eq(b.decode_s16(2), 32767)
	assert_eq(b.decode_s16(4), -32767)


func test_ui_sounds_are_short() -> void:
	for kind: String in UiTones.KINDS:
		assert_true(float(UiTones.LENGTHS[kind]) <= 0.35, kind + " never drags behind the menu")
