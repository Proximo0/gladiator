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


func test_step_lead_tracks_steady_motion_and_ignores_cuts() -> void:
	var v := Vector3.ZERO
	var p := Vector3.ZERO
	for i: int in 120:
		var n: Vector3 = p + Vector3(4.0 / 60.0, 0, 0)
		v = FightCamera.step_lead(v, p, n, 1.0 / 60.0, 8.0, 9.0, 0.3)
		p = n
	assert_near(v.x, 4.0, 0.05, "lead converges on the 4 m/s roll speed")
	var after_cut: Vector3 = FightCamera.step_lead(Vector3.ZERO, p, p + Vector3(5, 0, 0), 1.0 / 60.0, 8.0, 9.0, 0.3)
	assert_eq(after_cut, Vector3.ZERO, "a 5 m jump is a cut, not motion")
	assert_eq(FightCamera.step_lead(v, p, p, 0.0, 8.0, 9.0, 0.3), v, "zero delta keeps the lead")


func test_led_follow_has_no_steady_lag() -> void:
	# The update rule used by the camera: x += v dt, then x -> want at follow_rate. With v = the want's speed the
	# steady lag is ~0 (without the lead it is speed / rate = 0.8 m at 4 m/s).
	var x := Vector3.ZERO
	var w := Vector3.ZERO
	var v := Vector3.ZERO
	var k: float = FightCamera.smooth_factor(5.0, 1.0 / 60.0)
	for i: int in 180:
		var nw: Vector3 = w + Vector3(4.0 / 60.0, 0, 0)
		v = FightCamera.step_lead(v, w, nw, 1.0 / 60.0, 8.0, 9.0, 0.3)
		w = nw
		x = (x + v / 60.0).lerp(w, k)
	assert_true(x.distance_to(w) < 0.05, "lag %.3f" % x.distance_to(w))


func test_lens_widens_only_on_portrait() -> void:
	assert_eq(FightCamera.lens_for_aspect(55.0, 16.0 / 9.0, 50.0, 25.0), 55.0)
	var p: float = FightCamera.lens_for_aspect(55.0, 9.0 / 16.0, 50.0, 25.0)
	assert_true(p > 55.0 and p <= 80.0)
	var h: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(p) * 0.5) * 9.0 / 16.0))
	assert_true(h >= 49.0 or p >= 79.99, "horizontal view %.1f" % h)


func test_fit_dir_keeps_fitting_direction_and_turns_inward_continuously() -> void:
	var mid := Vector3(8, 0, 0)
	assert_eq(FightCamera.fit_dir(mid, Vector3(-1, 0, 0), 4.0, 10.3), Vector3(-1, 0, 0), "already inside")
	var prev := Vector3.ZERO
	for i: int in 30:
		var m := Vector3(6.0 + i * 0.1, 0, 0.5)
		var d: Vector3 = FightCamera.fit_dir(m, Vector3(0, 0, 1), 6.0, 10.3, m + prev * 6.0, i > 0)
		assert_true(Vector2(m.x + d.x * 6.0, m.z + d.z * 6.0).length() <= 10.3 + 0.01, "inside the wall")
		if i > 0:
			assert_true(d.distance_to(prev) < 0.2, "no jump at step %d" % i)
		prev = d


func test_swing_inside_is_continuous_and_inside() -> void:
	var look := Vector3(0, 1.8, 6.0)
	var sign: float = 0.0
	var prev := Vector3.INF
	for i: int in 200:
		# The camera's free pose drifts out through the wall behind a fighter backing up to it.
		var pos := Vector3(0.3, 4.0, 9.5 + i * 0.02)
		var sw: Dictionary = FightCamera.swing_inside(pos, look, 10.3, 0.8, 2.0, sign)
		sign = sw["sign"]
		var p: Vector3 = sw["pos"]
		assert_true(Vector2(p.x, p.z).length() <= 10.3 + 0.01, "inside")
		if prev != Vector3.INF:
			assert_true(p.distance_to(prev) < 0.15, "step %d moved %.2f" % [i, p.distance_to(prev)])
		prev = p
	assert_true(not FightCamera.swing_inside(Vector3(0, 4, 9), look, 10.3, 0.8, 2.0)["cut"])


