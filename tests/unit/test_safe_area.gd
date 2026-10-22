extends TestCase


func test_full_screen_has_no_insets() -> void:
	assert_eq(SafeArea.insets(Rect2(0.0, 0.0, 540.0, 1170.0), Vector2(540.0, 1170.0)), Vector4.ZERO)


func test_notch_and_gesture_bar_become_top_and_bottom_insets() -> void:
	var v: Vector4 = SafeArea.insets(Rect2(0.0, 60.0, 540.0, 1070.0), Vector2(540.0, 1170.0))
	assert_near(v.y, 60.0)
	assert_near(v.w, 40.0)
	assert_near(v.x, 0.0)
	assert_near(v.z, 0.0)


func test_absurd_insets_are_capped_and_empty_rect_is_ignored() -> void:
	var v: Vector4 = SafeArea.insets(Rect2(400.0, 0.0, 100.0, 500.0), Vector2(1000.0, 500.0))
	assert_near(v.x, 150.0)
	assert_eq(SafeArea.insets(Rect2(), Vector2(1000.0, 500.0)), Vector4.ZERO)


func test_title_hint_follows_the_device() -> void:
	var touch: Array = TitleScreen.hint_lines(false, true)
	assert_true(str(touch[0]).begins_with("Tap"))
	assert_true(touch.size() >= 2, "reuses the fight hint")
	assert_true(str(TitleScreen.hint_lines(false, false)[0]).contains("Enter"))
	assert_true(str(TitleScreen.hint_lines(true, true)[0]).contains("A:"))
	assert_true(TitleScreen.hint_font_units(0.28) > TitleScreen.hint_font_units(1.0))
	assert_eq(TitleScreen.hint_font_units(1.0), 24)


func test_fake_insets_argument() -> void:
	assert_eq(SafeArea.parse_arg("96,0,0,48"), Vector4(96.0, 0.0, 0.0, 48.0))
	assert_eq(SafeArea.parse_arg(""), Vector4.ZERO)
	assert_eq(SafeArea.parse_arg("1,2,3"), Vector4.ZERO, "needs four numbers")
	assert_eq(SafeArea.parse_arg("1,x,3,4"), Vector4.ZERO)
	assert_eq(SafeArea.parse_arg("1,-2,3,4"), Vector4.ZERO, "no negative insets")
