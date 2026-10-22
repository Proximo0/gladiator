extends TestCase
## ArenaDressing's material fix-ups and the textured weapon rack.


func _iron(textured: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = ArenaDressing.IRON_MATERIAL
	m.metallic = 1.0
	m.roughness = 0.55
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if textured:
		m.roughness_texture = PlaceholderTexture2D.new()
	return m


## Houdini's iron (metallic 1, roughness 0.55) mirrored the sky's blue top on every up face; it becomes matte half metal.
func test_iron_is_matte_half_metal_on_both_copies() -> void:
	for textured: bool in [false, true]:
		var o := ArenaDressing.opaque_material(_iron(textured), Color.WHITE) as BaseMaterial3D
		assert_eq(o.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
		assert_near(o.metallic, ArenaDressing.IRON_METALLIC)
		var effective: float = o.roughness * (ArenaDressing.ORM_METAL_G_MEAN if textured else 1.0)
		assert_near(effective, ArenaDressing.IRON_ROUGHNESS, 0.001, "effective roughness (textured=%s)" % textured)
		assert_true(o.albedo_color.v < 0.7, "iron darkened")


func test_other_materials_keep_their_metal() -> void:
	var m := StandardMaterial3D.new()
	m.resource_name = "bronze"
	m.metallic = 1.0
	m.roughness = 0.45
	var o := ArenaDressing.opaque_material(m, Color.WHITE) as BaseMaterial3D
	assert_near(o.metallic, 1.0)
	assert_near(o.roughness, 0.45)


## The rack loads its textured copy (wood grain, iron maps) like every other art loader.
func test_rack_uses_the_textured_copy() -> void:
	var d := ArenaDressing.new()
	var m: Mesh = d.mesh("weapon_rack")
	assert_true(m != null, "rack mesh")
	var textured: int = 0
	for s: int in m.get_surface_count():
		var mat := m.surface_get_material(s) as BaseMaterial3D
		if mat != null and mat.albedo_texture != null:
			textured += 1
	assert_eq(textured, m.get_surface_count(), "every rack surface textured")
