extends TestCase


func test_level_frac_clamps_to_full() -> void:
	assert_near(BloodMeter.level_frac(5.0, 5.0), 1.0)
	assert_near(BloodMeter.level_frac(2.5, 5.0), 0.5)
	assert_near(BloodMeter.level_frac(-1.0, 5.0), 0.0)
	assert_near(BloodMeter.level_frac(9.0, 5.0), 1.0)
	assert_near(BloodMeter.level_frac(3.0, 0.0), 0.0)


func test_danger_frac_is_zero_at_death_and_one_at_full() -> void:
	assert_near(BloodMeter.danger_frac(2.5, 2.5, 5.0), 0.0)
	assert_near(BloodMeter.danger_frac(5.0, 2.5, 5.0), 1.0)
	assert_near(BloodMeter.danger_frac(1.0, 2.5, 5.0), 0.0)
	assert_near(BloodMeter.danger_frac(3.75, 2.5, 5.0), 0.5)


func test_level_y_runs_from_empty_bulb_to_full_top() -> void:
	var rect: Rect2 = BloodMeter.vial_rect()
	assert_near(BloodMeter.level_y(rect, 5.0), rect.position.y + 6.0)
	assert_near(BloodMeter.level_y(rect, 0.0), rect.end.y - 2.0)
	assert_true(BloodMeter.level_y(rect, 2.5) > BloodMeter.level_y(rect, 4.0), "lower blood, lower surface")


func test_smooth_toward_moves_monotonically_and_converges() -> void:
	var v: float = 5.0
	var last: float = v
	for i: int in 240:
		v = BloodMeter.smooth_toward(v, 2.0, 1.0 / 60.0, BloodMeter.DRAIN_SPEED)
		assert_true(v <= last + 0.000001, "never rises toward a lower target")
		assert_true(v >= 2.0, "never overshoots")
		last = v
	assert_near(v, 2.0, 0.0006)


func test_smooth_toward_is_frame_rate_independent() -> void:
	var fine: float = 5.0
	for i: int in 120:
		fine = BloodMeter.smooth_toward(fine, 2.0, 1.0 / 120.0, 4.0)
	var coarse: float = BloodMeter.smooth_toward(5.0, 2.0, 1.0, 4.0)
	assert_near(fine, coarse, 0.001)


func test_smooth_toward_zero_delta_holds() -> void:
	assert_near(BloodMeter.smooth_toward(4.0, 2.0, 0.0, 6.0), 4.0)


func test_drip_hz_is_zero_when_not_bleeding() -> void:
	assert_near(BloodMeter.drip_hz(0.0), 0.0)
	assert_near(BloodMeter.drip_hz(0.001), 0.0)


func test_drip_hz_grows_with_bleed_rate_and_caps() -> void:
	var slow: float = BloodMeter.drip_hz(0.05)
	var fast: float = BloodMeter.drip_hz(0.5)
	assert_true(slow > 0.0, "a trickle still drips")
	assert_true(fast > slow, "more bleeding, faster drips")
	assert_near(BloodMeter.drip_hz(1.0), BloodMeter.DRIP_HZ_MAX)
	assert_near(BloodMeter.drip_hz(10.0), BloodMeter.DRIP_HZ_MAX)


func test_heartbeat_speeds_up_as_blood_drops() -> void:
	assert_near(BloodMeter.heartbeat_hz(5.0, 2.5, 5.0), BloodMeter.HEART_CALM_HZ)
	assert_near(BloodMeter.heartbeat_hz(2.5, 2.5, 5.0), BloodMeter.HEART_FAST_HZ)
	assert_true(BloodMeter.heartbeat_hz(3.0, 2.5, 5.0) > BloodMeter.heartbeat_hz(4.0, 2.5, 5.0))


func test_pulse_strength_grows_near_death() -> void:
	assert_near(BloodMeter.pulse_strength(5.0, 2.5, 5.0), BloodMeter.PULSE_CALM)
	assert_near(BloodMeter.pulse_strength(2.5, 2.5, 5.0), BloodMeter.PULSE_FAST)


func test_heartbeat_shape_peaks_on_the_beat_and_stays_in_range() -> void:
	assert_near(BloodMeter.heartbeat_shape(0.0), 1.0, 0.001)
	assert_near(BloodMeter.heartbeat_shape(0.5), 0.0, 0.001)
	assert_near(BloodMeter.heartbeat_shape(1.0), 1.0, 0.001, "wraps each cycle")
	assert_true(BloodMeter.heartbeat_shape(0.2) > 0.5, "the dub is a clear second beat")
	for i: int in 100:
		var s: float = BloodMeter.heartbeat_shape(float(i) / 100.0)
		assert_true(s >= 0.0 and s <= 1.0, "shape in 0..1")


