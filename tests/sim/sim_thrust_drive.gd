extends "res://tests/sim/sim_base.gd"
## Committed thrust speed: a spear fighter runs in from rest with SWING held (arms at swing reach) and presses THRUST
## part-way through the run (the CPU's drive, FighterBrain._do_drive). Reports the point's speed along the run at
## the end of the press window; the hips' lunge (thrust_lunge rows) must lift it over the plain sprint.

const FIGHTER: String = "res://game/fighter/fighter.gd"
const RUN_TICKS: int = 60
const PRESS_TICK: int = 28  ## the press, ticks into the run (the CPU presses ~0.2 s before the point arrives)


func run() -> Array:
	var plain: Array = await _drive({"thrust_lunge": 0.0, "thrust_lunge_accel": 0.0, "thrust_lunge_torso": 0.0})
	var lunge: Array = await _drive({})
	var ok: bool = float(lunge[0]) >= 5.5 and float(lunge[0]) > float(plain[0]) + 0.8 and float(lunge[1]) >= 0.5
	return [row("thrust_drive_tip_speed", ok, "plain %.2f m/s, lunge %.2f m/s (pelvis %.2f), min_balance %.2f" % [plain[0], lunge[0], lunge[2], lunge[1]])]


## [peak point speed along the run after the press, min balance, pelvis speed at that tick] for a tuning override.
func _drive(over: Dictionary) -> Array:
	await sandbox()
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)
	var tun := Tuning.new()
	for k: Variant in over:
		tun.set_value(str(k), float(over[k]))
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.setup({"weapon": "spear", "offhand": "", "armor": {}}, 0, tun)
	var inp := FighterInput.new()
	for _i: int in range(60):
		await step(1)
		f.apply_input(inp)
	var peak: float = 0.0
	var pel: float = 0.0
	var min_bal: float = 1.0
	var prev: Vector3 = (f.debug_frame()["tip_pos"] as Vector3)
	for i: int in range(RUN_TICKS):
		inp.move_y = 1000
		inp.buttons = FighterInput.SPRINT | FighterInput.SWING
		if i >= PRESS_TICK:
			inp.buttons |= FighterInput.THRUST
		await step(1)
		f.apply_input(inp)
		var d: Dictionary = f.debug_frame()
		var tip: Vector3 = d["tip_pos"]
		var v: float = -(tip - prev).z * 60.0
		prev = tip
		min_bal = minf(min_bal, float(d["balance"]))
		if i >= PRESS_TICK and v > peak:
			peak = v
			pel = ((d["pelvis_vel"] as Vector3).length()) if d.has("pelvis_vel") else 0.0
	await clear()
	return [peak, min_bal, pel]
