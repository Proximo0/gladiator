extends TestCase


func _tun() -> Tuning:
	return Tuning.new()


func test_cine_kinds() -> void:
	assert_true(FinisherCine.is_cine("behead"))
	assert_true(FinisherCine.is_cine("gut"))
	assert_true(FinisherCine.is_cine("run_through"))
	assert_false(FinisherCine.is_cine("skull_crush"))
	assert_false(FinisherCine.is_cine(""))


func test_time_scale_dips_holds_and_returns() -> void:
	var t: Tuning = _tun()
	assert_near(FinisherCine.time_scale_at("behead", 0.0, t), t.feel_cine_scale)
	assert_near(FinisherCine.time_scale_at("behead", t.feel_cine_hold_s * 0.9, t), t.feel_cine_scale)
	var mid: float = FinisherCine.time_scale_at("behead", t.feel_cine_hold_s + t.feel_cine_ramp_s * 0.5, t)
	assert_true(mid > t.feel_cine_scale and mid < 1.0)
	assert_near(FinisherCine.time_scale_at("behead", FinisherCine.length_s("behead", t) + 0.01, t), 1.0)
	var prev: float = 0.0
	for i: int in 100:
		var s: float = FinisherCine.time_scale_at("gut", float(i) * 0.02, t)
		assert_true(s >= prev - 0.0001, "never dips again once rising")
		prev = s


func test_other_ends_keep_the_plain_slowmo() -> void:
	var t: Tuning = _tun()
	assert_near(FinisherCine.time_scale_at("", 0.1, t), t.match_slowmo_scale)
	assert_near(FinisherCine.time_scale_at("skull_crush", t.match_slowmo_s + 0.01, t), 1.0)
	assert_near(FinisherCine.length_s("", t), t.match_slowmo_s)
	assert_eq(FinisherCine.roar_at("", t), -1.0)
	assert_eq(FinisherCine.muffle_at("", 0.5, t), 0.0)


func test_muffle_and_roar_meet_at_the_release() -> void:
	var t: Tuning = _tun()
	assert_near(FinisherCine.muffle_at("behead", t.feel_cine_hold_s * 0.5, t), 1.0)
	var roar: float = FinisherCine.roar_at("behead", t)
	assert_true(roar > 0.0 and roar <= t.feel_cine_hold_s)
	assert_eq(FinisherCine.muffle_at("behead", FinisherCine.length_s("behead", t), t), 0.0)
	assert_near(FinisherCine.cutoff_hz(1.0, t), t.feel_cine_lpf_hz, 0.5)
	assert_near(FinisherCine.cutoff_hz(0.0, t), 20000.0, 0.5)


func test_grade_fades_in_and_out() -> void:
	var t: Tuning = _tun()
	assert_eq(FinisherCine.grade_at("gut", -0.1, t), 0.0)
	assert_near(FinisherCine.grade_at("gut", t.feel_cine_hold_s * 0.5, t), 1.0)
	assert_eq(FinisherCine.grade_at("gut", FinisherCine.length_s("gut", t), t), 0.0)
	assert_eq(FinisherCine.grade_at("skull_crush", 0.3, t), 0.0)
