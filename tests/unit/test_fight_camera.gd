extends TestCase

const ASPECT: float = 16.0 / 9.0


func test_frame_ratio_close_pair_fits_and_far_pair_does_not() -> void:
	var look := Vector3(0, 1, 0)
	var pos := Vector3(0, 3, 8)
	var near_pts: Array = FightCamera.frame_points(Vector3(-0.8, 0.95, 0)) + FightCamera.frame_points(Vector3(0.8, 0.95, 0))
	var far_pts: Array = FightCamera.frame_points(Vector3(-9, 0.95, 0)) + FightCamera.frame_points(Vector3(9, 0.95, 0))
	assert_true(FightCamera.frame_ratio(pos, look, 55.0, ASPECT, near_pts) < 1.0)
	assert_true(FightCamera.frame_ratio(pos, look, 55.0, ASPECT, far_pts) > 1.0)


func test_point_behind_camera_is_outside() -> void:
	var pts: Array = [Vector3(0, 1, 20)]
	assert_true(FightCamera.frame_ratio(Vector3(0, 1, 0), Vector3(0, 1, -5), 55.0, ASPECT, pts) > 10.0)


func test_pull_back_frames_a_wide_pair_in_follow_pose() -> void:
	var me := Vector3(-8, 0.95, 0)
	var opp := Vector3(8, 0.95, 0)
	var pose: Dictionary = FightCamera.follow_pose(me, opp, 3.4, 1.9, 0.7)
	var pts: Array = FightCamera.frame_points(me) + FightCamera.frame_points(opp)
	var before: float = FightCamera.frame_ratio(pose["pos"], pose["look"], 55.0, ASPECT, pts)
	assert_true(before > 1.0, "the over-the-shoulder pose loses a far opponent")
	var pull: float = FightCamera.pull_back_for(pose["pos"], pose["look"], 55.0, ASPECT, pts, 0.82, 12.0)
	assert_true(pull > 0.0)
	var away: Vector3 = ((pose["pos"] as Vector3) - (pose["look"] as Vector3)).normalized()
	var after: float = FightCamera.frame_ratio((pose["pos"] as Vector3) + away * pull, pose["look"], 55.0, ASPECT, pts)
	assert_true(after <= 0.82 + 0.05, "framed after the pull: %f" % after)


func test_pull_is_capped_and_zero_when_already_framed() -> void:
	var pts: Array = FightCamera.frame_points(Vector3(-30, 1, 0)) + FightCamera.frame_points(Vector3(30, 1, 0))
	var pos := Vector3(0, 3, 6)
	assert_near(FightCamera.pull_back_for(pos, Vector3(0, 1, 0), 55.0, ASPECT, pts, 0.8, 3.0), 3.0)
	var near_pts: Array = FightCamera.frame_points(Vector3(-0.5, 1, 0))
	assert_eq(FightCamera.pull_back_for(pos, Vector3(0, 1, 0), 55.0, ASPECT, near_pts, 0.8, 3.0), 0.0)


func test_fov_widens_only_when_needed_and_is_capped() -> void:
	assert_eq(FightCamera.fov_to_fit(0.5, 55.0, 0.8, 18.0), 55.0)
	var w: float = FightCamera.fov_to_fit(1.2, 55.0, 0.8, 18.0)
	assert_true(w > 55.0 and w <= 73.0)
	assert_eq(FightCamera.fov_to_fit(9.0, 55.0, 0.8, 18.0), 73.0)


func test_wall_clamped_camera_gets_a_wider_lens_that_frames_both() -> void:
	# Fighters near the far wall, camera behind them pushed into the wall: widening must fit them.
	var me := Vector3(8, 0.95, 4)
	var opp := Vector3(8, 0.95, -4)
	var pts: Array = FightCamera.frame_points(me) + FightCamera.frame_points(opp)
	var pose: Dictionary = FightCamera.wide_pose(me, opp, 55.0, 3.2, 6.0, 10.3)
	var pos: Vector3 = FightCamera.clamp_to_arena(pose["pos"], 11.0, 0.7, 0.5)
	assert_true(pos.x < 8.0, "filmed from the inner side")
	var ratio: float = FightCamera.frame_ratio(pos, pose["look"], 55.0, ASPECT, pts)
	var fov: float = FightCamera.fov_to_fit(ratio, 55.0, 0.82, 18.0)
	assert_true(FightCamera.frame_ratio(pos, pose["look"], fov, ASPECT, pts) <= 0.82 + 0.02)


