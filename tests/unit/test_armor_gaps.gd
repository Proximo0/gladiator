extends TestCase
## ArmorGaps: joint bands on limbs, the neck and armpit band on the torso, the helmet's face opening.


func test_limb_ends_are_gaps_middle_is_plate() -> void:
	var t := Tuning.new()
	assert_true(ArmorGaps.in_gap("forearm_r", Vector3(0, 0.16, 0), t), "elbow end")
	assert_true(ArmorGaps.in_gap("forearm_r", Vector3(0, -0.15, 0), t), "wrist end")
	assert_false(ArmorGaps.in_gap("forearm_r", Vector3(0, 0.0, 0.02), t), "middle of the vambrace")
	assert_true(ArmorGaps.in_gap("thigh_l", Vector3(0, -0.2, 0), t), "knee")
	assert_false(ArmorGaps.in_gap("thigh_l", Vector3(0, 0.05, 0), t))


func test_torso_top_band_and_head_face() -> void:
	var t := Tuning.new()
	assert_true(ArmorGaps.in_gap("torso", Vector3(0.15, 0.22, 0), t), "armpit")
	assert_false(ArmorGaps.in_gap("torso", Vector3(0, 0.0, -0.11), t), "breastplate")
	assert_false(ArmorGaps.in_gap("pelvis", Vector3(0, 0, -0.1), t))
	assert_true(ArmorGaps.in_gap("head", Vector3(0, 0.0, -0.09), t), "face")
	assert_false(ArmorGaps.in_gap("head", Vector3(0, 0.08, -0.06), t), "brow and crown")
	assert_false(ArmorGaps.in_gap("head", Vector3(0, 0.0, 0.09), t), "back of the head")


func test_bypass_follows_tuning() -> void:
	var t := Tuning.new()
	assert_near(ArmorGaps.bypass("shin_r", Vector3(0, 0.2, 0), t), t.armor_gap_pass)
	assert_near(ArmorGaps.bypass("shin_r", Vector3(0, 0.0, 0), t), 0.0)
	t.armor_gap_len = 0.0
	assert_near(ArmorGaps.bypass("shin_r", Vector3(0, 0.2, 0), t), 0.0, 0.0001, "no band, no gaps")
