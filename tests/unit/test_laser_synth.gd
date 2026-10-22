extends TestCase
## Laser sword sound synthesis, hum logic and the blade trail state.


func test_hum_loops_seamlessly() -> void:
	var s: PackedFloat32Array = LaserSynth.hum_samples()
	assert_eq(s.size(), LaserSynth.RATE)
	# Whole cycles per second: the last sample flows into the first like any neighbouring pair.
	var step: float = absf(s[1] - s[0])
	assert_true(absf(s[0] - s[s.size() - 1]) < maxf(step * 3.0, 0.05), "wrap jump %f" % absf(s[0] - s[s.size() - 1]))
	var peak: float = 0.0
	for v: float in s:
		peak = maxf(peak, absf(v))
	assert_true(peak > 0.2 and peak <= 1.0)


func test_clash_and_cut_deterministic_and_bounded() -> void:
	var a: PackedFloat32Array = LaserSynth.clash_samples(1)
	var b: PackedFloat32Array = LaserSynth.clash_samples(1)
	assert_eq(a, b)
	assert_true(a != LaserSynth.clash_samples(2))
	for v: float in a:
		assert_true(absf(v) <= 1.0)
	assert_eq(LaserSynth.cut_samples(0).size(), int(LaserSynth.CUT_SECONDS * LaserSynth.RATE))


func test_streams() -> void:
	var h: AudioStreamWAV = LaserSynth.hum()
	assert_eq(h.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(h.data.size(), LaserSynth.RATE * 2)
	assert_true(LaserSynth.stream_for("synth/laser_clash", 5) != null)
	assert_true(LaserSynth.stream_for("synth/nope", 0) == null)


func test_hum_pitch_and_gain_follow_speed() -> void:
	assert_near(LaserHumLogic.pitch_for(0.0), LaserHumLogic.PITCH_IDLE)
	assert_true(LaserHumLogic.pitch_for(12.0) > LaserHumLogic.pitch_for(4.0))
	assert_near(LaserHumLogic.pitch_for(500.0), LaserHumLogic.PITCH_MAX)
	assert_true(LaserHumLogic.gain_db_for(14.0) > LaserHumLogic.gain_db_for(0.0))
	var p: float = LaserHumLogic.glide(1.0, 2.0, 0.05)
	assert_true(p > 1.0 and p < 2.0)


func test_trail_records_only_fast_and_fades() -> void:
	var t := BladeTrailLogic.new()
	t.max_samples = 4
	assert_false(t.push(Vector3.ZERO, Vector3.UP, 1.0), "resting blade leaves no trail")
	for i: int in 6:
		assert_true(t.push(Vector3(i, 0, 0), Vector3(i, 1, 0), 10.0))
	assert_eq(t.count(), 4, "capped")
	assert_true(t.alpha(3) >= t.alpha(0))
	t.step(BladeTrailLogic.MAX_AGE * 0.5)
	assert_eq(t.count(), 4)
	t.step(BladeTrailLogic.MAX_AGE)
	assert_eq(t.count(), 0, "faded out")
	var off := BladeTrailLogic.new()
	off.max_samples = 0
	assert_false(off.push(Vector3.ZERO, Vector3.UP, 20.0), "low quality: no trail")
