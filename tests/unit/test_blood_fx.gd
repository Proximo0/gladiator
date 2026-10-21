extends TestCase


class _FakeFighter extends Node3D:
	var parts: Dictionary = {}


func test_part_node_resolves_through_parts_dictionary() -> void:
	var fx: BloodFx = BloodFx.new()
	var f: _FakeFighter = _FakeFighter.new()
	var torso: Node3D = Node3D.new()
	f.parts["torso"] = torso
	assert_true(fx._part_node(f, "torso") == torso)
	assert_true(fx._part_node(f, "head") == null)
	assert_true(fx._part_node(null, "torso") == null)
	assert_true(fx._part_node(f, "") == null)
	torso.free()
	f.free()
	fx.free()


func test_droplet_mesh_is_rounded_and_has_white_vertex_colours() -> void:
	var mesh: ArrayMesh = BloodMesh.teardrop(7)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(cols.size(), verts.size())
	for c: Color in cols:
		assert_eq(c, Color.WHITE)
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n: Vector3 in norms:
		assert_near(n.length(), 1.0, 0.001)
	var zmin: float = 0.0
	var zmax: float = 0.0
	for v: Vector3 in verts:
		zmin = minf(zmin, v.z)
		zmax = maxf(zmax, v.z)
		assert_true(Vector2(v.x, v.y).length() <= 1.001)
	assert_near(zmax, 1.0, 0.001)
	assert_near(zmin, -1.0, 0.001)


func test_quality_changes_decal_and_stain_budgets_in_order() -> void:
	for q: int in 2:
		assert_true(BloodMath.decal_budget(q + 1) > BloodMath.decal_budget(q))
		assert_true(BloodMath.budget(q + 1) > BloodMath.budget(q))
		assert_true(BloodMath.mist_budget(q + 1) > BloodMath.mist_budget(q))
