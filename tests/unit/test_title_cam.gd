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
