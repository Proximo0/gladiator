extends TestCase
## Houdini armor art (assets/armor/*.glb): the armor defs' "art" maps point at real assets on parts they cover, and
## FighterArt.armor_art hands out opaque, per-caller meshes.


func test_art_maps_point_at_covered_parts_and_assets() -> void:
	var seen: int = 0
	for aid: String in CombatData.armor_ids():
		var ad: Dictionary = CombatData.armor(aid)
		if not ad.has("art"):
			continue
		assert_true(ad["art"] is Dictionary, aid + " art is a {part: asset} map")
		for pn: Variant in (ad["art"] as Dictionary):
			assert_true((ad.get("covers", []) as Array).has(str(pn)), "%s draws art on a part it covers (%s)" % [aid, pn])
			var path: String = FighterArt.ARMOR_ART_DIR + str((ad["art"] as Dictionary)[pn]) + ".glb"
			assert_true(ResourceLoader.exists(path), path + " exists")
			seen += 1
	assert_eq(seen, 5, "galea, two manicae, two greaves")


func test_armor_art_is_opaque_and_per_caller() -> void:
	var a: Mesh = FighterArt.armor_art("galea")
	var b: Mesh = FighterArt.armor_art("galea")
	assert_true(a != null and b != null, "galea loads")
	assert_true(a != b, "each caller gets its own mesh")
	assert_true(a.get_surface_count() >= 1)
	for s: int in a.get_surface_count():
		var m: BaseMaterial3D = a.surface_get_material(s) as BaseMaterial3D
		assert_true(m != null, "surface %d keeps its material" % s)
		assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "surface %d is opaque" % s)
	assert_true(FighterArt.armor_art("") == null)
	assert_true(FighterArt.armor_art("no_such_piece") == null)


## Pieces are built in their part's frame: each one fits around its part's centre (no stray offsets).
func test_art_sits_on_the_part() -> void:
	for id: String in ["galea", "manica_r", "manica_l", "greave_r", "greave_l"]:
		var box: AABB = FighterArt.armor_art(id).get_aabb()
		assert_true(box.has_point(Vector3.ZERO), id + " wraps the part centre")
		assert_true(box.size.length() < 0.7, id + " is part sized")