func test_fighters_sit_in_the_lower_middle_with_sand_under_their_feet() -> void:
	var a := Vector3(-1.2, 0.95, 0)
	var b := Vector3(1.2, 0.95, 0)
	var poses: Array = [
		FightCamera.wide_pose(a, b, 55.0, FightCamera.WIDE_HEIGHT, 6.0),
		FightCamera.follow_pose(a, b, 3.4, 2.3, 0.7),
	]
	for pose: Dictionary in poses:
		var look: Vector3 = pose["look"]
		var pts: Array = FightCamera.frame_points(a) + FightCamera.frame_points(b)
		var raw: Vector3 = pose["pos"]
		var pull: float = FightCamera.pull_back_for(raw, look, 55.0, ASPECT, pts, 0.82, 5.0)
		var pos: Vector3 = raw + (raw - look).normalized() * pull
		for p: Vector3 in [a, b]:
			var feet: float = FightCamera.screen_y(pos, look, 55.0, Vector3(p.x, 0.0, p.z))
			var head: float = FightCamera.screen_y(pos, look, 55.0, Vector3(p.x, 1.8, p.z))
			assert_true(feet < 0.82, "feet on screen with sand below: %f" % feet)
			assert_true(head > 0.2, "head on screen: %f" % head)
			assert_true((feet + head) * 0.5 > 0.42 and (feet + head) * 0.5 < 0.7, "body centre in the lower middle: %f" % ((feet + head) * 0.5))


func test_close_blend_is_full_in_melee_and_gone_at_range() -> void:
	assert_near(FightCamera.close_blend(1.0, 1.7, 3.6), 1.0)
	assert_near(FightCamera.close_blend(5.0, 1.7, 3.6), 0.0)
	var mid: float = FightCamera.close_blend(2.65, 1.7, 3.6)
	assert_true(mid > 0.4 and mid < 0.6, "smooth in between: %f" % mid)


func test_close_follow_pose_moves_off_the_back_line_and_up() -> void:
	var me := Vector3(0, 0.95, 0)
	var opp := Vector3(0, 0.95, -1.5)
	var far: Dictionary = FightCamera.follow_pose(me, opp, 3.4, 2.3, 0.7)
	var near: Dictionary = FightCamera.follow_pose(me, opp, 3.4, 2.3, 0.7, 1.0, 1.1, 0.7)
	assert_near(absf((near["pos"] as Vector3).x - (far["pos"] as Vector3).x), 1.1)
	assert_near((near["pos"] as Vector3).y - (far["pos"] as Vector3).y, 0.7)


func test_degenerate_inputs_never_give_nan_poses() -> void:
	var same := Vector3(2, 0.95, 1)
	var z: Dictionary = FightCamera.follow_pose(same, same, 3.4, 2.3, 0.7, 1.0, 1.1, 0.7)
	assert_true(FightCamera.is_finite_v3(z["pos"]) and FightCamera.is_finite_v3(z["look"]), "same spot follow")
	var w: Dictionary = FightCamera.wide_pose(same, same, 55.0, 4.4, 6.0, 10.0)
	assert_true(FightCamera.is_finite_v3(w["pos"]) and FightCamera.is_finite_v3(w["look"]), "same spot wide")
	assert_true(FightCamera.is_finite_v3(FightCamera.orbit_pose(same, 0.0, 0.3, 0.0)["pos"]))
	assert_near(FightCamera.close_blend(0.0, 1.7, 3.6), 1.0)
	assert_true(is_finite(FightCamera.frame_ratio(same, same, 55.0, ASPECT, FightCamera.frame_points(same))))
	assert_eq(FightCamera.pull_back_for(same, same, 55.0, ASPECT, [same], 0.9, 3.0), 0.0)


func test_smooth_factor_survives_zero_and_non_finite_delta() -> void:
	assert_eq(FightCamera.smooth_factor(5.0, 0.0), 0.0)
	assert_eq(FightCamera.smooth_factor(5.0, NAN), 0.0)
	assert_eq(FightCamera.smooth_factor(5.0, INF), 0.0)
	assert_eq(FightCamera.smooth_factor(NAN, 0.016), 0.0)


func test_limit_coord_and_finite_check() -> void:
	assert_false(FightCamera.is_finite_v3(Vector3(NAN, 0, 0)))
	assert_false(FightCamera.is_finite_v3(Vector3(0, INF, 0)))
	var v: Vector3 = FightCamera.limit_coord(Vector3(1.0e9, -1.0e9, 3.0))
	assert_eq(v, Vector3(FightCamera.MAX_COORD, -FightCamera.MAX_COORD, 3.0))
	var c: Vector3 = FightCamera.clamp_to_arena(v, 11.0, 0.7, 0.5)
	assert_true(Vector2(c.x, c.z).length() <= 10.3 + 0.001)


func test_real_delta_undoes_slow_motion() -> void:
	assert_true(absf(FightCamera.real_delta(0.004, 0.25) - 0.016) < 0.0001)
	assert_eq(FightCamera.real_delta(0.016, 1.0), 0.016)
	assert_eq(FightCamera.real_delta(0.016, 0.0) > 0.0, true)
	assert_eq(FightCamera.real_delta(NAN, 0.5), 0.0)
