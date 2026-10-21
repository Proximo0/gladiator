extends TestCase


func test_default_graphics_follows_platform() -> void:
	var s := MenuSettings.new()
	assert_eq(s.gfx_quality, GfxQuality.default_level())


func test_apply_quality_sets_the_global_level() -> void:
	var old: int = GfxQuality.level
	var s := MenuSettings.new()
	s.gfx_quality = GfxQuality.MEDIUM
	if not Flags.args.has("quality"):
		s.apply_quality()
		assert_eq(GfxQuality.level, GfxQuality.MEDIUM)
		assert_eq(GfxQuality.blood_level(), 1, "blood follows the graphics level")
	GfxQuality.set_level(old)


func test_scripted_runs_never_write_settings() -> void:
	assert_true(Flags.is_scripted_run())
	var s := MenuSettings.new()
	s.gfx_quality = 0
	var before: int = FileAccess.get_modified_time(MenuSettings.PATH) if FileAccess.file_exists(MenuSettings.PATH) else -1
	s.save_file()
	var after: int = FileAccess.get_modified_time(MenuSettings.PATH) if FileAccess.file_exists(MenuSettings.PATH) else -1
	assert_eq(after, before, "no settings file written in a scripted run")


func test_quality_picker_ids_match_levels() -> void:
	assert_eq(MenuSettings.QUALITY_NAMES.size(), 3)
	for i: int in 3:
		assert_eq(int(MenuSettings.QUALITY_NAMES[i][0]), i)


func test_feel_options_default_and_apply() -> void:
	var s := MenuSettings.new()
	assert_false(s.reduced_motion)
	assert_true(s.rumble)
	s.reduced_motion = true
	s.rumble = false
	s.apply()
	assert_true(FeelOptions.reduced_motion)
	assert_false(FeelOptions.rumble_enabled)
	s.reduced_motion = false
	s.rumble = true
	s.apply()
	assert_false(FeelOptions.reduced_motion)
	assert_true(FeelOptions.rumble_enabled)
