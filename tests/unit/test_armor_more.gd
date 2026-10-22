extends TestCase
## The second armor and shield set (Houdini art from tools/houdini/build_armor_more.py): six earned shields, nine
## earned armor pieces, their colliders and art fit, and the side-grade rule (nothing new strictly beats an old item).

const SHIELDS: Array[String] = ["buckler", "parma", "pelta", "kite_shield", "aspis", "tower_shield"]
const ARMOR: Array[String] = ["helm_murmillo", "helm_thraex", "helm_secutor", "lorica_segmentata", "lorica_squamata",
	"balteus", "retiarius_arm", "spaulders", "fasciae"]
const OLD_SHIELDS: Array[String] = ["shield_round", "scutum"]


func _p(matches: int, wins: int, ranked_wins: int = 0) -> Dictionary:
	return PlayerProgress.clean({"matches": matches, "wins": wins, "ranked_matches": ranked_wins, "ranked_wins": ranked_wins})


func test_shields_are_earned_offhands_with_art() -> void:
	for id: String in SHIELDS:
		var d: Dictionary = CombatData.weapon(id)
		assert_false(d.is_empty(), id + " exists")
		assert_true(LoadoutRules.is_shield(id), id + " is a shield")
		assert_true(WeaponUnlocks.is_unlockable(id), id + " is earned")
		assert_false(LoadoutRules.is_premium_weapon(id))
		assert_true(LoadoutRules.offhands().has(id))
		assert_false(LoadoutRules.picker_weapons().has(id), id + " is never a main weapon")
		assert_true(ResourceLoader.exists(str(d["art"])), id + " art exists")
		for k: String in ["mass", "length", "blunt_factor", "unlock"]:
			assert_true(d.has(k), "%s lacks %s" % [id, k])


func _face_area(d: Dictionary) -> float:
	if str(d.get("look", "shield")) == "shield":
		return PI * pow(float(d["length"]) * 0.5, 2.0)
	return float(d.get("width", 0.68)) * float(d["length"])


## Side-grades: a shield that is no heavier, no smaller and bashes no softer than another would just be better.
func test_shields_are_side_grades() -> void:
	var all: Array[String] = OLD_SHIELDS + SHIELDS
	for a: String in SHIELDS:
		var da: Dictionary = CombatData.weapon(a)
		for b: String in all:
			if a == b:
				continue
			var db: Dictionary = CombatData.weapon(b)
			var dominates: bool = float(da["mass"]) <= float(db["mass"]) and _face_area(da) >= _face_area(db) \
				and float(da["blunt_factor"]) >= float(db["blunt_factor"])
			assert_false(dominates, "%s strictly beats %s" % [a, b])


## The collider covers the art's face: built shields' Art AABB and their face collider agree within 6 cm.
func test_shield_colliders_match_the_art() -> void:
	for id: String in SHIELDS:
		var w := Weapon.new()
		w.build(CombatData.weapon(id))
		var art: Node3D = w.get_node_or_null("Art") as Node3D
		assert_true(art != null, id + " shows its Houdini art")
		if art == null:
			w.free()
			continue
		var art_box: AABB = _art_aabb(art)
		var face := AABB()
		var found: bool = false
		for c: Node in w.get_children():
			if not (c is CollisionShape3D):
				continue
			var cs := c as CollisionShape3D
			var box: AABB
			if cs.shape is BoxShape3D:
				var sz: Vector3 = (cs.shape as BoxShape3D).size
				box = AABB(cs.position - sz * 0.5, sz)
			elif cs.shape is CylinderShape3D:
				var r: float = (cs.shape as CylinderShape3D).radius
				box = AABB(cs.position - Vector3(r, r, 0.02), Vector3(2.0 * r, 2.0 * r, 0.04))
			else:
				continue
			if box.size.x * box.size.y > face.size.x * face.size.y:
				face = box
				found = true
		assert_true(found, id + " has a face collider")
		var ac: Vector2 = Vector2(art_box.get_center().x, art_box.get_center().y)
		var fc: Vector2 = Vector2(face.get_center().x, face.get_center().y)
		assert_true(ac.distance_to(fc) < 0.06, "%s collider centre %s vs art %s" % [id, fc, ac])
		assert_true(absf(face.size.x - art_box.size.x) < 0.06 and absf(face.size.y - art_box.size.y) < 0.06,
			"%s collider %s vs art %s" % [id, face.size, art_box.size])
		w.free()


## The aspis was modelled with its arm band toward -X; the game holds a left-hand shield with +X toward the holder's
## left, so the art is rolled half a turn and the bowl sits toward +X.
func test_aspis_band_faces_the_holders_left() -> void:
	var w := Weapon.new()
	w.build(CombatData.weapon("aspis"))
	var box: AABB = _art_aabb(w.get_node("Art") as Node3D)
	assert_true(box.get_center().x > 0.15, "bowl toward +X: %s" % box.get_center())
	assert_true(box.end.z > 0.1, "face still toward +Z")
	w.free()


