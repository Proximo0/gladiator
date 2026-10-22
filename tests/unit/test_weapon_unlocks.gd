extends TestCase
## Play-to-unlock weapons: data, milestones, the `owned` access list, LoadoutRules gating, placeholder builds and
## damage sanity (docs/weapons_unlocks.md).

const NEW_WEAPONS: Array[String] = ["machete", "sledgehammer", "mace", "falchion", "warhammer", "halberd"]
const STARTERS: Array[String] = ["fists", "rake", "bat", "club", "gladius", "longsword", "axe", "spear"]
const NEW_SHIELDS: Array[String] = ["buckler", "parma", "pelta", "kite_shield", "aspis", "tower_shield"]
const NEW_ARMOR: Array[String] = ["helm_murmillo", "helm_thraex", "helm_secutor", "lorica_segmentata", "lorica_squamata",
	"balteus", "retiarius_arm", "spaulders", "fasciae"]
const KAT: String = "sandblood.outfit.samurai"


func _p(matches: int, wins: int, ranked_wins: int = 0) -> Dictionary:
	return PlayerProgress.clean({"matches": matches, "wins": wins, "ranked_matches": ranked_wins, "ranked_wins": ranked_wins})


func test_new_weapons_have_data_and_rules() -> void:
	var ids: PackedStringArray = CombatData.weapon_ids()
	for id: String in NEW_WEAPONS:
		assert_true(ids.has(id), "missing " + id)
		var d: Dictionary = CombatData.weapon(id)
		for k: String in ["name", "mass", "length", "grip_offset", "balance_point", "shape", "look", "blunt_factor",
				"cut_factor", "pierce_factor", "two_handed", "color"]:
			assert_true(d.has(k), "%s lacks %s" % [id, k])
		assert_true(["sword", "axe", "club", "bat", "spear"].has(str(d["shape"])), id + " uses a shape the AI, contact and sound know")
		assert_true(float(d["balance_point"]) < float(d["length"]) - float(d["grip_offset"]), id + " balance inside the weapon")
		assert_true(WeaponUnlocks.is_unlockable(id), id + " is unlockable")
		assert_false(LoadoutRules.is_premium_weapon(id))
	assert_eq(WeaponUnlocks.unlockable_ids(), Array(NEW_WEAPONS) + ["scutum"] + NEW_SHIELDS + NEW_ARMOR,
		"data order: weapons and shields, then armor")


## The scutum: an earned off-hand shield, a side-grade to the round shield (bigger and heavier), gated like a weapon.
func test_scutum_is_an_earned_shield() -> void:
	var d: Dictionary = CombatData.weapon("scutum")
	var round_d: Dictionary = CombatData.weapon("shield_round")
	assert_true(LoadoutRules.is_shield("scutum"))
	assert_true(WeaponUnlocks.is_unlockable("scutum"))
	assert_true(float(d["mass"]) > float(round_d["mass"]), "heavier than the round shield")
	assert_true(float(d["length"]) > float(round_d["length"]), "taller than the round shield")
	assert_true(ResourceLoader.exists(str(d["art"])), "art exists")
	assert_true(LoadoutRules.offhands().has("scutum"))
	assert_false(LoadoutRules.picker_weapons().has("scutum"), "never a main weapon")
	var fresh: Array = WeaponUnlocks.access([], {}, false)
	var want: Dictionary = {"weapon": "gladius", "offhand": "scutum"}
	assert_eq(str(LoadoutRules.sanitize(want, fresh)["offhand"]), LoadoutRules.DEFAULT_OFFHAND, "locked: round shield")
	assert_eq(str(LoadoutRules.sanitize(want, WeaponUnlocks.access([], _p(5, 2), false))["offhand"]), "scutum")
	assert_eq(str(LoadoutRules.sanitize(want)["offhand"]), "scutum", "null owned trusts the loadout")
	assert_eq(LoadoutRules.lock_reason("scutum", fresh, _p(3, 1)), "Win 2 fights (1/2)")


func test_scutum_builds_a_box_shield() -> void:
	var w := Weapon.new()
	w.build(CombatData.weapon("scutum"))
	assert_eq(w.shape_kind, "shield")
	assert_true(w.get_node_or_null("Art") != null, "Houdini art on the shield")
	var boxes: int = 0
	for c: Node in w.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var sz: Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
			if sz.y > 1.0:
				boxes += 1
				assert_true(sz.x > 0.6 and sz.z < 0.1, "a tall flat board")
	assert_eq(boxes, 1, "one board collider")
	w.free()


