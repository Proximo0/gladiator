extends "res://tests/sim/sim_base.gd"
## Armor weight (ArmorLoad): a naked fighter walks and sprints visibly faster than one in the iron set, and the iron
## set pays stamina for every step. Each run builds its own floor and one fighter with a gladius.

const FIGHTER: String = "res://game/fighter/fighter.gd"
const IRON: Dictionary = {"head": "helm_iron", "torso": "cuirass_iron", "upper_arm_l": "bracers_iron", "thigh_l": "greaves_iron"}


func run() -> Array:
	var naked_w: Array = await _run({}, 0)
	var iron_w: Array = await _run(IRON, 0)
	var naked_s: Array = await _run({}, FighterInput.SPRINT)
	var iron_s: Array = await _run(IRON, FighterInput.SPRINT)
	var walk_ok: bool = float(naked_w[0]) >= float(iron_w[0]) * 1.1 and float(iron_w[0]) > 1.0
	var sprint_ok: bool = float(naked_s[0]) >= float(iron_s[0]) * 1.1 and float(iron_s[0]) > float(naked_w[0])
	var stamina_ok: bool = float(iron_s[1]) < float(naked_s[1]) - 0.1
	return [
		row("armor_walk_speed", walk_ok, "naked=%.2f m/s iron=%.2f m/s" % [naked_w[0], iron_w[0]]),
		row("armor_sprint_speed", sprint_ok, "naked=%.2f m/s iron=%.2f m/s 10 m dash naked=%.2f s iron=%.2f s"
			% [naked_s[0], iron_s[0], naked_s[2], iron_s[2]]),
		row("armor_sprint_stamina", stamina_ok, "stamina after a 4 s sprint naked=%.2f iron=%.2f" % [naked_s[1], iron_s[1]]),
	]


## Moves forward for 4 s from standing with `buttons` held: [mean speed from 1 m on, stamina left, time to 10 m (or 4 s)].
func _run(armor: Dictionary, buttons: int) -> Array:
	await sandbox()
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.setup({"weapon": "gladius", "offhand": "", "armor": armor}, 0, Tuning.new())
	var idle := FighterInput.new()
	var inp := FighterInput.new()
	inp.move_y = 1000
	inp.buttons = buttons
	for _i: int in range(30):
		await step(1)
		f.apply_input(idle)
	var t0: int = -1
	var t10: int = -1
	var dist: float = 0.0
	var ticks: int = 240
	for i: int in range(ticks):
		await step(1)
		f.apply_input(inp)
		dist = -((f.debug_frame() as Dictionary)["pelvis_pos"] as Vector3).z
		if t0 < 0 and dist >= 1.0:
			t0 = i
		if t10 < 0 and dist >= 10.0:
			t10 = i
	var speed: float = (dist - 1.0) / (float(ticks - 1 - t0) * DT) if t0 >= 0 and t0 < ticks - 1 else 0.0
	var stamina: float = (f.get("health") as FighterHealth).stamina
	await clear()
	return [speed, stamina, float(t10 if t10 >= 0 else ticks) * DT]
