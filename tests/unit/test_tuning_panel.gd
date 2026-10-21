extends TestCase


func test_group_names_follow_fields_order() -> void:
	var expected: PackedStringArray = PackedStringArray()
	for f: Array in Tuning.FIELDS:
		var group: String = f[5]
		if not expected.has(group):
			expected.append(group)
	assert_eq(TuningPanel.group_names(), expected)
	assert_eq(TuningPanel.group_names()[0], "World")


func test_unfiltered_layout_has_every_field_once_in_group_order() -> void:
	var layout: Array = TuningPanel.group_fields("")
	var seen: PackedStringArray = PackedStringArray()
	var groups: PackedStringArray = PackedStringArray()
	for entry: Dictionary in layout:
		groups.append(entry["group"])
		for field: String in entry["fields"]:
			seen.append(field)
			assert_eq(Tuning.field_info(field)["group"], entry["group"], field)
	assert_eq(seen.size(), Tuning.FIELDS.size())
	assert_eq(groups, TuningPanel.group_names())


func test_filter_matches_name_case_insensitive() -> void:
	var layout: Array = TuningPanel.group_fields("  ARENA ")
	assert_eq(layout.size(), 1)
	assert_eq(layout[0]["group"], "World")
	assert_eq(layout[0]["fields"], ["arena_radius"])


func test_filter_matches_doc_text() -> void:
	# "Walk speed" is the doc of move_speed only.
	var layout: Array = TuningPanel.group_fields("walk speed")
	assert_eq(layout.size(), 1)
	assert_eq(layout[0]["fields"], ["move_speed"])


func test_filter_on_group_name_keeps_whole_group() -> void:
	var layout: Array = TuningPanel.group_fields("movement")
	assert_eq(layout.size(), 1)
	assert_eq(layout[0]["group"], "Movement")
	var count: int = 0
	for f: Array in Tuning.FIELDS:
		if f[5] == "Movement":
			count += 1
	assert_eq(layout[0]["fields"].size(), count)


func test_filter_without_match_is_empty() -> void:
	assert_true(TuningPanel.group_fields("no_such_field_xyz").is_empty())


func test_is_modified_ignores_float_noise() -> void:
	assert_false(TuningPanel.is_modified("move_speed", 2.5))
	assert_false(TuningPanel.is_modified("move_speed", 2.5 + 0.0000001))
	assert_true(TuningPanel.is_modified("move_speed", 2.6))
	assert_false(TuningPanel.is_modified("no_such_field", 1.0))


func test_to_design_undoes_stretch() -> void:
	assert_near(TuningPanel.to_design(300.0, 2.0 / 3.0), 450.0, 0.01)
	assert_near(TuningPanel.to_design(300.0, 1.0), 300.0)


func test_header_text_shows_changed_count() -> void:
	assert_eq(TuningPanel.header_text("World", 0), "World")
	assert_eq(TuningPanel.header_text("World", 2), "World (2 changed)")


func test_preset_path_names() -> void:
	assert_eq(TuningPanel.preset_path("My Preset!"), "user://presets/My_Preset.json")
	assert_eq(TuningPanel.preset_path("fast-arms_2"), "user://presets/fast-arms_2.json")
	assert_eq(TuningPanel.preset_path("   "), "user://presets/preset.json")
	assert_eq(TuningPanel.preset_path("../escape"), "user://presets/escape.json")
	assert_eq(TuningPanel.preset_path("  a  b  "), "user://presets/a_b.json")


func test_preset_names_from_listing() -> void:
	var files: PackedStringArray = PackedStringArray(["b.json", "a.json", "notes.txt", "c.json.bak"])
	assert_eq(TuningPanel.preset_names(files), PackedStringArray(["a", "b"]))


func test_preset_values_fill_defaults_and_skip_unknown() -> void:
	var values: Dictionary = TuningPanel.preset_values({"move_speed": 5.0, "bogus": 1.0})
	assert_eq(values.size(), Tuning.FIELDS.size())
	assert_near(float(values["move_speed"]), 5.0)
	assert_near(float(values["gravity"]), 9.8)
	assert_false(values.has("bogus"))


func test_toggle_event_fallback_key() -> void:
	if InputMap.has_action(&"debug_tuning"):
		return  # the action is bound; the key fallback does not apply
	var key := InputEventKey.new()
	key.keycode = KEY_QUOTELEFT
	key.pressed = true
	assert_true(TuningPanel.is_toggle_event(key))
	key.pressed = false
	assert_false(TuningPanel.is_toggle_event(key))
	var other := InputEventKey.new()
	other.keycode = KEY_A
	other.pressed = true
	assert_false(TuningPanel.is_toggle_event(other))


func test_write_preset_refused_in_scripted_run() -> void:
	if not Flags.is_scripted_run():
		return  # would write to user:// on a real run
	assert_eq(TuningPanel.write_preset("user://presets/_test_refused.json", {"move_speed": 5.0}), ERR_UNAVAILABLE)
	assert_false(FileAccess.file_exists("user://presets/_test_refused.json"))
