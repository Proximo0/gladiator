extends TestCase
## FightOverlay's pure math (OverlayDraw): colours, fades, geometry, trail, text and the slow-motion scale.

const GREEN := Color(0.0, 1.0, 0.0)


func test_speed_color_stops_and_clamp() -> void:
	assert_eq(OverlayDraw.speed_color(0.0), OverlayDraw.SPEED_STOPS[0][1], "at rest")
	assert_eq(OverlayDraw.speed_color(2.0), OverlayDraw.SPEED_STOPS[1][1], "cyan stop")
	assert_eq(OverlayDraw.speed_color(-5.0), OverlayDraw.SPEED_STOPS[0][1], "negative clamps to rest")
	assert_eq(OverlayDraw.speed_color(99.0), OverlayDraw.SPEED_STOPS[3][1], "fast clamps to top stop")


func test_speed_color_interpolates_between_stops() -> void:
	var mid: Color = OverlayDraw.speed_color(1.0)
	var a: Color = OverlayDraw.SPEED_STOPS[0][1]
	var b: Color = OverlayDraw.SPEED_STOPS[1][1]
	assert_near(mid.r, (a.r + b.r) * 0.5, 0.0001)
	assert_near(mid.g, (a.g + b.g) * 0.5, 0.0001)
	assert_near(mid.b, (a.b + b.b) * 0.5, 0.0001)


func test_no_pure_green_in_palette() -> void:
	for s: float in [0.0, 1.0, 2.0, 4.0, 6.0, 9.0, 12.0, 30.0]:
		assert_false(OverlayDraw.speed_color(s).is_equal_approx(GREEN), "speed %f" % s)
	for kind: String in ["edge", "point", "flat", "blunt", "", "other"]:
		assert_false(OverlayDraw.contact_color(kind).is_equal_approx(GREEN), "kind %s" % kind)
	assert_false(OverlayDraw.TARGET_COLOR.is_equal_approx(GREEN), "target")
	assert_false(OverlayDraw.HAND_COLOR.is_equal_approx(GREEN), "hand")


func test_contact_color_per_kind() -> void:
	assert_eq(OverlayDraw.contact_color("edge"), OverlayDraw.EDGE_COLOR)
	assert_eq(OverlayDraw.contact_color("point"), OverlayDraw.POINT_COLOR)
	assert_eq(OverlayDraw.contact_color("flat"), OverlayDraw.FLAT_COLOR)
	assert_eq(OverlayDraw.contact_color("blunt"), OverlayDraw.BLUNT_COLOR)
	assert_eq(OverlayDraw.contact_color("bogus"), OverlayDraw.OTHER_COLOR, "unknown kind")


func test_age_from_physics_frames() -> void:
	assert_near(OverlayDraw.age_s(130, 100, 60.0), 0.5, 0.0001)
	assert_near(OverlayDraw.age_s(100, 100, 60.0), 0.0, 0.0001)
	assert_near(OverlayDraw.age_s(100, 100, 0.0), 0.0, 0.0001, "zero tick rate is guarded")


func test_fade_and_flash() -> void:
	assert_near(OverlayDraw.fade(0.0, 0.6), 1.0, 0.0001)
	assert_near(OverlayDraw.fade(0.3, 0.6), 0.5, 0.0001)
	assert_near(OverlayDraw.fade(0.6, 0.6), 0.0, 0.0001)
	assert_near(OverlayDraw.fade(2.0, 0.6), 0.0, 0.0001)
	assert_near(OverlayDraw.fade(0.1, 0.0), 0.0, 0.0001, "no life")
	assert_near(OverlayDraw.flash_alpha(0.0, 0.6), 1.0, 0.0001, "bright on impact")
	assert_near(OverlayDraw.flash_alpha(0.1, 0.6), OverlayDraw.BLINK_DIM * (1.0 - 0.1 / 0.6), 0.0001, "blink dim")
	assert_near(OverlayDraw.flash_alpha(0.6, 0.6), 0.0, 0.0001, "gone at life end")


func test_knock_length_clamped() -> void:
	assert_near(OverlayDraw.knock_length(0.0), 0.0, 0.0001)
	assert_near(OverlayDraw.knock_length(0.5), OverlayDraw.KNOCK_MIN_M, 0.0001, "small hits get a visible arrow")
	assert_near(OverlayDraw.knock_length(3.0), 0.3, 0.0001)
	assert_near(OverlayDraw.knock_length(500.0), OverlayDraw.KNOCK_MAX_M, 0.0001)


func test_cross_has_three_axes_through_centre() -> void:
	var c := Vector3(1.0, 2.0, 3.0)
	var pts: PackedVector3Array = OverlayDraw.cross(c, 0.1)
	assert_eq(pts.size(), 6)
	assert_true((pts[0] + pts[1]).is_equal_approx(c * 2.0), "x axis centred")
	assert_true((pts[2] + pts[3]).is_equal_approx(c * 2.0), "y axis centred")
	assert_true((pts[4] + pts[5]).is_equal_approx(c * 2.0), "z axis centred")


func test_arrow_empty_for_zero_vector() -> void:
	assert_eq(OverlayDraw.arrow(Vector3.ZERO, Vector3.ZERO).size(), 0)


