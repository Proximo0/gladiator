extends TestCase

const FIN: Dictionary = {"finisher": "behead", "energy": 5.0, "total": 3.0}


func _tun() -> Tuning:
	return Tuning.new()


func test_impact_scales_with_energy_and_damage() -> void:
	var t: Tuning = _tun()
	var tap: float = FeelLogic.impact({"energy": 3.0, "total": 1.0}, t)
	var mid: float = FeelLogic.impact({"energy": 80.0, "total": 15.0}, t)
	var big: float = FeelLogic.impact({"energy": 400.0, "total": 80.0}, t)
	assert_true(tap < 0.1, "tap is subtle")
	assert_true(tap < mid and mid < big)
	assert_true(big <= 1.0 and big > 0.9)
	assert_eq(FeelLogic.impact({}, t), 0.0)


func test_finisher_reads_hard_but_a_weapon_clash_does_not() -> void:
	var t: Tuning = _tun()
	assert_true(FeelLogic.impact(FIN, t) >= FeelLogic.FINISHER_IMPACT)
	assert_true(FeelLogic.is_finisher(FIN))
	var clash: Dictionary = FIN.duplicate()
	clash["hit_on_weapon"] = true
	assert_false(FeelLogic.is_finisher(clash))
	assert_true(FeelLogic.impact(clash, t) < 0.2)


func test_camera_strength_has_a_floor() -> void:
	var t: Tuning = _tun()
	assert_eq(FeelLogic.camera_strength(t.feel_shake_min * 0.9, t), 0.0)
	assert_near(FeelLogic.camera_strength(1.0, t), 1.0)
	assert_true(FeelLogic.camera_strength(0.5, t) > 0.0)


func test_blow_dir_prefers_relative_velocity() -> void:
	var d: Vector3 = FeelLogic.blow_dir({"rel_vel": Vector3(0, 0, -4), "normal": Vector3(1, 0, 0)})
	assert_near(d.z, -1.0)
	var n: Vector3 = FeelLogic.blow_dir({"normal": Vector3(1, 0, 0)})
	assert_near(n.x, -1.0)
	assert_eq(FeelLogic.blow_dir({}), Vector3.ZERO)


func test_flash_off_for_taps() -> void:
	var t: Tuning = _tun()
	assert_eq(FeelLogic.flash_strength(0.02, t), 0.0)
	assert_true(FeelLogic.flash_strength(1.0, t) > FeelLogic.flash_strength(0.2, t))
	t.feel_flash_s = 0.0
	assert_eq(FeelLogic.flash_strength(1.0, t), 0.0)


func test_sparks_for_metal_pairs_only() -> void:
	var t: Tuning = _tun()
	var clash: Dictionary = {"hit_on_weapon": true}
	assert_true(FeelLogic.strikes_sparks(clash, "steel", "steel", ""))
	assert_true(FeelLogic.strikes_sparks(clash, "steel", "aluminium", ""))
	assert_true(FeelLogic.strikes_sparks(clash, "aluminium", "steel", ""))
	assert_false(FeelLogic.strikes_sparks(clash, "steel", "wood", ""))
	assert_false(FeelLogic.strikes_sparks(clash, "wood", "wood", ""))
	assert_true(FeelLogic.strikes_sparks({}, "steel", "", "plate"))
	assert_true(FeelLogic.strikes_sparks({}, "steel", "", "mail"))
	assert_false(FeelLogic.strikes_sparks({}, "steel", "", "leather"))
	assert_false(FeelLogic.strikes_sparks({}, "steel", "", ""))
	assert_false(FeelLogic.strikes_sparks({}, "wood", "", "plate"))
	assert_eq(FeelLogic.spark_count(clash, "steel", "steel", "", 0.05, t), 0)
	assert_eq(FeelLogic.spark_count(clash, "steel", "wood", "", 1.0, t), 0)
	var lo: int = FeelLogic.spark_count(clash, "steel", "steel", "", 0.2, t)
	var hi: int = FeelLogic.spark_count(clash, "steel", "steel", "", 1.0, t)
	assert_true(lo >= 1 and hi > lo)
	assert_eq(hi, roundi(t.feel_spark_max))


func test_rumble_scales_and_switches_off() -> void:
	var t: Tuning = _tun()
	assert_eq(float(FeelLogic.rumble(0.1, true, t, 1.0)["dur"]), 0.0, "tap")
	assert_eq(float(FeelLogic.rumble(1.0, true, t, 0.0)["dur"]), 0.0, "option off")
	var taken: Dictionary = FeelLogic.rumble(0.9, true, t, 1.0)
	var dealt: Dictionary = FeelLogic.rumble(0.9, false, t, 1.0)
	assert_true(float(taken["strong"]) > float(dealt["strong"]))
	assert_true(float(taken["dur"]) > 0.0 and float(taken["dur"]) <= t.feel_rumble_s)
	var v: Dictionary = FeelLogic.vibrate(1.0, true, t, 1.0)
	assert_true(int(v["ms"]) > 0 and int(v["ms"]) <= FeelLogic.VIBRATE_MAX_MS)
	assert_eq(int(FeelLogic.vibrate(1.0, true, t, 0.0)["ms"]), 0)


func test_pad_assignment() -> void:
	assert_eq(FeelLogic.pad_for_side(0, 0, [] as Array[int]), -1)
	assert_eq(FeelLogic.pad_for_side(0, 0, [3] as Array[int]), 3)
	assert_eq(FeelLogic.pad_for_side(1, 0, [3] as Array[int]), -1)
	assert_eq(FeelLogic.pad_for_side(1, 0, [3, 5] as Array[int]), 5)
	assert_eq(FeelLogic.pad_for_side(-1, 0, [3, 5] as Array[int]), -1)


func test_options_switch_off_motion_and_rumble() -> void:
	var t: Tuning = _tun()
	assert_near(FeelOptions.motion_scale(t), 1.0)
	t.feel_shake_scale = 0.0
	assert_eq(FeelOptions.motion_scale(t), 0.0)
	t.feel_shake_scale = 1.0
	FeelOptions.reduced_motion = true
	assert_eq(FeelOptions.motion_scale(t), 0.0)
	FeelOptions.reduced_motion = false
	FeelOptions.rumble_enabled = false
	assert_eq(FeelOptions.rumble_scale(t), 0.0)
	FeelOptions.rumble_enabled = true
	assert_near(FeelOptions.rumble_scale(t), 1.0)
