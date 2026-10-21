extends TestCase


func _rt_vec(v: Vector3, scale: float) -> Vector3:
	var b := StreamPeerBuffer.new()
	NetQuant.put_vec_i16(b, v, scale)
	b.seek(0)
	return NetQuant.get_vec_i16(b, scale)


func test_position_round_trip_within_half_mm() -> void:
	var v := Vector3(3.14159, 0.98765, -10.5)
	var back: Vector3 = _rt_vec(v, NetQuant.POS_SCALE)
	assert_true((back - v).length() < 0.0009, "error %f" % (back - v).length())


func test_position_clamps_out_of_range() -> void:
	var back: Vector3 = _rt_vec(Vector3(100.0, -100.0, 0.0), NetQuant.POS_SCALE)
	assert_near(back.x, 32.767, 0.001)
	assert_near(back.y, -32.767, 0.001)


func test_velocity_round_trip_1cm() -> void:
	var v := Vector3(25.123, -3.456, 0.004)
	var back: Vector3 = _rt_vec(v, NetQuant.VEL_SCALE)
	assert_true((back - v).length() < 0.01)


func test_quaternion_round_trip_under_quarter_degree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var worst: float = 0.0
	for _i: int in range(200):
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length() < 0.01:
			continue
		var q := Quaternion(axis.normalized(), rng.randf_range(-PI, PI))
		var back: Quaternion = NetQuant.u32_quat(NetQuant.quat_u32(q))
		worst = maxf(worst, q.angle_to(back))
	assert_true(worst < deg_to_rad(0.25), "worst %f deg" % rad_to_deg(worst))


func test_quaternion_fits_32_bits_and_sign_is_canonical() -> void:
	var q := Quaternion(Vector3.UP, 2.0)
	var a: int = NetQuant.quat_u32(q)
	var b: int = NetQuant.quat_u32(-q)
	assert_true(a >= 0 and a <= 0xffffffff)
	assert_eq(a, b, "q and -q are the same rotation")


func test_identity_quaternion() -> void:
	var back: Quaternion = NetQuant.u32_quat(NetQuant.quat_u32(Quaternion.IDENTITY))
	assert_true(Quaternion.IDENTITY.angle_to(back) < 0.002)


func test_yaw_round_trip_and_wrap() -> void:
	assert_near(NetQuant.u16_yaw(NetQuant.yaw_u16(1.234)), 1.234, 0.0002)
	assert_near(wrapf(NetQuant.u16_yaw(NetQuant.yaw_u16(TAU + 0.5)), -PI, PI), 0.5, 0.0002)


func test_frac_and_dir() -> void:
	assert_eq(NetQuant.frac_u8(1.5), 255)
	assert_eq(NetQuant.frac_u8(-1.0), 0)
	assert_near(NetQuant.u8_frac(NetQuant.frac_u8(0.4)), 0.4, 0.002)
	var b := StreamPeerBuffer.new()
	NetQuant.put_dir(b, Vector3(0.0, 2.0, 2.0))
	NetQuant.put_dir(b, Vector3.ZERO)
	b.seek(0)
	var d: Vector3 = NetQuant.get_dir(b)
	assert_true((d - Vector3(0.0, 0.7071, 0.7071)).length() < 0.01)
	assert_eq(NetQuant.get_dir(b), Vector3.ZERO)


func test_short_strings() -> void:
	var b := StreamPeerBuffer.new()
	NetQuant.put_str(b, "gladius")
	NetQuant.put_str(b, "")
	b.seek(0)
	assert_eq(NetQuant.get_str(b), "gladius")
	assert_eq(NetQuant.get_str(b), "")
