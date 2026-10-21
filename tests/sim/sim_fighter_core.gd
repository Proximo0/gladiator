extends "res://tests/sim/sim_base.gd"
## Fighter core: standing balance, walking and sprint speed, swing tip speed (longsword vs club), and a heavy club
## hit knocking a standing dummy into stumbling or down. Each scenario builds its own floor and fighters.

const FIGHTER: String = "res://game/fighter/fighter.gd"


func run() -> Array:
	var rows: Array = []
	rows.append_array(await _stand())
	rows.append_array(await _walk())
	rows.append_array(await _swings())
	rows.append_array(await _heavy_hit())
	return rows


func _floor() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)


func _fighter(wid: String, side: int, pos: Vector3, yaw: float) -> Node3D:
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.position = pos
	f.rotation.y = yaw
	f.setup({"weapon": wid, "offhand": "", "armor": {}}, side, Tuning.new())
	return f


func _stand() -> Array:
	await sandbox()
	_floor()
	var f: Node3D = _fighter("longsword", 0, Vector3.ZERO, 0.0)
	var idle := FighterInput.new()
	var min_bal: float = 1.0
	var states: Dictionary = {}
	for i: int in range(600):
		await step(1)
		f.apply_input(idle)
		if i >= 30:
			var d: Dictionary = f.debug_frame()
			min_bal = minf(min_bal, float(d["balance"]))
			states[d["state"]] = true
	var ok: bool = min_bal >= 0.8 and states.keys() == ["standing"]
	await clear()
	return [row("fighter_stand_10s", ok, "min_balance=%.2f states=%s" % [min_bal, states.keys()])]


## Average speed over the distance from 1 m to 5 m travelled, with `buttons` held.
func _measure_walk(buttons: int) -> Array:
	await sandbox()
	_floor()
	var f: Node3D = _fighter("longsword", 0, Vector3.ZERO, 0.0)
	var inp := FighterInput.new()
	inp.move_y = 1000
	inp.buttons = buttons
	var t0: int = -1
	var t1: int = -1
	var min_bal: float = 1.0
	for i: int in range(480):
		await step(1)
		f.apply_input(inp)
		var d: Dictionary = f.debug_frame()
		var dist: float = -(d["pelvis_pos"] as Vector3).z
		min_bal = minf(min_bal, float(d["balance"]))
		if t0 < 0 and dist >= 1.0:
			t0 = i
		if t1 < 0 and dist >= 5.0:
			t1 = i
			break
	var speed: float = 4.0 / (float(t1 - t0) * DT) if t1 > t0 and t0 >= 0 else 0.0
	await clear()
	return [speed, min_bal]


func _walk() -> Array:
	var tun := Tuning.new()
	var w: Array = await _measure_walk(0)
	var s: Array = await _measure_walk(FighterInput.SPRINT)
	var walk_ok: bool = absf(float(w[0]) - tun.move_speed) <= tun.move_speed * 0.25 and float(w[1]) >= 0.6
	var sprint_ok: bool = float(s[0]) > float(w[0]) * 1.3 and float(s[1]) >= 0.5
	return [
		row("fighter_walk_5m", walk_ok, "speed=%.2f m/s (move_speed %.1f) min_balance=%.2f" % [w[0], tun.move_speed, w[1]]),
		row("fighter_sprint", sprint_ok, "speed=%.2f m/s (sprint_speed %.1f) min_balance=%.2f" % [s[0], tun.sprint_speed, s[1]]),
	]


## Peak tip speed of a right-high to left-low sweep of the aim (8 ticks) with SWING held.
func _swing_tip(wid: String) -> float:
	await sandbox()
	_floor()
	var f: Node3D = _fighter(wid, 0, Vector3.ZERO, 0.0)
	var inp := FighterInput.new()
	var best: float = 0.0
	for i: int in range(150):
		await step(1)
		if i >= 40 and i < 80:
			inp.aim_x = 1000
			inp.aim_y = 500
		elif i >= 80:
			var k: float = clampf((i - 80) / 8.0, 0.0, 1.0)
			inp.aim_x = int(lerpf(1000, -1000, k))
			inp.aim_y = int(lerpf(500, -300, k))
			inp.buttons = FighterInput.SWING
			best = maxf(best, float(f.debug_frame()["tip_speed"]))
		f.apply_input(inp)
	await clear()
	return best


func _swings() -> Array:
	var ls: float = await _swing_tip("longsword")
	var club: float = await _swing_tip("club")
	return [
		row("fighter_swing_longsword", ls >= 14.0 and ls <= 28.0, "tip_speed=%.1f m/s (target 15-25)" % ls),
		row("fighter_swing_club", club >= 8.0 and club <= 28.0, "tip_speed=%.1f m/s (longsword %.1f)" % [club, ls]),
	]


func _heavy_hit() -> Array:
	await sandbox()
	_floor()
	var f: Node3D = _fighter("club", 0, Vector3.ZERO, 0.0)
	var dm: Node3D = _fighter("fists", 1, Vector3(0, 0, -1.3), PI)
	f.opponent = dm
	dm.opponent = f
	var hits: Array = []
	dm.hit.connect(func(e: Dictionary) -> void: hits.append(e))
	var inp := FighterInput.new()
	var idle := FighterInput.new()
	var states: Dictionary = {}
	for i: int in range(240):
		await step(1)
		if i >= 60 and i < 100:
			inp.aim_x = 1000
			inp.aim_y = 600
		elif i >= 100:
			var k: float = clampf((i - 100) / 8.0, 0.0, 1.0)
			inp.aim_x = int(lerpf(1000, -1000, k))
			inp.aim_y = 300
			inp.buttons = FighterInput.SWING
		f.apply_input(inp)
		dm.apply_input(idle)
		states[dm.debug_frame()["state"]] = true
	var first: String = "none"
	if not hits.is_empty():
		var e: Dictionary = hits[0]
		first = "%s %s %.1fm/s stagger=%.2f" % [e["part"], e["contact"], (e["rel_vel"] as Vector3).length(), e["stagger"]]
	var ok: bool = states.has("stumbling") or states.has("down")
	await clear()
	return [row("fighter_heavy_hit", ok, "hits=%d first=[%s] dummy_states=%s" % [hits.size(), first, states.keys()])]