func test_realistic_numbers() -> void:
	assert_true(float(CombatData.weapon("sledgehammer")["mass"]) > 2.5, "a sledge is heavy")
	assert_true(float(CombatData.weapon("machete")["mass"]) < 1.0, "a machete is light")
	assert_true(float(CombatData.weapon("halberd")["length"]) > 1.8, "a halberd is a pole arm")
	assert_true(bool(CombatData.weapon("halberd")["two_handed"]) and bool(CombatData.weapon("sledgehammer")["two_handed"]))
	assert_false(bool(CombatData.weapon("mace")["two_handed"]))
	for id: String in ["mace", "sledgehammer"]:
		assert_near(float(CombatData.weapon(id)["cut_factor"]), 0.0, 0.0001, id + " cannot cut")
		assert_true(float(CombatData.weapon(id)["blunt_factor"]) > float(CombatData.weapon("club")["blunt_factor"]), id + " out-crushes a club")
	assert_true(float(CombatData.weapon("falchion")["cut_factor"]) <= float(CombatData.weapon("dai_katana")["cut_factor"]), "no free blade beats the premium one")


func test_starters_and_premium_have_no_milestone() -> void:
	for id: String in STARTERS:
		assert_false(WeaponUnlocks.is_unlockable(id), id)
		assert_true(WeaponUnlocks.is_unlocked(id, {}), id + " is free")
	assert_false(WeaponUnlocks.is_unlockable("dai_katana"))
	assert_false(WeaponUnlocks.is_unlockable("nope"))
	assert_eq(WeaponUnlocks.requirement_text("longsword"), "")


func test_milestones_and_text() -> void:
	assert_eq(WeaponUnlocks.requirement_text("mace"), "Win 1 fight")
	assert_eq(WeaponUnlocks.requirement_text("machete"), "Play 2 fights")
	assert_eq(WeaponUnlocks.requirement_text("halberd"), "Win 3 ranked Quick Matches")
	assert_eq(WeaponUnlocks.progress_text("falchion", _p(9, 1)), "Win 4 fights (1/4)")
	assert_eq(WeaponUnlocks.progress_text("falchion", _p(90, 40)), "Win 4 fights (4/4)", "capped")
	assert_false(WeaponUnlocks.is_unlocked("mace", _p(5, 0)))
	assert_true(WeaponUnlocks.is_unlocked("mace", _p(1, 1)))
	assert_false(WeaponUnlocks.is_unlocked("halberd", _p(50, 50, 2)), "off-line wins are not ranked wins")
	assert_true(WeaponUnlocks.is_unlocked("halberd", _p(3, 3, 3)))
	assert_eq(WeaponUnlocks.earned_ids({}), [])
	assert_eq(WeaponUnlocks.earned_ids(_p(2, 1)), ["machete", "mace", "buckler", "helm_secutor", "spaulders", "fasciae"])


func test_newly_unlocked() -> void:
	assert_eq(WeaponUnlocks.newly_unlocked(_p(1, 0), _p(2, 1)), ["machete", "mace", "helm_secutor", "spaulders"])
	assert_eq(WeaponUnlocks.newly_unlocked(_p(2, 1), _p(3, 1)), ["parma", "balteus"])
	assert_eq(WeaponUnlocks.newly_unlocked(_p(9, 3), _p(9, 3)), [])


func test_access_tokens_and_bypass() -> void:
	var none: Array = WeaponUnlocks.access([KAT], {}, false)
	assert_eq(none, [KAT], "store products kept, nothing earned")
	var some: Array = WeaponUnlocks.access([], _p(2, 1), false)
	assert_true(some.has(WeaponUnlocks.token("mace")) and not some.has(WeaponUnlocks.token("falchion")))
	var all: Array = WeaponUnlocks.access([], {}, true)
	for id: String in NEW_WEAPONS:
		assert_true(all.has(WeaponUnlocks.token(id)), "--unlock-all opens " + id)
	assert_false(all.has(KAT), "the bypass never grants a premium outfit")


func test_loadout_rules_gate_unlockables() -> void:
	var fresh: Array = WeaponUnlocks.access([], {}, false)
	var want: Dictionary = {"weapon": "warhammer", "offhand": "", "outfit": "samurai"}
	assert_eq(str(LoadoutRules.sanitize(want)["weapon"]), "warhammer", "null owned: trusted (network, bots)")
	var gated: Dictionary = LoadoutRules.sanitize(want, fresh)
	assert_eq(str(gated["weapon"]), LoadoutRules.PREMIUM_FALLBACK, "locked becomes the fallback")
	assert_eq(str(gated["outfit"]), "samurai", "the outfit rides along")
	assert_eq(str(LoadoutRules.sanitize(want, WeaponUnlocks.access([], {}, true))["weapon"]), "warhammer")
	assert_eq(str(LoadoutRules.sanitize({"weapon": "gladius"}, fresh)["weapon"]), "gladius", "starters stay free")
	assert_eq(str(LoadoutRules.sanitize({"weapon": "dai_katana"}, WeaponUnlocks.access([], {}, true))["weapon"]),
		LoadoutRules.PREMIUM_FALLBACK, "the bypass does not open premium weapons")
	var listed: Array = LoadoutRules.main_weapons(fresh)
	assert_false(listed.has("mace"))
	assert_true(listed.has("longsword"))
	var picker: Array = LoadoutRules.picker_weapons()
	for id: String in NEW_WEAPONS + ["dai_katana", "laser_sword"]:
		assert_true(picker.has(id), id + " is shown in the picker")
	assert_false(picker.has("shield_round"))


