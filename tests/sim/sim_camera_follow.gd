extends "res://tests/sim/sim_base.gd"
## Follow camera in motion, in a live tree. (1) Lag: a target strafing at walk speed and rolling at roll speed; the
## camera's distance from the pose it wants (m) must stay small. (2) A real presented bot fight filmed in follow mode
## at 16:9 and 9:16: fast-footwork lag, frames with a fighter off screen, camera inside the wall. (3) A beheading that
## follows a death: the flung head stays on screen through the finale shot. Numbers in sim seconds / frames only.

const WALK: float = 2.5
const ROLL: float = 4.0
const LAG_MAX_M: float = 0.25  ## steady lag allowed at roll speed
const FIGHT_S: float = 16.0
const FIGHT_SEED: int = 101
const OFF_FRAC_MAX: float = 0.02  ## share of fight frames a fighter may be off screen
const HEAD_OFF_FRAC_MAX: float = 0.1  ## share of post-beheading frames the head may be off screen


## Steady lag (m) of the camera behind its wanted pose while `a` moves at `speed` with the opponent kept 2.4 m ahead
## (`side` true: a strafe circling the opponent; false: straight runs, like a roll chasing them).
func _lag(speed: float, side: bool) -> float:
	await sandbox()
	var a := Node3D.new()
	var b := Node3D.new()
	world.add_child(a)
	world.add_child(b)
	a.position = Vector3(0.0, 0.95, 3.0)
	b.position = Vector3(0.0, 0.95, 0.6)
	var cam := FightCamera.new()
	world.add_child(cam)
	cam.arena_radius = 30.0  # no wall in the way: lag only
	cam.target = a
	cam.look_at_node = b
	cam.snap()
	var worst: float = 0.0
	var ang: float = 0.0
	for i: int in 150:
		if side:
			ang += speed * DT / 2.4
			a.position = b.position + Vector3(sin(ang), 0.0, cos(ang)) * 2.4 + Vector3(0.0, 0.35, 0.0)
		else:
			a.position += Vector3(speed * DT, 0.0, 0.0)
			b.position += Vector3(speed * DT, 0.0, 0.0)
		cam.update_camera(DT)
		if i >= 60:
			worst = maxf(worst, cam._base_pos.distance_to(cam.dbg_want_pos))
	await clear()
	return worst


## Off-screen test for one point set with the camera's real pose (shake included) and lens.
func _ratio(cam: FightCamera, pts: Array, aspect: float) -> float:
	var fwd: Vector3 = -cam.global_transform.basis.z
	return FightCamera.frame_ratio(cam.global_position, cam.global_position + fwd * 5.0, cam.fov, aspect, pts)


## A presented bot fight filmed in follow mode at `aspect`. Returns lag and framing numbers.
func _fight(aspect: float) -> Dictionary:
	await sandbox()
	var m := Match.new()
	world.add_child(m)
	m.setup({"mode": "bot_vs_bot", "seed": FIGHT_SEED, "presentation": true, "time_limit_s": FIGHT_S + 5.0, "loop": false})
	var cam: FightCamera = m.presenter.camera
	cam.set_mode("follow")
	cam.aspect_override = aspect
	cam.snap()
	var me: Node3D = cam.target
	var opp: Node3D = cam.look_at_node
	var prev: Vector3 = me.global_position
	var n: int = 0
	var fast: int = 0
	var lags: Array = []
	var off_me: int = 0
	var off_opp: int = 0
	var out_wall: int = 0
	var min_d: float = 99.0
	var lim: float = cam.arena_radius - FightCamera.WALL_MARGIN + 0.05
	for i: int in int(FIGHT_S * 60.0):
		await host.get_tree().process_frame
		if m.over or not is_instance_valid(me) or not is_instance_valid(opp):
			break
		var p: Vector3 = me.global_position
		var v: float = Vector2(p.x - prev.x, p.z - prev.z).length() / DT
		prev = p
		if i < 30:
			continue
		n += 1
		if v > 2.0:
			fast += 1
			lags.append(cam._base_pos.distance_to(cam.dbg_want_pos))
		# Head and feet must be inside the actual frame (1.0 = the frame edge).
		off_me += int(_ratio(cam, FightCamera.frame_points(p), aspect) > 1.0)
		off_opp += int(_ratio(cam, FightCamera.frame_points(opp.global_position), aspect) > 1.0)
		out_wall += int(Vector2(cam.global_position.x, cam.global_position.z).length() > lim)
		min_d = minf(min_d, cam.global_position.distance_to(p))
	lags.sort()
	var p95: float = float(lags[int(lags.size() * 0.95)]) if lags.size() > 0 else 0.0
	var mx: float = float(lags[lags.size() - 1]) if lags.size() > 0 else 0.0
	var out: Dictionary = {"n": n, "fast": fast, "lag_p95": p95, "lag_max": mx, "off_me": off_me, "off_opp": off_opp,
		"out_wall": out_wall, "min_d": min_d, "cuts": cam.cuts}
	await clear()
	return out


