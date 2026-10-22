extends TestCase
## Title menu layout and focus: every entry reachable, wrapping, nothing off screen or overlapping, finger-sized
## entries on touch screens.


func _screen(w: float, h: float, px: float, touch: bool) -> TitleScreen:
	var t := TitleScreen.new()
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	t.size = Vector2(w, h)
	t.layout_for(px, touch)
	return t


func _neighbour(b: Control, side: Side) -> Control:
	return b.get_node(b.get_focus_neighbor(side)) as Control


func _check(t: TitleScreen, label: String) -> void:
	var items: Array[TitleMenuItem] = t.items()
	var rect := Rect2(Vector2.ZERO, t.size)
	for i: int in items.size():
		var r: Rect2 = Rect2(items[i].position, items[i].size)
		assert_true(rect.encloses(r), "%s: item %d on screen %s" % [label, i, str(r)])
		for j: int in range(i + 1, items.size()):
			assert_false(r.grow(-1.0).intersects(Rect2(items[j].position, items[j].size)), "%s: items %d and %d overlap" % [label, i, j])
	# Down from the first entry visits every entry before it comes back round.
	var seen: Dictionary = {}
	var c: Control = items[0]
	for _k: int in items.size() * 2:
		seen[c] = true
		c = _neighbour(c, SIDE_BOTTOM)
		for side: Side in [SIDE_LEFT, SIDE_RIGHT]:
			seen[_neighbour(c, side)] = true
	assert_eq(seen.size(), items.size(), "%s: every entry reachable with up/down/left/right" % label)
	assert_eq(_neighbour(items[0], SIDE_TOP) != null, true)
	assert_true(_neighbour(_neighbour(items[0], SIDE_TOP), SIDE_BOTTOM) == items[0] or t.grid()["columns"] == 2, "%s: up then down returns" % label)
	t.free()


func test_desktop_landscape_is_one_list_down_the_left() -> void:
	var t := _screen(1920.0, 1080.0, 0.667, false)
	assert_eq(int(t.grid()["columns"]), 1)
	assert_true(t.items()[0].position.x < 1920.0 * 0.2)
	assert_true(t.backdrop_frame_x() > 0.0, "the gladiators move right of the menu")
	_check(t, "1280x720")


func test_phone_portrait_tiles_are_finger_sized() -> void:
	var px: float = 540.0 / 1000.0 * 0.28 / 0.28  # 540x960: 1000 units across, about 0.54 px per unit
	var t := _screen(1000.0, 1777.0, px, true)
	assert_eq(int(t.grid()["columns"]), 2)
	var min_units: float = MenuMetrics.touch_units(DisplayServer.screen_get_dpi(), px)
	for b: TitleMenuItem in t.items():
		assert_true(b.size.y >= min_units - 0.5, "tile %.0f >= %.0f units" % [b.size.y, min_units])
		assert_true(b.tile)
	_check(t, "540x960")


func test_phone_landscape_touch_goes_two_wide() -> void:
	var t := _screen(1920.0, 1080.0, 0.5, true)
	for b: TitleMenuItem in t.items():
		assert_true(b.size.y * 0.5 >= MenuMetrics.TOUCH_MIN_PX - 0.5, "at least %d px tall" % int(MenuMetrics.TOUCH_MIN_PX))
	_check(t, "phone landscape")


func test_logo_fits_the_width_it_is_given() -> void:
	for w: float in [300.0, 600.0, 920.0]:
		assert_true(TitleLogo.mark_width(TitleLogo.fit_px(w, 200.0)) <= w + 0.5, "fits %.0f" % w)
