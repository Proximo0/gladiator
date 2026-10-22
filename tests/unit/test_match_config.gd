extends TestCase


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_loadout_is_valid() -> void:
	var r: RandomNumberGenerator = _rng(5)
	for i: int in 60:
		var l: Dictionary = MatchConfig.random_loadout(r)
		var w: Dictionary = CombatData.weapon(str(l["weapon"]))
		assert_false(w.is_empty(), "weapon exists")
		assert_true(str(w["shape"]) != "shield", "a shield is never the main weapon")
		var off: String = str(l["offhand"])
		if off != "":
			assert_eq(str(CombatData.weapon(off)["shape"]), "shield")
			assert_false(bool(w.get("two_handed", false)), "no shield with a two-handed weapon")
		for slot: String in l["armor"]:
			assert_false(CombatData.armor(str(l["armor"][slot])).is_empty())
			assert_eq(str(CombatData.armor(str(l["armor"][slot]))["part"]), slot)


func test_loadouts_cover_everything() -> void:
	var r: RandomNumberGenerator = _rng(9)
	var weapons: Dictionary = {}
	var armors: Dictionary = {}
	var shields: int = 0
	var bare: int = 0
	for i: int in 600:
		var l: Dictionary = MatchConfig.random_loadout(r)
		weapons[l["weapon"]] = true
		if str(l["offhand"]) != "":
			shields += 1
		if (l["armor"] as Dictionary).is_empty():
			bare += 1
		for slot: String in l["armor"]:
			armors[l["armor"][slot]] = true
	for wid: String in CombatData.weapon_ids():
		if str(CombatData.weapon(wid)["shape"]) != "shield":
			assert_true(weapons.has(wid), "weapon %s appears" % wid)
	for aid: String in CombatData.armor_ids():
		assert_true(armors.has(aid), "armor %s appears" % aid)
	assert_true(shields > 50, "shields appear")
	assert_true(bare > 10 and bare < 300, "some fighters are unarmored, not all")


func test_same_seed_same_loadout() -> void:
	assert_eq(MatchConfig.random_loadout(_rng(77)), MatchConfig.random_loadout(_rng(77)))
	assert_eq(MatchConfig.normalize({"seed": 4}, 1)["loadouts"], MatchConfig.normalize({"seed": 4}, 9)["loadouts"])


func test_normalize_defaults() -> void:
	var c: Dictionary = MatchConfig.normalize({}, 12)
	assert_eq(c["mode"], "bot_vs_bot")
	assert_eq(c["seed"], 12)
	assert_eq((c["loadouts"] as Array).size(), 2)
	assert_eq((c["personalities"] as Array).size(), 2)
	assert_true(bool(c["presentation"]))
	assert_true(bool(c["loop"]), "presented bot vs bot loops")
	assert_near(float(c["time_limit_s"]), 180.0)
	var h: Dictionary = MatchConfig.normalize({"presentation": false}, 1)
	assert_false(bool(h["loop"]))
	assert_eq(MatchConfig.normalize({"mode": "nonsense"}, 1)["mode"], "bot_vs_bot")


func test_normalize_overrides_keep_the_other_side() -> void:
	var base: Dictionary = MatchConfig.normalize({"seed": 3}, 1)
	var given: Dictionary = {"weapon": "spear", "offhand": "", "armor": {}}
	var c: Dictionary = MatchConfig.normalize({"seed": 3, "loadouts": [given]}, 1)
	assert_eq((c["loadouts"] as Array)[0], given)
	assert_eq((c["loadouts"] as Array)[1], (base["loadouts"] as Array)[1])
	assert_eq(c["personalities"], base["personalities"])


func test_personality_is_a_preset() -> void:
	var r: RandomNumberGenerator = _rng(2)
	var seen: Dictionary = {}
	for i: int in 80:
		var p: Dictionary = MatchConfig.random_personality(r)
		assert_true(FighterBrain.PRESETS.has(p["preset"]))
		assert_true(float(p["aggression"]) >= 0.0 and float(p["aggression"]) <= 1.0)
		seen[p["preset"]] = true
	assert_eq(seen.size(), FighterBrain.PRESETS.size())


func test_names_distinct_and_stable() -> void:
	for s: int in 40:
		var n: Array = MatchConfig.names_for(s)
		assert_true(n[0] != n[1])
		assert_eq(n, MatchConfig.names_for(s))


func test_describe() -> void:
	assert_eq(MatchConfig.describe({"weapon": "gladius", "offhand": "shield_round", "armor": {"head": "helm_iron"}}),
		"gladius+shield_round [helm_iron]")


func test_practice_is_a_known_mode() -> void:
	assert_eq(str(MatchConfig.normalize({"mode": "practice"}, 1)["mode"]), "practice")
