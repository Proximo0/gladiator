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
	assert_true(b.held_ticks <= 2, "hardly ever past the extrapolation limit (0-133 ms jitter): held %d, delay %f, jitter %f" % [b.held_ticks, b.delay, b.jitter])
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
	var tau: float = NetConfig.EXTRAP_TAU_S * float(Engine.physics_ticks_per_second)  ## fade constant in ticks
	assert_near(x, 98.0 + tau * (1.0 - exp(-NetConfig.MAX_EXTRAPOLATE / tau)), 0.01)
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
	var prev_resyncs: int = 0
	var ok: bool = true
	for local: int in range(300):
		var host_tick: int = local if local < 150 else local - 100  # host restarts its clock lower
		if local % 2 == 0:
			b.push(_snap(host_tick), local)
		if b.advance(local):
			ok = ok and (b.render_tick >= prev or b.resyncs > prev_resyncs)  # only a restart may step back
			prev = b.render_tick
			prev_resyncs = b.resyncs
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


## 30 Hz snapshots over a 3-5 tick link with 5% loss, many seeds: the clock must stay stable (no snapshot thrown
## away as too old, no holding) and extrapolate on only a few ticks.
func test_lossy_jittery_link_stays_stable_over_many_seeds() -> void:
	var worst_extra: int = 0
	var worst_dropped: int = 0
	var worst_held: int = 0
	var worst_delay: float = 0.0
	for seed_value: int in range(1, 31):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var b := NetInterpBuffer.new(2.0)
		var inflight: Array = []
		for local: int in range(900):
			if local % 2 == 0 and rng.randf() >= 0.05:
				inflight.append([local + 3 + rng.randi_range(0, 2), _snap(local)])
			var keep: Array = []
			inflight.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
			for e: Array in inflight:
				if int(e[0]) <= local:
					b.push(e[1] as NetSnapshot, local)
				else:
					keep.append(e)
			inflight = keep
			b.advance(local)
		worst_extra = maxi(worst_extra, b.extrapolated_ticks)
		worst_dropped = maxi(worst_dropped, b.dropped_old)
		worst_held = maxi(worst_held, b.held_ticks)
		worst_delay = maxf(worst_delay, b.delay)
	assert_true(worst_dropped <= 6, "dropped as too old: %d" % worst_dropped)
	assert_eq(worst_held, 0)
	assert_true(worst_extra <= 45, "extrapolated %d of 900 ticks (worst seed), delay up to %.1f" % [worst_extra, worst_delay])


func test_clock_that_ran_ahead_of_the_stream_starts_over() -> void:
	var b := NetInterpBuffer.new(2.0)
	for local: int in range(60):
		if local % 2 == 0:
			b.push(_snap(local + 100), local)
		b.advance(local)
	# The host's tick counter stops for 40 ticks (a pause, a hitch) while the clock runs on, then continues.
	for local: int in range(60, 100):
		b.advance(local)
	var host_tick: int = 160
	for local: int in range(100, 200):
		if local % 2 == 0:
			b.push(_snap(host_tick), local)
			host_tick += 2
		b.advance(local)
	assert_true(b.resyncs >= 1)
	assert_true(absf(b.render_tick - float(b.newest_tick())) < 8.0, "clock %f newest %d" % [b.render_tick, b.newest_tick()])
