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
	assert_true(float(rake["pierce"]) < float(spear["pierce"]) * 0.1)
	assert_true(float(rake["bleed"]) > 0.0)  # a tine hit still draws blood
	assert_true(float(rake["total"]) < float(_r(_hit("torso", "club", "blunt", 8.0, 2.0))["total"]))  # weaker than a club
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


func test_bat_knocks_iron_helm_off() -> void:
	var r: Dictionary = _r(_hit("head", "bat", "blunt", 20.0, 1.0, ["helm_iron"]))
	assert_true(bool(r["dislodge"]))
	assert_eq(r["dislodged_id"], "helm_iron")


func test_no_armor_or_touch_no_dislodge() -> void:
	assert_false(bool(_r(_hit("head", "bat", "blunt", 20.0, 1.0))["dislodge"]))
	assert_false(bool(_r(_hit("head", "bat", "blunt", 2.0, 1.0, ["helm_iron"]))["dislodge"]))
	assert_false(bool(_r(_hit("head", "bat", "blunt", 6.0, 1.0, ["helm_iron"]))["dislodge"]))


func test_upward_blow_dislodges_more_easily() -> void:
	var level: Dictionary = _hit("head", "club", "blunt", 7.0, 1.6, ["helm_iron"])
	assert_false(bool(_r(level)["dislodge"]))
	var up: Dictionary = level.duplicate()
	up["rel_vel"] = Vector3(0, 7.0, -0.5)
	up["normal"] = Vector3(0, 1, 0)
	assert_true(bool(_r(up)["dislodge"]))


func test_wear_weakens_strap() -> void:
	# Round 7: this sat on a knife edge (8 m/s club = 51 J x club blunt vs strap 70), so any club blunt retune
	# above ~1.37 flipped the "fresh" half. 6.5 m/s keeps both halves clear for club blunt 0.7 to 2.0.
	var h: Dictionary = _hit("head", "club", "blunt", 6.5, 1.6, ["helm_iron"])
	h["armor_wear"] = {"helm_iron": 0.0}
	var fresh: bool = bool(_r(h)["dislodge"])
	h["armor_wear"] = {"helm_iron": 1.0}
	assert_false(fresh)
	assert_true(bool(_r(h)["dislodge"]))


func test_heavy_plate_cuirass_stays_on() -> void:
	assert_false(bool(_r(_hit("torso", "club", "blunt", 12.0, 1.6, ["cuirass_iron"]))["dislodge"]))


func test_hit_on_weapon_only_disarm_impulse() -> void:
	var h: Dictionary = _hit("forearm_r", "longsword", "edge", 20.0, 1.0, ["bracers_leather"])
	h["hit_on_weapon"] = true
	var r: Dictionary = _r(h)
	assert_near(float(r["total"]), 0.0)
	assert_near(float(r["bleed"]), 0.0)
	assert_false(bool(r["sever"]))
	assert_false(bool(r["dislodge"]))
	assert_eq(r["armor_wear"], {})
	assert_true(float(r["disarm_impulse"]) > 2.0)
	h["rel_vel"] = Vector3(0, 0, -2.0)
	assert_near(float(_r(h)["disarm_impulse"]), 0.0)


func test_forearm_hit_disarms_more_than_a_parry() -> void:
	var h: Dictionary = _hit("forearm_r", "bat", "blunt", 15.0, 1.0)
	var arm: float = float(_r(h)["disarm_impulse"])
	h["hit_on_weapon"] = true
	var wpn: float = float(_r(h)["disarm_impulse"])
	assert_true(wpn > 0.0 and arm > wpn)
	assert_near(float(_r(_hit("torso", "bat", "blunt", 15.0, 1.0))["disarm_impulse"]), 0.0)


func test_fist_on_weapon_disarms_less_than_club() -> void:
	var f: Dictionary = _hit("forearm_r", "fists", "blunt", 10.0, 1.0)
	f["hit_on_weapon"] = true
	var c: Dictionary = _hit("forearm_r", "club", "blunt", 10.0, 1.0)
	c["hit_on_weapon"] = true
	assert_true(float(_r(f)["disarm_impulse"]) < float(_r(c)["disarm_impulse"]))


func test_heavy_weapon_grip_holds_better() -> void:
	var t: Tuning = Tuning.new()
	assert_false(DamageModel.grip_holds(20.0, 1.0, 1.0, false, t, 1.0))
	assert_true(DamageModel.grip_holds(20.0, 1.0, 1.0, false, t, 3.5))


func test_grip_holds() -> void:
	var t := Tuning.new()
	assert_true(DamageModel.grip_holds(10.0, 1.0, 1.0, false, t))
	assert_false(DamageModel.grip_holds(25.0, 1.0, 1.0, false, t))
	assert_true(DamageModel.grip_holds(25.0, 1.0, 1.0, true, t))
	assert_false(DamageModel.grip_holds(10.0, 0.2, 0.2, false, t))
	assert_true(DamageModel.grip_holds(0.0, 0.0, 0.0, false, t))
	assert_true(DamageModel.grip_holds(10.0, 0.5, 0.5, true, t))


func test_armor_straps_defined() -> void:
	for id: String in CombatData.armor_ids():
		assert_true(float(CombatData.armor(id).get("strap", 0.0)) > 0.0, id)


func _fin(part: String, weapon: String, contact: String, speed: float, mass: float, bf: float, armor: Array = []) -> String:
	var h: Dictionary = _hit(part, weapon, contact, speed, mass, armor)
	h["blood_frac"] = bf
	return str(_r(h)["finisher"])


