extends TestCase


func test_tables_have_one_entry_per_level() -> void:
	for t: Array in [GfxQuality.CROWD_SPACING_MULT, GfxQuality.CROWD_BACK_SPACING, GfxQuality.SHADOW_DISTANCE,
			GfxQuality.SHADOW_BIAS, GfxQuality.SHADOW_NORMAL_BIAS, GfxQuality.SAND_TEXELS_PER_M, GfxQuality.SAND_MESH_CELL, GfxQuality.SAND_POOL_STEP_S, GfxQuality.SAND_UPLOAD_S]:
		assert_eq(t.size(), 3)
	for t: Array in [GfxQuality.CROWD_CHEER_TIER, GfxQuality.CROWD_SECTORS, GfxQuality.SHADOW_SPLITS, GfxQuality.MSAA,
			GfxQuality.SAND_GRAINS, GfxQuality.SAND_PUFFS, GfxQuality.SAND_PUFF_AMOUNT, GfxQuality.SAND_DETAIL,
			GfxQuality.CROWD_TIER_LOD]:
		assert_eq(t.size(), 3)


func test_low_is_cheaper_than_high() -> void:
	assert_true(GfxQuality.pick_f(GfxQuality.CROWD_SPACING_MULT, 0) > GfxQuality.pick_f(GfxQuality.CROWD_SPACING_MULT, 2))
	assert_true(GfxQuality.pick_i(GfxQuality.SAND_GRAINS, 0) < GfxQuality.pick_i(GfxQuality.SAND_GRAINS, 2))
	assert_true(GfxQuality.pick_f(GfxQuality.SAND_TEXELS_PER_M, 0) < GfxQuality.pick_f(GfxQuality.SAND_TEXELS_PER_M, 2))
	assert_true(GfxQuality.pick_f(GfxQuality.SAND_MESH_CELL, 0) > GfxQuality.pick_f(GfxQuality.SAND_MESH_CELL, 2))
	assert_true(GfxQuality.pick_i(GfxQuality.CROWD_SECTORS, 0) < GfxQuality.pick_i(GfxQuality.CROWD_SECTORS, 2))
	for tier: int in 6:
		assert_true(GfxQuality.tier_lod(tier, 0) >= GfxQuality.tier_lod(tier, 2), "lower quality never uses a finer mesh")


func test_lod_never_gets_finer_with_distance() -> void:
	for l: int in 3:
		for tier: int in range(1, 6):
			assert_true(GfxQuality.tier_lod(tier, l) >= GfxQuality.tier_lod(tier - 1, l))


func test_level_is_clamped_and_named() -> void:
	var old: int = GfxQuality.level
	GfxQuality.set_level(9)
	assert_eq(GfxQuality.level, GfxQuality.HIGH)
	GfxQuality.set_level(-4)
	assert_eq(GfxQuality.level, GfxQuality.LOW)
	assert_eq(GfxQuality.name_of(1), "medium")
	assert_eq(GfxQuality.blood_level(), 0)
	GfxQuality.set_level(old)


func test_small_part_shadows_off_only_on_low() -> void:
	assert_false(GfxQuality.small_part_shadows(0))
	assert_true(GfxQuality.small_part_shadows(1))
	assert_true(GfxQuality.small_part_shadows(2))
	assert_eq(GfxQuality.SMALL_PART_SHADOWS.size(), 3)
	assert_false(FighterArt.casts_shadow("forearm_r", 0))
	assert_true(FighterArt.casts_shadow("torso", 0), "big parts keep their shadow on low")
	assert_true(FighterArt.casts_shadow("shin_l", 2))


func test_apply_shadow_walks_the_subtree() -> void:
	var old: int = GfxQuality.level
	GfxQuality.set_level(0)
	var b := Node3D.new()
	var mi := MeshInstance3D.new()
	var look := Node3D.new()
	b.add_child(look)
	look.add_child(mi)
	FighterArt.apply_shadow(b, "forearm_l")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	FighterArt.apply_shadow(b, "torso")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	b.free()
	GfxQuality.set_level(old)