func test_side_pose_never_crosses_the_fight_line_near_the_wall() -> void:
	# Fighters walking along the wall: the side-on camera stays on one side of their line.
	for i: int in 40:
		var ang: float = i * 0.05
		var a := Vector3(cos(ang) * 8.0, 0.9, sin(ang) * 8.0)
		var b := Vector3(cos(ang + 0.4) * 8.0, 0.9, sin(ang + 0.4) * 8.0)
		var pose: Dictionary = FightCamera.side_pose(a, b, 55.0, 4.4, 6.0, 10.3, 1.0)
		var p: Vector3 = pose["pos"]
		var s: Vector3 = FightCamera.flat_dir(a, b).cross(Vector3.UP)
		assert_true((p - (a + b) * 0.5).dot(s) >= -0.01, "same side at %d" % i)
		assert_true(Vector2(p.x, p.z).length() <= 10.31)


func test_pull_back_is_refined_below_the_step() -> void:
	var me := Vector3(0, 0.95, 2.0)
	var opp := Vector3(0.3, 0.95, -2.0)
	var pose: Dictionary = FightCamera.follow_pose(me, opp, 3.4, 2.3, 0.7)
	var pts: Array = FightCamera.frame_points(me) + FightCamera.frame_points(opp)
	var pull: float = FightCamera.pull_back_for(pose["pos"], pose["look"], 55.0, 9.0 / 16.0, pts, 0.82, 12.0)
	var away: Vector3 = ((pose["pos"] as Vector3) - (pose["look"] as Vector3)).normalized()
	assert_true(FightCamera.frame_ratio((pose["pos"] as Vector3) + away * pull, pose["look"], 55.0, 9.0 / 16.0, pts) <= 0.82 + 0.001)
	if pull > 0.05:
		assert_true(FightCamera.frame_ratio((pose["pos"] as Vector3) + away * (pull - 0.03), pose["look"], 55.0, 9.0 / 16.0, pts) > 0.82, "close to the least pull")


func test_squeeze_blend_does_not_stick_at_the_deadband() -> void:
	var t: float = 0.12
	for i: int in 600:
		t = FightCamera.step_squeeze(t, 0.0, 1.0 / 60.0, 6.0, 1.2, 0.12)
	assert_true(t < 0.01, "left at %.3f" % t)


func test_tuned_falls_back_for_missing_rows() -> void:
	assert_eq(FightCamera.tuned(Tuning.shared(), "no_such_camera_row", 2.5), 2.5)
	assert_near(FightCamera.tuned(Tuning.shared(), "feel_frame_margin", 0.0), Tuning.shared().feel_frame_margin)


func test_real_frame_delta_uses_the_speed_the_frame_ran_at() -> void:
	var cam := FightCamera.new()
	var real: float = 1.0 / 60.0
	# Full speed, then slow motion (0.2) starts: the first slow frame still ran at full speed (delta unscaled).
	assert_near(cam.real_frame_delta(real, 1.0), real)
	assert_near(cam.real_frame_delta(real, 0.2), real, 0.0001, "first slow-motion frame is not 5x long")
	assert_near(cam.real_frame_delta(real * 0.2, 0.2), real, 0.0001, "slow frames undo the scale")
	# Back to full speed: the first full-speed frame still ran slowed (delta scaled by 0.2).
	assert_near(cam.real_frame_delta(real * 0.2, 1.0), real, 0.0001, "first full-speed frame is not 5x short")
	assert_near(cam.real_frame_delta(real, 1.0), real)
	assert_near(cam.real_frame_delta(real, NAN), real, 0.0001, "a NaN speed keeps the last good one")
	cam.free()