func test_finisher_run_through_point_weapons() -> void:
	assert_eq(_fin("torso", "spear", "point", 8.0, 2.0, 0.1), "run_through")
	assert_eq(_fin("pelvis", "gladius", "point", 8.0, 1.2, 0.05), "run_through")


func test_finisher_gut_with_edges() -> void:
	assert_eq(_fin("torso", "longsword", "edge", 20.0, 1.0, 0.0, ["mail"]), "gut")
	assert_eq(_fin("torso", "axe", "edge", 14.0, 1.8, 0.0, ["mail"]), "gut")
	var h: Dictionary = _hit("torso", "axe", "edge", 14.0, 1.8, ["mail"])
	h["blood_frac"] = 0.0
	assert_true(bool(_r(h)["gut"]))


func test_finisher_behead_low_blood_weaker_hit() -> void:
	assert_eq(_fin("head", "longsword", "edge", 20.0, 1.0, 0.1), "behead")
	# 12 m/s is too weak for a normal behead but enough when nearly bled out.
	assert_false(bool(_r(_hit("head", "axe", "edge", 11.0, 1.2))["behead"]))
	var h: Dictionary = _hit("head", "axe", "edge", 11.0, 1.2)
	h["blood_frac"] = 0.05
	var r: Dictionary = _r(h)
	assert_eq(r["finisher"], "behead")
	assert_true(bool(r["behead"]) and bool(r["sever"]))


func test_finisher_skull_crush_blunt_not_fists() -> void:
	assert_eq(_fin("head", "club", "blunt", 14.0, 1.6, 0.1), "skull_crush")
	assert_eq(_fin("head", "bat", "blunt", 20.0, 1.0, 0.1), "skull_crush")
	for contact: String in ["blunt", "flat", "edge", "point"]:
		assert_eq(_fin("head", "fists", contact, 30.0, 6.0, 0.0), "")
	assert_eq(_fin("torso", "bat", "blunt", 30.0, 2.0, 0.0), "")


func test_no_finisher_above_threshold() -> void:
	assert_eq(_fin("head", "bat", "blunt", 20.0, 1.0, 0.6), "")
	assert_eq(_fin("head", "bat", "blunt", 20.0, 1.0, 1.0), "")
	assert_eq(_fin("torso", "spear", "point", 8.0, 2.0, 0.7), "")
	assert_eq(str(_r(_hit("torso", "spear", "point", 8.0, 2.0))["finisher"]), "")


func test_finisher_threshold_scales_with_blood() -> void:
	assert_eq(_fin("torso", "spear", "point", 3.5, 2.0, 0.55), "")
	assert_eq(_fin("torso", "spear", "point", 5.0, 2.0, 0.55), "run_through")
	# The force needed shrinks from top_scale at the window edge to min_scale at blood_death.
	# Round 4 scales (0.15 at blood_death, 0.4 at the window edge): 3.5 m/s is short at the edge, plenty near death.
	assert_eq(_fin("torso", "spear", "point", 3.5, 2.0, 0.59), "")
	assert_eq(_fin("torso", "spear", "point", 3.5, 2.0, 0.0), "run_through")
	assert_eq(_fin("torso", "spear", "point", 4.0, 2.0, 0.0), "run_through")
	assert_eq(_fin("torso", "spear", "point", 5.0, 2.0, 0.0), "run_through")
	assert_eq(_fin("torso", "spear", "point", 2.0, 2.0, 0.0), "")


func test_finisher_blocked_by_plate_and_wrong_contact() -> void:
	# A thrust that runs an unarmored dying foe through stops on plate.
	assert_eq(_fin("torso", "spear", "point", 6.0, 2.0, 0.1), "run_through")
	assert_eq(_fin("torso", "spear", "point", 6.0, 2.0, 0.1, ["cuirass_iron"]), "")
	assert_eq(_fin("torso", "spear", "flat", 8.0, 2.0, 0.1), "")
	assert_eq(_fin("head", "longsword", "edge", 20.0, 1.0, 0.1, ["helm_iron"]), "")


func test_limp_attacker_blow_is_damped_and_cannot_behead() -> void:
	var h: Dictionary = _hit("head", "longsword", "edge", 20.0, 1.0)
	h["blood_frac"] = 0.1
	assert_eq(_r(h)["finisher"], "behead")
	h["attacker_limp"] = true
	h["attacker_conscious"] = false
	var r: Dictionary = _r(h)
	assert_eq(r["finisher"], "")
	assert_false(bool(r["behead"]))
	assert_near(float(r["energy"]), 0.5 * 20.0 * 20.0 * 0.15, 0.01)


func test_unconscious_attacker_cannot_finish_but_hits_full_force() -> void:
	var h: Dictionary = _hit("torso", "spear", "point", 8.0, 2.0)
	h["blood_frac"] = 0.1
	h["attacker_conscious"] = false
	assert_eq(_r(h)["finisher"], "")
	assert_near(float(_r(h)["energy"]), 0.5 * 2.0 * 64.0, 0.01)


func test_fists_pummel_finishes_downed_foe_head_only() -> void:
	var h: Dictionary = _hit("head", "fists", "blunt", 9.0, 8.0)
	h["blood_frac"] = 0.1
	assert_eq(_r(h)["finisher"], "")
	h["target_down"] = true
	assert_eq(_r(h)["finisher"], "pummel")
	var w: Dictionary = _hit("head", "club", "blunt", 14.0, 1.6)
	w["blood_frac"] = 0.1
	w["target_down"] = true
	assert_eq(_r(w)["finisher"], "skull_crush")  # weapons keep skull_crush even on a downed foe
	h["part"] = "torso"
	assert_eq(_r(h)["finisher"], "")
