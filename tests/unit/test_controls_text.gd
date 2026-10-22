extends TestCase


func test_default_hint_has_keyboard_line() -> void:
	var l: Array = ControlsText.hint_lines("player_vs_cpu", false, false)
	assert_true(l.size() >= 2)
	assert_true(str(l[0]).contains("WASD"))


func test_pad_and_touch_add_lines() -> void:
	var base: int = ControlsText.hint_lines("player_vs_cpu", false, false).size()
	assert_eq(ControlsText.hint_lines("player_vs_cpu", true, false).size(), base + 1)
	var touch: Array = ControlsText.hint_lines("player_vs_cpu", false, true)
	assert_true(str(touch[0]).contains("Touch"))


func test_local_2p_mentions_both_players() -> void:
	var s: String = " ".join(PackedStringArray(ControlsText.hint_lines("local_2p", false, false)))
	assert_true(s.contains("PLAYER 1") and s.contains("PLAYER 2"))


func test_table_rows_are_complete() -> void:
	for r: Array in ControlsText.TABLE:
		assert_eq(r.size(), 4)


func test_compact_lines_follow_the_device() -> void:
	var kb: Array = ControlsText.compact_lines("player_vs_cpu", false, false)
	assert_eq(kb.size(), 1)
	assert_true("WASD" in str(kb[0]))
	var touch: Array = ControlsText.compact_lines("player_vs_cpu", false, true)
	assert_true(touch.size() <= 2)
	assert_false("WASD" in " ".join(PackedStringArray(touch)))
	var pad: Array = ControlsText.compact_lines("player_vs_cpu", true, false)
	assert_eq(pad.size(), 2)
	assert_true("stick" in str(pad[0]))
	assert_eq(ControlsText.compact_lines("local_2p", false, false).size(), 2)
	for l: Variant in kb + touch + pad:
		assert_true(str(l).length() <= 90, "short enough: %s" % str(l))
