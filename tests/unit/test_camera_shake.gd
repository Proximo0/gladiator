extends TestCase


func _run(s: CameraShake, seconds: float) -> Dictionary:
	var out: Dictionary = {}
	for i: int in roundi(seconds * 60.0):
		out = s.update(1.0 / 60.0)
	return out


func test_idle_by_default() -> void:
	var s := CameraShake.new()
	var r: Dictionary = s.update(0.016)
	assert_eq(r["offset"], Vector3.ZERO)
	assert_eq(float(r["fov"]), 0.0)


func test_kick_moves_toward_blow_then_settles() -> void:
	var t := Tuning.new()
	var s := CameraShake.new()
	s.add_hit(Vector3(0, 0, -1), 1.0, t, 1.0)
	var peak: float = 0.0
	for i: int in 30:
		var r: Dictionary = s.update(1.0 / 60.0)
		peak = maxf(peak, -(r["offset"] as Vector3).z)
	assert_true(peak > t.feel_kick_m * 0.5, "kicks toward the blow")
	assert_true(peak < t.feel_kick_m * 1.6, "bounded")
	_run(s, 3.0)
	assert_true(s.is_idle(), "settles")


func test_kick_scales_with_strength() -> void:
	var t := Tuning.new()
	var a := CameraShake.new()
	var b := CameraShake.new()
	a.add_hit(Vector3.RIGHT, 0.2, t, 1.0)
	b.add_hit(Vector3.RIGHT, 1.0, t, 1.0)
	var pa: float = 0.0
	var pb: float = 0.0
	for i: int in 20:
		pa = maxf(pa, (a.update(1.0 / 60.0)["offset"] as Vector3).x)
		pb = maxf(pb, (b.update(1.0 / 60.0)["offset"] as Vector3).x)
	assert_true(pb > pa * 3.0)


func test_zero_scale_does_nothing() -> void:
	var t := Tuning.new()
	var s := CameraShake.new()
	s.add_hit(Vector3.RIGHT, 1.0, t, 0.0)
	s.add_zoom(t.feel_zoom_deg, 1.0, t, 0.0)
	assert_true(s.is_idle())


func test_zoom_punch_relaxes() -> void:
	var t := Tuning.new()
	var s := CameraShake.new()
	s.add_zoom(t.feel_zoom_deg, 1.0, t, 1.0)
	var first: Dictionary = s.update(1.0 / 60.0)
	assert_true(float(first["fov"]) > t.feel_zoom_deg * 0.8)
	_run(s, 3.0)
	assert_true(s.is_idle())


func test_shake_is_deterministic_and_decays() -> void:
	var t := Tuning.new()
	var a := CameraShake.new()
	var b := CameraShake.new()
	a.add_hit(Vector3.ZERO, 1.0, t, 1.0)
	b.add_hit(Vector3.ZERO, 1.0, t, 1.0)
	var ja: Vector3 = a.update(1.0 / 60.0)["jitter"]
	var jb: Vector3 = b.update(1.0 / 60.0)["jitter"]
	assert_eq(ja, jb)
	var early: float = 0.0
	for i: int in 6:
		early = maxf(early, ((a.update(1.0 / 60.0)["jitter"]) as Vector3).length())
	_run(a, 1.5)
	assert_true(early > 0.0)
	assert_true(a.shake < 0.01)


func test_non_finite_inputs_leave_the_shake_clean() -> void:
	var sh := CameraShake.new()
	var tun: Tuning = Tuning.shared()
	sh.add_hit(Vector3(NAN, 0, 0), 0.8, tun, 1.0)
	sh.add_hit(Vector3.RIGHT, NAN, tun, 1.0)
	sh.add_zoom(5.0, NAN, tun, 1.0)
	assert_true(sh.is_idle())
	sh.add_hit(Vector3.RIGHT, 0.8, tun, 1.0)
	var fx: Dictionary = sh.update(NAN)
	assert_true(FightCamera.is_finite_v3(fx["offset"]) and FightCamera.is_finite_v3(fx["jitter"]))
	fx = sh.update(0.0)
	assert_true(FightCamera.is_finite_v3(fx["offset"]))


func test_slow_frames_do_not_blow_up_the_kick() -> void:
	var sh := CameraShake.new()
	sh.add_hit(Vector3.RIGHT, 1.0, Tuning.shared(), 1.0)
	var worst: float = 0.0
	for i: int in 60:
		var fx: Dictionary = sh.update(0.1)
		worst = maxf(worst, (fx["offset"] as Vector3).length())
	assert_true(worst < 1.0, "kick stays small at 10 fps, got %f" % worst)
