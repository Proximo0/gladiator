extends TestCase
## The outfit-bundled weapons: data, gating by the store entitlement, shop line, sparks, sound and damage sanity.

const KAT: String = "sandblood.outfit.samurai"
const ALI: String = "sandblood.outfit.alien"


func _hit(part: String, weapon: String, contact: String, speed: float, mass: float) -> Dictionary:
	return {
		"part": part, "weapon_id": weapon, "contact": contact, "rel_vel": Vector3(0, 0, -speed),
		"normal": Vector3(0, 0, -1), "edge_alignment": 1.0, "effective_mass": mass, "armor_ids": [], "armor_wear": {},
	}


func _r(h: Dictionary) -> Dictionary:
	return DamageModel.resolve(h, Tuning.new())


func test_data_and_requirements() -> void:
	var k: Dictionary = CombatData.weapon("dai_katana")
	var l: Dictionary = CombatData.weapon("laser_sword")
	assert_eq(str(k["requires_outfit"]), "samurai")
	assert_eq(str(l["requires_outfit"]), "alien")
	assert_eq(OutfitRules.weapon_of("samurai"), "dai_katana")
	assert_eq(OutfitRules.weapon_of("alien"), "laser_sword")
	assert_eq(OutfitRules.weapon_of("default"), "")
	# They stay "sword" shaped so contact, AI and sound treat them as blades.
	assert_eq(str(k["shape"]), "sword")
	assert_eq(str(l["shape"]), "sword")
	assert_true(bool(k["two_handed"]))
	assert_false(bool(l["two_handed"]))
	assert_true(float(k["length"]) >= 1.2 and float(k["edge_len"]) >= 0.9)
	assert_true(float(l["edge_len"]) >= 1.0 and float(l["length"]) >= 1.2, "long energy blade")
	assert_true(float(k["blunt_factor"]) < float(CombatData.weapon("longsword")["blunt_factor"]), "poor blunt")
	assert_true(float(l["mass"]) < float(k["mass"]))


func test_includes_line() -> void:
	assert_eq(OutfitRules.includes_line("samurai"), "Includes: Dai-katana")
	assert_eq(OutfitRules.includes_line("alien"), "Includes: Laser sword")
	assert_eq(OutfitRules.includes_line("default"), "")


func test_sanitize_gating() -> void:
	var want: Dictionary = {"weapon": "dai_katana", "offhand": "shield_round"}
	assert_eq(str(LoadoutRules.sanitize(want)["weapon"]), "dai_katana", "no owned list: trusted (network, bots)")
	assert_eq(str(LoadoutRules.sanitize(want, [])["weapon"]), "longsword", "locked falls back")
	assert_eq(str(LoadoutRules.sanitize(want, [ALI])["weapon"]), "longsword", "the other outfit does not unlock it")
	assert_eq(str(LoadoutRules.sanitize(want, [KAT])["weapon"]), "dai_katana")
	assert_eq(str(LoadoutRules.sanitize(want, [KAT])["offhand"]), "", "two-handed blocks the off hand")
	var laser: Dictionary = {"weapon": "laser_sword"}
	assert_eq(str(LoadoutRules.sanitize(laser, [KAT])["weapon"]), "longsword")
	assert_eq(str(LoadoutRules.sanitize(laser, [ALI])["weapon"]), "laser_sword")
	assert_eq(str(LoadoutRules.sanitize({"weapon": "gladius"}, [])["weapon"]), "gladius", "free weapons never gated")


func test_picker_lists_only_owned() -> void:
	var none: Array = LoadoutRules.main_weapons([])
	assert_false(none.has("dai_katana") or none.has("laser_sword"))
	assert_true(none.has("longsword"))
	var one: Array = LoadoutRules.main_weapons([KAT])
	assert_true(one.has("dai_katana"))
	assert_false(one.has("laser_sword"))
	var all: Array = LoadoutRules.main_weapons()
	assert_true(all.has("dai_katana") and all.has("laser_sword"))
	assert_true(LoadoutRules.is_premium_weapon("laser_sword"))
	assert_false(LoadoutRules.is_premium_weapon("longsword"))


