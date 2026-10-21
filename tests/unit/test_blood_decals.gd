extends TestCase


func test_add_creates_and_merges_nearby() -> void:
	var d: BloodDecals = BloodDecals.new(8)
	var a: int = d.add(Vector3(1, 0, 1), 0.01, 0.3)
	var b: int = d.add(Vector3(1.02, 0, 1.01), 0.01, 0.6)
	assert_eq(a, b)
	assert_eq(d.count, 1)
	var c: int = d.add(Vector3(3, 0, 3), 0.01, 0.1)
	assert_true(c != a)
	assert_eq(d.count, 2)


func test_pool_grows_toward_target_and_never_shrinks() -> void:
	var d: BloodDecals = BloodDecals.new(4)
	var s: int = d.add(Vector3.ZERO, 0.5, 0.2)
	assert_true(d.is_pool(s))
	var last: float = d.radius[s]
	for i: int in 300:
		d.step(0.05)
		assert_true(d.radius[s] >= last - 0.00001)
		last = d.radius[s]
	assert_near(d.radius[s], BloodMath.pool_radius(0.5), 0.01)
	d.add(Vector3.ZERO, 2.0, 0.2)
	assert_true(d.target[s] > BloodMath.pool_radius(0.5))


func test_spot_fades_pool_keeps_crust() -> void:
	var d: BloodDecals = BloodDecals.new(4)
	var spot: int = d.add(Vector3(5, 0, 5), 0.002, 0.1)
	var pool: int = d.add(Vector3(-5, 0, -5), 1.0, 0.1)
	assert_false(d.is_pool(spot))
	for i: int in 30:
		d.step(5.0)
	assert_near(d.alpha_of(spot), 0.0, 0.001)
	assert_true(d.alpha_of(pool) > 0.5)
	assert_true(d.buf[pool * BloodDecals.STRIDE + 12] > 0.85, "dried")


func test_full_pool_recycles_oldest_and_keeps_count() -> void:
	var d: BloodDecals = BloodDecals.new(3)
	for i: int in 7:
		d.add(Vector3(float(i) * 2.0, 0, 0), 0.01, 0.5)
	assert_eq(d.count, 3)
	assert_eq(d._cells.size(), 3)


func test_fresh_blood_refreshes_colour() -> void:
	var d: BloodDecals = BloodDecals.new(2)
	var s: int = d.add(Vector3.ZERO, 0.3, 0.2)
	for i: int in 40:
		d.step(5.0)
	var old_dry: float = BloodMath.dryness(d.age[s])
	d.add(Vector3.ZERO, 0.3, 0.2)
	assert_true(BloodMath.dryness(d.age[s]) < old_dry)


func test_feed_keeps_one_growing_pool() -> void:
	var d: BloodDecals = BloodDecals.new(8)
	var slot: int = -1
	for i: int in 40:
		slot = d.feed(slot, Vector3(0, 0, 0), 0.05, 0.3)
	assert_eq(d.count, 1)
	assert_near(d.target[slot], BloodMath.pool_radius(2.0), 0.001)
	var other: int = d.feed(slot, Vector3(3, 0, 0), 0.05, 0.3)
	assert_true(other != slot)
