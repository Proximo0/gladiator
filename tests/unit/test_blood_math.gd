extends TestCase


func test_drag_size_dependent() -> void:
	var small: float = BloodMath.drag_factor(6.0, 0.0015, 0.016)
	var big: float = BloodMath.drag_factor(6.0, 0.008, 0.016)
	assert_true(small < big, "small drops slow faster")
	assert_true(big < 1.0 and small > 0.0)


func test_step_velocity_gravity_and_drag() -> void:
	var v: Vector3 = BloodMath.step_velocity(Vector3(0, 0, 5), 0.016, 9.8, 0.004)
	assert_true(v.y < 0.0)
	assert_true(v.z < 5.0 and v.z > 4.5)
	var rest: Vector3 = BloodMath.step_velocity(Vector3.ZERO, 0.1, 9.8, 0.004)
	assert_near(rest.y, -0.98, 0.03)


func test_pressure_tracks_blood() -> void:
	assert_near(BloodMath.reserve(5.0, 5.0, 2.5), 1.0)
	assert_near(BloodMath.reserve(2.5, 5.0, 2.5), 0.0)
	assert_near(BloodMath.reserve(1.0, 5.0, 2.5), 0.0)
	assert_true(BloodMath.pressure(0.8) > BloodMath.pressure(0.3))
	assert_near(BloodMath.pressure(0.0), 0.0)


func test_heart_rate_rises_then_fails() -> void:
	assert_true(BloodMath.heart_rate_bpm(0.4) > BloodMath.heart_rate_bpm(1.0))
	assert_true(BloodMath.heart_rate_bpm(0.02) < BloodMath.heart_rate_bpm(0.3))


func test_pulse_shape() -> void:
	assert_near(BloodMath.pulse(0.18), 1.0, 0.01)
	assert_near(BloodMath.pulse(0.75), 0.0)
	assert_near(BloodMath.pulse(1.15), BloodMath.pulse(0.15), 0.0001, "periodic")
	assert_true(BloodMath.pulse(0.53) > 0.1, "dicrotic bump")


func test_flow_decays_and_scales() -> void:
	var a: float = BloodMath.spurt_flow(1.0, 1.0, 1.0, 0.0, 10.0)
	var b: float = BloodMath.spurt_flow(1.0, 1.0, 1.0, 10.0, 10.0)
	assert_near(a, 1.0)
	assert_true(b < a * 0.4)
	assert_true(BloodMath.spurt_flow(1.0, 0.5, 1.0, 0.0, 10.0) < a)
	assert_true(BloodMath.spurt_flow(1.0, 1.0, 0.0, 0.0, 10.0) < 0.2, "between beats")


func test_cone_dir_within_angle() -> void:
	var axis: Vector3 = Vector3(0.3, 1.0, -0.2).normalized()
	for i: int in 20:
		var d: Vector3 = BloodMath.cone_dir(axis, 0.3, float(i) / 20.0, float(i) * 0.37)
		assert_near(d.length(), 1.0, 0.001)
		assert_true(d.dot(axis) >= cos(0.3) - 0.001)
	assert_true(BloodMath.cone_dir(Vector3.UP, 0.3, 0.0, 0.5).dot(Vector3.UP) > 0.999)


func test_spray_scales_with_contact_and_damage() -> void:
	assert_true(BloodMath.spray_count(40.0, "edge") > BloodMath.spray_count(40.0, "point"))
	assert_true(BloodMath.spray_count(40.0, "point") > BloodMath.spray_count(40.0, "blunt"))
	assert_true(BloodMath.spray_count(80.0, "edge") > BloodMath.spray_count(10.0, "edge"))
	assert_eq(BloodMath.spray_count(0.0, "edge"), 0)
	assert_true(BloodMath.spray_count(9999.0, "edge") <= 260)


func test_budgets() -> void:
	assert_eq(BloodMath.budget(0), 600)
	assert_eq(BloodMath.budget(2), 5000)
	assert_eq(BloodMath.budget(9), 5000)
	assert_true(BloodMath.rate_mult(2) > BloodMath.rate_mult(0))


func test_splat_helpers() -> void:
	assert_true(BloodMath.splat_radius(0.01) > BloodMath.splat_radius(0.001))
	assert_true(BloodMath.droplet_litres(0.006) > BloodMath.droplet_litres(0.003) * 7.0)
	assert_eq(BloodMath.splat_cell(0.05, -0.05, 0.1), Vector2i(0, -1))


func test_stretch_length_capped() -> void:
	assert_true(BloodMath.stretch_length(8.0, 0.004, 2.5) > BloodMath.stretch_length(1.0, 0.004, 2.5))
	assert_true(BloodMath.stretch_length(500.0, 0.004, 2.5) <= 0.004 * BloodMath.TAIL_CAP + 0.00001)


func test_dryness_and_colour_stay_red() -> void:
	assert_near(BloodMath.dryness(0.0), 0.0, 0.0001)
	assert_true(BloodMath.dryness(300.0) > 0.9)
	assert_true(BloodMath.dryness(10.0) < BloodMath.dryness(60.0))
	for k: int in 11:
		var c: Color = BloodMath.blood_color(float(k) / 10.0)
		assert_true(c.r > c.g * 3.0 and c.r > c.b * 3.0, "red dominates at dryness %d" % k)
	assert_true(BloodMath.blood_color(0.0).r > BloodMath.blood_color(1.0).r)


func test_stain_bucket_and_pool_radius() -> void:
	assert_eq(BloodMath.stain_bucket(0.0, 4), 0)
	assert_eq(BloodMath.stain_bucket(9999.0, 4), 3)
	assert_true(BloodMath.pool_radius(1.0) > BloodMath.pool_radius(0.1))
	assert_true(BloodMath.pool_radius(500.0) <= 1.15)
	assert_true(BloodMath.decal_budget(2) > BloodMath.decal_budget(0))
	assert_true(BloodMath.stain_budget(2) > BloodMath.stain_budget(0))
