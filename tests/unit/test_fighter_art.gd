extends TestCase
## FighterArt cut caps: prebuilt caps (prebuild_step) are the ones a cut attaches, placed exactly as caps built in the
## frame of the cut, and unused prebuilt caps are freed with the fighter.


func _fighter(side: int) -> Fighter:
	var f := Fighter.new()
	f.look_seed = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(f)  ## world transforms need a tree
	f.setup({"weapon": "fists", "offhand": "", "armor": {}}, side, Tuning.shared())
	return f


func _prebuild_all(f: Fighter) -> int:
	var steps: int = 0
	while f._art.prebuild_step(f.parts):
		steps += 1
		if steps > 100:
			break
	return steps


func test_prebuild_builds_every_cut_cap_once() -> void:
	var f: Fighter = _fighter(0)
	var steps: int = _prebuild_all(f)
	assert_eq(steps, f._art._ready_caps.size(), "one cap per step")
	assert_true(f._art._ready_caps.has("head_piece") and f._art._ready_caps.has("head_stump"))
	assert_false(f._art._ready_caps.has("torso_piece"), "the torso is never cut off")
	assert_false(f._art.prebuild_step(f.parts), "nothing left to build")
	f.free()


func test_cut_attaches_the_prebuilt_caps() -> void:
	var f: Fighter = _fighter(0)
	_prebuild_all(f)
	var ready: Node3D = f._art._ready_caps["forearm_l_piece"]
	f._art.cut(f.parts, "forearm_l")
	assert_eq(f._art._caps["forearm_l_piece"], ready, "the prebuilt cap is used")
	assert_true(ready.is_inside_tree())
	assert_eq(ready.get_parent(), (f.parts["forearm_l"] as Node3D).get_node("Look"))
	assert_false(f._art._ready_caps.has("forearm_l_piece"))
	f.free()


func test_prebuilt_caps_sit_where_built_caps_sit() -> void:
	var a: Fighter = _fighter(0)
	var b: Fighter = _fighter(0)
	_prebuild_all(a)
	for n: String in ["head", "shin_r"]:
		a._art.cut(a.parts, n)
		b._art.cut(b.parts, n)
		for k: String in [n + "_piece", n + "_stump"]:
			var ta: Transform3D = (a._art._caps[k] as Node3D).transform
			var tb: Transform3D = (b._art._caps[k] as Node3D).transform
			assert_true(ta.is_equal_approx(tb), "%s placed the same" % k)
	a.free()
	b.free()


func test_unused_prebuilt_caps_are_freed_with_the_fighter() -> void:
	var f: Fighter = _fighter(1)
	_prebuild_all(f)
	var left: Node3D = f._art._ready_caps["head_piece"]
	f.free()
	assert_false(is_instance_valid(left))


func test_gore_faces_share_one_material() -> void:
	var f: Fighter = _fighter(0)
	f._art.cut(f.parts, "head")
	f._art.cut(f.parts, "forearm_r")
	var mats: Array = []
	for k: String in ["head_piece", "head_stump", "forearm_r_piece"]:
		mats.append(((f._art._caps[k] as Node3D).get_node("Face") as MeshInstance3D).material_override)
	assert_true(mats[0] != null and mats[0] == mats[1] and mats[1] == mats[2])
	f.free()
