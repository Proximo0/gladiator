extends TestCase


func test_fall_scales_with_impact() -> void:
	var t: Tuning = Tuning.shared()
	var soft: Dictionary = SandFxPlan.fall(t, 1.0, 0.012, 0.0)
	var hard: Dictionary = SandFxPlan.fall(t, 1.0, 0.062, 0.0)
	assert_true(int(hard["grains"]) > 100, "hard fall grains %d" % int(hard["grains"]))
	assert_true(int(hard["dust"]) > int(soft["dust"]))
	assert_eq(int(soft["grains"]), 0)


func test_quality_share_scales_counts() -> void:
	var t: Tuning = Tuning.shared()
	var hi: Dictionary = SandFxPlan.fall(t, 1.0, 0.062, 0.0)
	var lo: Dictionary = SandFxPlan.fall(t, 0.45, 0.062, 0.0)
	assert_true(int(lo["grains"]) < int(hi["grains"]) * 0.6)


func test_every_step_kicks_and_running_kicks_more() -> void:
	var t: Tuning = Tuning.shared()
	var walk: Dictionary = SandFxPlan.step(t, 1.0, 0.0, 0.0)
	var run: Dictionary = SandFxPlan.step(t, 1.0, 1.0, 0.0)
	assert_true(int(walk["grains"]) >= 4 and int(walk["dust"]) >= 1)
	assert_true(int(run["grains"]) > int(walk["grains"]))


func test_slide_needs_speed() -> void:
	var t: Tuning = Tuning.shared()
	assert_eq(int(SandFxPlan.slide(t, 1.0, 0.5, 0.06, 0.0)["grains"]), 0)
	var fast: Dictionary = SandFxPlan.slide(t, 1.0, 8.0, 0.2, 0.0)
	assert_true(int(fast["grains"]) > 8 and int(fast["dust"]) >= 1)


func test_strike_sprays() -> void:
	var t: Tuning = Tuning.shared()
	assert_true(int(SandFxPlan.strike(t, 1.0, 1.0, 0.0)["grains"]) > 30)


func test_deepen_and_lift() -> void:
	var t: Tuning = Tuning.shared()
	var foot: float = SandMap.deepen(0.018, t.sand_depth_scale, t.sand_deep_from, t.sand_deep_gain, t.sand_max_depth)
	assert_true(foot > 0.035 and foot < 0.05, "a step is a few cm: %f" % foot)
	var fall: float = SandMap.deepen(0.062, t.sand_depth_scale, t.sand_deep_from, t.sand_deep_gain, t.sand_max_depth)
	assert_true(fall > 0.15 and fall <= t.sand_max_depth, "a fall is deeper: %f" % fall)
	assert_near(SandMap.deepen(5.0, 2.0, 0.0, 1.0, 0.1), 0.1, 0.0001, "capped")
	assert_near(SandMap.lift_at(0.0, 0.0, 11.0, 0.03), 0.03)
	assert_near(SandMap.lift_at(11.5, 0.0, 11.0, 0.03), 0.0)
