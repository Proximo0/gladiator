extends TestCase


func test_burst_arcs_and_lands() -> void:
	var fx: SandFx = SandFx.new(100, 1)
	fx.burst(Vector3.ZERO, Vector3.UP, 4.0, 40)
	assert_eq(fx.count, 40)
	var peak: float = 0.0
	for i in range(30):
		fx.step(1.0 / 60.0)
		for k in range(fx.count):
			peak = maxf(peak, fx.position_of(k).y)
	assert_true(peak > 0.3, "grains rise, peak %f" % peak)
	for i in range(200):
		fx.step(1.0 / 60.0)
	assert_eq(fx.flying_count(), 0)
	assert_true(fx.landed_total > 20, "landed %d" % fx.landed_total)


func test_landed_grains_expire() -> void:
	var fx: SandFx = SandFx.new(50, 2)
	fx.kick(Vector3.ZERO, Vector3.RIGHT, 3.0, 20)
	for i in range(400):
		fx.step(1.0 / 60.0)
	assert_eq(fx.count, 0)


func test_ground_callback_is_respected() -> void:
	var fx: SandFx = SandFx.new(50, 3)
	fx.set_ground(func(_p: Vector3) -> float: return 0.5)
	fx.burst(Vector3(0, 1, 0), Vector3.UP, 1.0, 10)
	for i in range(300):
		fx.step(1.0 / 60.0)
		for k in range(fx.count):
			assert_true(fx.position_of(k).y >= 0.5, "grain below the ground")


func test_pool_never_overflows() -> void:
	var fx: SandFx = SandFx.new(30, 4)
	fx.fountain(Vector3.ZERO, 0.1, 3.0, 100)
	assert_eq(fx.count, 30)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(30 * SandFx.FLOATS_PER_GRAIN)
	assert_eq(fx.fill_buffer(buf, Color(0.6, 0.4, 0.2)), 30)


func test_same_seed_same_grains() -> void:
	var a: SandFx = SandFx.new(40, 9)
	var b: SandFx = SandFx.new(40, 9)
	a.fountain(Vector3.ZERO, 0.2, 2.0, 25)
	b.fountain(Vector3.ZERO, 0.2, 2.0, 25)
	for i in range(20):
		a.step(0.02)
		b.step(0.02)
	assert_eq(a.position_of(7), b.position_of(7))
