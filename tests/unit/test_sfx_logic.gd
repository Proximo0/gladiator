extends TestCase


func _ev(over: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {
		"part": "torso", "weapon_id": "gladius", "contact": "edge", "energy": 80.0, "total": 12.0, "blunt": 1.0,
		"hit_on_weapon": false, "glanced": false, "armor_ids": [],
	}
	ev.merge(over, true)
	return ev


func _keys(plan: Array[Dictionary]) -> Array:
	var k: Array = []
	for l: Dictionary in plan:
		k.append(l["key"])
	return k


func test_every_variant_path_is_well_formed() -> void:
	for key: String in SfxLogic.VARIANTS:
		assert_true(SfxLogic.variant_count(key) >= 1, key)
		assert_true(SfxLogic.BASE_DB.has(key), "base db for " + key)
	assert_eq(SfxLogic.path_for("impact/clang_steel", 0), "res://assets/audio/impact/clang_steel_1.wav")
	assert_eq(SfxLogic.variant_count("nope/none"), 0)


func test_pick_variant_never_repeats_and_stays_in_range() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var last: int = -1
	for i: int in range(200):
		var v: int = SfxLogic.pick_variant("impact/clang_steel", rng, last)
		assert_true(v >= 0 and v < 5 and v != last)
		last = v
	assert_eq(SfxLogic.pick_variant("crowd/amb_low", rng, 0), 0)


func test_intensity_curve() -> void:
	assert_near(SfxLogic.intensity(0.0), 0.0)
	assert_true(SfxLogic.intensity(10.0) < SfxLogic.intensity(100.0))
	assert_true(SfxLogic.intensity(100000.0) <= 1.0)
	assert_near(SfxLogic.intensity_db(1.0), 0.0)
	assert_near(SfxLogic.intensity_db(0.0), SfxLogic.QUIET_DB)
	assert_true(SfxLogic.intensity_db(0.3) < SfxLogic.intensity_db(0.6))
	assert_true(SfxLogic.impact_pitch(0.9) < SfxLogic.impact_pitch(0.1))


func test_weapon_material() -> void:
	assert_eq(SfxLogic.weapon_material({"shape": "sword"}), "steel")
	assert_eq(SfxLogic.weapon_material({"shape": "axe"}), "steel")
	assert_eq(SfxLogic.weapon_material({"shape": "fist"}), "fist")
	assert_eq(SfxLogic.weapon_material({"shape": "bat"}), "wood")
	assert_eq(SfxLogic.weapon_material({"shape": "bat", "material": "aluminium"}), "aluminium")
	assert_eq(SfxLogic.weapon_material({"shape": "bat", "material": "aluminum"}), "aluminium")
	assert_eq(SfxLogic.weapon_material({"shape": "shield"}), "shield")
	assert_eq(SfxLogic.weapon_material({"shape": "rake"}), "wood")
	assert_eq(SfxLogic.weapon_material(CombatData.weapon("gladius")), "steel")


func test_armor_kind_picks_hardest() -> void:
	assert_eq(SfxLogic.armor_kind_of([]), "")
	assert_eq(SfxLogic.armor_kind_of(["leather", "plate"]), "plate")
	assert_eq(SfxLogic.armor_kind_of(["cloth", "mail"]), "mail")
	assert_eq(SfxLogic.armor_kind_for(["helm_iron"]), "plate")
	assert_eq(SfxLogic.armor_kind_for(["mail", "cuirass_leather"]), "mail")


func test_steel_on_steel_clangs_and_rings_when_hard() -> void:
	var soft_plan: Array[Dictionary] = SfxLogic.impact_plan(_ev({"hit_on_weapon": true, "energy": 8.0}), "steel", "steel", "")
	assert_eq(_keys(soft_plan), ["impact/clang_steel"])
	var hard: Array[Dictionary] = SfxLogic.impact_plan(_ev({"hit_on_weapon": true, "energy": 200.0}), "steel", "steel", "")
	assert_true(_keys(hard).has("impact/ring_steel"))


func test_steel_on_wood_thunks_aluminium_tinks() -> void:
	var a: Array[Dictionary] = SfxLogic.impact_plan(_ev({"hit_on_weapon": true}), "steel", "shield", "")
	assert_eq(_keys(a)[0], "impact/thunk_wood")
	var b: Array[Dictionary] = SfxLogic.impact_plan(_ev({"hit_on_weapon": true}), "aluminium", "steel", "")
	assert_true(_keys(b).has("impact/bat_tink"))
	var c: Array[Dictionary] = SfxLogic.impact_plan(_ev({"hit_on_weapon": true}), "wood", "wood", "")
	assert_true(_keys(c).has("impact/bat_crack"))


func test_flesh_hits_by_contact() -> void:
	assert_eq(_keys(SfxLogic.impact_plan(_ev({"contact": "edge"}), "steel", "", "")), ["impact/flesh_cut"])
	assert_eq(_keys(SfxLogic.impact_plan(_ev({"contact": "point"}), "steel", "", "")), ["impact/flesh_pierce"])
	assert_true(_keys(SfxLogic.impact_plan(_ev({"contact": "flat"}), "steel", "", "")).has("impact/body_thud"))
	assert_true(_keys(SfxLogic.impact_plan(_ev({"contact": "blunt"}), "wood", "", "")).has("impact/bat_crack"))
	assert_true(_keys(SfxLogic.impact_plan(_ev({"contact": "blunt"}), "aluminium", "", "")).has("impact/bat_tink"))
	assert_true(_keys(SfxLogic.impact_plan(_ev({"contact": "blunt"}), "fist", "", "")).has("impact/fist_punch"))


func test_armor_layers() -> void:
	var plate: Array = _keys(SfxLogic.impact_plan(_ev({"total": 0.5}), "steel", "", "plate"))
	assert_true(plate.has("impact/armor_clank") and not plate.has("impact/flesh_cut"), "plate eats the cut")
	assert_true(plate.has("impact/ring_steel"), "steel on plate rings")
	var through: Array = _keys(SfxLogic.impact_plan(_ev({"total": 9.0}), "steel", "", "plate"))
	assert_true(through.has("impact/armor_clank") and through.has("impact/flesh_cut"))
	assert_true(_keys(SfxLogic.impact_plan(_ev(), "steel", "", "mail")).has("impact/mail_jingle"))
	assert_true(_keys(SfxLogic.impact_plan(_ev(), "steel", "", "leather")).has("impact/leather_slap"))


func test_bone_crack_and_finisher_and_helm() -> void:
	var limb: Array = _keys(SfxLogic.impact_plan(_ev({"part": "head", "contact": "blunt", "blunt": 20.0}), "wood", "", ""))
	assert_true(limb.has("impact/bone_crack"))
	var torso_small: Array = _keys(SfxLogic.impact_plan(_ev({"part": "torso", "contact": "blunt", "blunt": 10.0}), "wood", "", ""))
	assert_false(torso_small.has("impact/bone_crack"))
	var crush: Array = _keys(SfxLogic.impact_plan(_ev({"finisher": "skull_crush", "contact": "blunt"}), "wood", "", ""))
	assert_true(crush.has("impact/bone_crack"))
	var helm: Array = _keys(SfxLogic.impact_plan(_ev({"dislodge": true, "dislodged_id": "helm_iron"}), "wood", "", "plate"))
	assert_true(helm.has("impact/helm_knock"))


func test_no_sound_below_min_energy_and_glance_is_quiet() -> void:
	assert_true(SfxLogic.impact_plan(_ev({"energy": 0.2}), "steel", "", "").is_empty())
	var glance: Array[Dictionary] = SfxLogic.impact_plan(_ev({"glanced": true}), "steel", "", "")
	assert_eq(_keys(glance), ["impact/leather_slap"])
	assert_true(float(glance[0]["gain_db"]) < -8.0)


func test_louder_for_more_energy() -> void:
	var lo: float = float(SfxLogic.impact_plan(_ev({"energy": 10.0}), "steel", "", "")[0]["gain_db"])
	var hi: float = float(SfxLogic.impact_plan(_ev({"energy": 150.0}), "steel", "", "")[0]["gain_db"])
	assert_true(hi > lo)


func test_voice_plan_scales_with_damage() -> void:
	assert_true(SfxLogic.voice_plan(_ev({"total": 1.0})).is_empty())
	assert_eq(_keys(SfxLogic.voice_plan(_ev({"total": 8.0}))), ["voice/pain_light"])
	assert_eq(_keys(SfxLogic.voice_plan(_ev({"total": 30.0}))), ["voice/pain_heavy"])
	assert_eq(_keys(SfxLogic.voice_plan(_ev({"total": 8.0, "sever": true}))), ["voice/pain_heavy"])
	assert_true(SfxLogic.voice_plan(_ev({"total": 30.0, "behead": true})).is_empty())
	assert_true(SfxLogic.voice_plan(_ev({"total": 30.0, "hit_on_weapon": true})).is_empty())


func test_whoosh_selection() -> void:
	assert_eq(SfxLogic.whoosh_key(2.0), "")
	assert_eq(SfxLogic.whoosh_key(5.0), "move/whoosh_slow")
	assert_eq(SfxLogic.whoosh_key(9.0), "move/whoosh_mid")
	assert_eq(SfxLogic.whoosh_key(15.0), "move/whoosh_fast")
	assert_true(SfxLogic.whoosh_gain_db(14.0) > SfxLogic.whoosh_gain_db(5.0))
	assert_true(SfxLogic.whoosh_pitch(10.0, 3.0) < SfxLogic.whoosh_pitch(10.0, 0.6))
	assert_true(SfxLogic.grunt_chance(14.0, 2.0) > SfxLogic.grunt_chance(4.0, 0.6))


func test_gore_keys_and_spurt_curves() -> void:
	assert_eq(SfxLogic.gore_key("sever"), "gore/sever")
	assert_eq(SfxLogic.gore_key("behead"), "gore/behead")
	assert_eq(SfxLogic.gore_key("gut"), "gore/gut")
	assert_eq(SfxLogic.gore_key("run_through"), "gore/run_through")
	assert_eq(SfxLogic.gore_key("bleed"), "")
	assert_true(SfxLogic.spurt_interval(0.2) > SfxLogic.spurt_interval(1.0))
	assert_true(SfxLogic.spurt_gain_db(3.0, 0.5) < SfxLogic.spurt_gain_db(0.5, 0.5))
	assert_true(SfxLogic.spurt_gain_db(1.0, 0.2) < SfxLogic.spurt_gain_db(1.0, 1.0))
	assert_true(SfxLogic.spatter_delay(1.5) > SfxLogic.spatter_delay(0.2))


func test_whoosh_gate_fires_once_per_swing() -> void:
	var g: SfxWhooshGate = SfxWhooshGate.new()
	var fired: int = 0
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	for i: int in range(120):  # accelerate to 12 m/s, hold, then decelerate
		var s: float = minf(12.0, i * 0.4) if i < 60 else maxf(0.0, 12.0 - (i - 60) * 0.5)
		t += dt
		var peak: float = g.update(s, dt, t)
		if peak > 0.0:
			fired += 1
			assert_true(peak >= SfxLogic.WHOOSH_MIN_SPEED)
	assert_eq(fired, 1)


func test_whoosh_gate_cooldown_and_rearm() -> void:
	var g: SfxWhooshGate = SfxWhooshGate.new()
	assert_true(g.update(5.0, 0.016, 0.0) > 0.0)
	assert_eq(g.update(5.0, 0.016, 0.016), 0.0, "not rearmed while still fast")
	g.update(0.5, 0.016, 0.03)
	assert_eq(g.update(6.0, 0.016, 0.1), 0.0, "cooldown")
	assert_true(g.update(6.0, 0.016, 0.5) > 0.0)


func test_step_tracker_distance_and_sides() -> void:
	var s: SfxStepTracker = SfxStepTracker.new()
	var steps: Array = []
	for i: int in range(600):  # 10 s at 2 m/s = 20 m
		var r: int = s.update(2.0, 1.0 / 60.0, true)
		if r != 0:
			steps.append(r)
	var stride: float = SfxStepTracker.stride_for(2.0)
	assert_true(absi(steps.size() - int(20.0 / stride)) <= 1, "step count %d" % steps.size())
	assert_true(steps[0] != steps[1], "sides alternate")
	var still: SfxStepTracker = SfxStepTracker.new()
	var n: int = 0
	for i: int in range(300):
		n += absi(still.update(0.1, 1.0 / 60.0, true))
	assert_eq(n, 0, "no steps when nearly still")
	var air: SfxStepTracker = SfxStepTracker.new()
	for i: int in range(300):
		n += absi(air.update(3.0, 1.0 / 60.0, false))
	assert_eq(n, 0, "no steps when not grounded")


func test_step_tracker_contacts() -> void:
	var s: SfxStepTracker = SfxStepTracker.new()
	assert_eq(s.update_contacts(true, false), -1)
	assert_eq(s.update_contacts(true, false), 0)
	assert_eq(s.update_contacts(false, true), 1)
	assert_eq(s.update_contacts(false, false), 0)
