extends TestCase


func test_sweep_length_range_and_tail() -> void:
	var s: PackedFloat32Array = FeelTones.sweep(80.0, 40.0, 0.5, 0.2, 2.0, 8000)
	assert_eq(s.size(), 4000)
	var peak: float = 0.0
	for v: float in s:
		peak = maxf(peak, absf(v))
	assert_true(peak > 0.5 and peak <= 1.0001, "peak %f" % peak)
	assert_near(s[0], 0.0, 0.001, "starts silent (no click)")
	assert_near(s[s.size() - 1], 0.0, 0.001, "ends silent (no click)")


func test_sweep_decays() -> void:
	var s: PackedFloat32Array = FeelTones.sweep(60.0, 60.0, 1.0, 0.15, 1.0, 8000)
	var early: float = 0.0
	var late: float = 0.0
	for i: int in range(0, 800):
		early = maxf(early, absf(s[i]))
	for i: int in range(6000, 7000):
		late = maxf(late, absf(s[i]))
	assert_true(late < early * 0.05, "early %f late %f" % [early, late])


func test_presets_and_wav() -> void:
	var fin: PackedFloat32Array = FeelTones.finisher_samples()
	var thump: PackedFloat32Array = FeelTones.thump_samples()
	assert_true(fin.size() > thump.size())
	var w: AudioStreamWAV = FeelTones.to_wav(thump)
	assert_eq(w.data.size(), thump.size() * 2)
	assert_eq(w.mix_rate, FeelTones.RATE)
	assert_near(w.get_length(), float(thump.size()) / float(FeelTones.RATE), 0.01)
