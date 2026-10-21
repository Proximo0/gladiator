extends TestCase


func _snap(tick: int) -> NetSnapshot:
	var s := NetSnapshot.new()
	s.tick = tick
	var f := NetFighterSnap.new()
	f.pos.append(Vector3(float(tick), 0.0, 0.0))
	f.rot.append(Quaternion.IDENTITY)
	f.vel.append(Vector3(60.0, 0.0, 0.0))  # one unit per tick, like the positions
	s.fighters = [f]
	return s


func test_steady_stream_interpolates_smoothly_behind_host() -> void:
	var b := NetInterpBuffer.new(2.0)
	var last_x: float = -1.0
	var steps_ok: bool = true
	for local: int in range(400):
		if local % 2 == 0:
			b.push(_snap(local + 100), local)  # host is 100 ticks ahead, zero latency
		if b.advance(local) and local > 60:
			var x: float = b.sample().fighters[0].pos[0].x
			steps_ok = steps_ok and absf(x - last_x - 1.0) < 0.15
			last_x = x
		elif b.size() > 0:
			last_x = b.sample().fighters[0].pos[0].x
	assert_true(steps_ok, "one tick of motion per tick once settled")
	assert_eq(b.extrapolated_ticks, 0)
	assert_true(b.delay <= 4.0, "delay %f" % b.delay)


func test_jitter_raises_delay_and_avoids_starving() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var b := NetInterpBuffer.new(2.0)
	var inflight: Array = []
	for local: int in range(1200):
		if local % 2 == 0:
			inflight.append([local + rng.randi_range(0, 8), _snap(local)])
		var keep: Array = []
		for e: Array in inflight:
			if int(e[0]) <= local:
				b.push(e[1] as NetSnapshot, local)
			else:
				keep.append(e)
		inflight = keep
		b.advance(local)
	assert_true(b.delay > 4.0, "delay %f grows with 0-8 tick jitter" % b.delay)
	assert_true(b.held_ticks == 0, "never past the extrapolation limit: held %d, delay %f, jitter %f" % [b.held_ticks, b.delay, b.jitter])
	assert_true(b.extrapolated_ticks < 60, "extrapolated %d of 1200 ticks" % b.extrapolated_ticks)


func test_stream_stop_extrapolates_then_holds() -> void:
	var b := NetInterpBuffer.new(2.0)
	for local: int in range(100):
		if local % 2 == 0:
			b.push(_snap(local), local)
		b.advance(local)
	for local: int in range(100, 140):
		b.advance(local)
	var x: float = b.sample().fighters[0].pos[0].x
	assert_near(x, 98.0 + NetConfig.MAX_EXTRAPOLATE, 0.01)
	assert_true(b.held_ticks > 0)


func test_old_and_duplicate_snapshots_dropped() -> void:
	var b := NetInterpBuffer.new(2.0)
	b.push(_snap(10), 0)
	b.push(_snap(10), 0)
	b.push(_snap(8), 0)
	assert_eq(b.size(), 1)
	assert_eq(b.dropped_old, 2)


func test_render_clock_never_runs_backwards() -> void:
	var b := NetInterpBuffer.new(2.0)
	var prev: float = -INF
	var ok: bool = true
	for local: int in range(300):
		var host_tick: int = local if local < 150 else local - 100  # host restarts its clock lower
		if local % 2 == 0:
			b.push(_snap(host_tick), local)
		if b.advance(local):
			ok = ok and b.render_tick >= prev
			prev = b.render_tick
	assert_true(ok)


func test_events_released_at_their_tick() -> void:
	var b := NetInterpBuffer.new(2.0)
	b.push_event(30, 1, "hit", {"total": 5.0})
	b.push_event(60, 0, "gore", {"kind": "bleed"})
	var got: Array = []
	for local: int in range(50):
		if local % 2 == 0:
			b.push(_snap(local), local)
		b.advance(local)
		for e: Array in b.take_due_events():
			got.append([int(e[0]), b.render_tick])
	assert_eq(got.size(), 1)
	assert_true(float(got[0][1]) >= 30.0)
	assert_eq(b.take_all_events().size(), 1)
