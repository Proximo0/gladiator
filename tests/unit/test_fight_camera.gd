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
