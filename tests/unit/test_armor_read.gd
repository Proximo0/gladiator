extends TestCase
## ArmorRead (the CPU's read of the foe's armor) and the FighterBrain choices built on it: gap thrusts at plate,
## helmet targeting by weapon kind, a lighter fighter kiting a heavy one.

const DT: float = 1.0 / 60.0
const IRON: Dictionary = {"head": "helm_iron", "torso": "cuirass_iron", "pelvis": "cuirass_iron",
	"upper_arm_l": "bracers_iron", "upper_arm_r": "bracers_iron", "forearm_l": "bracers_iron", "forearm_r": "bracers_iron",
	"thigh_l": "greaves_iron", "thigh_r": "greaves_iron", "shin_l": "greaves_iron", "shin_r": "greaves_iron"}
const LEATHER: Dictionary = {"head": "helm_leather", "torso": "cuirass_leather", "pelvis": "cuirass_leather"}


func _frame(side: int, pos: Vector3, yaw: float, weapon: String, armor: Dictionary) -> Dictionary:
	var parts: Dictionary = {}
	var offs: Dictionary = {
		"pelvis": 0.95, "torso": 1.3, "head": 1.65, "upper_arm_l": 1.4, "upper_arm_r": 1.4, "forearm_l": 1.2,
		"forearm_r": 1.2, "thigh_l": 0.7, "thigh_r": 0.7, "shin_l": 0.3, "shin_r": 0.3,
	}
	for n: String in offs:
		parts[n] = {"pos": Vector3(pos.x, float(offs[n]), pos.z), "hp": 50.0, "severed": false}
	return {
		"tick": 0, "side": side, "pelvis_pos": Vector3(pos.x, 0.95, pos.z), "pelvis_vel": Vector3.ZERO,
		"facing_yaw": yaw, "balance": 1.0, "stamina": 1.0, "consciousness": 1.0, "hand_target": Vector3.ZERO,
		"hand_pos": Vector3.ZERO, "tip_pos": Vector3(pos.x, 1.2, pos.z - 0.5), "tip_speed": 0.0, "weapon_id": weapon,
		"grip": "normal", "parts": parts, "contacts": [], "state": "standing", "armor": armor.duplicate(),
	}


func _brain(difficulty: String = "hard", seed: int = 7) -> FighterBrain:
	return FighterBrain.new(seed, {"preset": "duelist", "reaction_ms": 0.0, "aim_noise": 0.0, "spawn_hold": 0,
		"difficulty": difficulty})


## Plans made against a foe 1.5 m ahead: {"gap": n, "head": n, "n": n}.
func _plans(weapon: String, armor: Dictionary, difficulty: String = "hard") -> Dictionary:
	var b := _brain(difficulty)
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0, weapon, {})
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -1.5), PI, "gladius", armor)
	b.think(me, foe, DT)
	var out: Dictionary = {"gap": 0, "head": 0, "n": 300, "gaps": {}}
	for i in 300:
		var p: Dictionary = b._make_plan(me, foe, false)
		if str(p["gap"]) != "":
			out["gap"] = int(out["gap"]) + 1
			out["gaps"][p["gap"]] = int(out["gaps"].get(p["gap"], 0)) + 1
			assert_eq(str(p["kind"]), "thrust", "a gap is thrust at")
		if str(p["part"]) == "head" and str(p["gap"]) == "":
			out["head"] = int(out["head"]) + 1
	return out


func test_plate_parts_and_gaps() -> void:
	assert_true(ArmorRead.plate_on(IRON, "head"))
	assert_false(ArmorRead.plate_on(LEATHER, "head"))
	assert_false(ArmorRead.plate_on({"torso": "mail"}, "torso"), "mail has no gaps to find")
	var g: Dictionary = ArmorRead.open_gaps(IRON)
	for k: String in ["neck", "face", "elbow_r", "elbow_l", "knee_l", "knee_r"]:
		assert_true(g.has(k), k)
	assert_true(ArmorRead.open_gaps(LEATHER).is_empty())
	assert_eq(ArmorRead.open_gaps({"head": "helm_thraex"}).keys(), ["face"])
	assert_eq(ArmorRead.worn_ids(IRON).size(), 4)


