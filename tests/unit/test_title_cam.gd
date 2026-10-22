extends TestCase


func test_camera_stays_low_and_near_the_pair() -> void:
	for i: int in 200:
		var t: float = float(i) * 7.3
		var p: Dictionary = TitleCam.pose(t, 0.0, 46.0, 16.0 / 9.0)
		var pos: Vector3 = p["pos"]
		var flat: float = Vector2(pos.x, pos.z).length()
		assert_true(flat >= TitleCam.RADIUS - TitleCam.RADIUS_SWAY - 0.01 and flat <= TitleCam.RADIUS + TitleCam.RADIUS_SWAY + 0.01, "radius at t=%f" % t)
		assert_true(pos.y >= TitleCam.HEIGHT - TitleCam.HEIGHT_SWAY - 0.01 and pos.y <= TitleCam.HEIGHT + TitleCam.HEIGHT_SWAY + 0.01, "height")
		assert_true((p["target"] as Vector3).is_equal_approx(TitleCam.SUBJECT), "centred framing looks at the pair")


func test_drift_is_slow_and_smooth() -> void:
	var a: Vector3 = TitleCam.pose(30.0, 0.3, 46.0, 1.78)["pos"]
	var b: Vector3 = TitleCam.pose(30.0 + 1.0 / 60.0, 0.3, 46.0, 1.78)["pos"]
	assert_true(a.distance_to(b) < 0.01, "under 0.6 m/s")
	assert_true(a.distance_to(TitleCam.pose(60.0, 0.3, 46.0, 1.78)["pos"]) > 0.3, "but it does move")


func test_frame_x_puts_the_pair_right_of_centre() -> void:
	var p: Dictionary = TitleCam.pose(12.0, 0.36, 46.0, 16.0 / 9.0)
	var pos: Vector3 = p["pos"]
	var basis := Basis.looking_at((p["target"] as Vector3) - pos, Vector3.UP)
	var local: Vector3 = basis.inverse() * (TitleCam.SUBJECT - pos)
	var ndc_x: float = (local.x / -local.z) / (tan(deg_to_rad(46.0) * 0.5) * 16.0 / 9.0)
	assert_near(ndc_x, 0.36, 0.06)


## Screen position (x, y in half-widths and half-heights, y up) of `world` for a pose and aspect.
func _ndc(p: Dictionary, world: Vector3, aspect: float) -> Vector2:
	var pos: Vector3 = p["pos"]
	var basis := Basis.looking_at((p["target"] as Vector3) - pos, Vector3.UP)
	var local: Vector3 = basis.inverse() * (world - pos)
	var tv: float = tan(deg_to_rad(float(p["fov"])) * 0.5)
	return Vector2((local.x / -local.z) / (tv * aspect), (local.y / -local.z) / tv)


func test_wide_screen_keeps_the_lens_and_path() -> void:
	var p: Dictionary = TitleCam.pose(20.0, 0.0, 46.0, 16.0 / 9.0)
	assert_near(float(p["fov"]), 46.0, 0.001)
	var q: Dictionary = TitleCam.pose(20.0, 0.0, 46.0, 16.0 / 9.0, 0.0, 1.0)
	assert_true((p["pos"] as Vector3).is_equal_approx(q["pos"]), "defaults are the full screen")


func test_tall_phone_fits_the_pair_inside_the_band() -> void:
	for aspect: float in [540.0 / 960.0, 1080.0 / 2400.0]:
		var band: float = 0.3
		var fy: float = 0.25
		for i: int in 120:
			var t: float = float(i) * 9.1
			var p: Dictionary = TitleCam.pose(t, 0.0, 46.0, aspect, fy, band)
			var pos: Vector3 = p["pos"]
			assert_true(Vector2(pos.x, pos.z).length() < 10.0, "camera inside the arena wall at t=%f" % t)
			var centre: Vector2 = _ndc(p, TitleCam.SUBJECT, aspect)
			assert_near(centre.y, fy, 0.03)
			# Either fighter (1.75 m out along any bearing) stays on screen across.
			for s: float in [-1.0, 1.0]:
				for ang: float in [0.0, 0.8, 1.6]:
					var f: Vector3 = TitleCam.SUBJECT + Vector3(cos(ang), 0.0, sin(ang)) * 1.75 * s
					assert_true(absf(_ndc(p, f, aspect).x) < 0.9, "fighter on screen, aspect %f t=%f" % [aspect, t])
			# The pair's height fits the band: head to feet within 2 * band of the 2-unit screen height.
			var top: float = _ndc(p, TitleCam.SUBJECT + Vector3.UP * 1.1, aspect).y
			var bottom: float = _ndc(p, TitleCam.SUBJECT - Vector3.UP * 1.05, aspect).y
			assert_true(top - bottom <= 2.0 * band + 0.02, "height in band, aspect %f" % aspect)