## Bot fight; at `death_s` fighter 1 dies, `delay_s` later its head comes off and is flung along the blow. Counts the
## frames in the following 3 s where the head or the body is off screen.
func _behead(delay_s: float) -> Dictionary:
	await sandbox()
	var m := Match.new()
	world.add_child(m)
	m.setup({"mode": "bot_vs_bot", "seed": FIGHT_SEED, "presentation": true, "time_limit_s": 60.0, "loop": false})
	var cam: FightCamera = m.presenter.camera
	cam.set_mode("follow")
	cam.aspect_override = 16.0 / 9.0
	cam.snap()
	for i: int in 120:
		await host.get_tree().process_frame
	var victim: Fighter = m.fighters[1]
	var killer: Fighter = m.fighters[0]
	victim.health.dead = true
	victim._die()
	for i: int in int(delay_s * 60.0):
		await host.get_tree().process_frame
	var head: RigidBody3D = victim.parts["head"]
	var blow: Vector3 = FightCamera.flat_dir(killer.parts["pelvis"].global_position, victim.parts["pelvis"].global_position)
	victim._sever("head")
	head.linear_velocity = blow * 4.5 + Vector3(0.0, 3.5, 0.0)
	var off_head: int = 0
	var off_body: int = 0
	var n: int = 0
	var re: bool = false
	for i: int in 180:
		await host.get_tree().process_frame
		if not is_instance_valid(head) or not is_instance_valid(victim):
			break
		n += 1
		re = re or cam.finale.active
		off_head += int(_ratio(cam, [head.global_position], 16.0 / 9.0) > 1.0)
		off_body += int(_ratio(cam, [victim.parts["pelvis"].global_position], 16.0 / 9.0) > 1.0)
	var out: Dictionary = {"n": n, "off_head": off_head, "off_body": off_body, "finale": re}
	await clear()
	Engine.time_scale = 1.0
	return out


func run() -> Array:
	var rows: Array = []
	var walk: float = await _lag(WALK, true)
	var roll: float = await _lag(ROLL, false)
	rows.append(row("camera_follow_lag_strafe", walk <= LAG_MAX_M, "%.2f m at %.1f m/s" % [walk, WALK]))
	rows.append(row("camera_follow_lag_roll", roll <= LAG_MAX_M, "%.2f m at %.1f m/s" % [roll, ROLL]))
	for asp: float in [16.0 / 9.0, 9.0 / 16.0]:
		var tag: String = "land" if asp > 1.0 else "port"
		var f: Dictionary = await _fight(asp)
		var nn: float = maxf(float(f["n"]), 1.0)
		rows.append(row("camera_fight_%s_info" % tag, null, "frames=%d fast=%d lag p95 %.2f m max %.2f m, off me=%d opp=%d, min dist %.2f m, cuts %d" % [
			f["n"], f["fast"], f["lag_p95"], f["lag_max"], f["off_me"], f["off_opp"], f["min_d"], f["cuts"]]))
		rows.append(row("camera_fight_%s_lag" % tag, float(f["lag_p95"]) <= LAG_MAX_M * 2.0, "p95 %.2f m" % f["lag_p95"]))
		rows.append(row("camera_fight_%s_onscreen" % tag, float(f["off_me"]) / nn <= OFF_FRAC_MAX and float(f["off_opp"]) / nn <= OFF_FRAC_MAX,
			"off me %d opp %d of %d" % [f["off_me"], f["off_opp"], f["n"]]))
		rows.append(row("camera_fight_%s_inside_wall" % tag, int(f["out_wall"]) == 0, "frames outside %d" % f["out_wall"]))
	for d: float in [0.0, 1.5, 5.5]:
		var b: Dictionary = await _behead(d)
		var nb: float = maxf(float(b["n"]), 1.0)
		rows.append(row("camera_behead_after_%.1fs" % d, float(b["off_head"]) / nb <= HEAD_OFF_FRAC_MAX and b["finale"],
			"head off %d body off %d of %d, finale %s" % [b["off_head"], b["off_body"], b["n"], b["finale"]]))
	return rows