func test_gap_points_land_in_the_gaps() -> void:
	var parts: Dictionary = {"torso": {"pos": Vector3(0, 1.3, 0)}, "head": {"pos": Vector3(0, 1.65, 0)},
		"upper_arm_r": {"pos": Vector3(0.2, 1.4, 0)}, "forearm_r": {"pos": Vector3(0.2, 1.08, 0)}}
	var neck: Vector3 = ArmorRead.gap_point("neck", parts, Vector3.ZERO)
	assert_true(ArmorGaps.in_gap("torso", neck - Vector3(0, 1.3, 0)), "the neck point is in the torso's top band")
	assert_near(ArmorRead.gap_point("elbow_r", parts, Vector3.ZERO).y, 1.24, 0.001)
	assert_true(ArmorRead.gap_point("face", parts, Vector3.ZERO).y < 1.65)
	assert_eq(ArmorRead.gap_point("neck", {}, Vector3(0, 1.0, 0)).y > 1.0, true, "falls back without parts")


func test_load_and_kite_rule() -> void:
	assert_near(ArmorRead.load_of({}), 0.0)
	assert_true(ArmorRead.load_of(IRON) > 0.95)
	assert_true(ArmorRead.should_kite(0.0, 1.0, 1.0, 1.0), "naked v iron: kite")
	assert_false(ArmorRead.should_kite(1.0, 0.0, 1.0, 1.0), "the heavy side never kites")
	assert_false(ArmorRead.should_kite(0.0, ArmorRead.load_of(LEATHER), 1.0, 1.0), "leather is too light to run from")
	assert_false(ArmorRead.should_kite(0.0, 1.0, 1.0, 0.2), "a winded foe is gone in on")
	assert_false(ArmorRead.should_kite(0.0, 1.0, 0.1, 1.0), "no breath to run")


func test_point_weapon_thrusts_at_gaps_in_plate_only() -> void:
	var iron: Dictionary = _plans("gladius", IRON)
	assert_true(int(iron["gap"]) > 90, "gladius v iron set: %d of 300 plans aim at a gap" % int(iron["gap"]))
	assert_true(int(iron["gaps"].get("neck", 0)) > int(iron["gaps"].get("knee_l", 0)), "the neck is the favourite")
	assert_eq(int(_plans("gladius", LEATHER)["gap"]), 0, "nothing to find in leather")
	assert_eq(int(_plans("gladius", {})["gap"]), 0)
	assert_eq(int(_plans("bat", IRON)["gap"]), 0, "a bat has no point")
	var easy: Dictionary = _plans("gladius", IRON, "easy")
	assert_true(int(easy["gap"]) < int(iron["gap"]) / 3, "easy rarely reads the gaps")


func test_helmet_targeting_by_weapon() -> void:
	var helm: Dictionary = {"head": "helm_iron"}
	var cap: Dictionary = {"head": "helm_leather"}
	assert_true(int(_plans("bat", helm)["head"]) > int(_plans("bat", cap)["head"]), "a bat bashes the plate helmet")
	assert_true(int(_plans("falchion", helm)["head"]) < int(_plans("falchion", cap)["head"]), "a blade stops cutting at it")


func test_naked_fighter_kites_a_fresh_plate_fighter() -> void:
	var b := _brain()
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0, "gladius", {})
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -2.4), PI, "gladius", IRON)
	var back: int = 0
	for i in 60:
		var inp: FighterInput = b.think(me, foe, DT)
		if inp.move_y < 0:
			back += 1
		assert_false(inp.has(FighterInput.SWING) and i > 30, "no attack while kiting")
	assert_true(back > 40, "gives ground: %d of 60 ticks" % back)
	# Same spot, the plate fighter winded: no kiting.
	var c := _brain()
	foe["stamina"] = 0.2
	for i in 60:
		c.think(me, foe, DT)
		if c._kite_t > 0:
			assert_true(false, "kites a winded plate fighter at tick %d" % i)
			return


func test_plate_fighter_does_not_kite() -> void:
	var b := _brain()
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0, "gladius", IRON)
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -2.4), PI, "gladius", {})
	assert_false(b._kite(me, foe, FighterInput.new()))


func test_kiting_ends_and_re_engages() -> void:
	var b := _brain()
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0, "gladius", {})
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -2.4), PI, "gladius", IRON)
	var kiting: int = 0
	for i in FighterBrain.KITE_MAX_TICKS + 60:
		b.think(me, foe, DT)
		if b._kite_t > 0:
			kiting += 1
	assert_true(kiting <= FighterBrain.KITE_MAX_TICKS + 1, "a stint is capped")
	assert_true(b._kite_cd > 0 or b._burst_t > 0, "then a cooldown and a committed burst")
