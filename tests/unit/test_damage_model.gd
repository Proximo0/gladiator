extends TestCase


func _hit(part: String, weapon: String, contact: String, speed: float, mass: float, armor: Array = []) -> Dictionary:
	return {
		"part": part, "weapon_id": weapon, "contact": contact, "rel_vel": Vector3(0, 0, -speed),
		"normal": Vector3(0, 0, -1), "edge_alignment": 1.0, "effective_mass": mass, "armor_ids": armor, "armor_wear": {},
	}


func _r(h: Dictionary) -> Dictionary:
	return DamageModel.resolve(h, Tuning.new())


func test_touch_does_nothing() -> void:
	var r: Dictionary = _r(_hit("forearm_r", "longsword", "edge", 2.0, 1.0))
	assert_near(float(r["total"]), 0.0)
	assert_false(bool(r["sever"]))
	assert_near(float(r["stagger"]), 0.0)
	assert_near((r["knockback"] as Vector3).length(), 0.0)


func test_energy_is_kinetic() -> void:
	var r: Dictionary = _r(_hit("torso", "bat", "blunt", 10.0, 2.0))
	assert_near(float(r["energy"]), 100.0, 0.001)


func test_longsword_severs_unarmored_forearm() -> void:
	var r: Dictionary = _r(_hit("forearm_r", "longsword", "edge", 20.0, 1.0))
	assert_true(bool(r["sever"]))
	assert_false(bool(r["behead"]))
	assert_true(float(r["bleed"]) > 0.5)


func test_longsword_glances_iron_plate() -> void:
	var r: Dictionary = _r(_hit("forearm_r", "longsword", "edge", 20.0, 1.0, ["bracers_iron"]))
	assert_false(bool(r["sever"]))
	assert_true(bool(r["glanced"]))
	assert_true(float(r["cut"]) < 5.0)
	assert_true(float(r["blunt"]) > 0.5 and float(r["blunt"]) < 5.0)


func test_bat_to_head_staggers_and_drains_consciousness() -> void:
	var r: Dictionary = _r(_hit("head", "bat", "blunt", 20.0, 1.0))
	assert_true(float(r["stagger"]) > 0.9)
	assert_near(float(r["cut"]), 0.0)
	assert_false(bool(r["sever"]))
	var h := FighterHealth.new(Tuning.new())
	h.apply(r, "head")
	assert_true(h.consciousness < 0.3)
	assert_false(h.dead)


func test_spear_passes_mail_and_guts() -> void:
	var r: Dictionary = _r(_hit("torso", "spear", "point", 8.0, 2.0, ["mail"]))
	assert_true(bool(r["gut"]))
	assert_true(float(r["pierce"]) > 20.0)
	var plate: Dictionary = _r(_hit("torso", "spear", "point", 8.0, 2.0, ["cuirass_iron"]))
	assert_false(bool(plate["gut"]))
	assert_true(bool(plate["glanced"]) or float(plate["pierce"]) < 12.0)


func test_mail_stops_sword_cut() -> void:
	var bare: Dictionary = _r(_hit("torso", "longsword", "edge", 20.0, 1.0))
	var mail: Dictionary = _r(_hit("torso", "longsword", "edge", 20.0, 1.0, ["mail"]))
	assert_true(bool(bare["gut"]))
	assert_false(bool(mail["gut"]))
	assert_true(float(mail["cut"]) < float(bare["cut"]) * 0.4)


func test_behead_rules() -> void:
	var bare: Dictionary = _r(_hit("head", "longsword", "edge", 20.0, 1.0))
	assert_true(bool(bare["behead"]) and bool(bare["sever"]))
	var iron: Dictionary = _r(_hit("head", "longsword", "edge", 20.0, 1.0, ["helm_iron"]))
	assert_false(bool(iron["behead"]))
	var weak: Dictionary = _r(_hit("head", "longsword", "edge", 20.0, 1.0, ["helm_leather"]))
	var weak_hurt_h: Dictionary = _hit("head", "longsword", "edge", 20.0, 1.0, ["helm_leather"])
	weak_hurt_h["part_hp_frac"] = 0.2
	assert_false(bool(weak["behead"]))
	assert_true(bool(_r(weak_hurt_h)["behead"]))
	var soft: Dictionary = _r(_hit("head", "longsword", "edge", 8.0, 1.0))
	assert_false(bool(soft["behead"]))
	var bat: Dictionary = _r(_hit("head", "bat", "blunt", 30.0, 2.0))
	assert_false(bool(bat["behead"]))


