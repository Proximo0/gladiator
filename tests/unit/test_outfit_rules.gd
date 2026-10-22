extends TestCase


func test_outfits_in_data() -> void:
	assert_eq(OutfitRules.ids(), ["default", "samurai", "alien"])
	assert_eq(OutfitRules.premium_ids(), ["samurai", "alien"])
	assert_false(OutfitRules.is_premium("default"))
	assert_eq(OutfitRules.product_id("samurai"), "sandblood.outfit.samurai")
	assert_eq(OutfitRules.product_id("alien"), "sandblood.outfit.alien")
	assert_eq(OutfitRules.product_id("default"), "")
	assert_eq(OutfitRules.fallback_price("samurai"), "$4.99")


func test_product_lookup() -> void:
	assert_eq(OutfitRules.outfit_for_product("sandblood.outfit.alien"), "alien")
	assert_eq(OutfitRules.outfit_for_product("nope"), "")
	assert_eq(OutfitRules.outfit_for_product(""), "")


func test_clean_id() -> void:
	assert_eq(OutfitRules.clean_id("samurai"), "samurai")
	assert_eq(OutfitRules.clean_id("bogus"), "default")
	assert_eq(OutfitRules.clean_id(null), "default")
	assert_eq(OutfitRules.clean_id(7), "default")


func test_entitlement() -> void:
	assert_eq(OutfitRules.usable_id("samurai", []), "default")
	assert_eq(OutfitRules.usable_id("samurai", ["sandblood.outfit.samurai"]), "samurai")
	assert_eq(OutfitRules.usable_id("alien", ["sandblood.outfit.samurai"]), "default")
	assert_eq(OutfitRules.usable_id("default", []), "default")
	assert_true(OutfitRules.can_equip("default", []))
	assert_false(OutfitRules.can_equip("alien", []))
	assert_false(OutfitRules.can_equip("bogus", ["sandblood.outfit.alien"]))


func test_loadout_carries_outfit() -> void:
	var base: Dictionary = LoadoutRules.default_loadout()
	var worn: Dictionary = OutfitRules.with_outfit(base, "alien")
	assert_eq(OutfitRules.outfit_of(worn), "alien")
	assert_false(base.has("outfit"), "original untouched")
	assert_eq(OutfitRules.outfit_of(base), "default")
	assert_false(OutfitRules.with_outfit(worn, "default").has("outfit"))
	assert_eq(OutfitRules.outfit_of({"outfit": "junk"}), "default")


func test_outfits_change_no_stats() -> void:
	var base: Dictionary = LoadoutRules.default_loadout()
	var worn: Dictionary = OutfitRules.with_outfit(base, "samurai")
	assert_near(LoadoutRules.total_mass(worn), LoadoutRules.total_mass(base))
	assert_eq(LoadoutRules.sanitize(worn), worn, "sanitize carries the cosmetic key so the opponent sees it")
	assert_eq(LoadoutRules.sanitize(OutfitRules.with_outfit(base, "junk")), base, "unknown outfits are dropped")
	for id: String in OutfitRules.ids():
		for k: Variant in OutfitRules.def(id):
			assert_true(["name", "blurb", "premium", "product_id", "fallback_price", "palette", "blood"].has(str(k)), "no stat key %s" % str(k))


func test_palette_and_covers() -> void:
	assert_true(OutfitRules.covers("samurai", "torso"))
	assert_false(OutfitRules.covers("samurai", "forearm_l"))
	assert_true(OutfitRules.covers("alien", "forearm_l"))
	assert_false(OutfitRules.covers("default", "torso"))
	var pal: Dictionary = OutfitRules.palette("samurai")
	assert_true(OutfitRules.color(pal, "armor", Color.BLACK) != Color.BLACK)
	assert_eq(OutfitRules.color({}, "x", Color.RED), Color.RED)
	for id: String in OutfitRules.premium_ids():
		var covered: Array = OutfitRules.palette(id)["covered"]
		for part: String in covered:
			assert_true(FighterRig.names().has(part), "%s covers a real part: %s" % [id, part])


func test_blood_palettes_red_by_default_ichor_for_alien() -> void:
	var red: BloodPalette = OutfitRules.blood_palette("default")
	assert_true(red.fresh.r > 0.6 and red.fresh.g < 0.1 and red.fresh.b < 0.1, "default bleeds red")
	assert_near(red.emission, 0.0)
	assert_eq(OutfitRules.blood_palette("samurai").fresh, red.fresh)
	var ichor: BloodPalette = OutfitRules.blood_palette("alien")
	assert_true(ichor.fresh.g > 0.7 and ichor.fresh.b > 0.45 and ichor.fresh.r < 0.2, "ichor is cyan-green")
	assert_true(ichor.dried.g > ichor.dried.r * 3.0 and ichor.dried.g < 0.35, "dries to dark teal")
	assert_true(ichor.emission > 0.0, "ichor glows a little")
	assert_true(ichor.flesh != red.flesh and ichor.bone != red.bone, "alien insides differ")
	assert_eq(OutfitRules.blood_palette("bogus").fresh, red.fresh, "unknown outfit bleeds red")


func test_blood_palette_follows_the_loadout_outfit() -> void:
	var base: Dictionary = LoadoutRules.default_loadout()
	var alien: Dictionary = OutfitRules.with_outfit(base, "alien")
	assert_eq(OutfitRules.blood_palette_of(alien).fresh, OutfitRules.blood_palette("alien").fresh)
	assert_eq(OutfitRules.blood_palette_of(base).fresh, BloodPalette.red().fresh)
	assert_eq(OutfitRules.blood_palette_of({"outfit": "junk"}).fresh, BloodPalette.red().fresh)