func test_blood_color_red_when_full_brown_black_at_death() -> void:
	var full: Color = BloodMeter.blood_color(5.0, 2.5, 5.0)
	assert_near(full.r, BloodMeter.DEEP_RED.r, 0.001)
	assert_near(full.g, BloodMeter.DEEP_RED.g, 0.001)
	var death: Color = BloodMeter.blood_color(2.5, 2.5, 5.0)
	assert_near(death.r, BloodMeter.BROWN_BLACK.r, 0.001)
	assert_near(death.g, BloodMeter.BROWN_BLACK.g, 0.001)
	assert_true(death.get_luminance() < full.get_luminance() * 0.5, "much darker near death")


func test_blood_color_darkens_monotonically() -> void:
	var prev: float = -1.0
	for i: int in 30:
		var blood: float = 2.5 + 2.5 * float(i) / 29.0
		var lum: float = BloodMeter.blood_color(blood, 2.5, 5.0).get_luminance()
		assert_true(lum >= prev - 0.000001, "lighter with more blood")
		prev = lum


func test_stamina_span_is_a_fraction_of_a_turn() -> void:
	assert_near(BloodMeter.stamina_span(0.5), PI, 0.0001)
	assert_near(BloodMeter.stamina_span(1.0), TAU, 0.0001)
	assert_near(BloodMeter.stamina_span(2.0), TAU, 0.0001)
	assert_near(BloodMeter.stamina_span(-1.0), 0.0, 0.0001)


func test_clip_below_keeps_the_lower_part_of_a_square() -> void:
	var sq: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var clipped: PackedVector2Array = BloodMeter.clip_below(sq, 5.0)
	assert_eq(clipped.size(), 4)
	for p: Vector2 in clipped:
		assert_true(p.y >= 5.0 - 0.0001, "every point at or below the cut")
	var area: float = _shoelace(clipped)
	assert_near(area, 50.0, 0.001)


func test_clip_below_is_empty_or_whole_outside_the_shape() -> void:
	var sq: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	assert_eq(BloodMeter.clip_below(sq, 20.0).size(), 0)
	assert_eq(BloodMeter.clip_below(sq, -5.0).size(), 4)


func test_vial_outline_stays_inside_its_rect() -> void:
	var rect: Rect2 = BloodMeter.vial_rect()
	var pts: PackedVector2Array = BloodMeter.vial_outline(rect)
	assert_true(pts.size() > 8)
	for p: Vector2 in pts:
		assert_true(rect.grow(0.001).has_point(p), "point inside the vial rect")


func test_half_width_matches_neck_and_bulb() -> void:
	var rect: Rect2 = BloodMeter.vial_rect()
	var r: float = rect.size.x * 0.5
	assert_near(BloodMeter.half_width(rect, rect.position.y + 5.0), r * BloodMeter.NECK_FRAC)
	assert_near(BloodMeter.half_width(rect, rect.end.y - r), r, 0.0001, "widest at the bulb centre")
	assert_near(BloodMeter.half_width(rect, rect.end.y + 1.0), 0.0, 0.0001, "nothing below the bulb")


func test_meander_cells_fill_the_width_inside_one_cell_height() -> void:
	var cells: Array = BloodMeter.meander_cells(100.0, 8.0, Vector2(10.0, 20.0))
	assert_eq(cells.size(), 12, "floor(100 / 8) cells")
	for seg: PackedVector2Array in cells:
		assert_eq(seg.size(), BloodMeter.meander_unit().size())
		for p: Vector2 in seg:
			assert_true(p.x >= 10.0 - 0.001 and p.x <= 10.0 + 96.0 + 0.001, "inside the band width")
			assert_true(p.y >= 20.0 - 0.001 and p.y <= 28.0 + 0.001, "inside one cell height")
	assert_eq(BloodMeter.meander_cells(100.0, 0.0, Vector2.ZERO).size(), 0, "no cells for a zero cell size")


func _shoelace(pts: PackedVector2Array) -> float:
	var s: float = 0.0
	for i: int in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


func test_meander_segments_match_cells() -> void:
	var cells: Array = BloodMeter.meander_cells(80.0, 8.0, Vector2(2.0, 3.0))
	var segs: PackedVector2Array = BloodMeter.meander_segments(80.0, 8.0, Vector2(2.0, 3.0))
	var expect: int = 0
	for c: PackedVector2Array in cells:
		expect += (c.size() - 1) * 2
	assert_eq(segs.size(), expect)
	assert_eq(segs.size() % 2, 0, "segment pairs")
	var first: PackedVector2Array = cells[0]
	assert_eq(segs[0], first[0])
	assert_eq(segs[1], first[1])