func test_energy_sparks_and_sound() -> void:
	var ev: Dictionary = {"hit_on_weapon": true, "energy": 80.0}
	assert_true(FeelLogic.strikes_sparks(ev, "energy", "steel", ""))
	assert_true(FeelLogic.strikes_sparks(ev, "steel", "energy", ""))
	assert_false(FeelLogic.strikes_sparks(ev, "energy", "wood", ""))
	assert_eq(SfxLogic.weapon_material(CombatData.weapon("laser_sword")), "energy")
	assert_eq(SfxLogic.weapon_material(CombatData.weapon("dai_katana")), "steel")
	var plan: Array[Dictionary] = SfxLogic.impact_plan(ev, "energy", "steel", "")
	var keys: Array = []
	for l: Dictionary in plan:
		keys.append(str(l["key"]))
	assert_true(keys.has("synth/laser_clash") and keys.has("impact/clang_steel"))
	assert_true(SfxLogic.variant_count("synth/laser_clash") > 0)


func test_light_taps_do_not_kill() -> void:
	# A gentle 4 m/s tap with each premium blade cannot sever or gut and stays well under a limb's hp.
	for id: String in ["dai_katana", "laser_sword"]:
		for part: String in ["head", "torso", "forearm_r", "thigh_r"]:
			var r: Dictionary = _r(_hit(part, id, "edge", 4.0, 1.2))
			assert_false(bool(r["sever"]) or bool(r["gut"]) or bool(r["behead"]), "%s tap on %s" % [id, part])
			assert_true(float(r["total"]) < 12.0, "%s tap total on %s" % [id, part])


func test_premium_cuts_but_shoves_less_than_longsword() -> void:
	var ls: Dictionary = _r(_hit("torso", "longsword", "edge", 15.0, 1.2))
	for id: String in ["dai_katana", "laser_sword"]:
		var r: Dictionary = _r(_hit("torso", id, "edge", 15.0, 1.2))
		assert_true(float(r["cut"]) > float(ls["cut"]), id + " cuts better")
		assert_true((r["knockback"] as Vector3).length() < (ls["knockback"] as Vector3).length(), id + " shoves less")
		assert_true(float(r["stagger"]) <= float(ls["stagger"]))


func _art_materials(n: Node, out: Array[BaseMaterial3D]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s: int in range(mi.mesh.get_surface_count()):
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null:
				out.append(m)
	for c: Node in n.get_children():
		_art_materials(c, out)


func test_art_materials_are_opaque() -> void:
	for id: String in ["dai_katana", "laser_sword", "rake", "longsword"]:
		var w := Weapon.new()
		w.build(CombatData.weapon(id))
		var art: Node = w.get_node_or_null("Art")
		assert_true(art != null, "%s has art" % id)
		if art == null:
			w.free()
			continue
		var mats: Array[BaseMaterial3D] = []
		_art_materials(art, mats)
		assert_true(mats.size() > 0, "%s art has materials" % id)
		for m: BaseMaterial3D in mats:
			assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "%s/%s opaque" % [id, m.resource_name])
		w.free()


## Two weapons of one id must not share a mesh resource (a shared mesh made headless teardown log
## `Parameter "material" is null` twice per identical-weapon match).
func test_art_meshes_not_shared_between_weapons() -> void:
	var a := Weapon.new()
	a.build(CombatData.weapon("longsword"))
	var b := Weapon.new()
	b.build(CombatData.weapon("longsword"))
	var ma: Array[Mesh] = []
	var mb: Array[Mesh] = []
	_art_meshes(a.get_node("Art"), ma)
	_art_meshes(b.get_node("Art"), mb)
	assert_true(ma.size() > 0, "art has meshes")
	for m: Mesh in ma:
		assert_false(mb.has(m), "art mesh is per weapon")
	a.free()
	b.free()


func _art_meshes(n: Node, out: Array[Mesh]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append((n as MeshInstance3D).mesh)
	for c: Node in n.get_children():
		_art_meshes(c, out)


func test_rake_art_fits_collider() -> void:
	var w := Weapon.new()
	w.build(CombatData.weapon("rake"))
	var art: Node3D = w.get_node("Art") as Node3D
	# Art spans y -0.2..1.4 (1.6 m) and x +-0.18; after the fit it must span -0.2..1.25 and x +-0.13.
	assert_near(art.scale.y * 1.4 + art.position.y, 1.25, 0.001)
	assert_near(art.scale.y * -0.2 + art.position.y, -0.2, 0.001)
	assert_near(art.scale.x * 0.18, 0.13, 0.001)
	w.free()
