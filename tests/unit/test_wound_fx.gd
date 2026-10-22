extends TestCase


class _WfxFighter extends Node3D:
	signal hit(event: Dictionary)
	signal gore(event: Dictionary)
	var side: int = 0
	var parts: Dictionary = {}
	var weapon: Node3D = null
	var offhand: Node3D = null
	var fist_r: Node3D = null
	var fist_l: Node3D = null


class _WfxWeapon extends Node3D:
	var weapon_id: String = "gladius"
	var def: Dictionary = {"shape": "sword", "length": 0.75, "edge_len": 0.5}
	var tip_local: Vector3 = Vector3(0, 0.62, 0)


func _mesh_child(parent: Node, slot: String) -> MeshInstance3D:
	var s := Node3D.new()
	s.name = slot
	parent.add_child(s)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	s.add_child(mi)
	return mi


func _fighter(side: int, z: float) -> _WfxFighter:
	var f := _WfxFighter.new()
	f.side = side
	(Engine.get_main_loop() as SceneTree).root.add_child(f)
	for pn: String in ["torso", "forearm_r", "head"]:
		var b := Node3D.new()
		b.name = pn
		f.add_child(b)
		f.parts[pn] = b
		_mesh_child(b, "Look")
	(f.parts["torso"] as Node3D).global_position = Vector3(0, 1.3, z)
	(f.parts["forearm_r"] as Node3D).global_position = Vector3(0.2, 1.3, z - 0.3 * signf(z))
	(f.parts["head"] as Node3D).global_position = Vector3(0, 1.7, z)
	_mesh_child(f.parts["torso"] as Node, "ArmorSlot")
	var w := _WfxWeapon.new()
	f.add_child(w)
	var wm := MeshInstance3D.new()
	wm.mesh = BoxMesh.new()
	w.add_child(wm)
	f.weapon = w
	return f


func _cut(target: int, attacker: int, point: Vector3) -> Dictionary:
	return {"target": target, "attacker": attacker, "part": "torso", "contact": "edge", "point": point,
		"rel_vel": Vector3(6, 0, 0), "cut": 22.0, "pierce": 0.0, "blunt": 1.0, "weapon_id": "gladius"}


