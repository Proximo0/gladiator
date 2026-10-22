extends TestCase


func _inp(i: int) -> FighterInput:
	return FighterInput.from_array([i, 0, 0, 0, 0])


func test_waits_for_target_depth_then_plays_in_order() -> void:
	var b := NetInputBuffer.new(2, 8)
	b.push(0, _inp(1))
	assert_eq(b.pop().move_x, 0, "neutral until the buffer holds target + 1")
	b.push(1, _inp(2))
	b.push(2, _inp(3))
	assert_eq(b.pop().move_x, 1)
	assert_eq(b.last_applied_tick, 0)
	assert_eq(b.pop().move_x, 2)
	assert_eq(b.pop().move_x, 3)
	assert_eq(b.pop().move_x, 3, "empty: repeat the last input")
	assert_eq(b.underruns, 1)


func test_redundant_copies_count_as_duplicates() -> void:
	var b := NetInputBuffer.new(0, 8)
	b.push(0, _inp(1))
	b.pop()
	b.push(0, _inp(1))
	b.push(1, _inp(2))
	b.push(1, _inp(2))
	assert_eq(b.duplicates, 2)
	assert_eq(b.received, 2)


func test_lost_tick_is_skipped_once_newer_arrive() -> void:
	var b := NetInputBuffer.new(0, 8)
	b.push(0, _inp(1))
	assert_eq(b.pop().move_x, 1)
	b.push(2, _inp(3))
	assert_eq(b.pop().move_x, 1, "tick 1 is missing: hold")
	assert_eq(b.skipped, 1)
	assert_eq(b.pop().move_x, 3)
	b.push(1, _inp(2))
	assert_eq(b.late, 1, "tick 1 turned up after it was skipped")


func test_overfull_buffer_skips_to_target() -> void:
	var b := NetInputBuffer.new(2, 5)
	for t: int in range(3):
		b.push(t, _inp(t))
	b.pop()
	for t: int in range(3, 20):
		b.push(t, _inp(t))
	var got: FighterInput = b.pop()
	assert_eq(got.move_x, 17, "jumps to newest - target")
	assert_true(b.depth() <= 3)
	assert_true(b.skipped > 0)


func test_lossy_stream_plays_every_tick_with_redundancy() -> void:
	# 20% of packets lost, each carrying 4 ticks: nearly every tick still gets played, and in order.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var p := NetInputPacker.new(4)
	var b := NetInputBuffer.new(2, 10)
	var played: Array = []
	for t: int in range(600):
		p.record(t, _inp(t % 1000))
		if rng.randf() >= 0.2:
			for r: Array in NetInputPacker.unpack(p.pack()):
				b.push(int(r[0]), r[1] as FighterInput)
		b.pop()
		played.append(b.last_applied_tick)
	var distinct: Dictionary = {}
	for x: int in played:
		distinct[x] = true
	assert_true(distinct.size() > 590, "played %d distinct ticks" % distinct.size())
	assert_eq(b.late, 0)


func test_default_target_is_one_tick_on_a_clean_stream() -> void:
	var b := NetInputBuffer.new()
	assert_eq(b.target, 1)
	for t: int in range(400):
		b.push(t, _inp(t % 1000))
		b.pop()
	assert_eq(b.underruns, 0)
	assert_eq(b.skipped, 0)
	assert_true(b.depth() <= 2, "depth %d" % b.depth())


func test_jitter_grows_the_buffer_by_itself_and_calm_gives_it_back() -> void:
	var b := NetInputBuffer.new()
	# A stall (nothing arrives for 3 ticks, then the burst): underruns, and the buffer ends up deeper.
	for t: int in range(30):
		b.push(t, _inp(t))
		b.pop()
	var next_tick: int = 30
	for _i: int in range(3):
		b.pop()
	for _i: int in range(3):
		b.push(next_tick, _inp(next_tick))
		next_tick += 1
	assert_true(b.underruns >= 1)
	var deep: int = b.depth()
	# Clean again for a few windows: the extra depth is given back, one tick per window, down to target.
	for _i: int in range(NetInputBuffer.SHRINK_WINDOW * 4):
		b.push(next_tick, _inp(next_tick % 1000))
		next_tick += 1
		b.pop()
	assert_true(b.depth() < deep or deep <= b.target + 1, "depth %d -> %d" % [deep, b.depth()])
	assert_true(b.depth() <= b.target + 1, "back to about the target: %d" % b.depth())


