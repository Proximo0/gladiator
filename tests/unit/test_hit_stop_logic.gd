extends TestCase

const DT: float = 1.0 / 60.0


func _tun() -> Tuning:
	return Tuning.new()


func _hit(energy: float, total: float) -> Dictionary:
	return {"energy": energy, "total": total}


func test_classes_follow_impact_and_kind() -> void:
	var t: Tuning = _tun()
	assert_eq(HitStopLogic.hit_class({}, 0.05, t), HitStopLogic.CLASS_NONE)
	assert_eq(HitStopLogic.hit_class({}, 0.3, t), HitStopLogic.CLASS_LIGHT)
	assert_eq(HitStopLogic.hit_class({}, 0.6, t), HitStopLogic.CLASS_MEDIUM)
	assert_eq(HitStopLogic.hit_class({}, 0.9, t), HitStopLogic.CLASS_HEAVY)
	assert_eq(HitStopLogic.hit_class({"hit_on_weapon": true}, 0.9, t), HitStopLogic.CLASS_CLASH)
	assert_eq(HitStopLogic.hit_class({"sever": true}, 0.5, t), HitStopLogic.CLASS_SEVER)
	assert_eq(HitStopLogic.hit_class({"finisher": "behead"}, 0.1, t), HitStopLogic.CLASS_FINISHER)
	# A clash on a finishing blow is not a finisher (FeelLogic rule).
	assert_eq(HitStopLogic.hit_class({"finisher": "behead", "hit_on_weapon": true}, 0.5, t), HitStopLogic.CLASS_CLASH)


func test_hold_scales_with_impact_and_has_floors() -> void:
	var t: Tuning = _tun()
	assert_eq(HitStopLogic.request_s({}, 0.1, t), 0.0, "a tap does not stop")
	var light: float = HitStopLogic.request_s({}, t.feel_hitstop_min + 0.01, t)
	var heavy: float = HitStopLogic.request_s({}, 1.0, t)
	assert_true(light > 0.0 and light < heavy, "light %f heavy %f" % [light, heavy])
	assert_near(heavy, t.feel_hitstop_heavy_s, 0.001)
	assert_true(HitStopLogic.request_s({"sever": true}, 0.3, t) >= t.feel_hitstop_sever_s)
	assert_true(HitStopLogic.request_s({"hit_on_weapon": true}, 1.0, t) < heavy, "a clash is shorter")
	assert_true(HitStopLogic.request_s({"glanced": true}, 1.0, t) < heavy, "a glance is shorter")
	assert_near(HitStopLogic.request_s({"finisher": "gut"}, 0.9, t), t.feel_hitstop_finisher_s, 0.001)


func test_hold_then_catch_up_back_to_physics() -> void:
	var t: Tuning = _tun()
	var h := HitStopLogic.new()
	var held: float = h.request({}, 1.0, t)
	assert_true(held > 0.0)
	var slow_frames: int = 0
	var fast_frames: int = 0
	for i: int in 60:
		var rate: float = h.step(DT, t)
		if rate < 0.5:
			slow_frames += 1
		elif rate > 1.0:
			fast_frames += 1
	assert_false(h.active(), "back on physics within a second")
	assert_eq(h.lag, 0.0)
	assert_true(slow_frames >= 5 and slow_frames <= 7, "about 95 ms of hold at 60 fps: %d" % slow_frames)
	assert_true(fast_frames > 0, "catches up")


func test_holds_never_add_up() -> void:
	var t: Tuning = _tun()
	var h := HitStopLogic.new()
	h.request({}, 1.0, t)
	var first: float = h.hold_left
	h.step(DT, t)
	h.request({}, 0.4, t)  # shorter than what is left: ignored
	assert_true(h.hold_left < first)
	h.request({"finisher": "behead"}, 1.0, t)
	assert_near(h.hold_left, HitStopLogic.request_s({"finisher": "behead"}, 1.0, t), 0.0001, "the longer hold replaces, never adds")


func test_flurry_is_bounded() -> void:
	var t: Tuning = _tun()
	var h := HitStopLogic.new()
	var longest: float = 0.0
	var run: float = 0.0
	var stalled: float = 0.0
	# A heavy hit every 4 frames for 3 s: the worst flurry.
	for i: int in 180:
		if i % 4 == 0:
			h.request(_hit(500.0, 80.0), 1.0, t)
		var rate: float = h.step(DT, t)
		assert_true(h.lag <= t.feel_hitstop_lag_max + 0.0001, "lag capped")
		if rate < 0.5:
			run += DT
			stalled += DT
			longest = maxf(longest, run)
		else:
			run = 0.0
	assert_true(longest <= 0.2, "longest continuous stall %f" % longest)
	assert_true(stalled / 3.0 < 0.35, "share of time stalled %f" % (stalled / 3.0))


func test_finisher_ignores_debt() -> void:
	var t: Tuning = _tun()
	var h := HitStopLogic.new()
	h.debt = t.feel_hitstop_budget_s * 2.0
	assert_eq(h.request({}, 1.0, t), 0.0, "spent budget: no stop")
	assert_true(h.request({"finisher": "run_through"}, 1.0, t) > 0.0)


func test_bad_dt_is_harmless() -> void:
	var t: Tuning = _tun()
	var h := HitStopLogic.new()
	h.request({}, 1.0, t)
	assert_eq(h.step(0.0, t), 1.0)
	assert_eq(h.step(NAN, t), 1.0)
	h.reset()
	assert_false(h.active())
