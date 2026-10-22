extends TestCase


func _run(f: QuickMatchFlow, seconds: float, step: float = 0.1) -> bool:
	var changed: bool = false
	var t: float = 0.0
	while t < seconds - 0.0001:
		changed = f.tick(step) or changed
		t += step
	return changed


func test_search_counts_and_found_moves_to_confirm() -> void:
	var f := QuickMatchFlow.new()
	f.begin_search()
	_run(f, 4.0)
	assert_near(f.search_s, 4.0, 0.01)
	assert_true(f.found(false))
	assert_false(f.found(false), "a second match while not searching is ignored")
	assert_eq(f.phase, QuickMatchFlow.Phase.FOUND)
	assert_eq(f.confirm_left(), int(QuickMatchFlow.CONFIRM_S))
	assert_true(_run(f, QuickMatchFlow.FOUND_S + 0.05), "the card's beat ends: the client connects")
	assert_eq(f.phase, QuickMatchFlow.Phase.CONFIRM)


func test_countdown_readies_by_itself() -> void:
	var f := QuickMatchFlow.new()
	f.begin_search()
	f.found(true)
	_run(f, QuickMatchFlow.FOUND_S + 0.05)
	_run(f, 3.0)
	assert_eq(f.confirm_left(), int(ceilf(QuickMatchFlow.CONFIRM_S - 3.0)))
	assert_false(f.local_ready)
	_run(f, QuickMatchFlow.CONFIRM_S)
	assert_true(f.local_ready and f.auto_ready)
	assert_eq(f.confirm_left(), 0)


func test_host_starts_when_both_ready_or_after_grace() -> void:
	var f := QuickMatchFlow.new()
	f.begin_search()
	f.found(true)
	assert_true(f.press_ready(), "ready on the card skips to the confirm")
	assert_false(f.press_ready())
	assert_eq(f.phase, QuickMatchFlow.Phase.CONFIRM)
	assert_false(f.can_start(false), "nobody connected yet")
	assert_false(f.can_start(true), "waits for the other's ready")
	assert_true(f.take_ready_note(true))
	assert_false(f.take_ready_note(true), "one note only")
	f.on_remote_ready()
	assert_true(f.can_start(true))
	var g := QuickMatchFlow.new()
	g.begin_search()
	g.found(true)
	g.press_ready()
	_run(g, QuickMatchFlow.READY_GRACE_S + 0.1)
	assert_true(g.can_start(true), "an older build sends no note: start after the grace")
	var c := QuickMatchFlow.new()
	c.begin_search()
	c.found(false)
	c.press_ready()
	c.on_remote_ready()
	assert_false(c.can_start(true), "only the host starts")


func test_join_timeout_and_requeue_kinds() -> void:
	var f := QuickMatchFlow.new()
	f.begin_search()
	f.found(false)
	_run(f, QuickMatchFlow.JOIN_TIMEOUT_S - 1.0)
	assert_false(f.join_timed_out(false))
	_run(f, 1.5)
	assert_true(f.join_timed_out(false))
	assert_false(f.join_timed_out(true), "connected: no timeout")
	f.fail("Verus left")
	assert_eq(f.phase, QuickMatchFlow.Phase.IDLE)
	assert_true(f.should_requeue())
	f.fail("version mismatch: different protocol (host 2, client 3)")
	assert_false(f.should_requeue(), "a version problem does not go away by searching again")
	f.cancel()
	assert_eq(f.failure, {})


func test_estimate_learns_from_searches() -> void:
	var f := QuickMatchFlow.new()
	assert_near(f.estimate_s(-1.0), QuickMatchFlow.DEFAULT_WAIT_S)
	assert_near(f.estimate_s(12.0), 12.0)
	for w: float in [10.0, 20.0]:
		f.begin_search()
		_run(f, w, 0.5)
		f.found(true)
	assert_near(f.estimate_s(12.0), 15.0, 0.01)
	for i: int in QuickMatchFlow.WAIT_SAMPLES + 3:
		f.begin_search()
		_run(f, 2.0, 0.5)
		f.found(true)
	assert_eq(f.waits.size(), QuickMatchFlow.WAIT_SAMPLES)
	assert_near(f.estimate_s(12.0), QuickMatchFlow.MIN_ESTIMATE_S, 0.01, "lucky instant matches do not promise 0:02")