func _art_aabb(art: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for n: Node in art.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf: Transform3D = art.transform
		var p: Node = mi
		var chain := Transform3D.IDENTITY
		while p != art:
			chain = (p as Node3D).transform * chain
			p = p.get_parent()
		var box: AABB = (xf * chain) * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func test_armor_pieces_have_data_art_and_rules() -> void:
	var slots: Array = LoadoutRules.slot_names()
	for id: String in ARMOR:
		var d: Dictionary = CombatData.armor(id)
		assert_false(d.is_empty(), id + " exists")
		assert_true(slots.has(str(d["part"])), id + " fills a loadout slot")
		assert_true(LoadoutRules.armor_options(str(d["part"])).has(id), id + " is listed in its slot")
		assert_true(WeaponUnlocks.is_unlockable(id), id + " is earned")
		for k: String in ["mass", "kind", "cut_resist", "pierce_resist", "blunt_resist", "durability", "strap", "covers"]:
			assert_true(d.has(k), "%s lacks %s" % [id, k])
		assert_true(["cloth", "leather", "mail", "plate"].has(str(d["kind"])), id + " uses a kind the AI and sounds know")
		for pn: Variant in (d["art"] as Dictionary):
			assert_true(FighterArt.armor_art(str((d["art"] as Dictionary)[pn])) != null, "%s art on %s loads" % [id, pn])


## No new piece strictly beats another piece of the same slot (no heavier, covers at least as much, resists at least
## as well everywhere, wears and stays on at least as well).
func test_armor_is_side_grades() -> void:
	for a: String in ARMOR:
		var da: Dictionary = CombatData.armor(a)
		for b: String in CombatData.armor_ids():
			if a == b:
				continue
			var db: Dictionary = CombatData.armor(b)
			if str(db["part"]) != str(da["part"]):
				continue
			var covers_all: bool = true
			for pn: Variant in db["covers"]:
				covers_all = covers_all and (da["covers"] as Array).has(pn)
			var better: bool = covers_all and float(da["mass"]) <= float(db["mass"])
			for k: String in ["cut_resist", "pierce_resist", "blunt_resist", "durability", "strap"]:
				better = better and float(da[k]) >= float(db[k])
			assert_false(better, "%s strictly beats %s" % [a, b])


func test_locked_armor_falls_back_to_the_slot_default() -> void:
	var fresh: Array = WeaponUnlocks.access([], {}, false)
	var want: Dictionary = {"weapon": "gladius", "offhand": "aspis",
		"armor": {"head": "helm_murmillo", "torso": "lorica_segmentata", "thigh_l": "fasciae"}}
	var gated: Dictionary = LoadoutRules.sanitize(want, fresh)
	assert_eq(str(gated["offhand"]), LoadoutRules.DEFAULT_OFFHAND, "locked shield: round shield")
	assert_eq(gated["armor"], {"head": "helm_leather", "torso": "cuirass_leather"}, "locked pieces: slot defaults or none")
	var earned: Dictionary = LoadoutRules.sanitize(want, WeaponUnlocks.access([], _p(9, 7), false))
	assert_eq(str(earned["offhand"]), "aspis")
	assert_eq(earned["armor"], want["armor"])
	assert_eq(LoadoutRules.sanitize(want)["armor"], want["armor"], "null owned trusts the loadout")
	assert_eq(LoadoutRules.sanitize(want, WeaponUnlocks.access([], {}, true))["armor"], want["armor"], "--unlock-all")
	assert_eq(LoadoutRules.lock_reason("helm_thraex", fresh, _p(4, 1)), "Win 3 fights (1/3)")
	assert_eq(LoadoutRules.lock_reason("helm_leather", fresh), "", "starter armor is free")
	assert_eq(MenuFlow.unlocked_text(["helm_secutor"]), "Unlocked: Secutor helmet! Pick it in your loadout.")


func test_covers_text() -> void:
	assert_eq(LoadoutRules.covers_text(["head"]), "head")
	assert_eq(LoadoutRules.covers_text(["torso", "pelvis"]), "chest, belly")
	assert_eq(LoadoutRules.covers_text(["upper_arm_l", "forearm_l"]), "left arm")
	assert_eq(LoadoutRules.covers_text(["upper_arm_l", "upper_arm_r"]), "both arms")
	assert_eq(LoadoutRules.covers_text(["thigh_l", "thigh_r", "shin_l", "shin_r"]), "both legs")
	assert_true(LoadoutRules.armor_stats("fasciae")["line"].ends_with("both legs"))
