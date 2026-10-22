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


class _SideFighter extends Node3D:
	var side: int = 0
	var parts: Dictionary = {}


func test_palettes_reach_the_materials_and_droplets_keep_their_blood() -> void:
	var fx: BloodFx = BloodFx.new()
	fx.auto_step = false
	fx._build()
	fx.set_palette(1, OutfitRules.blood_palette("alien"))
	var red: Color = fx.palette_of(0).drop_bright()
	var ichor: Color = fx.palette_of(1).drop_bright()
	assert_eq(fx._drop_mat.get_shader_parameter("blood_bright"), red)
	assert_eq(fx._drop_mat.get_shader_parameter("blood_bright1"), ichor)
	assert_true(ichor.g > ichor.r * 3.0 and red.r > red.g * 10.0)
	var stain: Color = (((fx._stain_mats[1] as Array)[0] as Array)[0] as ShaderMaterial).get_shader_parameter("blood_color")
	assert_true(stain.g > stain.r, "ichor stain is green-blue")
	stain = (((fx._stain_mats[0] as Array)[0] as Array)[0] as ShaderMaterial).get_shader_parameter("blood_color")
	assert_true(stain.r > stain.g, "red stain is red")
	# Droplets of each colour land: each leaves a decal of its own colour.
	fx.sim.emit(Vector3(-1, 0.02, 0), Vector3(0, -2, 0), 0.006, 1.0, 5.0, 0.5, 0)
	fx.sim.emit(Vector3(1, 0.02, 0), Vector3(0, -2, 0), 0.006, 1.0, 5.0, 0.5, 1)
	fx.step(0.02)
	assert_eq(fx.decals.count, 2)
	var seen: Array = []
	for i: int in fx.decals.count:
		seen.append(int(fx.decals.slots[i]) * 10 + (0 if fx.decals.pos[i].x < 0.0 else 1))
	seen.sort()
	assert_eq(seen, [0, 11])
	fx.free()


func test_tracked_fighter_slot_follows_its_side() -> void:
	var fx: BloodFx = BloodFx.new()
	var a: _SideFighter = _SideFighter.new()
	var b: _SideFighter = _SideFighter.new()
	b.side = 1
	fx.track(a)
	fx.track(b)
	assert_eq(fx._slot_of(a), 0)
	assert_eq(fx._slot_of(b), 1)
	assert_eq(fx._slot_of(null), 0)
	a.free()
	b.free()
	fx.free()
