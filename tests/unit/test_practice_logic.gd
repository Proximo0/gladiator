extends TestCase

const DT: float = 1.0 / 60.0


func _obs(over: Dictionary = {}) -> Dictionary:
	var o: Dictionary = {"pos": Vector2.ZERO, "aim": Vector2.ZERO, "tip_speed": 0.0, "min_speed": 3.0, "swing": false,
			"thrust": false, "rolling": false, "armed": true, "hits": 0, "finishers": 0}
	for k: Variant in over:
		o[k] = over[k]
	return o


func _to_step(l: PracticeLogic, id: String, over: Dictionary = {}) -> void:
	l.update(_obs(over), DT)
	while l.step_id() != id and not l.complete:
		l.skip_step()
		l.update(_obs(over), DT)


func test_starts_on_move_and_enters_it() -> void:
	var l := PracticeLogic.new()
	assert_eq(l.step_id(), "move")
	assert_true("enter:move" in l.update(_obs(), DT))


func test_move_needs_real_walking_not_a_teleport() -> void:
	var l := PracticeLogic.new()
	l.update(_obs(), DT)
	l.update(_obs({"pos": Vector2(30.0, 0.0)}), DT)
	assert_eq(l.step_id(), "move", "a 30 m jump is a reset, not walking")
	var x: float = 30.0
	for i: int in 120:
		x += 0.05
		l.update(_obs({"pos": Vector2(x, 0.0)}), DT)
	assert_eq(l.step_id(), "aim", "6 m of steps walked")


func test_aim_needs_three_extremes() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "aim")
	l.update(_obs({"aim": Vector2(-0.8, 0.0)}), DT)
	l.update(_obs({"aim": Vector2(0.8, 0.0)}), DT)
	assert_eq(l.step_id(), "aim")
	assert_near(l.progress(), 2.0 / 3.0, 0.01)
	l.update(_obs({"aim": Vector2(0.0, 0.9)}), DT)
	assert_eq(l.step_id(), "swing")


func test_swing_counts_only_fast_held_swings_and_rearms() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "swing")
	for n: int in 2:
		l.update(_obs({"swing": true, "tip_speed": 2.5}), DT)  # too slow
	assert_eq(l.counter_text(), "0 / 3")
	l.update(_obs({"swing": false, "tip_speed": 6.0}), DT)  # fast but not swinging
	assert_eq(l.counter_text(), "0 / 3")
	l.update(_obs({"swing": true, "tip_speed": 5.0}), DT)
	l.update(_obs({"swing": true, "tip_speed": 6.0}), DT)  # same swing: no second count
	assert_eq(l.counter_text(), "1 / 3")
	l.update(_obs({"swing": true, "tip_speed": 0.5}), DT)  # slowed: re-armed
	l.update(_obs({"swing": true, "tip_speed": 4.0}), DT)
	l.update(_obs({"swing": true, "tip_speed": 0.5}), DT)
	l.update(_obs({"swing": true, "tip_speed": 4.0}), DT)
	assert_eq(l.step_id(), "thrust")
	assert_true(l.best_tip == 0.0, "best tip resets on the new step")


func test_thrust_counts_a_fast_hand_inside_the_window() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "thrust")
	l.update(_obs({"thrust": true, "tip_speed": 1.0}), DT)
	for i: int in 60:  # window passes with no speed
		l.update(_obs({"thrust": true, "tip_speed": 1.0}), DT)
	assert_eq(l.counter_text(), "0 / 2")
	l.update(_obs(), DT)
	l.update(_obs({"thrust": true, "tip_speed": 1.0}), DT)
	l.update(_obs({"thrust": true, "tip_speed": 4.0}), DT)
	assert_eq(l.counter_text(), "1 / 2")
	l.update(_obs(), DT)
	l.update(_obs({"thrust": true, "tip_speed": 1.0}), DT)
	l.update(_obs({"thrust": true, "tip_speed": 5.0}), DT)
	assert_eq(l.step_id(), "strike")


func test_strike_counts_hits_after_entering() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "strike", {"hits": 7})
	l.update(_obs({"hits": 7}), DT)
	l.update(_obs({"hits": 9}), DT)
	assert_eq(l.step_id(), "strike")
	l.update(_obs({"hits": 10}), DT)
	assert_eq(l.step_id(), "shove")


func test_roll_counts_rising_edges() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "roll")
	l.update(_obs({"rolling": true}), DT)
	l.update(_obs({"rolling": true}), DT)
	assert_eq(l.counter_text(), "1 / 2", "a long roll counts once")
	l.update(_obs({"rolling": false}), DT)
	l.update(_obs({"rolling": true}), DT)
	assert_eq(l.step_id(), "grab")


