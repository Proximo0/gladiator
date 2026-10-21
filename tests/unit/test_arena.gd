extends TestCase


func test_spawn_points_face_centre() -> void:
	var a: Transform3D = Arena.spawn_transform(0, 11.0)
	var b: Transform3D = Arena.spawn_transform(1, 11.0)
	assert_near(a.origin.z, 4.0)
	assert_near(b.origin.z, -4.0)
	assert_near(a.origin.y, 0.0)
	assert_near((-a.basis.z).z, -1.0, 0.001, "side 0 faces -Z")
	assert_near((-b.basis.z).z, 1.0, 0.001, "side 1 faces +Z")


func test_spawn_shrinks_in_small_arena() -> void:
	assert_near(Arena.spawn_transform(0, 6.0).origin.z, 3.0)


func test_radius_from_tuning() -> void:
	var t: Tuning = Tuning.shared()
	var old: float = t.arena_radius
	t.set_value("arena_radius", 8.0)
	var arena := Arena.new()
	arena.radius = t.arena_radius
	assert_near(arena.spawn_point(0).origin.z, 4.0)
	t.set_value("arena_radius", old)
	arena.free()


func test_ring_geometry() -> void:
	var p: Vector3 = Arena.ring_point(10.0, 0.0, 2.0, 48)
	assert_near(p.y, 2.0)
	assert_true(p.x > 10.0, "polygon corner lies outside the apothem")
	var b: Basis = Arena.ring_basis(0.0)
	assert_near(b.z.x, 1.0, 0.001, "local +Z points outward")


func test_flat_dir_and_fallback() -> void:
	assert_near(FightCamera.flat_dir(Vector3.ZERO, Vector3(0, 5, -2)).z, -1.0)
	assert_near(FightCamera.flat_dir(Vector3.ONE, Vector3.ONE).z, -1.0)


func test_follow_pose_is_behind_and_above() -> void:
	var pose: Dictionary = FightCamera.follow_pose(Vector3(0, 0, 4), Vector3(0, 0, -4), 3.0, 2.0, 0.5)
	var pos: Vector3 = pose["pos"]
	assert_near(pos.z, 7.0)
	assert_near(pos.y, 2.0)
	assert_near(pos.x, 0.5, 0.001, "right shoulder")
	var look: Vector3 = pose["look"]
	assert_true(look.z < 4.0, "looks toward the opponent")


func test_wide_distance_grows_with_separation() -> void:
	var near_d: float = FightCamera.wide_distance(2.0, 70.0, 4.0)
	var far_d: float = FightCamera.wide_distance(20.0, 70.0, 4.0)
	assert_true(far_d > near_d)
	assert_true(near_d >= 4.0)


func test_wide_pose_is_side_on() -> void:
	var pose: Dictionary = FightCamera.wide_pose(Vector3(0, 0, 4), Vector3(0, 0, -4), 70.0, 3.0, 6.0)
	var pos: Vector3 = pose["pos"]
	assert_true(absf(pos.x) > 5.0, "off to the side")
	assert_near(pos.z, 0.0, 0.001)


func test_clamp_keeps_camera_inside_wall() -> void:
	var c: Vector3 = FightCamera.clamp_to_arena(Vector3(20, -1, 0), 11.0, 0.7, 0.5)
	assert_near(Vector2(c.x, c.z).length(), 10.3, 0.001)
	assert_near(c.y, 0.5)
	var inside: Vector3 = FightCamera.clamp_to_arena(Vector3(1, 2, 1), 11.0, 0.7, 0.5)
	assert_eq(inside, Vector3(1, 2, 1))


func test_smooth_factor_is_frame_rate_independent() -> void:
	var one: float = 1.0 - FightCamera.smooth_factor(5.0, 0.1)
	var two: float = (1.0 - FightCamera.smooth_factor(5.0, 0.05)) * (1.0 - FightCamera.smooth_factor(5.0, 0.05))
	assert_near(one, two, 0.0001)
	assert_near(FightCamera.smooth_factor(5.0, 0.0), 0.0)


func test_orbit_pose_distance() -> void:
	var pose: Dictionary = FightCamera.orbit_pose(Vector3(1, 1, 1), 0.7, 0.3, 6.0)
	var pos: Vector3 = pose["pos"]
	assert_near(pos.distance_to(Vector3(1, 1, 1)), 6.0, 0.001)
