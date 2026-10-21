extends "res://tests/sim/sim_base.gd"
## Fighter core: standing balance, walking and sprint speed, swing tip speed (longsword vs club), and a heavy club
## hit knocking a standing dummy into stumbling or down, kneeling to pick a weapon up off the sand, and getting up
## from a sit with straight legs (round 3: seed 5007). Each scenario builds its own floor and fighters.

const FIGHTER: String = "res://game/fighter/fighter.gd"


func run() -> Array:
	var rows: Array = []
	rows.append_array(await _stand())
	rows.append_array(await _walk())
	rows.append_array(await _swings())
	rows.append_array(await _heavy_hit())
	rows.append_array(await _ground_pickup())
	rows.append_array(await _sit_getup())
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
			inp.aim_y = 0  # a torso-high sweep: at 300 the dummy's guard fist took the whole swing (round 3)
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


## A disarmed fighter with a gladius lying on the sand ahead of it: CROUCH held, GRAB pulsed like the bot does.
## A small grab radius (0.3 m), so only a hand that really gets down to the sand picks it up.
func _ground_pickup() -> Array:
	await sandbox()
	_floor()
	var tun := Tuning.new()
	tun.grab_radius = 0.3
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.setup({"weapon": "gladius", "offhand": "", "armor": {}}, 0, tun)
	var idle := FighterInput.new()
	for i: int in range(30):
		await step(1)
		f.apply_input(idle)
	var w: Weapon = f.get("weapon") as Weapon
	f.call("drop_weapon")
	w.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.15, 0.05, -0.5))
	w.linear_velocity = Vector3.ZERO
	w.angular_velocity = Vector3.ZERO
	for i: int in range(30):
		await step(1)
		f.apply_input(idle)
	var prop_y: float = w.global_position.y
	var inp := FighterInput.new()
	inp.aim_y = -1000
	var picked: int = -1
	var min_hand: float = 9.0
	var min_pelvis: float = 9.0
	var states: Dictionary = {}
	for i: int in range(240):
		inp.buttons = FighterInput.CROUCH | (FighterInput.GRAB if i % 12 < 6 else 0)
		f.apply_input(inp)
		await step(1)
		var d: Dictionary = f.debug_frame()
		states[d["state"]] = true
		min_hand = minf(min_hand, (d["hand_pos"] as Vector3).y)
		min_pelvis = minf(min_pelvis, (d["pelvis_pos"] as Vector3).y)
		if str(d["weapon_id"]) == "gladius":
			picked = i
			break
	var log: Dictionary = f.debug_frame()["weapon_log"]
	var ok: bool = picked >= 0 and picked <= 150 and not states.has("down") and int(log["rearms"]) == 1
	await clear()
	return [row("fighter_ground_pickup", ok, "picked_tick=%d prop_y=%.2f min_hand_y=%.2f min_pelvis_y=%.2f states=%s" % [
		picked, prop_y, min_hand, min_pelvis, states.keys()])]