func test_grab_needs_the_weapon_off_then_on_again() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "grab")
	assert_near(l.progress(), 0.0, 0.001)
	l.update(_obs({"armed": true}), DT)
	assert_eq(l.step_id(), "grab", "still armed: not done")
	for i: int in 10:
		l.update(_obs({"armed": false}), DT)
	assert_near(l.progress(), 0.5, 0.001)
	l.update(_obs({"armed": true}), DT)
	assert_eq(l.step_id(), "finish")


func test_grab_counts_a_regrab_one_tick_after_the_drop() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "grab")
	l.update(_obs({"armed": true}), DT)
	l.update(_obs({"armed": false}), DT)
	l.update(_obs({"armed": true}), DT)
	assert_eq(l.step_id(), "finish")


func test_finish_completes_the_course_and_emits_events() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "finish")
	var ev: Array = l.update(_obs({"finishers": 0}), DT)
	assert_false("done:finish" in ev)
	ev = l.update(_obs({"finishers": 1}), DT)
	assert_true("done:finish" in ev and "complete" in ev)
	assert_true(l.complete)
	assert_eq(l.step_id(), "")
	assert_eq(l.update(_obs(), DT), [])


func test_enter_events_set_the_scene() -> void:
	var l := PracticeLogic.new()
	l.update(_obs(), DT)
	var seen: Array = []
	for i: int in PracticeLogic.STEP_IDS.size():
		for e: Variant in l.skip_step():
			seen.append(e)
		for e: Variant in l.update(_obs(), DT):
			seen.append(e)
	assert_true("enter:grab" in seen and "enter:finish" in seen and "enter:hold" in seen)


func test_skip_all_completes_and_records_skips() -> void:
	var l := PracticeLogic.new()
	l.update(_obs(), DT)
	var ev: Array = l.skip_all()
	assert_true(l.complete and "complete" in ev)
	assert_eq(l.skipped.size(), PracticeLogic.STEP_IDS.size())


func test_stuck_after_long_time_on_one_step() -> void:
	var l := PracticeLogic.new({"stuck_after_s": 1.0})
	for i: int in 30:
		l.update(_obs(), DT)
	assert_false(l.stuck())
	for i: int in 40:
		l.update(_obs(), DT)
	assert_true(l.stuck())


func test_config_file_loads_and_matches_defaults_keys() -> void:
	var c: Dictionary = PracticeLogic.load_config()
	for k: Variant in PracticeLogic.DEFAULTS:
		assert_true(c.has(k), "key %s" % str(k))
	assert_true(float(c["finish_dummy_blood_frac"]) < Tuning.shared().finisher_blood_frac, "the drained dummy is inside the finisher window")


func test_every_step_has_text_for_every_device() -> void:
	for id: String in PracticeLogic.STEP_IDS:
		assert_eq(PracticeText.heading(id).size(), 2)
		for dev: String in ["kbm", "pad", "touch"]:
			assert_true(PracticeText.body(id, dev, 3.0) != "", "%s %s" % [id, dev])
	assert_true(PracticeText.body("swing", "kbm", 3.0).contains("3 m/s"))
	assert_eq(PracticeText.device_for(true, true), "pad")
	assert_eq(PracticeText.device_for(false, true), "touch")
	assert_eq(PracticeText.device_for(false, false), "kbm")


func test_shove_counts_landed_shoves_from_the_step_start() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "shove", {"shoves": 3})  # shoves landed before the step do not count
	l.update(_obs({"shoves": 3}), DT)
	assert_eq(l.counter_text(), "0 / 2")
	l.update(_obs({"shoves": 4}), DT)
	assert_eq(l.counter_text(), "1 / 2")
	assert_near(l.progress(), 0.5, 0.001)
	var ev: Array = l.update(_obs({"shoves": 5}), DT)
	assert_true("done:shove" in ev, str(ev))
	assert_eq(l.step_id(), "kick")


func test_kick_needs_two_landed_kicks() -> void:
	var l := PracticeLogic.new()
	_to_step(l, "kick")
	l.update(_obs({"kicks": 1}), DT)
	assert_eq(l.step_id(), "kick")
	l.update(_obs({"kicks": 2}), DT)
	assert_eq(l.step_id(), "hold")


func test_hold_needs_one_unbroken_hold() -> void:
	var l := PracticeLogic.new({"hold_s": 0.44})  # 27 ticks
	_to_step(l, "hold")
	for i: int in 20:
		l.update(_obs({"holding": true}), DT)
	l.update(_obs({"holding": false}), DT)
	assert_near(l.progress(), 0.0, 0.001, "a broken hold starts over")
	for i: int in 26:
		l.update(_obs({"holding": true}), DT)
	assert_eq(l.step_id(), "hold")
	l.update(_obs({"holding": true}), DT)
	assert_eq(l.step_id(), "roll")