func test_arrow_shaft_and_head() -> void:
	var from := Vector3(0.0, 1.0, 0.0)
	var vec := Vector3(0.0, 0.0, -0.5)
	var pts: PackedVector3Array = OverlayDraw.arrow(from, vec)
	assert_eq(pts.size(), 6, "shaft plus two wings")
	assert_true(pts[0].is_equal_approx(from), "shaft starts at the contact")
	assert_true(pts[1].is_equal_approx(from + vec), "shaft ends at the tip")
	for i: int in [3, 5]:
		assert_true(pts[i].is_equal_approx(pts[1]) or pts[i].z > pts[1].z, "wings trail behind the tip")
		assert_true(absf(pts[i].y - from.y) < 0.0001, "wings stay level in a flat arrow")


func test_arrow_vertical_still_has_head() -> void:
	var pts: PackedVector3Array = OverlayDraw.arrow(Vector3.ZERO, Vector3(0.0, -0.4, 0.0))
	assert_eq(pts.size(), 6)
	assert_true(pts[3].length() > 0.01, "wing is not degenerate")


func test_guard_corners_rectangle() -> void:
	var pts: PackedVector3Array = OverlayDraw.guard_corners(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, 0.7, 0.5)
	assert_eq(pts.size(), 8)
	assert_true(pts[0].is_equal_approx(Vector3(-0.7, -0.5, 0.0)), "bottom left")
	assert_true(pts[3].is_equal_approx(Vector3(0.7, 0.5, 0.0)), "top right")
	assert_true(pts[6].is_equal_approx(Vector3(-0.7, 0.5, 0.0)), "top left")


func test_trail_segments_coloured_by_speed_and_faded() -> void:
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var speeds := PackedFloat32Array([0.0, 6.0, 12.0])
	var ages := PackedFloat32Array([0.0, 0.25, 0.5])
	var t: Dictionary = OverlayDraw.trail(pts, speeds, ages)
	var segs: PackedVector3Array = t["segs"]
	var cols: PackedColorArray = t["cols"]
	assert_eq(segs.size(), 4, "two segments")
	assert_eq(cols.size(), 4)
	assert_true(segs[2].is_equal_approx(Vector3(1, 0, 0)) and segs[3].is_equal_approx(Vector3(2, 0, 0)))
	var c2: Color = OverlayDraw.speed_color(12.0)
	assert_near(cols[2].r, c2.r, 0.0001, "colour from the later sample's speed")
	assert_near(cols[0].a, 0.5, 0.0001, "segment ending at age 0.25 is half faded")
	assert_near(cols[2].a, 0.0, 0.0001, "segment ending at the life limit is gone")


func test_trail_empty_and_single_sample() -> void:
	var one: Dictionary = OverlayDraw.trail(PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([1.0]),
		PackedFloat32Array([0.0]))
	assert_eq((one["segs"] as PackedVector3Array).size(), 0)
	var none: Dictionary = OverlayDraw.trail(PackedVector3Array(), PackedFloat32Array(), PackedFloat32Array())
	assert_eq((none["cols"] as PackedColorArray).size(), 0)


func test_paint_one_colour() -> void:
	var cols: PackedColorArray = OverlayDraw.paint(PackedVector3Array([Vector3.ZERO, Vector3.UP]), Color.RED)
	assert_eq(cols.size(), 2)
	assert_eq(cols[1], Color.RED)


func test_format_fighter_lines() -> void:
	var d: Dictionary = {
		"side": 1, "state": "standing", "balance": 0.912, "stamina": 0.8, "consciousness": 1.0,
		"blood_frac": 0.66, "tip_speed": 4.4, "weapon_id": "longsword", "grip": "half",
		"hand_target": Vector3(0.0, 0.0, 0.0), "hand_pos": Vector3(0.3, 0.0, 0.0),
	}
	var text: String = OverlayDraw.format_fighter(d, "strike")
	var lines: PackedStringArray = text.split("\n")
	assert_eq(lines.size(), 5)
	assert_eq(lines[0], "P2  standing  brain strike")
	assert_eq(lines[1], "balance 0.91  stamina 0.80")
	assert_eq(lines[2], "consciousness 1.00  blood 0.66")
	assert_eq(lines[3], "tip 4.4 m/s  longsword  grip half")
	assert_eq(lines[4], "hand gap 0.30 m")


func test_format_fighter_without_brain() -> void:
	var text: String = OverlayDraw.format_fighter({"side": 0, "state": "down"}, "")
	assert_eq(text.split("\n")[0], "P1  down", "no brain tag for a human side")


func test_format_status_states() -> void:
	assert_eq(OverlayDraw.format_status(false, false), "F1 overlay  F2 slow-mo off  F3 freeze off  . step")
	assert_eq(OverlayDraw.format_status(true, true), "F1 overlay  F2 slow-mo 0.25x  F3 freeze on  . step")


func test_time_scale_for_slowmo() -> void:
	assert_near(OverlayDraw.time_scale_for(true), 0.25, 0.0001)
	assert_near(OverlayDraw.time_scale_for(false), 1.0, 0.0001)
