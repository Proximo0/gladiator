extends TestCase
## KillcamPlan: picking the killing blow, the playback rate and shots around it, and where the cameras go.

const P: Dictionary = {"lead_s": 3.5, "tail_s": 1.6, "slow_rate": 0.25, "slow_pre_s": 0.2, "slow_post_s": 0.5,
	"tail_rate": 0.6, "ramp_s": 0.25}


func _hit(t: int, target: int, total: float = 10.0, on_weapon: bool = false) -> Array:
	return [t, target, "hit", {"target": target, "total": total, "hit_on_weapon": on_weapon, "point": Vector3(t, 1, 0)}, 7]


func _gore(t: int, side: int, kind: String, part: String = "head") -> Array:
	return [t, side, "gore", {"kind": kind, "part": part, "point": Vector3(0, 1.5, t)}, 9]


func test_finisher_gore_beats_a_later_hit() -> void:
	var ev: Array = [_hit(100, 1), _gore(300, 1, "gut", "torso"), _hit(310, 1, 2.0)]
	var m: Dictionary = KillcamPlan.pick(ev, 0, 0, 500, 210, 96)
	assert_eq(m["kill_tick"], 300)
	assert_eq(m["kind"], "gut")
	assert_eq(m["victim"], 1)
	assert_eq(m["attacker"], 0)
	assert_eq(m["start_tick"], 90)
	assert_eq(m["end_tick"], 396)
	assert_true((m["point"] as Vector3).is_equal_approx(Vector3(0, 1.5, 300)))


func test_head_sever_counts_as_behead_and_wins_a_tie() -> void:
	var ev: Array = [_gore(200, 0, "bleed"), _gore(200, 0, "sever", "upper_arm_r"), _gore(200, 0, "sever", "head")]
	var m: Dictionary = KillcamPlan.pick(ev, 1, 0, 400, 210, 96)
	assert_eq(m["kind"], "behead")
	assert_eq(m["part"], "head")


func test_winners_wounds_and_weapon_hits_are_not_the_kill() -> void:
	var ev: Array = [_hit(150, 1), _gore(260, 0, "behead"), _hit(270, 1, 30.0, true), _hit(280, 0)]
	var m: Dictionary = KillcamPlan.pick(ev, 0, 0, 400, 210, 96)
	assert_eq(m["kill_tick"], 150, "the last real hit on the victim")
	assert_eq(m["kind"], "hit")


func test_falls_back_to_the_death_and_clamps_to_the_buffer() -> void:
	var ev: Array = [_hit(5, 1), [400, 1, "died", {"point": Vector3(1, 0.3, 2)}, 0]]
	var m: Dictionary = KillcamPlan.pick(ev, 0, 0, 450, 210, 96)
	assert_eq(m["kind"], "death", "a hit at the very start of the buffer has no lead: the death is shown")
	assert_eq(m["start_tick"], 190)
	assert_eq(m["end_tick"], 450, "clamped to the newest stored tick")


func test_nothing_to_replay() -> void:
	assert_true(KillcamPlan.pick([_gore(100, 1, "behead")], -1, 0, 400, 210, 96).is_empty(), "a draw")
	assert_true(KillcamPlan.pick([], 0, 0, 400, 210, 96).is_empty(), "no events")
	assert_true(KillcamPlan.pick([_hit(100, 1)], 0, 0, 10, 210, 96).is_empty(), "too little recorded")
	assert_true(KillcamPlan.pick([_hit(600, 1)], 0, 0, 400, 210, 96).is_empty(), "after the buffer")


func test_rate_is_slow_at_the_impact_and_eases() -> void:
	assert_near(KillcamPlan.rate_at(-2.0, P), 1.0)
	assert_near(KillcamPlan.rate_at(0.0, P), 0.25)
	assert_near(KillcamPlan.rate_at(0.5, P), 0.25)
	assert_near(KillcamPlan.rate_at(1.5, P), 0.6)
	var mid: float = KillcamPlan.rate_at(-0.325, P)
	assert_true(mid < 1.0 and mid > 0.25, "eases in: %f" % mid)
	var prev: float = 2.0
	for i: int in 40:
		var r: float = KillcamPlan.rate_at(-0.6 + float(i) * 0.01, P)
		assert_true(r <= prev + 0.00001, "monotone into the slow motion")
		prev = r


func test_shots_run_hero_orbit_close() -> void:
	assert_eq(KillcamPlan.shot_at(-3.0, P), KillcamPlan.HERO)
	assert_eq(KillcamPlan.shot_at(-0.3, P), KillcamPlan.ORBIT)
	assert_eq(KillcamPlan.shot_at(0.3, P), KillcamPlan.ORBIT)
	assert_eq(KillcamPlan.shot_at(0.6, P), KillcamPlan.CLOSE)