func test_idle_banner_is_hidden() -> void:
	var h := HUD.new()
	assert_false(h.get("_banner").visible)
	h.free()


func test_banner_fit_scale_never_overflows() -> void:
	# A 1500 px line on a 1920 wide viewport must shrink to 90 percent of it; short lines keep the usual scale.
	var k: float = HUD.fit_scale(1500.0, 1920.0, 0.9)
	assert_true(1500.0 * k <= 1920.0 * 0.9 + 0.01)
	assert_true(HUD.fit_scale(300.0, 1920.0, 0.9) > 1.0)
	assert_eq(HUD.fit_scale(0.0, 1920.0, 0.9), HUD.BANNER_MAX_SCALE)


func test_meter_layout_keeps_text_readable() -> void:
	var m := BloodMeter.new()
	m.configure(1.0, 0.28)  # a phone: 0.28 screen px per unit
	assert_true(m.text_size(16.0, BloodMeter.MIN_PX_LATIN) >= int(BloodMeter.MIN_PX_LATIN / 0.28))
	m.configure(3.0, 0.28)
	assert_near(m.size.x, BloodMeter.METER_SIZE.x * 3.0)
	assert_eq(m.text_size(32.0, 1.0), 96)  # grows with the meter when above the floor
	m.free()
	assert_near(HUD.meter_px(540.0), HUD.METER_MIN_PX)
	assert_near(HUD.meter_px(5000.0), HUD.METER_MAX_PX)


func test_meters_sit_at_the_bottom_for_mouse_and_at_the_top_for_touch() -> void:
	var vp: Vector2 = Vector2(1920.0, 4160.0)
	var meter: Vector2 = Vector2(600.0, 930.0)
	var desk: Array = HUD.meter_positions(vp, meter, 0.28, Vector4.ZERO, false)
	assert_true((desk[0] as Vector2).y > vp.y * 0.5, "bottom")
	var touch: Array = HUD.meter_positions(vp, meter, 0.28, Vector4(0.0, 60.0, 0.0, 0.0), true)
	assert_true((touch[0] as Vector2).y * 0.28 >= 60.0, "below the notch")
	assert_near((touch[0] as Vector2).y, (touch[1] as Vector2).y)
	assert_true((touch[1] as Vector2).x + meter.x <= vp.x, "opponent meter on screen")
	assert_true((touch[0] as Vector2).x + meter.x < (touch[1] as Vector2).x, "the two meters do not touch")


func test_touch_block_covers_the_meters() -> void:
	assert_true(HUD.touch_block_px(540.0, 1170.0, 0.0) > 60.0)


func test_touch_meters_shrink_on_a_short_landscape_screen_only() -> void:
	assert_true(HUD.meter_px(1170.0, 540.0, true) < HUD.meter_px(1170.0, 540.0, false))
	assert_true(HUD.touch_block_px(1170.0, 540.0, 0.0) <= 540.0 * 0.5, "leaves the lower half to the thumbs")
	assert_false(HUD.is_compact(1170.0, 540.0, true))
	assert_false(HUD.is_compact(540.0, 1170.0, false), "mouse never uses the compact meters")


func test_portrait_touch_uses_compact_meters_that_leave_the_arena() -> void:
	assert_true(HUD.is_compact(540.0, 1170.0, true))
	var w: float = HUD.meter_px(540.0, 1170.0, true)
	assert_true(w * 2.0 < 540.0, "two side by side")
	assert_true(HUD.touch_block_px(540.0, 1170.0, 0.0) < 1170.0 * 0.14, "well under the old quarter of the screen")
	var m: BloodMeter = BloodMeter.new()
	m.configure(1.0, 1.0, true)
	assert_eq(m.custom_minimum_size, BloodMeter.COMPACT_SIZE)
	m.configure(1.0, 1.0, false)
	assert_eq(m.custom_minimum_size, BloodMeter.METER_SIZE)
	m.free()
	assert_true(BloodMeter.compact_bar_rect().end.x < BloodMeter.compact_ring_centre().x - BloodMeter.COMPACT_RING_R, "bar and ring do not overlap")


