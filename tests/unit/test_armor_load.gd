extends TestCase
## ArmorLoad: worn mass, per-arm mass, load and the speed, stamina, get-up and hand force scales.

const IRON: Array = ["helm_iron", "cuirass_iron", "bracers_iron", "greaves_iron"]


func test_mass_sums_worn_pieces() -> void:
	assert_near(ArmorLoad.mass([]), 0.0, 0.0001)
	assert_near(ArmorLoad.mass(IRON), 19.3, 0.001)
	assert_near(ArmorLoad.mass(["no_such_piece"]), 0.0, 0.0001, "unknown ids weigh nothing")


func test_arm_mass_shares_by_cover() -> void:
	# Bracers cover four arm parts: half on each arm.
	assert_near(ArmorLoad.arm_mass(["bracers_iron"], "r"), 1.75, 0.001)
	assert_near(ArmorLoad.arm_mass(["bracers_iron"], "l"), 1.75, 0.001)
	# The galerus set covers the left arm and the right forearm: two thirds left, one third right.
	assert_near(ArmorLoad.arm_mass(["retiarius_arm"], "l"), 2.0, 0.001)
	assert_near(ArmorLoad.arm_mass(["retiarius_arm"], "r"), 1.0, 0.001)
	assert_near(ArmorLoad.arm_mass(["cuirass_iron", "helm_iron"], "r"), 0.0, 0.0001, "no arm pieces")


func test_load_is_mass_over_ref_and_capped() -> void:
	var t := Tuning.new()
	assert_near(ArmorLoad.load_of(0.0, t), 0.0, 0.0001)
	assert_near(ArmorLoad.load_of(t.armor_load_ref, t), 1.0, 0.0001)
	assert_near(ArmorLoad.load_of(1000.0, t), t.armor_load_max, 0.0001)


func test_naked_costs_nothing() -> void:
	var t := Tuning.new()
	assert_near(ArmorLoad.speed_scale(0.0, t), 1.0, 0.0001)
	assert_near(ArmorLoad.accel_scale(0.0, t), 1.0, 0.0001)
	assert_near(ArmorLoad.step_cost(0.0, t), 0.0, 0.0001)
	assert_near(ArmorLoad.swing_cost(0.0, t), 0.0, 0.0001)
	assert_near(ArmorLoad.getup_scale(0.0, t), 1.0, 0.0001)
	assert_near(ArmorLoad.arm_force_scale(0.0, t), 1.0, 0.0001)


func test_full_load_follows_tuning_rows() -> void:
	var t := Tuning.new()
	assert_near(ArmorLoad.speed_scale(1.0, t), 1.0 - t.armor_speed_loss, 0.0001)
	assert_near(ArmorLoad.accel_scale(1.0, t), 1.0 - t.armor_accel_loss, 0.0001)
	assert_near(ArmorLoad.step_cost(1.0, t), t.armor_step_stamina, 0.0001)
	assert_near(ArmorLoad.swing_cost(1.0, t), t.armor_swing_stamina, 0.0001)
	assert_near(ArmorLoad.getup_scale(1.0, t), 1.0 + t.armor_getup_slow, 0.0001)
	assert_near(ArmorLoad.arm_force_scale(t.armor_arm_ref, t), 1.0 - t.armor_arm_force_loss, 0.0001)


func test_heavier_is_monotonic_and_bounded() -> void:
	var t := Tuning.new()
	var prev_speed: float = 2.0
	var prev_getup: float = 0.0
	for kg: int in range(0, 60, 5):
		var ld: float = ArmorLoad.load_of(float(kg), t)
		var sp: float = ArmorLoad.speed_scale(ld, t)
		var gu: float = ArmorLoad.getup_scale(ld, t)
		assert_true(sp <= prev_speed and sp >= 0.2, "speed falls with mass, never below 0.2")
		assert_true(gu >= prev_getup, "get-up grows with mass")
		prev_speed = sp
		prev_getup = gu
	t.armor_speed_loss = 5.0
	assert_near(ArmorLoad.speed_scale(1.0, t), 0.2, 0.0001, "floor holds against a wild tuning value")


func test_iron_set_slower_than_leather() -> void:
	var t := Tuning.new()
	var leather: float = ArmorLoad.load_of(ArmorLoad.mass(["helm_leather", "cuirass_leather", "bracers_leather", "greaves_leather"]), t)
	var iron: float = ArmorLoad.load_of(ArmorLoad.mass(IRON), t)
	assert_true(ArmorLoad.speed_scale(iron, t) < ArmorLoad.speed_scale(leather, t))
	assert_true(ArmorLoad.step_cost(iron, t) > ArmorLoad.step_cost(leather, t))
