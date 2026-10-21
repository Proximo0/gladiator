extends TestCase


func test_window_rate_includes_overhead() -> void:
	var m := NetBandwidth.new(60)
	for t: int in range(120):
		if t % 2 == 0:
			m.add(t, 500)
	assert_near(m.per_second(119), 30.0 * (500 + NetConfig.PACKET_OVERHEAD), 0.5)
	assert_eq(m.total_packets, 60)
	assert_near(m.average(120), 30.0 * (500 + NetConfig.PACKET_OVERHEAD), 0.5)


func test_peak_tracks_bursts() -> void:
	var m := NetBandwidth.new(60)
	m.add(0, 10000)
	m.per_second(0)
	m.per_second(200)
	assert_true(m.peak_per_s >= 10000.0)
	assert_near(m.per_second(200), 0.0)
