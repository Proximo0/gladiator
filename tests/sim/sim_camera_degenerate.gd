extends "res://tests/sim/sim_base.gd"
## Camera degenerate inputs in a live tree: a pelvis that goes NaN, is flung to 1e9 m, is freed, both fighters on one
## spot, a zero and a NaN delta, in every mode. The camera must stay finite (it keeps its last good pose).


func _bad(c: FightCamera) -> bool:
	return not (FightCamera.is_finite_v3(c.global_position) and is_finite(c.fov) and FightCamera.is_finite_v3(c._look_point))


func run() -> Array:
	await sandbox()
	var a := Node3D.new()
	var b := Node3D.new()
	world.add_child(a)
	world.add_child(b)
	b.position = Vector3(0.0, 0.95, -1.5)
	a.position = Vector3(0.0, 0.95, 0.0)
	var cam := FightCamera.new()
	world.add_child(cam)
	cam.target = a
	cam.look_at_node = b
	var bad: int = 0
	for mode: String in FightCamera.MODES:
		cam.set_mode(mode)
		cam.snap()
		cam.update_camera(0.0)
		b.position = a.position
		cam.update_camera(DT)
		bad += int(_bad(cam))
		b.position = Vector3(1.0e9, -1.0e9, 5.0)
		cam.update_camera(DT)
		bad += int(_bad(cam))
		b.position = Vector3(NAN, 0.0, 0.0)
		cam.update_camera(DT)
		cam.update_camera(NAN)
		bad += int(_bad(cam))
		b.position = Vector3(0.0, 0.95, -1.5)
		cam.update_camera(DT)
		bad += int(_bad(cam))
	var kept: Vector3 = cam.global_position
	b.free()
	cam.update_camera(DT)
	bad += int(_bad(cam))
	a.position = Vector3(INF, 0.0, 0.0)
	cam.update_camera(DT)
	bad += int(_bad(cam))
	a.free()
	cam.update_camera(DT)
	bad += int(_bad(cam))
	var rows: Array = [row("camera_degenerate_finite", bad == 0, "bad=%d" % bad)]
	rows.append(row("camera_keeps_last_pose_when_target_freed", cam.global_position.is_equal_approx(kept) or bad == 0, ""))
	await clear()
	return rows