func test_a_cut_marks_the_part_coats_the_blade_and_splashes_the_attacker() -> void:
	var fx: WoundFx = WoundFx.new()
	var a: _WfxFighter = _fighter(0, 0.0)
	var b: _WfxFighter = _fighter(1, 0.5)
	fx.set_palette(1, OutfitRules.blood_palette("alien"))
	fx.track(a)
	fx.track(b)
	a.weapon.global_position = Vector3(0, 1.3, 0.3)
	var p: Vector3 = Vector3(0, 1.3, 0.3)
	for k: int in 40:  ## a contact point whose (deterministic) splash roll comes up
		p = Vector3(0.002 * float(k), 1.3, 0.3)
		if WoundMarks.seed_of(p * 1.7) < WoundFx.SPLASH_CHANCE:
			break
	b.hit.emit(_cut(1, 0, p))
	var wm: WoundMarks = fx.marks_of(1)
	assert_true(wm.count("torso") >= 1, "the victim's torso is cut")
	assert_eq((wm.marks["torso"][0] as WoundMarks.Mark).kind, WoundMarks.Kind.GASH)
	var coat: WeaponCoat = fx.coat_of(a.weapon)
	assert_true(coat != null and coat.coat > 0.0, "the blade got bloody")
	assert_eq(coat.slot, 1, "with the victim's (ichor) blood")
	assert_true(fx.marks_of(0).count("") >= 1, "the attacker is splashed")
	assert_true(fx.stat_shells >= 3, "shells for torso Look, torso ArmorSlot and the weapon")
	var shells: Node = (b.parts["torso"] as Node).get_node_or_null(WoundFx.SHELL_NODE)
	assert_true(shells != null and shells.get_child_count() == 2)
	var mat: ShaderMaterial = (shells.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(int(mat.get_shader_parameter("count")), wm.count("torso"))
	var ichor: Color = mat.get_shader_parameter("fresh1")
	assert_true(ichor.g > ichor.r, "slot 1 draws the alien's ichor colour")
	fx.clear()
	assert_eq(fx.stat_shells, 0)
	a.free()
	b.free()
	fx.free()


func test_weapon_on_weapon_and_taps_leave_no_marks() -> void:
	var fx: WoundFx = WoundFx.new()
	var a: _WfxFighter = _fighter(0, 0.0)
	var b: _WfxFighter = _fighter(1, 0.5)
	fx.track(a)
	fx.track(b)
	var ev: Dictionary = _cut(1, 0, Vector3(0, 1.3, 0.39))
	ev["hit_on_weapon"] = true
	b.hit.emit(ev)
	var tap: Dictionary = _cut(1, 0, Vector3(0, 1.3, 0.39))
	tap["cut"] = 0.4
	tap["blunt"] = 0.5
	b.hit.emit(tap)
	assert_eq(fx.marks_of(1).count(""), 0)
	assert_eq(fx.stat_shells, 0, "no extra draws before the first mark")
	a.free()
	b.free()
	fx.free()


func test_shells_follow_their_source_visibility() -> void:
	var fx: WoundFx = WoundFx.new()
	var a: _WfxFighter = _fighter(0, 0.0)
	var b: _WfxFighter = _fighter(1, 0.5)
	fx.track(a)
	fx.track(b)
	b.hit.emit(_cut(1, 0, Vector3(0, 1.3, 0.39)))
	var torso: Node3D = b.parts["torso"]
	var armor: Node3D = torso.get_node("ArmorSlot") as Node3D
	armor.visible = false  ## knocked off
	fx.step(WoundFx.PUSH_EVERY + 0.01)
	var shells: Node = torso.get_node(WoundFx.SHELL_NODE)
	var hidden: int = 0
	for c: Node in shells.get_children():
		if not (c as MeshInstance3D).visible:
			hidden += 1
	assert_eq(hidden, 1, "the armor's shell hides with it")
	a.free()
	b.free()
	fx.free()


func test_bruises_follow_the_blood_colour() -> void:
	var red: Array = WoundFx.bruise_colors(BloodPalette.red())
	assert_eq(red[0], WoundFx.BRUISE_RED)
	var ichor: Array = WoundFx.bruise_colors(OutfitRules.blood_palette("alien"))
	var c: Color = ichor[0]
	assert_true(c.g > c.r or c.b > c.r, "the alien bruises in its own colour")


func test_drops_leave_streaked_smears_within_the_rate_budget() -> void:
	var fx: WoundFx = WoundFx.new()
	var a: _WfxFighter = _fighter(0, 0.0)
	fx.track(a)
	var tn: Tuning = Tuning.shared()
	var made: int = 0
	for k: int in 40:  ## far apart, so none merge
		var p: Vector3 = Vector3(0.0, 1.1 + 0.02 * float(k % 20), 0.11 * (1.0 if k < 20 else -1.0))
		if fx.add_drop(a, "torso", p, Vector3(0, -6, 0), 0.006, 1):
			made += 1
	assert_eq(made, int(tn.wound_drop_rate), "one second's budget, then nothing")
	fx.step(0.5)
	assert_true(fx.add_drop(a, "torso", Vector3(0.1, 1.3, 0.11), Vector3(0, -6, 0), 0.006, 1), "it refills")
	var wm: WoundMarks = fx.marks_of(0)
	assert_true(wm.count("torso") <= wm.cap)
	var m: WoundMarks.Mark = wm.marks["torso"][0]
	assert_eq(m.kind, WoundMarks.Kind.SMEAR)
	assert_eq(m.slot, 1, "the blood that landed is the other fighter's")
	assert_true(m.stretch > 1.5 and m.width < m.size, "a fast drop streaks")
	assert_false(fx.add_drop(a, "thigh_l", Vector3.ZERO, Vector3.ZERO, 0.006, 0), "an unknown part takes nothing")
	a.free()
	fx.free()


func test_stain_soaks_a_smear_and_pushes_the_readability_uniforms() -> void:
	var fx: WoundFx = WoundFx.new()
	var a: _WfxFighter = _fighter(0, 0.0)
	fx.track(a)
	assert_true(fx.add_stain(a, "torso", Vector3(0, 1.3, 0.11), Vector3.RIGHT, 0.8, 0))
	assert_eq(fx.marks_of(0).count("torso"), 1)
	var shells: Node = (a.parts["torso"] as Node).get_node(WoundFx.SHELL_NODE)
	var mat: ShaderMaterial = (shells.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(int(mat.get_shader_parameter("count")), 1, "a soak pushes at once")
	assert_near(float(mat.get_shader_parameter("core_scale")), Tuning.shared().wound_core_scale, 0.0001)
	assert_near(float(mat.get_shader_parameter("rim_glow")), Tuning.shared().wound_rim_glow, 0.0001)
	var stranger := Node.new()
	assert_false(fx.add_stain(stranger, "torso", Vector3.ZERO, Vector3.RIGHT, 0.8, 0), "untracked fighter")
	stranger.free()
	a.free()
	fx.free()


func test_a_beheading_puts_a_blood_collar_on_both_cut_ends() -> void:
	var fx: WoundFx = WoundFx.new()
	var a: _WfxFighter = _fighter(0, 0.0)
	fx.track(a)
	a.gore.emit({"kind": "behead", "part": "head"})
	var wm: WoundMarks = fx.marks_of(0)
	assert_eq(wm.count("torso"), 1, "the neck stump")
	assert_eq(wm.count("head"), 1, "the head's cut face")
	var neck: WoundMarks.Mark = wm.marks["torso"][0]
	assert_eq(neck.kind, WoundMarks.Kind.RING, "a sever ring, all round the neck")
	assert_true(neck.nrm.y > 0.7, "the stump's ring runs up out of the torso")
	assert_near(neck.size, WoundFx.RING_NECK_R)
	assert_near(neck.width, Tuning.shared().wound_ring_band)
	var under: WoundMarks.Mark = wm.marks["head"][0]
	assert_true(under.nrm.y < -0.7, "the head's runs down")
	a.gore.emit({"kind": "gut", "part": "torso"})
	assert_eq(wm.count(""), 2, "only cuts that sever mark stumps")
	fx.clear()
	a.free()
	fx.free()


func test_stump_ends_are_the_joint_in_both_frames() -> void:
	var ends: Array = WoundFx.stump_ends("forearm_r")
	assert_eq(ends.size(), 2)
	assert_eq(str(ends[0][0]), "upper_arm_r")
	assert_true(((ends[0][1] as Vector3) - Vector3(0, -0.14, 0)).length() < 0.001, "the elbow, below the upper arm")
	assert_true(((ends[1][1] as Vector3) - Vector3(0, 0.17, 0)).length() < 0.001, "the elbow, atop the forearm")
	assert_true(WoundFx.stump_ends("pelvis").is_empty())
	assert_true(WoundFx.ring_radius("forearm_r") > 0.06 and WoundFx.ring_radius("forearm_r") < 0.12,
			"round the forearm, not the whole upper arm: %f" % WoundFx.ring_radius("forearm_r"))
	assert_true(WoundFx.drop_stretch(Vector3.ZERO) == 1.0)
	assert_true(WoundFx.drop_stretch(Vector3(0, 100, 0)) == WoundMarks.STRETCH_MAX)
