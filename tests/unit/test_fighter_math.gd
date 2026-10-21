extends TestCase
## FighterMath (pure ragdoll helpers) and FighterRig (body plan).


func test_rotation_error_zero_when_aligned() -> void:
	var b := Basis(Vector3(0, 1, 0), 0.7)
	assert_near(FighterMath.rotation_error(b, b).length(), 0.0, 0.00001)


func test_rotation_error_axis_and_angle() -> void:
	var e: Vector3 = FighterMath.rotation_error(Basis(), Basis(Vector3(1, 0, 0), 0.4))
	assert_near(e.x, 0.4, 0.0001)
	assert_near(e.y, 0.0, 0.0001)
	var back: Vector3 = FighterMath.rotation_error(Basis(Vector3(1, 0, 0), 0.4), Basis())
	assert_near(back.x, -0.4, 0.0001)


func test_rotation_error_takes_short_way() -> void:
	var e: Vector3 = FighterMath.rotation_error(Basis(), Basis(Vector3(0, 1, 0), 1.9 * PI))
	assert_near(e.y, -0.1 * PI, 0.0001)


func test_pd_torque_spring_damper_and_cap() -> void:
	var t: Vector3 = FighterMath.pd_torque(Vector3(0.1, 0, 0), Vector3.ZERO, 2.0, 10.0, 1.0, 1000.0)
	assert_near(t.x, 2.0 * 100.0 * 0.1, 0.0001)
	var d: Vector3 = FighterMath.pd_torque(Vector3.ZERO, Vector3(0, 1, 0), 2.0, 10.0, 1.0, 1000.0)
	assert_near(d.y, -2.0 * 2.0 * 10.0, 0.0001)
	var c: Vector3 = FighterMath.pd_torque(Vector3(5, 0, 0), Vector3.ZERO, 2.0, 10.0, 1.0, 50.0)
	assert_near(c.length(), 50.0, 0.0001)


func test_pd_force_capped() -> void:
	var f: Vector3 = FighterMath.pd_force(Vector3(0, 0, -1), Vector3.ZERO, 3.0, 20.0, 0.5, 900.0)
	assert_near(f.length(), 900.0, 0.001)
	assert_true(f.z < 0.0)


func test_stable_inertia_caps_damping_rate() -> void:
	var dt: float = 1.0 / 60.0
	var i: float = FighterMath.stable_inertia(5.0, 1.0, 14.0, 1.0, dt, 0.8)
	assert_near(2.0 * 14.0 * dt * i / 1.0, 0.8, 0.0001)
	assert_near(FighterMath.stable_inertia(0.1, 1.0, 14.0, 1.0, dt, 0.8), 0.1, 0.00001)


func test_leg_ik_straight_down() -> void:
	var a: Vector3 = FighterMath.leg_ik(Vector3(0, -0.8, 0), 0.44, 0.40)
	assert_near(a.y, 0.0, 0.0001, "no abduction")
	assert_true(a.z < 0.0, "knee bends back")
	assert_true(a.x > 0.0, "thigh forward of the line")


func test_leg_ik_reaches_target() -> void:
	var foot := Vector3(0.05, -0.75, -0.2)
	var a: Vector3 = FighterMath.leg_ik(foot, 0.44, 0.40)
	var bases: Array[Basis] = FighterMath.leg_bases(a)
	var knee: Vector3 = bases[0] * Vector3(0, -0.44, 0)
	var ankle: Vector3 = knee + (bases[0] * bases[1]) * Vector3(0, -0.40, 0)
	assert_near(ankle.distance_to(foot), 0.0, 0.002)


func test_arm_ik_lengths() -> void:
	var sh := Vector3(0.2, 1.5, 0)
	var r: Array[Vector3] = FighterMath.arm_ik(sh, Vector3(0.1, 1.3, -0.4), 0.28, 0.31, Vector3.DOWN)
	assert_near(r[0].distance_to(sh), 0.28, 0.0001)
	assert_near(r[0].distance_to(r[1]), 0.31, 0.0001)
	assert_true(r[0].y < 1.5, "elbow bends down")


func test_arm_ik_clamps_reach() -> void:
	var r: Array[Vector3] = FighterMath.arm_ik(Vector3.ZERO, Vector3(0, 0, -5), 0.28, 0.31, Vector3.DOWN)
	assert_true(r[1].length() < 0.59 + 0.0001)


func test_bone_basis_points_bone() -> void:
	var d := Vector3(0.3, 0.2, -0.9).normalized()
	assert_near((FighterMath.bone_basis(d) * Vector3.DOWN).distance_to(d), 0.0, 0.0001)
	assert_near((FighterMath.bone_basis(Vector3.UP) * Vector3.DOWN).distance_to(Vector3.UP), 0.0, 0.0001)


func _guard(aim: Vector2, thrust: float) -> Vector3:
	var p: Dictionary = {"w": 0.7, "h": 0.5, "fwd": 0.42, "thrust": 0.45, "min_fwd": 0.2}
	var origin := Vector3(0, 1.4, -0.42)
	var shoulder := Vector3(0.23, 1.53, 0)
	return FighterMath.guard_target(aim, thrust, origin, Vector3.RIGHT, Vector3.UP, Vector3.FORWARD, shoulder, 0.57, p)


func test_guard_centre_is_in_front() -> void:
	var t: Vector3 = _guard(Vector2.ZERO, 0.0)
	assert_true(t.z < -0.2, "in front of the chest")
	assert_true(t.distance_to(Vector3(0.23, 1.53, 0)) <= 0.5701)


