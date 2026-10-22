extends TestCase


func test_weight_eases_in_holds_and_releases() -> void:
	assert_eq(FinaleShot.weight_at(0.0, 0.6, 3.0, 1.5), 0.0)
	var mid: float = FinaleShot.weight_at(0.3, 0.6, 3.0, 1.5)
	assert_true(mid > 0.0 and mid < 1.0)
	assert_eq(FinaleShot.weight_at(2.0, 0.6, 3.0, 1.5), 1.0)
	assert_true(FinaleShot.weight_at(3.75, 0.6, 3.0, 1.5) < 1.0)
	assert_eq(FinaleShot.weight_at(5.0, 0.6, 3.0, 1.5), 0.0)


func test_side_dir_is_perpendicular_and_faces_arena_centre() -> void:
	var s: Vector3 = FinaleShot.side_dir(Vector3(8, 1, 0), Vector3(9, 1, 0))
	assert_true(absf(s.x) < 0.001 and absf(s.length() - 1.0) < 0.001)
	var s2: Vector3 = FinaleShot.side_dir(Vector3(0, 1, 0), Vector3(1, 1, 4))
	var victim := Vector2(1, 4)
	var chosen: float = (victim + Vector2(s2.x, s2.z)).length()
	var other: float = (victim - Vector2(s2.x, s2.z)).length()
	assert_true(chosen <= other + 0.001, "camera side is the one nearer the arena centre")


func test_start_holds_chest_point_and_clears_after_release() -> void:
	var tun: Tuning = Tuning.shared()
	var f := FinaleShot.new()
	f.start(Vector3(1, 1, 0), Vector3(-1, 0.3, 0), Vector3(-1, 1.5, 0), tun)
	assert_true(f.active)
	assert_true(absf(f.look().y - tun.feel_finale_look_y) < 0.001, "held at chest height, not the fallen pelvis")
	for i: int in 600:
		f.update(1.0 / 60.0, Vector3(-1, 0.1, 0))
	assert_true(not f.active)
	assert_eq(f.weight, 0.0)


func test_update_ignores_non_finite_victim() -> void:
	var f := FinaleShot.new()
	f.start(Vector3.ZERO, Vector3(2, 1, 0), Vector3(2, 1, 0), Tuning.shared())
	f.update(0.1, Vector3(NAN, 0, NAN))
	assert_true(FightCamera.is_finite_v3(f.look()))


func test_squeeze_hysteresis_holds_then_falls_slowly() -> void:
	var t: float = 0.0
	for i: int in 30:
		t = FightCamera.step_squeeze(t, 0.8, 1.0 / 60.0, 6.0, 1.2, 0.12)
	assert_true(t > 0.5)
	var held: float = FightCamera.step_squeeze(t, t - 0.05, 1.0 / 60.0, 6.0, 1.2, 0.12)
	assert_eq(held, t, "inside the deadband nothing moves")
	var fall: float = FightCamera.step_squeeze(t, 0.0, 1.0 / 60.0, 6.0, 1.2, 0.12)
	var rise: float = FightCamera.step_squeeze(0.0, 0.8, 1.0 / 60.0, 6.0, 1.2, 0.12)
	assert_true(fall < t and t - fall < rise, "falls slower than it rises")


func test_flicker_target_does_not_make_blend_jitter() -> void:
	var t: float = 0.5
	var lo: float = t
	var hi: float = t
	for i: int in 120:
		var target: float = 0.5 + (0.08 if i % 2 == 0 else -0.08)
		t = FightCamera.step_squeeze(t, target, 1.0 / 60.0, 6.0, 1.2, 0.12)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	assert_true(hi - lo < 0.1)


func test_choose_view_stays_inside_the_wall() -> void:
	# Victim near the wall on +X, attacker inside: a side-on camera 3.6 m away fits on one side only.
	var v: Dictionary = FinaleShot.choose_view(Vector3(6, 0, 0), Vector3(9.5, 0, 0), 3.6, 11.0, 0.7)
	var d: Vector3 = v["dir"]
	assert_true(not bool(v["high"]))
	var cam := Vector2(9.5 + d.x * 3.6, d.z * 3.6)
	assert_true(cam.length() <= 11.0 - 0.7 + 0.001, "camera inside the wall radius")


func test_choose_view_falls_back_to_high_three_quarter() -> void:
	# Both sides are outside the wall: high shot from the interior side.
	var v: Dictionary = FinaleShot.choose_view(Vector3(8, 0, 0), Vector3(10, 0, 0), 6.0, 11.0, 0.7)
	assert_true(bool(v["high"]))
	var d: Vector3 = v["dir"]
	assert_true(d.x < 0.0, "points toward the arena centre")
	assert_true(absf(d.length() - 1.0) < 0.001)


func test_inside_wall_clamps_a_flung_victim() -> void:
	var p: Vector3 = FinaleShot.inside_wall(Vector3(30, 0.4, 0), 11.0, 0.7)
	assert_true(Vector2(p.x, p.z).length() <= 10.3 + 0.001)
	assert_true(absf(p.y - 0.4) < 0.0001)
	assert_eq(FinaleShot.inside_wall(Vector3(3, 1, 3), 11.0, 0.7), Vector3(3, 1, 3))