func test_real_duration_of_the_default_replay() -> void:
	var d: float = KillcamPlan.real_duration(-3.5, 1.6, P)
	assert_true(d > 7.0 and d < 10.0, "about 8 s real for 5.1 s of fight: %f" % d)
	assert_near(KillcamPlan.real_duration(-3.0, -1.0, P), 2.0, 0.01)


func test_cameras_stay_inside_the_wall_and_above_the_sand() -> void:
	var att := Vector3(9.5, 0.9, 0.0)
	var vic := Vector3(10.4, 0.9, 0.5)
	var side: float = KillcamPlan.hero_side(att, vic, 11.0)
	for t: float in [0.0, 1.0, 4.0]:
		var h: Array = KillcamPlan.hero_view(att, vic, side, t, 11.0)
		var o: Array = KillcamPlan.orbit_view(vic, 0.0, t * 3.0, 11.0)
		var c: Array = KillcamPlan.close_view(Vector3(10.6, 0.1, 0.0), Vector3(1, 0, 0), t, 11.0)
		for v: Array in [h, o, c]:
			var p: Vector3 = v[0]
			assert_true(Vector2(p.x, p.z).length() <= 11.0 - KillcamPlan.WALL_MARGIN + 0.001, "inside the wall %s" % str(p))
			assert_true(p.y >= KillcamPlan.CAM_MIN_Y - 0.001, "above the sand %s" % str(p))
	var hv: Array = KillcamPlan.hero_view(Vector3.ZERO, Vector3(0, 0, -2), 1.0, 0.0, 11.0)
	assert_near((hv[0] as Vector3).y, KillcamPlan.HERO_LOW_Y, 0.001, "hero is low")
	assert_true((hv[1] as Vector3).y > (hv[0] as Vector3).y, "and looks up")


func test_orbit_turns_around_the_impact() -> void:
	var c := Vector3(1, 1, 1)
	var a: Array = KillcamPlan.orbit_view(c, 0.0, 0.0, 0.0)
	var b: Array = KillcamPlan.orbit_view(c, 0.0, 2.0, 0.0)
	assert_near(KillcamPlan.angle_of(c, b[0] as Vector3) - KillcamPlan.angle_of(c, a[0] as Vector3), deg_to_rad(KillcamPlan.ORBIT_DEG_S * 2.0), 0.001)
	assert_near(Vector2((a[0] as Vector3).x - c.x, (a[0] as Vector3).z - c.z).length(), KillcamPlan.ORBIT_RADIUS, 0.001)
	assert_true((a[1] as Vector3).is_equal_approx(c))


func test_params_read_tuning() -> void:
	var p: Dictionary = KillcamPlan.params(Tuning.shared())
	assert_near(float(p["slow_rate"]), Tuning.shared().killcam_slow_rate)
	assert_near(float(KillcamPlan.params(null)["lead_s"]), 3.5)


func test_skip_events_and_hint() -> void:
	var k := InputEventKey.new()
	k.pressed = true
	assert_true(KillCam.is_skip_event(k))
	k.echo = true
	assert_false(KillCam.is_skip_event(k), "a held key's repeat is not a skip")
	var mb := InputEventMouseButton.new()
	mb.pressed = false
	assert_false(KillCam.is_skip_event(mb), "a release is not a skip")
	var t := InputEventScreenTouch.new()
	t.pressed = true
	assert_true(KillCam.is_skip_event(t))
	assert_false(KillCam.is_skip_event(InputEventMouseMotion.new()))
	assert_eq(KillcamOverlay.hint_text(true), "Tap to skip")


func test_orbit_starts_side_on_and_turns_toward_the_attackers_back() -> void:
	var att := Vector3(0, 0.9, 1.0)
	var pt := Vector3(0, 1.2, 0)
	var o: Array = KillcamPlan.orbit_start(att, pt, 11.0)
	var a0: float = float(o[0])
	var turn: float = float(o[1])
	var side_a: float = a0 + turn * deg_to_rad(KillcamPlan.ORBIT_LEAD_DEG)
	assert_near(absf(cos(side_a)), 1.0, 0.001, "side-on to a blow along z is along x")
	var behind: float = KillcamPlan.angle_of(pt, att)
	var later: float = side_a + turn * deg_to_rad(45.0)
	assert_true(absf(angle_difference(later, behind)) < absf(angle_difference(side_a, behind)), "turning brings it behind the attacker")