func test_fists_blunt_only() -> void:
	for contact: String in ["edge", "point", "flat", "blunt"]:
		var r: Dictionary = _r(_hit("head", "fists", contact, 8.0, 3.0))
		assert_near(float(r["cut"]), 0.0)
		assert_near(float(r["pierce"]), 0.0)
		assert_true(float(r["blunt"]) > 0.0)
		assert_false(bool(r["sever"]))
		assert_near(float(r["bleed"]), 0.0)


func test_rake_tines_weak_pierce() -> void:
	var rake: Dictionary = _r(_hit("torso", "rake", "point", 8.0, 2.0))
	var spear: Dictionary = _r(_hit("torso", "spear", "point", 8.0, 2.0))
	assert_true(float(rake["pierce"]) > 0.0)
	assert_true(float(rake["pierce"]) < float(spear["pierce"]) * 0.4)
	assert_false(bool(rake["gut"]))
	assert_near(float(_r(_hit("forearm_r", "rake", "edge", 15.0, 1.3))["cut"]), 0.0)


func test_damage_grows_with_speed_and_mass() -> void:
	var a: float = float(_r(_hit("torso", "club", "blunt", 6.0, 1.5))["total"])
	var b: float = float(_r(_hit("torso", "club", "blunt", 12.0, 1.5))["total"])
	var c: float = float(_r(_hit("torso", "club", "blunt", 12.0, 3.0))["total"])
	assert_true(b > a * 3.9 and c > b * 1.9)


func test_edge_alignment_scales_cut() -> void:
	var h: Dictionary = _hit("torso", "longsword", "edge", 15.0, 1.0)
	var full: float = float(_r(h)["cut"])
	h["edge_alignment"] = 0.25
	assert_near(float(_r(h)["cut"]), full * 0.25, 0.001)


func test_flat_hit_with_sword_is_blunt() -> void:
	var r: Dictionary = _r(_hit("forearm_r", "longsword", "flat", 20.0, 1.0))
	assert_near(float(r["cut"]), 0.0)
	assert_false(bool(r["sever"]))
	assert_true(float(r["blunt"]) > 0.0)


func test_armor_wear_accumulates_and_weakens() -> void:
	var h: Dictionary = _hit("torso", "longsword", "edge", 20.0, 1.0, ["mail"])
	var r1: Dictionary = _r(h)
	var wear1: float = float((r1["armor_wear"] as Dictionary)["mail"])
	assert_true(wear1 > 0.0)
	h["armor_wear"] = {"mail": 1.0}
	var r2: Dictionary = _r(h)
	assert_true(float(r2["cut"]) > float(r1["cut"]))
	h["armor_wear"] = {"mail": wear1}
	var r3: Dictionary = _r(h)
	assert_true(float((r3["armor_wear"] as Dictionary)["mail"]) > wear1)
	assert_true(float((r3["armor_wear"] as Dictionary)["mail"]) <= 1.0)


func test_stacked_armor_stronger() -> void:
	var one: float = float(_r(_hit("torso", "longsword", "edge", 20.0, 1.0, ["cuirass_leather"]))["cut"])
	var two: float = float(_r(_hit("torso", "longsword", "edge", 20.0, 1.0, ["cuirass_leather", "mail"]))["cut"])
	assert_true(two < one)


func test_knockback_along_normal() -> void:
	var r: Dictionary = _r(_hit("torso", "bat", "blunt", 15.0, 1.0))
	var kb: Vector3 = r["knockback"]
	assert_true(kb.z < -1.0)
	assert_near(kb.x, 0.0)


func test_deterministic() -> void:
	var h: Dictionary = _hit("shin_l", "axe", "edge", 14.0, 1.8, ["greaves_leather"])
	assert_eq(_r(h), _r(h))


func test_tuning_override_and_missing_field_fallback() -> void:
	var t := Tuning.new()
	t.set_value("damage_min_speed", 10.0)
	var h: Dictionary = _hit("torso", "club", "blunt", 8.0, 2.0)
	assert_near(float(DamageModel.resolve(h, t)["total"]), 0.0)
	assert_near(DamageModel.tuning_value(t, "no_such_field", 7.5), 7.5)
	assert_near(DamageModel.tuning_value(t, "damage_min_speed", 1.0), 10.0)


func test_unknown_weapon_is_harmless() -> void:
	assert_near(float(_r(_hit("torso", "nothing", "edge", 20.0, 1.0))["total"]), 0.0)
