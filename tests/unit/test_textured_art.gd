extends TestCase
## Textured Houdini art (assets/textured/, TexturedArt): loaders pick the textured copy when there is one and fall back
## to the untextured file; the copies share the VRAM-compressed library textures instead of embedding their own.


func test_path_prefers_the_textured_copy() -> void:
	assert_eq(TexturedArt.path("res://assets/weapons/longsword.glb"), "res://assets/textured/weapons/longsword.glb")
	assert_eq(TexturedArt.path("res://assets/armor/scutum.glb"), "res://assets/textured/armor/scutum.glb")
	assert_eq(TexturedArt.path("res://assets/gore/liver.glb"), "res://assets/textured/gore/liver.glb")
	assert_eq(TexturedArt.path("res://assets/textured/weapons/axe.glb"), "res://assets/textured/weapons/axe.glb")


func test_path_falls_back_and_keeps_the_laser_sword_plain() -> void:
	assert_eq(TexturedArt.path("res://assets/weapons/laser_sword.glb"), "res://assets/weapons/laser_sword.glb")
	assert_eq(TexturedArt.path("res://assets/body/torso.glb"), "res://assets/body/torso.glb", "no textured copy")
	assert_eq(TexturedArt.path("res://other/x.glb"), "res://other/x.glb")
	TexturedArt.enabled = false
	assert_eq(TexturedArt.path("res://assets/weapons/longsword.glb"), "res://assets/weapons/longsword.glb", "switch off")
	assert_true(TexturedArt.library("organic_normal") == null)
	TexturedArt.enabled = true


## Every textured copy loads, opaque, with its textures from the shared library (one copy of each in memory). A few
## materials have no texture family (the brazier's ember) and stay flat.
func test_copies_use_the_shared_library() -> void:
	var dirs: PackedStringArray = ["armor", "decor", "dressing", "gore", "weapons"]
	var seen: int = 0
	var textured: int = 0
	for d: String in dirs:
		for f: String in ResourceLoader.list_directory(TexturedArt.DIR + d):
			if not f.ends_with(".glb"):
				continue
			var root: Node = (load(TexturedArt.DIR + d + "/" + f) as PackedScene).instantiate()
			for n: Node in root.find_children("*", "MeshInstance3D", true, false):
				var m: Mesh = (n as MeshInstance3D).mesh
				for s: int in m.get_surface_count():
					var mat: BaseMaterial3D = m.surface_get_material(s) as BaseMaterial3D
					assert_true(mat != null, "%s surface %d has a material" % [f, s])
					if mat == null:
						continue
					assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, f + " opaque")
					for t: Texture2D in [mat.albedo_texture, mat.normal_texture]:
						assert_true(t == null or t.resource_path.begins_with(TexturedArt.LIBRARY),
								"%s/%s textures from the library" % [f, mat.resource_name])
					textured += 1 if mat.albedo_texture != null else 0
			root.free()
			seen += 1
	assert_eq(seen, 37, "37 textured models")
	assert_true(textured >= 60, "nearly every surface is textured (%d)" % textured)


func test_library_textures_are_vram_compressed() -> void:
	for n: String in ["metal_normal", "steel_albedo", "organic_orm"]:
		var t: Texture2D = TexturedArt.library(n)
		assert_true(t != null, n + " loads")
		var img: Image = t.get_image()
		assert_true(img.is_compressed(), n + " is VRAM compressed")
		assert_true(img.has_mipmaps(), n + " has mipmaps")


func test_gut_pieces_carry_uvs_and_tangents_for_the_organic_maps() -> void:
	var m: Mesh = GutArt.mesh(GutSim.K_LINK)
	var arr: Array = m.surface_get_arrays(0)
	assert_true(arr[Mesh.ARRAY_TEX_UV] is PackedVector2Array and (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0)
	assert_true(arr[Mesh.ARRAY_TANGENT] is PackedFloat32Array and (arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() > 0)
	var mat: BaseMaterial3D = GutArt.material()
	assert_true(mat.vertex_color_use_as_albedo, "the blood palette still tints the spill")
	assert_true(mat.normal_enabled and mat.normal_texture != null)


## Godot's ORMMaterial3D shader reads roughness and metallic straight from the map and ignores both factors (every
## metal rendered at roughness ~0.9, fully metallic), so the library materials feed the ORM map through channel selects
## on a StandardMaterial3D. Metals keep tools/textured_import.py's roughness floor (below it they mirror the blue sky).
func test_library_materials_apply_their_roughness_and_metallic() -> void:
	var metals: int = 0
	for f: String in ResourceLoader.list_directory(TexturedArt.DIR + "materials"):
		if not f.ends_with(".tres"):
			continue
		var mat: BaseMaterial3D = load(TexturedArt.DIR + "materials/" + f) as BaseMaterial3D
		assert_false(mat is ORMMaterial3D, f + " is not an ORM material")
		if mat.roughness_texture != null:
			assert_eq(mat.roughness_texture_channel, BaseMaterial3D.TEXTURE_CHANNEL_GREEN, f + " roughness from G")
			assert_eq(mat.metallic_texture_channel, BaseMaterial3D.TEXTURE_CHANNEL_BLUE, f + " metallic from B")
		if mat.metallic >= 0.9:
			metals += 1
			assert_true(mat.roughness * 0.9 >= 0.45 - 0.001, "%s rough enough (%.3f)" % [f, mat.roughness])
	assert_true(metals >= 5, "metals checked (%d)" % metals)