func test_head_bias_moves_from_fountain_to_head() -> void:
	assert_true(absf(FinaleShot.head_bias(0.0, 0.2, 0.65, 2.0) - 0.2) < 0.001)
	assert_true(absf(FinaleShot.head_bias(5.0, 0.2, 0.65, 2.0) - 0.65) < 0.001)
	assert_true(FinaleShot.head_bias(1.0, 0.2, 0.65, 2.0) > 0.2)


func test_head_distance_and_reach_are_clamped() -> void:
	assert_eq(FinaleShot.framing_dist(3.6, 0.0, 7.5), 3.6)
	assert_eq(FinaleShot.framing_dist(3.6, 40.0, 7.5), 7.5)
	var h: Vector3 = FinaleShot.clamp_head(Vector3.ZERO, Vector3(20, 0, 0), 5.0)
	assert_true(absf(h.x - 5.0) < 0.001)
	assert_eq(FinaleShot.clamp_head(Vector3.ZERO, Vector3(2, 0, 0), 5.0), Vector3(2, 0, 0))


func test_beheading_shot_tracks_head_then_leans_to_it() -> void:
	var tun: Tuning = Tuning.shared()
	var f := FinaleShot.new()
	f.start(Vector3(1, 1, 0), Vector3(-1, 0.3, 0), Vector3(-1, 1.5, 0), tun, 11.0, 0.7)
	var body := Vector3(-1, 0.3, 0)
	f.update(0.016, body, Vector3(-1.2, 0.2, 0.0))
	assert_true(f.has_head())
	var early: float = f.look().distance_to(f.look_body())
	for i: int in 180:
		f.update(1.0 / 60.0, body, Vector3(-3.5, 0.15, 1.0))
	var late: float = f.look().distance_to(f.look_body())
	assert_true(late > early, "look point has moved toward the rolled head")
	assert_true(f.distance() > tun.feel_finale_dist and f.distance() <= tun.feel_finale_dist_max + 0.001)
	f.update(0.016, body, Vector3(200, 0, 0))
	assert_true(f.head_point().distance_to(f.look_body()) <= tun.feel_finale_head_reach + 0.01, "far head is clamped")
	f.update(0.016, body)
	assert_true(not f.has_head())


func test_head_free_after_the_shot_ended_restarts_it() -> void:
	var f := FinaleShot.new()
	f.start(Vector3(1, 1, 0), Vector3(-1, 0.9, 0), Vector3(-1, 1.5, 0), Tuning.shared())
	for i: int in 600:
		f.update(1.0 / 60.0, Vector3(-1, 0.2, 0))
	assert_true(not f.active)
	f.head_free(Vector3(-1.5, 0.2, 0.5))
	assert_true(f.active)
	assert_eq(f.weight, 0.0, "eases in from nothing")
	var max_w: float = 0.0
	for i: int in 60:
		f.update(1.0 / 60.0, Vector3(-1.5, 0.2, 0.5), Vector3(0.5, 0.2, 0.5))
		max_w = maxf(max_w, f.weight)
	assert_true(max_w > 0.99 and f.has_head())


func test_head_free_in_release_rises_without_a_jump_and_extends_the_hold() -> void:
	var f := FinaleShot.new()
	f.start(Vector3(1, 1, 0), Vector3(-1, 0.9, 0), Vector3(-1, 1.5, 0), Tuning.shared())
	var steps: int = int((Tuning.shared().feel_finale_hold_s + 0.4) * 60.0)
	for i: int in steps:
		f.update(1.0 / 60.0, Vector3(-1, 0.2, 0))
	var w0: float = f.weight
	assert_true(w0 < 1.0 and w0 > 0.0, "in the release")
	f.head_free(Vector3(-1, 0.2, 0))
	assert_near(f.weight, w0, 0.01, "no jump")
	for i: int in 120:
		f.update(1.0 / 60.0, Vector3(-1, 0.2, 0), Vector3(1.0, 0.2, 1.0))
	assert_eq(f.weight, 1.0, "held again for the head")


func test_head_side_films_body_and_head_side_on() -> void:
	var s: Vector3 = FinaleShot.head_side(Vector3(0, 0.5, 0), Vector3(2, 0.2, 0), Vector3(0, 0, 1))
	assert_near(s.x, 0.0, 0.001)
	assert_near(s.z, 1.0, 0.001, "keeps the side nearer the current one")
	assert_eq(FinaleShot.head_side(Vector3.ZERO, Vector3(0.1, 0, 0), Vector3(1, 0, 0)), Vector3(1, 0, 0))
	var t: Vector3 = FinaleShot.turn_toward(Vector3(1, 0, 0), Vector3(0, 0, 1), 0.1)
	assert_near(Vector2(1, 0).angle_to(Vector2(t.x, t.z)), 0.1, 0.001)


func test_look_sinks_to_a_body_on_the_sand() -> void:
	var tun: Tuning = Tuning.shared()
	var f := FinaleShot.new()
	f.start(Vector3(1, 1, 0), Vector3(-1, 0.9, 0), Vector3(-1, 1.5, 0), tun)
	for i: int in 150:
		f.update(1.0 / 60.0, Vector3(-1, 0.15, 0))
	assert_true(f.look().y < tun.feel_finale_look_y - 0.2, "look %.2f" % f.look().y)
	assert_true(f.look().y >= 0.34)