## The pose seed 5007's side 0 was stuck in for 40 s (round 3 trace, tick 900): sitting, right leg straight out in
## front, left leg folded back beside the hips, with its knocked-off iron cuirass lying across the right thigh.
## Frames are relative to the pelvis ground point and facing.
const STUCK_SIT: Dictionary = {
	"pelvis": "Transform3D(0.97046703, 0.22587013, -0.08471388, -0.23025517, 0.97204065, -0.046038672, 0.071946554, 0.06418483, 0.9953411, 0, 0.117965065, 0)",
	"torso": "Transform3D(0.9910677, 0.124273896, -0.04838206, -0.12606728, 0.9913697, -0.035960604, 0.043495566, 0.04173878, 0.9981814, 0.05300069, 0.4632308, 0.016426325)",
	"head": "Transform3D(0.9788372, 0.19607607, -0.058583766, -0.20169628, 0.9727641, -0.11423062, 0.03459029, 0.1236293, 0.99172544, 0.10733175, 0.82805943, 0.041645765)",
	"upper_arm_l": "Transform3D(0.5396819, 0.27632716, 0.79522747, -0.14905642, 0.96103746, -0.23278585, -0.8285684, 0.007096529, 0.5598428, -0.18908691, 0.5562709, 0.013785124)",
	"upper_arm_r": "Transform3D(-0.26524407, 0.41492775, 0.8703336, 0.94033766, 0.3108251, 0.13839404, -0.213098, 0.8551156, -0.47261673, 0.25355172, 0.5820948, -0.084753275)",
	"forearm_l": "Transform3D(0.9592938, -0.19815429, -0.20122193, -0.16982746, 0.16452563, -0.97164285, 0.22564131, 0.966264, 0.12417638, -0.19388413, 0.39406422, -0.15138948)",
	"forearm_r": "Transform3D(-0.75058675, 0.55139154, 0.3641249, 0.5041661, 0.12168658, 0.8549906, 0.4271255, 0.825324, -0.36932933, 0.10189128, 0.51799345, -0.3433199)",
	"thigh_l": "Transform3D(0.35272574, 0.63023645, -0.69165486, -0.9114952, 0.064293265, -0.4062545, -0.21156776, 0.7737365, 0.5971355, -0.25370336, 0.057460126, -0.18228757)",
	"thigh_r": "Transform3D(0.78274864, -0.0494747, 0.62036824, 0.6223187, 0.070080996, -0.7796205, -0.0049045086, 0.9963137, 0.08564487, 0.09029484, -0.0064957617, -0.2168535)",
	"shin_l": "Transform3D(0.1834943, -0.04622814, 0.9819332, -0.98286015, -0.026686788, 0.1824111, 0.017772073, -0.9985744, -0.050332695, -0.38237762, 0.053742424, -0.16233528)",
	"shin_r": "Transform3D(0.87558836, -0.13733953, 0.46312305, 0.4528824, -0.100152016, -0.8859273, 0.16805547, 0.9854479, -0.025493197, 0.12582469, 0.03625612, -0.62877226)",
}


## Posed in STUCK_SIT with the cuirass prop on the thigh: it must get up (at most 3 tries, legs at full hp).
func _sit_getup() -> Array:
	await sandbox()
	_floor()
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.setup({"weapon": "gladius", "offhand": "", "armor": {"torso": "cuirass_iron"}}, 0, Tuning.new())
	var parts: Dictionary = f.get("parts")
	for n: Variant in STUCK_SIT:
		(parts[n] as RigidBody3D).global_transform = str_to_var(STUCK_SIT[n]) as Transform3D
	(f.get("health") as FighterHealth).consciousness = 0.55  # dazed, as in the trace
	f.call("_dislodge", "cuirass_iron", "torso", Vector3.ZERO)
	var thigh: Vector3 = (parts["thigh_r"] as RigidBody3D).global_position
	for ap: Node in host.get_tree().get_nodes_in_group("armor_props"):
		var prop: RigidBody3D = ap as RigidBody3D
		prop.global_transform = Transform3D(Basis(), Vector3(thigh.x, 0.12, thigh.z))
		prop.linear_velocity = Vector3.ZERO
	var idle := FighterInput.new()
	var tries: int = 0
	var prev: String = ""
	var stood: int = -1
	var low: float = 9.0
	for i: int in range(900):
		f.apply_input(idle)
		await step(1)
		var d: Dictionary = f.debug_frame()
		var st: String = d["state"]
		low = minf(low, (d["pelvis_pos"] as Vector3).y)
		if st == "getting_up" and prev != "getting_up":
			tries += 1
		prev = st
		if st == "standing" and i > 30 and tries > 0:
			stood = i
			break
	var ok: bool = stood >= 0 and tries <= 3
	await clear()
	return [row("fighter_sit_getup", ok, "stood_tick=%d tries=%d lowest_pelvis=%.2f" % [stood, tries, low])]
