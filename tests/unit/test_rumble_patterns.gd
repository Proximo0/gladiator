extends TestCase


func _tun() -> Tuning:
	return Tuning.new()


func test_off_and_taps_are_silent() -> void:
	var t: Tuning = _tun()
	assert_true(RumblePatterns.pattern(HitStopLogic.CLASS_HEAVY, 1.0, true, t, 0.0).is_empty(), "switched off")
	assert_true(RumblePatterns.pattern(HitStopLogic.CLASS_NONE, 1.0, true, t, 1.0).is_empty())
	assert_true(RumblePatterns.pattern(HitStopLogic.CLASS_LIGHT, 0.05, true, t, 1.0).is_empty(), "under the floor")


func test_classes_feel_different() -> void:
	var t: Tuning = _tun()
	var light: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_LIGHT, 0.4, true, t, 1.0)
	var heavy: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_HEAVY, 0.9, true, t, 1.0)
	var clash: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_CLASH, 0.9, true, t, 1.0)
	var sever: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_SEVER, 0.9, true, t, 1.0)
	var fin: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_FINISHER, 0.95, true, t, 1.0)
	assert_eq(light.size(), 1)
	assert_eq(heavy.size(), 2)
	assert_eq(clash.size(), 2)
	assert_true(sever.size() >= 3)
	assert_true(float(clash[0]["weak"]) > float(clash[0]["strong"]), "a clash buzzes on the light motor")
	assert_true(float(heavy[0]["strong"]) > float(light[0]["strong"]))
	assert_true(RumblePatterns.span_s(light) < RumblePatterns.span_s(heavy))
	# The finisher swells again at the crowd roar.
	assert_near(float(fin[1]["at"]), maxf(t.feel_cine_hold_s - FinisherCine.ROAR_LEAD_S, 0.4), 0.0001)
	assert_near(float(fin[0]["strong"]), 1.0)


func test_dealer_feels_less() -> void:
	var t: Tuning = _tun()
	var taken: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_HEAVY, 0.9, true, t, 1.0)
	var dealt: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_HEAVY, 0.9, false, t, 1.0)
	assert_true(float(dealt[0]["strong"]) < float(taken[0]["strong"]))
	var fin_d: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_FINISHER, 0.95, false, t, 1.0)
	assert_true(float(fin_d[0]["strong"]) < 1.0)


func test_phone_pattern_is_one_motor_and_capped() -> void:
	var t: Tuning = _tun()
	var fin: Array[Dictionary] = RumblePatterns.pattern(HitStopLogic.CLASS_FINISHER, 0.95, true, t, 1.0)
	var ph: Array[Dictionary] = RumblePatterns.phone(fin)
	assert_eq(ph.size(), fin.size())
	for p: Dictionary in ph:
		assert_true(int(p["ms"]) <= FeelLogic.VIBRATE_MAX_MS and int(p["ms"]) >= RumblePatterns.PHONE_MIN_MS)
		assert_true(float(p["amp"]) > 0.0 and float(p["amp"]) <= 1.0)
	var tiny: Array[Dictionary] = [{"at": 0.0, "weak": 0.5, "strong": 0.5, "dur": 0.005}]
	assert_true(RumblePatterns.phone(tiny).is_empty(), "too short for a phone motor")


func test_values_stay_in_range() -> void:
	var t: Tuning = _tun()
	for cls: String in HitStopLogic.CLASSES:
		for p: Dictionary in RumblePatterns.pattern(cls, 1.0, true, t, 1.0):
			for k: String in ["weak", "strong"]:
				assert_true(float(p[k]) >= 0.0 and float(p[k]) <= 1.0, cls)
			assert_true(float(p["at"]) >= 0.0 and float(p["dur"]) > 0.0, cls)
