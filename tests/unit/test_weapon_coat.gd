extends TestCase


func test_coat_grows_with_bleeding_hits_and_caps() -> void:
	var c: WeaponCoat = WeaponCoat.new()
	assert_false(c.is_bloody())
	c.add_hit(Vector3(0, 0.5, 0), 10.0, 0.0, 0.0, 1)
	var one: float = c.coat
	assert_true(one > 0.0)
	assert_eq(c.slot, 1)
	c.add_hit(Vector3(0, 0.3, 0), 10.0, 0.0, 0.0, 0)
	assert_true(c.coat > one)
	assert_eq(c.slot, 0, "the last victim's blood colours it")
	for i: int in 50:
		c.add_hit(Vector3(0, 0.1 * float(i % 6), 0), 40.0, 0.0, 0.0, 0)
	assert_near(c.coat, 1.0)
	assert_true(c.blots.size() <= WeaponCoat.MAX_BLOTS)


func test_taps_leave_the_weapon_clean() -> void:
	var c: WeaponCoat = WeaponCoat.new()
	c.add_hit(Vector3.ZERO, 0.5, 0.2, 1.0, 0)
	assert_false(c.is_bloody())


func test_blunt_hits_bloody_knuckles_slowly() -> void:
	var c: WeaponCoat = WeaponCoat.new()
	c.add_hit(Vector3(0, 0.02, 0.05), 0.0, 0.0, 20.0, 0)
	assert_true(c.is_bloody())
	var blunt: float = c.coat
	var s: WeaponCoat = WeaponCoat.new()
	s.add_hit(Vector3(0, 0.02, 0.05), 20.0, 0.0, 0.0, 0)
	assert_true(s.coat > blunt)


func test_blots_merge_and_dry() -> void:
	var c: WeaponCoat = WeaponCoat.new()
	c.add_hit(Vector3(0, 0.5, 0), 10.0, 0.0, 0.0, 0)
	c.add_hit(Vector3(0.01, 0.51, 0), 10.0, 0.0, 0.0, 0)
	assert_eq(c.blots.size(), 1)
	assert_near(c.dryness(), 0.0)
	c.step(60.0)
	assert_true(c.dryness() > 0.5)
	var pk: Dictionary = c.pack()
	assert_eq(int(pk["count"]), 1)
	assert_eq((pk["blots"] as PackedVector4Array).size(), WeaponCoat.MAX_BLOTS)


func test_coat_shape_by_weapon_kind() -> void:
	var sword: Dictionary = WoundFx.coat_shape({"shape": "sword", "length": 0.9, "edge_len": 0.6}, Vector3(0, 0.75, 0))
	assert_eq(int(sword["mode"]), 0)
	assert_near(float(sword["base_y"]), 0.15, 0.001)
	assert_true(float(sword["edge_x"]) > 0.0)
	assert_eq(int(WoundFx.coat_shape({"shape": "club", "length": 0.8}, Vector3(0, 0.7, 0))["mode"]), 1)
	assert_eq(int(WoundFx.coat_shape({"shape": "shield", "length": 0.6}, Vector3(0, 0.3, 0.05))["mode"]), 2)
	assert_eq(int(WoundFx.coat_shape({"shape": "fist", "length": 0.1}, Vector3(0, 0.03, 0))["mode"]), 3)