func _btn(move: int, buttons: int) -> FighterInput:
	return FighterInput.from_array([move, move, 0, 0, buttons])


func test_roll_press_on_a_skipped_tick_is_carried() -> void:
	# Soak 2026-10: a one-tick ROLL press on a tick the host skipped (lost for good, or dropped to shrink) never rolled.
	var b := NetInputBuffer.new(0, 8)
	b.push(0, _btn(0, 0))
	b.pop()
	b.push(2, _btn(0, 0))
	assert_eq(b.pop().buttons, 0, "tick 1 missing: hold")
	b.push(1, _btn(0, FighterInput.ROLL))  # arrives late, after its tick was passed
	assert_eq(b.late, 1)
	b.push(3, _btn(0, 0))
	assert_true(b.pop().has(FighterInput.ROLL), "the late press rides on the next tick played")
	assert_eq(b.carried, 1)
	assert_false(b.pop().has(FighterInput.ROLL), "and only once")


func test_roll_press_on_a_buffer_skip_is_carried() -> void:
	var b := NetInputBuffer.new(1, 4)
	for t: int in range(3):
		b.push(t, _inp(t))
	b.pop()
	b.pop()
	for t: int in range(3, 14):  # a burst deeper than the maximum: the buffer jumps ahead, over tick 5
		b.push(t, _btn(0, FighterInput.ROLL if t == 5 else 0))
	var got: bool = false
	for _i: int in range(3):
		got = got or b.pop().has(FighterInput.ROLL)
	assert_true(b.skipped > 0)
	assert_true(got, "the press on a skipped tick still arrives")


func test_held_buttons_are_not_carried() -> void:
	var b := NetInputBuffer.new(0, 8)
	b.push(0, _btn(0, 0))
	b.pop()
	b.push(1, _btn(0, FighterInput.SWING | FighterInput.SPRINT))
	b.push(3, _btn(0, 0))
	b.pop()
	b.pop()
	assert_eq(b.carried, 0)


func test_silent_stream_goes_neutral_but_keeps_aim() -> void:
	# Soak 2026-10: with the client's packets gone the host's fighter 1 kept walking and swinging on the last input.
	var b := NetInputBuffer.new(0, 8)
	b.push(0, FighterInput.from_array([300, 1000, 200, 150, FighterInput.SWING | FighterInput.SPRINT]))
	b.pop()
	for _i: int in range(NetConfig.INPUT_STALE_TICKS):
		var held: FighterInput = b.pop()
		assert_eq(held.move_y, 1000, "a short gap repeats the last input")
	var quiet: FighterInput = b.pop()
	assert_eq(quiet.move_x, 0)
	assert_eq(quiet.move_y, 0)
	assert_eq(quiet.buttons, 0)
	assert_eq(quiet.aim_x, 200, "the weapon hand stays where it was")
	assert_eq(quiet.aim_y, 150)
	assert_eq(b.stale_pops, 1)
	b.push(1, FighterInput.from_array([0, 500, 0, 0, 0]))
	assert_eq(b.pop().move_y, 500, "input resumes at once when the stream does")


func test_close_range_presses_are_edge_buttons() -> void:
	for b: int in [FighterInput.SHOVE, FighterInput.KICK, FighterInput.CLINCH]:
		assert_true((NetInputBuffer.EDGE_BUTTONS & b) != 0, "a skipped tick must not swallow bit %d" % b)
