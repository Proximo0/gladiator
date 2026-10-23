extends TestCase
## ReachPlan: who holds a long blade, the bait cycle's standing distance, and the over-commit recovery.


func test_holder_is_a_long_two_handed_blade() -> void:
	assert_true(ReachPlan.is_holder("sword", true, 1.25, 1.2), "dai-katana")
	assert_false(ReachPlan.is_holder("sword", false, 1.25, 1.2), "laser sword is one-handed")
	assert_false(ReachPlan.is_holder("sword", true, 1.05, 1.2), "shorter two-handed sword")
	assert_false(ReachPlan.is_holder("axe", true, 1.5, 1.2), "not a sword")


func test_bait_hold_steps_in_then_out() -> void:
	assert_near(ReachPlan.bait_hold(10, 100, 60, 30, 2.0, 0.35, 0.25), 2.35, 0.001, "waiting outside")
	assert_near(ReachPlan.bait_hold(60, 100, 60, 30, 2.0, 0.35, 0.25), 1.75, 0.001, "bait starts")
	assert_near(ReachPlan.bait_hold(89, 100, 60, 30, 2.0, 0.35, 0.25), 1.75, 0.001, "last bait tick")
	assert_near(ReachPlan.bait_hold(90, 100, 60, 30, 2.0, 0.35, 0.25), 2.35, 0.001, "falls back out")
	assert_near(ReachPlan.bait_hold(160, 100, 60, 30, 2.0, 0.35, 0.25), 1.75, 0.001, "the cycle repeats")


func test_baiting_matches_the_hold() -> void:
	assert_false(ReachPlan.baiting(59, 100, 60, 30))
	assert_true(ReachPlan.baiting(75, 100, 60, 30))
	assert_false(ReachPlan.baiting(95, 100, 60, 30))
	assert_false(ReachPlan.baiting(5, 0, 60, 30), "a zero cycle does not divide by zero")


func test_recover_stretches_only_an_over_commit() -> void:
	assert_eq(ReachPlan.recover_ticks(30, false, 2.0, 65), 30)
	assert_eq(ReachPlan.recover_ticks(30, true, 2.0, 65), 60)
	assert_eq(ReachPlan.recover_ticks(40, true, 2.0, 65), 65, "capped")
	assert_eq(ReachPlan.recover_ticks(30, true, 0.5, 65), 30, "never shorter than the base")
