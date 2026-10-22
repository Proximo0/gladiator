extends TestCase

const WEAPONS: Array[String] = ["fists", "rake", "bat", "club", "gladius", "longsword", "axe", "spear", "shield_round"]
const WEAPON_KEYS: Array[String] = ["id", "name", "tier", "mass", "length", "grip_offset", "balance_point", "shape",
	"edge_len", "point", "blunt_factor", "cut_factor", "pierce_factor", "two_handed", "half_sword", "color"]
const ARMOR_KEYS: Array[String] = ["id", "name", "part", "covers", "mass", "kind", "cut_resist", "pierce_resist",
	"blunt_resist", "durability", "strap"]
const PARTS: Array[String] = ["pelvis", "torso", "head", "upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r"]


func test_all_v1_weapons_present_with_keys() -> void:
	var ids: PackedStringArray = CombatData.weapon_ids()
	for w: String in WEAPONS:
		assert_true(ids.has(w), "missing weapon " + w)
		var d: Dictionary = CombatData.weapon(w)
		for k: String in WEAPON_KEYS:
			assert_true(d.has(k), "%s lacks %s" % [w, k])
		assert_eq(d.get("id"), w)


func test_armor_defs_valid() -> void:
	var ids: PackedStringArray = CombatData.armor_ids()
	assert_true(ids.size() >= 9)
	var kinds: Dictionary = {}
	for id: String in ids:
		var d: Dictionary = CombatData.armor(id)
		for k: String in ARMOR_KEYS:
			assert_true(d.has(k), "%s lacks %s" % [id, k])
		kinds[d.get("kind")] = true
		var covers: Array = d.get("covers", [])
		assert_true(covers.size() > 0, id)
		for c: Variant in covers:
			assert_true(PARTS.has(str(c)), "%s covers unknown %s" % [id, str(c)])
		for r: String in ["cut_resist", "pierce_resist", "blunt_resist"]:
			var v: float = float(d.get(r, -1.0))
			assert_true(v >= 0.0 and v <= 1.0, id + r)
	assert_true(kinds.has("leather") and kinds.has("mail") and kinds.has("plate"))


func test_realistic_masses_and_lengths() -> void:
	var ls: Dictionary = CombatData.weapon("longsword")
	assert_near(float(ls["mass"]), 1.4, 0.2)
	assert_near(float(ls["length"]), 1.2, 0.1)
	var sp: Dictionary = CombatData.weapon("spear")
	assert_near(float(sp["mass"]), 2.0, 0.3)
	assert_near(float(sp["length"]), 2.2, 0.2)
	assert_near(float(CombatData.weapon("bat")["mass"]), 1.0, 0.2)
	assert_near(float(CombatData.weapon("bat")["length"]), 0.85, 0.1)
	assert_near(float(CombatData.weapon("rake")["mass"]), 1.7, 0.2)
	assert_near(float(CombatData.weapon("rake")["length"]), 1.45, 0.1)


func test_fists_and_blunt_weapons_cannot_cut() -> void:
	for w: String in ["fists", "bat", "club", "shield_round"]:
		var d: Dictionary = CombatData.weapon(w)
		assert_near(float(d["cut_factor"]), 0.0, 0.0001, w)
		assert_near(float(d["edge_len"]), 0.0, 0.0001, w)
	var rake: Dictionary = CombatData.weapon("rake")
	assert_true(bool(rake["point"]))
	assert_true(float(rake["pierce_factor"]) < float(CombatData.weapon("spear")["pierce_factor"]) * 0.2)


func test_unknown_ids_empty_and_copies() -> void:
	assert_true(CombatData.weapon("nope").is_empty())
	assert_true(CombatData.armor("nope").is_empty())
	var d: Dictionary = CombatData.weapon("bat")
	d["mass"] = 99.0
	assert_near(float(CombatData.weapon("bat")["mass"]), 1.0, 0.2)


func test_part_table_covers_all_body_parts() -> void:
	for p: String in PARTS:
		var info: Dictionary = CombatData.part_info(p)
		assert_true(float(info.get("hp", 0.0)) > 0.0, p)
	assert_near(float(CombatData.part_info("torso")["sever"]), 0.0)
	assert_true(float(CombatData.part_info("forearm_r")["sever"]) > 0.0)
