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


## Regression (gut_close.png showed the victim's back and shorts): the close shot of a gut wound is filmed from the
## wound's side, i.e. the attacker's side of the victim, a little low, whatever way the previous shot looked.
func test_gut_close_shot_faces_the_wound_not_the_back() -> void:
	var torso := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1.33, 0))  # the victim faces +Z
	var attacker := Vector3(0, 1.3, 1.0)
	var point := Vector3(0.03, 1.2, 0.11)  # the blade's contact on the belly
	var wf: Dictionary = KillcamPlan.wound_frame(torso, point, attacker)
	var out_w: Vector3 = torso.basis * (wf["out"] as Vector3)
	assert_true(out_w.z > 0.9, "the wound faces the attacker: %s" % str(out_w))
	var target: Vector3 = torso * (wf["point"] as Vector3)
	assert_true(target.is_equal_approx(point), "the wound point round-trips")
	for side: float in [1.0, -1.0]:
		var v: Array = KillcamPlan.close_wound_view(target, out_w, side, 1.0, 11.0)
		var cam: Vector3 = v[0]
		assert_true(cam.z - target.z > 0.8, "camera on the belly side, not behind: %s" % str(cam))
		assert_true(cam.y < target.y, "slightly low: %s" % str(cam))
		assert_true((v[1] as Vector3).is_equal_approx(target))


func test_wound_on_the_far_side_turns_to_the_attacker() -> void:
	var part := Transform3D(Basis(), Vector3(0, 1.3, 0))
	var wf: Dictionary = KillcamPlan.wound_frame(part, Vector3(0, 1.3, 0.1), Vector3(0, 1.3, -2.0))
	assert_true((wf["out"] as Vector3).z < -0.9, "flipped toward the attacker at -Z: %s" % str(wf["out"]))
	var on_axis: Dictionary = KillcamPlan.wound_frame(part, Vector3(0, 1.4, 0.0), Vector3(2.0, 1.3, 0))
	assert_true((on_axis["out"] as Vector3).x > 0.9, "no radius: the attacker's direction")


func test_wound_follows_the_body_when_it_falls() -> void:
	var standing := Transform3D(Basis(), Vector3(0, 1.3, 0))  # faces -Z
	var wf: Dictionary = KillcamPlan.wound_frame(standing, Vector3(0, 1.25, -0.11), Vector3(0, 1.3, -1.0))
	var on_back := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.15, 0))  # local -Z now points up
	var out_w: Vector3 = on_back.basis * (wf["out"] as Vector3)
	assert_true(out_w.y > 0.9, "the belly faces the sky: %s" % str(out_w))
	var target: Vector3 = on_back * (wf["point"] as Vector3)
	var cam: Vector3 = KillcamPlan.close_wound_view(target, out_w, 1.0, 2.0, 11.0)[0]
	assert_true(cam.y > target.y + 1.0, "filmed from above: %s" % str(cam))
	var face_down: Vector3 = KillcamPlan.close_wound_view(Vector3(0, 0.15, 0), Vector3.DOWN, 1.0, 2.0, 11.0)[0]
	assert_true(face_down.y >= KillcamPlan.CAM_MIN_Y - 0.001, "a wound facing the sand is filmed from its side, above the sand")


func test_wound_side_keeps_the_attacker_out_of_the_sightline() -> void:
	var target := Vector3(0, 1.2, 0)
	var out := Vector3(0, 0, 1)
	var attacker := Vector3(0.4, 1.3, 0.9)  # in front of the wound, a little to +X
	var s: float = KillcamPlan.wound_side(target, out, attacker)
	var cam: Vector3 = KillcamPlan.close_wound_view(target, out, s, 2.0, 11.0)[0]
	assert_true(cam.x < 0.0, "swings to -X, away from him: %s" % str(cam))
	assert_eq(KillcamPlan.wound_side(target, out, Vector3(-0.4, 1.3, 0.9)), -s, "mirrored attacker, mirrored side")


func test_stump_frame_looks_at_the_cut_face() -> void:
	var arm: Dictionary = KillcamPlan.stump_frame("upper_arm_r")
	assert_true((arm["point"] as Vector3).is_equal_approx(Vector3(0.23, 0.2, 0.0)), "the shoulder on the torso")
	assert_true((arm["out"] as Vector3).y < 0.0 and (arm["out"] as Vector3).x > 0.0, "down along the arm, from the right side")
	var leg: Dictionary = KillcamPlan.stump_frame("shin_l")
	assert_true((leg["out"] as Vector3).y < -0.99, "a knee stump faces down: %s" % str(leg["out"]))
	assert_true(KillcamPlan.stump_frame("pelvis").is_empty())
