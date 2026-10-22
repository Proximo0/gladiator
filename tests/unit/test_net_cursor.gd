extends TestCase


func _inp(ax: int, ay: int, buttons: int = 0) -> FighterInput:
	return FighterInput.from_array([0, 0, ax, ay, buttons])


func test_matches_guard_target_for_centre_aim() -> void:
	var tun: Tuning = Tuning.new()
	var torso := Transform3D(Basis(), Vector3(0.0, 1.33, 0.0))
	var p: Vector3 = NetCursor.predict(_inp(0, 0), torso, 0.0, false, tun)
	# Facing -Z at yaw 0: the centre of the guard plane is in front of the chest.
	assert_true(p.z < -0.15, "in front: %s" % str(p))
	assert_near(p.y, 1.33 + NetCursor.CHEST_UP - NetCursor.ORIGIN_DOWN, 0.05)


func test_aim_moves_cursor_right_and_up_in_facing_frame() -> void:
	var tun: Tuning = Tuning.new()
	var torso := Transform3D(Basis(), Vector3(2.0, 1.33, 1.0))
	var c: Vector3 = NetCursor.predict(_inp(0, 0), torso, PI * 0.5, false, tun)
	var r: Vector3 = NetCursor.predict(_inp(600, 0), torso, PI * 0.5, false, tun)
	var u: Vector3 = NetCursor.predict(_inp(0, 600), torso, PI * 0.5, false, tun)
	var right: Vector3 = Basis(Vector3.UP, PI * 0.5).x
	assert_true((r - c).dot(right) > 0.1)
	assert_true(u.y - c.y > 0.1)


func test_thrust_reaches_further() -> void:
	var tun: Tuning = Tuning.new()
	var torso := Transform3D(Basis(), Vector3(0.0, 1.33, 0.0))
	var g: Vector3 = NetCursor.predict(_inp(0, 0), torso, 0.0, false, tun)
	var t: Vector3 = NetCursor.predict(_inp(0, 0, FighterInput.THRUST), torso, 0.0, false, tun)
	assert_true(t.z < g.z)


func test_follow_snaps_then_eases() -> void:
	var c := NetCursor.new()
	assert_eq(c.follow(Vector3(1, 0, 0), 1.0 / 60.0), Vector3(1, 0, 0))
	var p: Vector3 = c.follow(Vector3(2, 0, 0), 1.0 / 60.0)
	assert_true(p.x > 1.0 and p.x < 2.0)


func test_hit_pulse_fades_over_flash_time() -> void:
	var c := NetCursor.new()
	c.hit(0.6)
	c.hit(0.3)
	assert_near(c.flash, 0.6, 0.0001, "a weaker pulse does not cut a stronger one")
	var n: int = 0
	while c.flash_step(1.0 / 60.0) > 0.0 and n < 100:
		n += 1
	assert_true(n <= int(ceil(NetConfig.HIT_CONFIRM_FLASH_S * 60.0)) + 1, "faded in %d ticks" % n)
