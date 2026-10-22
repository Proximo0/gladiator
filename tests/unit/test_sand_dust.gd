extends TestCase


func test_cloud_drifts_and_expires() -> void:
	var d: SandDust = SandDust.new(50, 1)
	d.cloud(Vector3.ZERO, Vector3.UP, 1.0, 20, 0.1, 0.4, 2.0, 0.2)
	assert_eq(d.count, 20)
	for i in range(60):
		d.step(1.0 / 60.0)
	assert_true(d.count > 0)
	for i in range(400):
		d.step(1.0 / 60.0)
	assert_eq(d.count, 0)


func test_pool_never_overflows() -> void:
	var d: SandDust = SandDust.new(10, 2)
	d.cloud(Vector3.ZERO, Vector3.UP, 1.0, 100, 0.1, 0.4, 2.0, 0.2)
	assert_eq(d.count, 10)


func test_fade_and_buffer() -> void:
	var d: SandDust = SandDust.new(4, 3)
	d.add(Vector3(1, 2, 3), Vector3.ZERO, 0.1, 0.5, 2.0, 0.3)
	assert_near(d.fade_of(0), 0.0, 0.001, "starts invisible")
	d.step(0.4)
	assert_true(d.fade_of(0) > 0.3, "fades in")
	d.step(1.5)
	assert_true(d.fade_of(0) < 0.05, "fades out")
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(4 * SandDust.FLOATS_PER_SPRITE)
	assert_eq(d.fill_buffer(buf, Color.WHITE), 1)
	assert_true(buf[0] > 0.1 and buf[0] <= 0.5, "size grows")


func test_same_seed_same_dust() -> void:
	var a: SandDust = SandDust.new(20, 9)
	var b: SandDust = SandDust.new(20, 9)
	a.cloud(Vector3.ZERO, Vector3.RIGHT, 2.0, 10, 0.1, 0.3, 2.0, 0.2)
	b.cloud(Vector3.ZERO, Vector3.RIGHT, 2.0, 10, 0.1, 0.3, 2.0, 0.2)
	a.step(0.1)
	b.step(0.1)
	assert_eq(a.position_of(5), b.position_of(5))
