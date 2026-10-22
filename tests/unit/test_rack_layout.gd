extends TestCase
## RackLayout: what each arena rack holds and how it stands.


func _ids(items: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for it: Dictionary in items:
		out.append(str(it["id"]))
	return out


func test_own_weapon_first_and_shield_extra() -> void:
	var items: Array[Dictionary] = RackLayout.stock({"weapon": "dai_katana", "offhand": "shield_round"}, 0)
	var ids: Array[String] = _ids(items)
	assert_eq(ids[0], "dai_katana", "the fighter's own weapon is the first spare, premium or not")
	assert_eq(ids[ids.size() - 1], "shield_round", "its shield leans in front")
	assert_eq(ids.size(), RackLayout.FILL + 1)
	assert_eq(ids.count("dai_katana"), 1)


func test_fillers_are_starters_and_racks_differ() -> void:
	var pool: Array[String] = RackLayout.filler_pool()
	assert_true(pool.size() >= RackLayout.FILL, "enough starters to fill a rack")
	for id: String in pool:
		assert_false(LoadoutRules.is_shield(id))
		assert_false(LoadoutRules.is_premium_weapon(id))
		assert_false(WeaponUnlocks.is_unlockable(id))
		assert_true(id != "fists")
	var a: Array[String] = _ids(RackLayout.stock({}, 0))
	var b: Array[String] = _ids(RackLayout.stock({}, 1))
	assert_eq(a.size(), RackLayout.FILL)
	assert_true(a != b, "the two racks are stocked differently")


func test_fists_and_low_fill() -> void:
	var ids: Array[String] = _ids(RackLayout.stock({"weapon": "fists"}, 1, RackLayout.FILL_LOW))
	assert_eq(ids.size(), RackLayout.FILL_LOW)
	assert_false(ids.has("fists"))


func test_long_weapons_stand_in_the_cup_and_short_ones_hang() -> void:
	var spear: Dictionary = CombatData.weapon("spear")
	var xf: Transform3D = RackLayout.slot_pose(spear, 0)
	var butt: Vector3 = xf * Vector3(0, -float(spear["grip_offset"]), 0)
	assert_near(butt.y, RackLayout.CUP_Y, 1e-4, "the butt sits in the cup")
	assert_near(butt.z, RackLayout.CUP_Z, 1e-4)
	assert_near(butt.x, RackLayout.SLOT_X[0], 1e-4)
	assert_true(xf.basis.y.y > 0.99, "standing tip-up")
	var gladius: Dictionary = CombatData.weapon("gladius")
	var g: Transform3D = RackLayout.slot_pose(gladius, 3)
	var tip: Vector3 = g * Vector3(0, float(gladius["length"]) - float(gladius["grip_offset"]), 0)
	assert_true(g.basis.y.y < -0.99, "hung tip-down")
	assert_true(tip.y > 0.3, "the tip clears the butt rail")
	assert_near(g.basis.z.z, 1.0, 1e-4, "flat toward the arena")


func test_shield_rests_on_the_sand_facing_out() -> void:
	for id: String in ["shield_round", "tower_shield", "aspis", "kite_shield"]:
		var d: Dictionary = CombatData.weapon(id)
		var xf: Transform3D = RackLayout.shield_pose(d)
		var face: Vector3 = xf * Weapon.face_center(d)
		assert_true(face.y > 0.1 and face.y < 1.0, id + " face centre at a sensible height")
		assert_true(xf.basis.z.z > 0.9, id + " faces the arena")
		assert_true(xf.basis.z.y > 0.0, id + " leans back on the rack")
