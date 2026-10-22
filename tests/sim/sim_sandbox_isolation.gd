extends "res://tests/sim/sim_base.gd"
## The sims share one process and one physics server. A scenario built in `sandbox(true)` runs in a fresh physics
## space and must replay bit for bit whatever ran before it: a fighter walks up to a foe and swings, then bodies and
## fighters are built, stepped and freed in the shared space (as earlier sims leave behind), then the same scenario
## runs again. The same pair in the shared space is INFO only: a Jolt space's results depend on the bodies it created
## and freed before. Last in SIM_FILES, so its churn of the shared space cannot move a later sim.

const TICKS: int = 90


func run() -> Array:
	var shared_a: String = await _walk(false)
	var own_a: String = await _walk(true)
	await _churn()
	var shared_b: String = await _walk(false)
	var own_b: String = await _walk(true)
	return [
		row("sandbox_own_space_replays_exactly", own_a == own_b, "path h%x then h%x after churn" % [own_a.hash(), own_b.hash()]),
		row("sandbox_shared_space_depends_on_history", null, "shared space path unchanged after churn=%s" % (shared_a == shared_b)),
	]


func _floor() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)


func _pair() -> Array:
	var out: Array = []
	for side: int in range(2):
		var f := Fighter.new()
		world.add_child(f)
		f.position = Vector3(0, 0, -1.6 * side)
		f.rotation.y = PI * side
		f.setup({"weapon": "gladius" if side == 0 else "fists", "offhand": "", "armor": {}}, side, Tuning.new())
		out.append(f)
	(out[0] as Fighter).opponent = out[1]
	(out[1] as Fighter).opponent = out[0]
	return out


## Fighter 0 walks at the foe and swings side to side. Returns every part position of both fighters, every tick.
func _walk(own_space: bool) -> String:
	await sandbox(own_space)
	_floor()
	var fs: Array = _pair()
	var path := PackedStringArray()
	for i: int in range(TICKS):
		await step(1)
		var inp := FighterInput.new()
		if i >= 10:
			inp.move_y = 1000
		if i >= 30:
			inp.buttons = FighterInput.SWING
			inp.aim_x = 1000 if (i / 12) % 2 == 0 else -1000
		(fs[0] as Fighter).apply_input(inp)
		(fs[1] as Fighter).apply_input(FighterInput.new())
		for f: Fighter in fs:
			for n: String in FighterRig.names():
				path.append(var_to_str((f.parts[n] as RigidBody3D).global_position))
	await clear()
	return "".join(path)


## Bodies dropped on a floor and a fighter pair, stepped and freed in the shared space.
func _churn() -> void:
	await sandbox()
	_floor()
	for i: int in range(40):
		var b := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.2
		cs.shape = sh
		b.add_child(cs)
		b.position = Vector3(float(i % 8) * 0.5 - 2.0, 0.5 + float(i / 8) * 0.5, 3.0)
		world.add_child(b)
	_pair()
	await step(30)
	await clear()
