extends TestCase


func test_from_dict_falls_back_to_red() -> void:
	var p: BloodPalette = BloodPalette.from_dict({"fresh": "nonsense", "emission": 9.0})
	assert_eq(p.fresh, BloodPalette.red().fresh)
	assert_near(p.emission, 2.0, 0.0001, "emission is capped")
	assert_eq(BloodPalette.from_dict({}).flesh, BloodPalette.red().flesh)


func test_scaled_keeps_hue_and_never_exceeds_one() -> void:
	var c: Color = Color(0.10, 0.85, 0.60)
	var s: Color = BloodPalette.scaled(c, 1.225)
	assert_true(maxf(s.r, maxf(s.g, s.b)) <= 1.0001)
	assert_near(s.r / s.g, c.r / c.g, 0.001)
	assert_near(s.b / s.g, c.b / c.g, 0.001)
	var d: Color = BloodPalette.scaled(c, 0.6)
	assert_near(d.g, 0.51, 0.001)


func test_red_media_stay_close_to_the_old_look() -> void:
	var r: BloodPalette = BloodPalette.red()
	assert_near(r.drop_bright().r, 0.98, 0.01)
	assert_near(r.drop_dark().r, 0.52, 0.01)
	assert_near(r.decal_fresh().r, 0.48, 0.01)
	assert_near(r.sand_fresh().r, 0.45, 0.01)
	assert_near(r.sand_dried().r, 0.20, 0.01)


func test_stain_colour_dries() -> void:
	var p: BloodPalette = OutfitRules.blood_palette("alien")
	assert_eq(p.stain_color(0.0), p.fresh)
	assert_true(p.stain_color(1.0).g < p.stain_color(0.0).g)
	assert_eq(p.inner("fat"), p.fat)
	assert_eq(p.inner("anything"), p.flesh)