func test_guard_maps_right_and_up() -> void:
	var c: Vector3 = _guard(Vector2.ZERO, 0.0)
	assert_true(_guard(Vector2(1, 0), 0.0).x > c.x)
	assert_true(_guard(Vector2(-1, 0), 0.0).x < c.x)
	assert_true(_guard(Vector2(0, 1), 0.0).y > c.y)
	assert_true(_guard(Vector2(0, -1), 0.0).y < c.y)


func test_guard_thrust_pushes_forward() -> void:
	assert_true(_guard(Vector2.ZERO, 1.0).z < _guard(Vector2.ZERO, 0.0).z)


func test_guard_never_behind_chest() -> void:
	var t: Vector3 = _guard(Vector2(-1, -1), 0.0)
	assert_true(-t.z >= 0.2 - 0.0001)


func test_yaw_helpers() -> void:
	assert_near(FighterMath.yaw_of(Vector3.FORWARD), 0.0, 0.0001)
	assert_near(FighterMath.yaw_of(-Basis(Vector3.UP, 1.2).z), 1.2, 0.0001)
	assert_near(FighterMath.turn_toward(3.0, -3.0, 0.1), wrapf(3.1, -PI, PI), 0.0001)
	assert_near(FighterMath.turn_toward(0.0, 0.05, 0.1), 0.05, 0.0001)


func test_balance_and_strength() -> void:
	assert_near(FighterMath.balance_from_tilt(0.0, 1.0), 1.0)
	assert_near(FighterMath.balance_from_tilt(0.5, 1.0), 0.5)
	assert_near(FighterMath.balance_from_tilt(2.0, 1.0), 0.0)
	assert_near(FighterMath.strength(1.0, 1.0, 0.45), 1.0)
	assert_near(FighterMath.strength(0.0, 1.0, 0.45), 0.45)
	assert_near(FighterMath.strength(1.0, 0.0, 0.45), 0.0)
	assert_near(FighterMath.limb_factor(0.0, 0.25), 0.25)


func test_gait_feet_alternate() -> void:
	var a: Vector3 = FighterMath.foot_offset(0.0, Vector2(0, 1), 0.3, 0.1)
	var b: Vector3 = FighterMath.foot_offset(PI, Vector2(0, 1), 0.3, 0.1)
	assert_near(a.z, 0.3, 0.0001, "back at swing start")
	assert_near(b.z, -0.3, 0.0001, "front at swing end")
	assert_near(FighterMath.foot_offset(PI * 0.5, Vector2(0, 1), 0.3, 0.1).y, 0.1, 0.0001)
	assert_near(FighterMath.foot_offset(PI * 1.5, Vector2(0, 1), 0.3, 0.1).y, 0.0, 0.0001)


func test_stride_is_continuous_and_capped() -> void:
	assert_near(FighterMath.stride_amp(0.0, 0.15, 0.08, 0.45), 0.0)
	assert_true(FighterMath.stride_amp(0.01, 0.15, 0.08, 0.45) < 0.01)
	assert_near(FighterMath.stride_amp(20.0, 0.15, 0.08, 0.45), 0.45)


func test_effective_mass_tip_lighter_than_centre() -> void:
	var at_com: float = FighterMath.effective_mass(1.4, 0.17, 0.0, 0.0)
	var at_tip: float = FighterMath.effective_mass(1.4, 0.17, 0.45, 0.0)
	assert_near(at_com, 1.4, 0.0001)
	assert_true(at_tip < at_com)
	assert_near(FighterMath.effective_mass(1.0, 0.1, 0.0, 0.5), 1.5, 0.0001)


func test_classify_contact() -> void:
	var sword: Dictionary = {"shape": "sword", "length": 1.2, "grip_offset": 0.1, "edge_len": 0.9, "point": true}
	assert_eq(FighterMath.classify_contact(sword, 0.8, Vector3(5, 0, 0))["contact"], "edge")
	assert_eq(FighterMath.classify_contact(sword, 0.8, Vector3(0, 0, 5))["contact"], "flat")
	assert_eq(FighterMath.classify_contact(sword, 1.08, Vector3(0, 5, 0))["contact"], "point")
	assert_eq(FighterMath.classify_contact(sword, 0.0, Vector3(5, 0, 0))["contact"], "blunt", "hilt")
	var club: Dictionary = {"shape": "club", "length": 0.75, "grip_offset": 0.1}
	assert_eq(FighterMath.classify_contact(club, 0.5, Vector3(5, 0, 0))["contact"], "blunt")
	assert_near(float(FighterMath.classify_contact(sword, 0.8, Vector3(3, 0, 4))["edge_alignment"]), 0.6, 0.0001)


func test_rig_masses_and_tree() -> void:
	assert_eq(FighterRig.PARTS.size(), 11)
	var m: float = FighterRig.total_mass()
	assert_true(m > 70.0 and m < 82.0, "about 75 kg: %f" % m)
	assert_eq(FighterRig.subtree("upper_arm_r"), PackedStringArray(["upper_arm_r", "forearm_r"]))
	assert_eq(FighterRig.subtree("thigh_l"), PackedStringArray(["thigh_l", "shin_l"]))
	assert_true(FighterRig.joint_inertia("thigh_l") > FighterRig.joint_inertia("shin_l"))
	assert_true(FighterRig.pair_inertia("torso", {}) > 0.0)


func test_rig_limits_ordered() -> void:
	for p: Dictionary in FighterRig.PARTS:
		var lim: Array = p["lim"]
		for i: int in range(3):
			assert_true(float(lim[i * 2]) <= float(lim[i * 2 + 1]), "%s axis %d" % [p["name"], i])
