extends "res://tests/sim/sim_base.gd"
## Finisher camera in a live tree: the shot eases in toward the held point, stays finite and above the sand, and hands
## back to the normal pose; a restart primes only after the wait.


func run() -> Array:
	await sandbox()
	var a := Node3D.new()
	var b := Node3D.new()
	world.add_child(a)
	world.add_child(b)
	a.position = Vector3(0.0, 0.95, 0.0)
	b.position = Vector3(0.0, 0.95, -1.5)
	var cam := FightCamera.new()
	world.add_child(cam)
	cam.target = a
	cam.look_at_node = b
	cam.snap()
	await step(2)
	var normal: Vector3 = cam.global_position
	cam.start_finale(a.global_position, b, b.global_position + Vector3(0, 0.5, 0), 1.0)
	var worst_y: float = 99.0
	var bad: int = 0
	var max_w: float = 0.0
	var moved: float = 0.0
	for i: int in 420:
		b.position.y = maxf(0.2, b.position.y - 0.01)  # the victim slumps
		await step(1)
		worst_y = minf(worst_y, cam.global_position.y)
		bad += int(not FightCamera.is_finite_v3(cam.global_position))
		bad += int(cam.global_position.length() > 30.0)
		max_w = maxf(max_w, cam.finale.weight)
		moved = maxf(moved, cam.global_position.distance_to(normal))
	var rows: Array = [row("finale_camera_finite_and_bounded", bad == 0, "bad=%d" % bad)]
	rows.append(row("finale_camera_above_sand", worst_y > 0.2, "min y %.2f" % worst_y))
	rows.append(row("finale_reaches_full_weight_then_releases", max_w > 0.99 and not cam.finale.active, "w=%.2f" % max_w))
	rows.append(row("finale_moves_the_camera", moved > 0.5, "moved %.2f" % moved))
	rows.append(row("finale_off_under_reduced_motion", true, ""))
	cam.start_finale(a.global_position, b, b.global_position, 0.0)
	rows[rows.size() - 1][1] = not cam.finale.active
	cam.snap_after_ticks(2)
	var before: Vector3 = cam.global_position
	a.position = Vector3(5.0, 0.95, 5.0)
	await step(1)
	rows.append(row("restart_prime_waits", cam.global_position.is_equal_approx(before), ""))
	await step(3)
	rows.append(row("restart_primes_after_wait", not cam.global_position.is_equal_approx(before), ""))
	await clear()
	return rows
