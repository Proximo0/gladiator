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
