extends TestCase


func test_main_weapons_exclude_shields() -> void:
	var w: Array = LoadoutRules.main_weapons()
	assert_true(w.has("fists") and w.has("gladius") and w.has("spear"))
	assert_false(w.has("shield_round"))
	assert_eq(str(w[0]), "fists")


func test_offhands_start_empty_then_shields() -> void:
	var o: Array = LoadoutRules.offhands()
	assert_eq(str(o[0]), "")
	assert_true(o.has("shield_round"))
	assert_false(o.has("gladius"))


func test_two_handed_blocks_offhand() -> void:
	assert_true(LoadoutRules.offhand_blocked("spear"))
	assert_true(LoadoutRules.offhand_blocked("rake"))
	assert_false(LoadoutRules.offhand_blocked("gladius"))
	var l: Dictionary = LoadoutRules.sanitize({"weapon": "spear", "offhand": "shield_round"})
	assert_eq(str(l["offhand"]), "")


func test_armor_options_fit_slot_light_to_heavy() -> void:
	for slot: String in LoadoutRules.slot_names():
		var opts: Array = LoadoutRules.armor_options(slot)
		assert_eq(str(opts[0]), "", "none first")
		assert_true(opts.size() >= 2, "slot %s has armor" % slot)
		var last: float = -1.0
		for i: int in range(1, opts.size()):
			var d: Dictionary = CombatData.armor(str(opts[i]))
			assert_eq(str(d["part"]), slot)
			assert_true(float(d["mass"]) >= last)
			last = float(d["mass"])


func test_sanitize_repairs_bad_data() -> void:
	var l: Dictionary = LoadoutRules.sanitize({"weapon": "nonsense", "offhand": "gladius",
			"armor": {"head": "cuirass_iron", "torso": "mail", "legs": "x"}})
	assert_eq(str(l["weapon"]), "fists")
	assert_eq(str(l["offhand"]), "")
	assert_false((l["armor"] as Dictionary).has("head"))
	assert_eq(str(l["armor"]["torso"]), "mail")
	assert_eq((l["armor"] as Dictionary).size(), 1)
	assert_eq(str(LoadoutRules.sanitize({"weapon": "shield_round"})["weapon"]), "fists")


func test_default_loadout_is_valid_and_stable() -> void:
	var l: Dictionary = LoadoutRules.default_loadout()
	assert_eq(LoadoutRules.sanitize(l), l)
	assert_eq(str(l["weapon"]), "gladius")
	# A new player owns nothing: the default must be a real starter, not fists and not a locked weapon.
	assert_eq(str(LoadoutRules.sanitize(l, [])["weapon"]), "gladius")


func test_stats() -> void:
	var s: Dictionary = LoadoutRules.weapon_stats("axe")
	assert_near(float(s["mass"]), 1.8)
	assert_true(float(s["cut"]) > float(s["pierce"]))
	assert_true(float(s["cut"]) <= 1.0)
	assert_true(bool(LoadoutRules.weapon_stats("spear")["two_handed"]))
	assert_eq(str(LoadoutRules.weapon_stats("")["name"]), "None")
	var a: Dictionary = LoadoutRules.armor_stats("helm_iron")
	assert_true(float(a["cut"]) > 0.9)
	assert_eq(LoadoutRules.display_name(""), "None")
	assert_eq(LoadoutRules.display_name("mail"), "Mail hauberk")


func test_total_mass() -> void:
	var l: Dictionary = {"weapon": "gladius", "offhand": "shield_round", "armor": {"head": "helm_iron"}}
	assert_near(LoadoutRules.total_mass(l), 0.8 + 3.5 + 1.8)
