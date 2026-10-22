extends TestCase
## GaitLogic: planted feet hold their spot, the feet take turns, cadence and stance time follow speed, the feet
## never cross sideways, and a standing fighter only steps when a foot has drifted.


func _p() -> Dictionary:
	return {
		"cadence_base": 2.0, "cadence_per_speed": 0.45, "cadence_lateral": 1.0, "span": 0.45, "span_lat": 0.3,
		"stance_max": 0.4, "swing_min": 0.18, "swing_max": 0.45, "lift": 0.13, "shuffle_lift": 0.45, "reach": 0.42,
		"lead_max": 0.3, "min_gap": 0.14, "idle_err": 0.12, "min_speed": 0.25,
		"stance_l": Vector3(-0.07, 0.0, -0.18), "stance_r": Vector3(0.07, 0.0, -0.06),
	}


func _hips(c: Vector3) -> Array:
	return [c + Vector3(-0.1, 0.86, 0.0), c + Vector3(0.1, 0.86, 0.0)]


## Walks the hips along `vel` for `ticks`; returns [gait, landings per foot, max planted drift, min side gap].
func _walk(vel: Vector3, ticks: int) -> Array:
	var g := GaitLogic.new()
	var p: Dictionary = _p()
	var yb := Basis()
	var c := Vector3.ZERO
	var drift: float = 0.0
	var gap: float = 9.0
	var lands: Array[int] = [0, 0]
	g.reset(_hips(c), yb, p)
	for _k: int in range(ticks):
		var before: Array = [g.plant[0], g.plant[1], g.planted(0), g.planted(1)]
		c += vel / 60.0
		g.tick(1.0 / 60.0, _hips(c), yb, vel, p)
		for i: int in range(2):
			if bool(before[2 + i]) and g.planted(i):
				drift = maxf(drift, (g.plant[i] - (before[i] as Vector3)).length())
			elif not bool(before[2 + i]) and g.planted(i):
				lands[i] += 1
		gap = minf(gap, g.target(1).x - g.target(0).x)
	return [g, lands, drift, gap]


func test_standing_still_never_steps() -> void:
	var r: Array = _walk(Vector3.ZERO, 120)
	assert_eq((r[1] as Array), [0, 0])
	assert_true((r[0] as GaitLogic).planted(0) and (r[0] as GaitLogic).planted(1))


func test_walk_alternates_feet_and_planted_feet_hold() -> void:
	var r: Array = _walk(Vector3(0, 0, -2.5), 180)
	var lands: Array = r[1]
	assert_true(int(lands[0]) >= 3 and int(lands[1]) >= 3, "both feet step: %s" % [lands])
	assert_true(absi(int(lands[0]) - int(lands[1])) <= 1, "alternating: %s" % [lands])
	assert_near(float(r[2]), 0.0, 0.0001)


func test_strafe_feet_never_cross() -> void:
	for v: Vector3 in [Vector3(1.75, 0, 0), Vector3(-1.75, 0, 0)]:
		var r: Array = _walk(v, 240)
		assert_true(float(r[3]) >= 0.14 - 0.0001, "gap %.3f" % float(r[3]))
		assert_true(int((r[1] as Array)[0]) >= 3, "steps sideways")


func test_cadence_and_stance_follow_speed() -> void:
	var p: Dictionary = _p()
	var walk: float = GaitLogic.cadence(Vector3(0, 0, -2.5), Basis(), p)
	var sprint: float = GaitLogic.cadence(Vector3(0, 0, -4.5), Basis(), p)
	assert_true(sprint > walk)
	assert_true(GaitLogic.cadence(Vector3(1.5, 0, 0), Basis(), p) > GaitLogic.cadence(Vector3(0, 0, -1.5), Basis(), p))
	var st_walk: float = GaitLogic.stance_time(2.5, 1.0 / walk, p)
	var st_sprint: float = GaitLogic.stance_time(4.5, 1.0 / sprint, p)
	assert_true(st_sprint < st_walk)
	assert_near(st_walk, 0.45 / 2.5, 0.0001)
	assert_true(GaitLogic.swing_time(2.5, 1.0 / walk, p) >= 0.18)


func test_drifted_foot_steps_back_under() -> void:
	var g := GaitLogic.new()
	var p: Dictionary = _p()
	g.reset(_hips(Vector3.ZERO), Basis(), p)
	g.plant[1] += Vector3(0.3, 0, 0)
	var landed: bool = false
	for _k: int in range(60):
		g.tick(1.0 / 60.0, _hips(Vector3.ZERO), Basis(), Vector3.ZERO, p)
		landed = landed or (g.steps > 0)
	assert_true(landed)
	assert_near(g.plant[1].x, 0.17, 0.02)


func test_lands_where_the_foot_really_is() -> void:
	var g := GaitLogic.new()
	var p: Dictionary = _p()
	var c := Vector3.ZERO
	var v := Vector3(0, 0, -2.5)
	var real: Array = [Vector3(-0.3, 0.0, 0.5), Vector3(0.3, 0.0, 0.5)]
	for _k: int in range(90):
		c += v / 60.0
		g.tick(1.0 / 60.0, _hips(c), Basis(), v, p, true, real)
	assert_true(g.steps > 0)
	var hit: bool = g.plant[0].is_equal_approx(real[0]) or g.plant[1].is_equal_approx(real[1])
	assert_true(hit)


func test_swing_arc_and_sway() -> void:
	var g := GaitLogic.new()
	var p: Dictionary = _p()
	var c := Vector3.ZERO
	var v := Vector3(0, 0, -2.0)
	var top: float = 0.0
	var sway_seen: bool = false
	for _k: int in range(60):
		c += v / 60.0
		g.tick(1.0 / 60.0, _hips(c), Basis(), v, p)
		for i: int in range(2):
			top = maxf(top, g.target(i).y)
			if not g.planted(i):
				sway_seen = sway_seen or absf(g.sway()) > 0.3
		assert_true(g.bob() >= 0.0 and g.bob() <= 1.0)
	assert_true(top > 0.05 and top <= 0.13 + 0.0001)
	assert_true(sway_seen)


func test_round_trip() -> void:
	var r: Array = _walk(Vector3(0, 0, -2.5), 37)
	var g: GaitLogic = r[0]
	var h := GaitLogic.new()
	h.from_array(g.to_array())
	assert_eq(h.to_array(), g.to_array())
	var e := GaitLogic.new()
	e.from_array([])
	assert_false(e.ready)
