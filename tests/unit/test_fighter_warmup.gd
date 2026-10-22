extends TestCase
## FighterWarmup runs once per session and never in headless runs (nothing is drawn there).


func test_headless_or_done_starts_nothing() -> void:
	var was: bool = FighterWarmup.done
	FighterWarmup.done = false
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	assert_eq(FighterWarmup.start(root), null, "headless: no warm-up")
	FighterWarmup.done = true
	assert_eq(FighterWarmup.start(root), null, "already done")
	assert_eq(FighterWarmup.start(null), null)
	FighterWarmup.done = was


func test_keep_collects_each_material_once() -> void:
	var w := FighterWarmup.new()
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	for i: int in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = mat
		n.add_child(mi)
	var before: int = FighterWarmup._kept.size()
	w._keep(n)
	assert_eq(FighterWarmup._kept.size(), before + 1)
	FighterWarmup._kept.erase(mat)
	n.free()
	w.free()