func test_lock_reasons() -> void:
	var fresh: Array = WeaponUnlocks.access([], {}, false)
	assert_eq(LoadoutRules.lock_reason("gladius", fresh), "")
	assert_eq(LoadoutRules.lock_reason("falchion", fresh, _p(3, 2)), "Win 4 fights (2/4)")
	assert_eq(LoadoutRules.lock_reason("dai_katana", fresh), "Comes with the %s outfit (Shop)" % OutfitRules.display_name("samurai"))
	assert_eq(LoadoutRules.lock_reason("falchion", null), "", "null owned: nothing locked")


func test_unlocked_text() -> void:
	assert_eq(MenuFlow.unlocked_text([]), "")
	assert_eq(MenuFlow.unlocked_text(["mace", "machete"]), "Unlocked: Flanged mace, Machete! Pick it in your loadout.")


func _shape_extent(w: Weapon) -> Vector2:
	var lo: float = 1e9
	var hi: float = -1e9
	for c: Node in w.get_children():
		if c is CollisionShape3D:
			var cs := c as CollisionShape3D
			var ext: float = 0.0
			if cs.shape is BoxShape3D:
				var b: Vector3 = (cs.shape as BoxShape3D).size * 0.5
				var bs: Basis = cs.transform.basis
				ext = absf(bs.x.y) * b.x + absf(bs.y.y) * b.y + absf(bs.z.y) * b.z
			elif cs.shape is CapsuleShape3D:
				ext = (cs.shape as CapsuleShape3D).height * 0.5
			elif cs.shape is CylinderShape3D:
				ext = (cs.shape as CylinderShape3D).height * 0.5
			elif cs.shape is SphereShape3D:
				ext = (cs.shape as SphereShape3D).radius
			lo = minf(lo, cs.position.y - ext)
			hi = maxf(hi, cs.position.y + ext)
	return Vector2(lo, hi)


func test_placeholders_span_the_weapon() -> void:
	for id: String in NEW_WEAPONS:
		var d: Dictionary = CombatData.weapon(id)
		var w := Weapon.new()
		w.build(d)
		var span: Vector2 = _shape_extent(w)
		var tip: float = float(d["length"]) - float(d["grip_offset"])
		assert_near(span.y, tip, 0.03, id + " colliders reach the tip")
		assert_near(span.x, -float(d["grip_offset"]), 0.04, id + " colliders reach the butt")
		var meshes: int = 0
		for c: Node in w.get_children():
			if c is MeshInstance3D:
				meshes += 1
		assert_true(meshes >= 3, id + " has a recognisable placeholder")
		w.free()


func _hit(part: String, weapon: String, contact: String, speed: float, mass: float) -> Dictionary:
	return {
		"part": part, "weapon_id": weapon, "contact": contact, "rel_vel": Vector3(0, 0, -speed),
		"normal": Vector3(0, 0, -1), "edge_alignment": 1.0, "effective_mass": mass, "armor_ids": [], "armor_wear": {},
	}


func test_light_taps_do_not_kill() -> void:
	for id: String in NEW_WEAPONS:
		var contact: String = "edge" if float(CombatData.weapon(id)["cut_factor"]) > 0.0 else "blunt"
		for part: String in ["head", "torso", "forearm_r", "thigh_r"]:
			var r: Dictionary = DamageModel.resolve(_hit(part, id, contact, 4.0, 1.2), Tuning.new())
			assert_false(bool(r["sever"]) or bool(r["gut"]) or bool(r["behead"]), "%s tap on %s" % [id, part])
			assert_true(float(r["total"]) < 12.0, "%s tap total on %s" % [id, part])


func test_contact_kinds() -> void:
	# The halberd's spike thrusts, its blade cuts; the war hammer's beak is a short edge; the mace never cuts.
	var hal: Dictionary = CombatData.weapon("halberd")
	var tip: float = float(hal["length"]) - float(hal["grip_offset"])
	assert_eq(str(FighterMath.classify_contact(hal, tip - 0.02, Vector3(0, 5, 0))["contact"]), "point")
	assert_eq(str(FighterMath.classify_contact(hal, tip - 0.15, Vector3(5, 0, 0))["contact"]), "edge")
	assert_eq(str(FighterMath.classify_contact(hal, 0.5, Vector3(5, 0, 0))["contact"]), "blunt", "the haft is blunt")
	var mace: Dictionary = CombatData.weapon("mace")
	assert_eq(str(FighterMath.classify_contact(mace, 0.55, Vector3(5, 0, 0))["contact"]), "blunt")
	assert_eq(SfxLogic.weapon_material(mace), "steel")