func test_clock_text_counts_up_then_down_the_last_30_s() -> void:
	assert_eq(HUD.clock_text(0.0, 180.0), "0:00")
	assert_eq(HUD.clock_text(59.99, 180.0), "0:59", "whole seconds gone")
	assert_eq(HUD.clock_text(61.0, 180.0), "1:01")
	assert_eq(HUD.clock_text(149.9, 180.0), "2:29", "30.1 s left: still counting up")
	assert_eq(HUD.clock_text(150.0, 180.0), "0:30", "30 s left: the countdown starts")
	assert_eq(HUD.clock_text(150.5, 180.0), "0:30", "seconds left round up")
	assert_eq(HUD.clock_text(179.5, 180.0), "0:01")
	assert_eq(HUD.clock_text(180.0, 180.0), "0:00")
	assert_eq(HUD.clock_text(200.0, 180.0), "0:00", "never below zero")
	assert_eq(HUD.clock_text(-3.0, 180.0), "0:00", "never negative before the release")
	assert_eq(HUD.clock_text(125.0, 0.0), "2:05", "no limit: counts up only")


func test_clock_counts_down_only_near_the_limit() -> void:
	assert_false(HUD.clock_counts_down(0.0, 180.0))
	assert_true(HUD.clock_counts_down(150.0, 180.0))
	assert_true(HUD.clock_counts_down(0.0, 20.0), "a short limit counts down from the start")
	assert_false(HUD.clock_counts_down(500.0, 0.0), "no limit, no countdown")


func test_clock_mouse_sits_bottom_centre_above_the_diagnostics_line() -> void:
	var vp := Vector2(1920.0, 1080.0)
	var c := Vector2(150.0, 60.0)
	var p: Vector2 = HUD.clock_position(vp, c, 0.667, Vector4.ZERO, false, false, Vector2.ZERO, Vector2.ZERO)
	assert_near(p.x + c.x * 0.5, vp.x * 0.5, 0.01, "centred")
	assert_true(p.y + c.y <= vp.y - HUD.diag_clear(), "clear of the render-toggles plate")
	var meters: Array = HUD.meter_positions(vp, BloodMeter.METER_SIZE, 0.667, Vector4.ZERO, false)
	assert_true(p.x > (meters[0] as Vector2).x + BloodMeter.METER_SIZE.x, "right of the player's meter")
	assert_true(p.x + c.x < (meters[1] as Vector2).x, "left of the opponent's meter")


func test_clock_touch_landscape_sits_left_of_the_pause_button() -> void:
	var vp := Vector2(1920.0, 886.0)  # a 2340x1080 phone
	var k: float = 1080.0 / 886.0
	var c := Vector2(120.0, 50.0)
	var ins := Vector4(90.0, 0.0, 0.0, 0.0)
	var p: Vector2 = HUD.clock_position(vp, c, k, ins, true, false, Vector2.ZERO, Vector2.ZERO)
	var pause: float = HUD.pause_side(vp, k)
	var pause_left: float = (vp.x - pause) * 0.5
	assert_true(p.x + c.x <= pause_left, "left of the pause button")
	assert_near(pause_left - (p.x + c.x), HUD.CLOCK_GAP_PX / k, 0.01)
	var meters: Array = HUD.meter_positions(vp, BloodMeter.METER_SIZE * 0.7, k, ins, true)
	assert_true(p.x > (meters[0] as Vector2).x + BloodMeter.METER_SIZE.x * 0.7, "right of the player's meter")
	assert_true(p.y >= 0.0 and p.y + c.y <= pause + HUD.TOUCH_EDGE_PX / k + 0.01, "in the pause button's row")


func test_clock_touch_portrait_sits_under_the_players_meter() -> void:
	var meter_at := Vector2(20.0, 30.0)
	var meter := Vector2(400.0, 190.0)
	var p: Vector2 = HUD.clock_position(Vector2(1000.0, 2000.0), Vector2(100.0, 40.0), 0.5, Vector4.ZERO, true, true, meter_at, meter)
	assert_near(p.x, meter_at.x)
	assert_true(p.y > meter_at.y + meter.y, "below the meter")


func test_pause_side_matches_menu_flow() -> void:
	assert_near(HUD.pause_side(Vector2(1920.0, 1080.0), 1.0), 96.0, 0.001, "landscape: the design size")
	assert_near(HUD.pause_side(Vector2(1920.0, 1080.0), 0.1), MenuFlow.PAUSE_MIN_PX / 0.1, 0.001, "never under the on-screen minimum")
	assert_near(HUD.pause_side(Vector2(1000.0, 2000.0), 1.0), 96.0 * 1000.0 / MenuFlow.PORTRAIT_UNITS, 0.001, "portrait menu scale")
