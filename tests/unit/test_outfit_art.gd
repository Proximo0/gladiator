extends TestCase
## FighterArt outfit support without a scene: the palette fallback is chosen when assets/outfits/<id>/ is absent.


func test_default_has_no_armor_material() -> void:
	var a := FighterArt.new(0, 5)
	assert_true(a._armor == null)


func test_palette_fallback_materials() -> void:
	var a := FighterArt.new(0, 5, "samurai")
	assert_true(a._armor != null)
	assert_eq(a._armor.albedo_color, Color.html("#8a1c14"))
	assert_eq(a._cloth.albedo_color, Color.html("#1c2a55"))
	# Skin tone is still the seed's on an outfit that sets no skin.
	assert_eq(a._skin.albedo_color, BodyLook.skin_color(5, 0))


func test_alien_skin_override() -> void:
	var a := FighterArt.new(1, 9, "alien")
	assert_eq(a._skin.albedo_color, Color.html("#6fcf97"))


func test_unknown_outfit_is_default() -> void:
	var a := FighterArt.new(0, 5, "nonsense")
	assert_true(a._armor == null)


func test_covered_head_drops_beard() -> void:
	for s: int in 40:
		if BodyLook.bearded(s, 0):
			assert_eq(FighterArt.new(0, s, "samurai")._head_scene, "head")
			assert_eq(FighterArt.new(0, s)._head_scene, "head_b")
			return
	assert_true(false, "no bearded seed in 40")


func test_covered_parts_use_armor_and_exposed_use_skin() -> void:
	var a := FighterArt.new(0, 5, "samurai")
	var torso := _mesh_with(["skin", "cloth"])
	a._tint(torso, true, false)
	assert_true(torso.get_surface_override_material(0) == a._armor, "covered skin -> armor")
	assert_true(torso.get_surface_override_material(1) == a._cloth)
	var arm := _mesh_with(["skin", "cloth"])
	a._tint(arm, false, false)
	assert_true(arm.get_surface_override_material(0) == a._skin, "exposed skin -> skin tone")
	torso.free()
	arm.free()


func test_own_art_skin_and_team_cloth() -> void:
	var a := FighterArt.new(0, 5, "samurai")
	var m := _mesh_with(["skin", "cloth", "lacquer_red"])
	a._tint(m, true, true)
	assert_true(m.get_surface_override_material(0) == a._skin, "samurai skin surface takes the skin tone")
	assert_eq(a._skin.albedo_color, BodyLook.skin_color(5, 0))
	assert_true(m.get_surface_override_material(1) == a._team, "cloth takes the team colour")
	assert_eq(a._team.albedo_color, BodyLook.cloth_color(0))
	assert_true(m.get_surface_override_material(2) == null, "other surfaces keep the glb material")
	m.free()


func test_alien_surfaces_never_take_skin_tone() -> void:
	var a := FighterArt.new(0, 5, "alien")
	var m := _mesh_with(["alien_skin", "alien_chitin", "alien_eye"])
	a._tint(m, true, true)
	var sk: Material = m.get_surface_override_material(0)
	assert_true(sk != null and sk != a._skin, "alien_skin has its own override")
	assert_true(m.get_surface_override_material(1) == null)
	var eye: StandardMaterial3D = m.get_surface_override_material(2) as StandardMaterial3D
	assert_true(eye != null and eye.roughness < 0.1 and eye.albedo_color.v < 0.01, "glossy black eyes")
	m.free()


func test_cap_surfaces_use_blood_palette() -> void:
	var al := FighterArt.new(0, 5, "alien")
	var m := _mesh_with(["alien_flesh", "alien_fat", "alien_bone", "alien_skin"])
	al._tint(m, false, true, true)
	var pal: BloodPalette = OutfitRules.blood_palette("alien")
	assert_eq((m.get_surface_override_material(0) as StandardMaterial3D).albedo_color, pal.flesh)
	assert_eq((m.get_surface_override_material(1) as StandardMaterial3D).albedo_color, pal.fat)
	assert_eq((m.get_surface_override_material(2) as StandardMaterial3D).albedo_color, pal.bone)
	m.free()
	var hu := FighterArt.new(0, 5)
	var h := _mesh_with(["flesh", "skin"])
	hu._tint(h, false, false, true)
	assert_eq((h.get_surface_override_material(0) as StandardMaterial3D).albedo_color, BloodPalette.red().flesh)
	assert_true(h.get_surface_override_material(1) == hu._skin, "cap skin ring keeps the skin tone")
	h.free()


func test_shows_armor_rule() -> void:
	assert_true(OutfitRules.art_shows_armor("samurai", "torso"))
	assert_true(OutfitRules.art_shows_armor("samurai", "pelvis"))
	assert_false(OutfitRules.art_shows_armor("alien", "torso"))
	assert_false(OutfitRules.art_shows_armor("default", "torso"))


func _mesh_with(names: Array) -> MeshInstance3D:
	var am := ArrayMesh.new()
	for n: String in names:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := StandardMaterial3D.new()
		mat.resource_name = n
		am.surface_set_material(am.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	return mi


func test_cap_face_discs_use_palette() -> void:
	var red := FighterArt.new(0, 5)
	var holder := Node3D.new()
	red._cap_face(holder, 0.06)
	assert_eq(holder.get_child_count(), FighterArt.CAP_DISCS.size())
	var flesh: MeshInstance3D = holder.get_node("Disc_flesh") as MeshInstance3D
	var m: StandardMaterial3D = flesh.material_override as StandardMaterial3D
	assert_true(m.albedo_color.r > m.albedo_color.g * 3.0, "red flesh")
	assert_false(m.emission_enabled)
	holder.free()
	var alien := FighterArt.new(1, 9, "alien")
	var h2 := Node3D.new()
	alien._cap_face(h2, 0.06)
	var am: StandardMaterial3D = (h2.get_node("Disc_flesh") as MeshInstance3D).material_override as StandardMaterial3D
	assert_true(am.albedo_color != m.albedo_color, "ichor tint differs from red")
	h2.free()
