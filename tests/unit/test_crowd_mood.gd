extends TestCase


func test_rises_fast_and_falls_slow() -> void:
	var m := CrowdMood.new()
	m.set_target(1.0)
	m.tick(0.2)
	assert_near(m.level, 0.5, 0.001)
	m.set_target(0.0)
	m.tick(0.2)
	assert_near(m.level, 0.44, 0.001)


func test_level_never_passes_goal() -> void:
	var m := CrowdMood.new()
	m.set_target(0.3)
	m.tick(5.0)
	assert_near(m.level, 0.3)
	m.set_target(0.0)
	m.tick(100.0)
	assert_near(m.level, 0.0)


func test_react_pulses_then_fades() -> void:
	var m := CrowdMood.new()
	m.react("finisher")
	m.tick(1.0)
	assert_true(m.level > 0.9)
	for i: int in 400:
		m.tick(0.1)
	assert_near(m.level, 0.0)
	m.react("nonsense")
	assert_near(m.pulse, 0.0)


func test_twins_are_complementary() -> void:
	for e: float in [0.0, 0.18, 0.5, 0.96, 1.0]:
		for th: float in [0.18, 0.5, 0.96, 1.0]:
			assert_eq(CrowdMood.cheering(e, th), not (e < th + 0.0001), "e=%f th=%f" % [e, th])
	assert_false(CrowdMood.cheering(0.08, CrowdMood.CHEER_THRESHOLD_MIN), "baseline crowd is calm")
	assert_true(CrowdMood.cheering(1.0, CrowdMood.CHEER_THRESHOLD_MAX), "full roar stands everyone")


func test_pick_variants() -> void:
	var s: PackedStringArray = CrowdMood.pick_variants(true, false, 0.99)
	assert_eq(s[1], "")
	assert_true(s[0].begins_with("sit_"))
	var f: PackedStringArray = CrowdMood.pick_variants(false, true, 0.5)
	assert_eq(f[0], "stand_idle_f")
	assert_eq(f[1], "stand_cheer_f")
	for k: int in 20:
		var v: PackedStringArray = CrowdMood.pick_variants(false, false, float(k) / 20.0)
		assert_true(v[0] in CrowdMood.ALL_VARIANTS and v[1] in CrowdMood.ALL_VARIANTS, v[0] + v[1])


func test_thresholds_spread_over_range() -> void:
	var lo: float = 1.0
	var hi: float = 0.0
	var standing_at_half: int = 0
	for i: int in CrowdMood.SEED_COUNT:
		var t: float = CrowdMood.threshold_for(i)
		lo = minf(lo, t)
		hi = maxf(hi, t)
		if CrowdMood.cheering(0.5, t):
			standing_at_half += 1
	assert_true(lo >= CrowdMood.CHEER_THRESHOLD_MIN - 0.0001 and hi <= CrowdMood.CHEER_THRESHOLD_MAX + 0.0001)
	var share: float = float(standing_at_half) / float(CrowdMood.SEED_COUNT)
	assert_true(share > 0.35 and share < 0.55, "about 40 percent stand at 0.5, got %f" % share)
	assert_true(float(CrowdMood.SEED_COUNT) <= 2048.0, "seed is exact in a half float")
