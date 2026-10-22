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


class _DummyHealth extends RefCounted:
	var blood: float = 2.0  ## below the death line: a normal arterial spurt would stop at once
	var dead: bool = true


class _BeheadFighter extends Node3D:
	var side: int = 1
	var health: _DummyHealth = _DummyHealth.new()
	var torso: Node3D = Node3D.new()
	var head: Node3D = Node3D.new()


func _beheaded(quality: int) -> Array:
	var fx: BloodFx = BloodFx.new()
	fx.auto_step = false
	fx._build()
	fx.set_quality(quality)
	fx.set_palette(1, OutfitRules.blood_palette("alien"))
	var f: _BeheadFighter = _BeheadFighter.new()
	f.add_child(f.torso)
	f.add_child(f.head)
	(Engine.get_main_loop() as SceneTree).root.add_child(f)  ## world transforms need a tree
	f.torso.position = Vector3(0, 1.3, 0)
	fx.track(f)
	fx.on_gore({"kind": "behead", "part": "head", "point": Vector3(0, 1.6, 0), "normal": Vector3.UP, "amount": 1.0}, f)
	return [fx, f]


func test_behead_fountain_runs_without_touching_the_fighters_blood() -> void:
	var pair: Array = _beheaded(1)
	var fx: BloodFx = pair[0]
	var f: _BeheadFighter = pair[1]
	var peak: int = 0
	for i: int in 120:
		fx.step(1.0 / 60.0)
		peak = maxi(peak, fx.live_droplets())
	assert_true(peak > 300, "a dead fighter with blood below the death line still fountains")
	assert_near(f.health.blood, 2.0)
	assert_true(f.health.dead)
	assert_true(fx._spurts.size() >= 1, "still running after 2 s")
	for i: int in 60 * 10:
		fx.step(1.0 / 60.0)
	assert_eq(fx._spurts.size(), 0, "the fountain tapers off and ends")
	f.free()
	fx.free()


func test_behead_fountain_scales_down_at_low_quality_and_respects_the_pool() -> void:
	var peaks: Array[int] = []
	for q: int in 3:
		var pair: Array = _beheaded(q)
		var fx: BloodFx = pair[0]
		var peak: int = 0
		for i: int in 90:
			fx.step(1.0 / 60.0)
			peak = maxi(peak, fx.live_droplets())
		assert_true(peak <= fx.sim.capacity)
		peaks.append(peak)
		(pair[1] as Node).free()
		fx.free()
	assert_true(peaks[0] < peaks[1], "low quality emits less")
	assert_true(peaks[0] <= BloodMath.budget(0))


func test_behead_fountain_droplets_carry_the_victims_palette_slot() -> void:
	var pair: Array = _beheaded(1)
	var fx: BloodFx = pair[0]
	for i: int in 20:
		fx.step(1.0 / 60.0)
	var alien: int = 0
	for i: int in fx.sim.count:
		if fx.sim.slot_of(i) == 1:
			alien += 1
	assert_true(alien > 100)
	assert_eq(alien, fx.sim.count, "every droplet of the fountain is the fighter's own colour")
	(pair[1] as Node).free()
	fx.free()


class _GutFighter extends Node3D:
	var side: int = 1
	var health: _DummyHealth = _DummyHealth.new()
	var torso: Node3D = Node3D.new()


func _gutted(kind: String, quality: int) -> Array:
	var fx: BloodFx = BloodFx.new()
	fx.auto_step = false
	fx._build()
	fx.set_quality(quality)
	fx.set_palette(1, OutfitRules.blood_palette("alien"))
	var f: _GutFighter = _GutFighter.new()
	f.add_child(f.torso)
	(Engine.get_main_loop() as SceneTree).root.add_child(f)
	f.torso.position = Vector3(0, 1.2, 0)
	fx.track(f)
	fx.on_gore({"kind": kind, "part": "torso", "point": Vector3(0, 1.2, 0.2), "normal": Vector3(0, 0, 1), "amount": 1.0}, f)
	return [fx, f]


func test_gut_spills_strings_and_chunks_without_touching_blood() -> void:
	var pair: Array = _gutted("gut", 1)
	var fx: BloodFx = pair[0]
	var f: _GutFighter = pair[1]
	assert_true(fx.guts.rope_count() >= 2)
	assert_true(fx.guts.blob_count() >= 2)
	var peak: int = 0
	for i: int in 120:
		fx.step(1.0 / 60.0)
		peak = maxi(peak, fx.live_droplets())
	assert_true(peak > 300, "a big gush")
	assert_near(f.health.blood, 2.0)
	for i: int in 60 * 8:
		fx.step(1.0 / 60.0)
	assert_eq(fx._spurts.size(), 0, "the gush ends")
	assert_true(fx.guts.rope_count() >= 2, "the guts stay on the sand")
	f.free()
	fx.free()


func test_run_through_gushes_from_both_sides_and_spills_guts() -> void:
	var pair: Array = _gutted("run_through", 1)
	var fx: BloodFx = pair[0]
	var kinds: Array = []
	for s: Variant in fx._spurts:
		kinds.append(s.kind)
	assert_true(kinds.has("gut") and kinds.has("gut_exit"), "entry and exit")
	var exit_s: Variant = fx._spurts[1]
	var entry_s: Variant = fx._spurts[0]
	assert_true(exit_s.ldir.z < 0.0 and entry_s.ldir.z > 0.0, "the exit points the other way")
	assert_true(fx.guts.rope_count() >= 2)
	(pair[1] as Node).free()
	fx.free()


func test_gut_spill_scales_with_quality_and_respects_caps() -> void:
	var ropes: Array[int] = []
	for q: int in 3:
		var pair: Array = _gutted("gut", q)
		var fx: BloodFx = pair[0]
		ropes.append(fx.guts.rope_count())
		for k: int in 6:
			fx.on_gore({"kind": "gut", "part": "torso", "point": Vector3(0, 1.2, 0.2), "normal": Vector3(0, 0, 1), "amount": 1.0}, pair[1])
		assert_true(fx.guts.rope_count() <= fx.guts.rope_cap)
		assert_true(fx.guts.blob_count() <= fx.guts.blob_cap)
		for i: int in 30:
			fx.step(1.0 / 60.0)
		(pair[1] as Node).free()
		fx.free()
	assert_true(ropes[0] < ropes[2], "low quality spills less")


func test_gut_droplets_and_guts_carry_the_victims_slot() -> void:
	var pair: Array = _gutted("run_through", 1)
	var fx: BloodFx = pair[0]
	for i: int in 20:
		fx.step(1.0 / 60.0)
	assert_true(fx.sim.count > 100)
	for i: int in fx.sim.count:
		assert_eq(fx.sim.slot_of(i), 1)
	for r: GutRope in fx.guts.ropes:
		assert_eq(r.slot, 1)
	(pair[1] as Node).free()
	fx.free()


func test_droplet_mesh_detail_drops_with_quality() -> void:
	var tris: Array[int] = []
	for q: int in 3:
		var m: ArrayMesh = BloodMesh.for_quality(q)
		tris.append((m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3)
	assert_eq(tris[2], 336)
	assert_true(tris[0] < tris[1] and tris[1] < tris[2])
	assert_true(tris[0] <= 100)


func test_splat_area_budget_follows_quality() -> void:
	assert_true(BloodMath.splat_area(0) < BloodMath.splat_area(1) and BloodMath.splat_area(1) < BloodMath.splat_area(2))
