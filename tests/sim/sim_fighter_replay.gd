extends "res://tests/sim/sim_base.gd"
## Fighter snapshot/restore: run 10 s of scripted input, restore the snapshot taken at the start and replay the same
## inputs; report the largest body-part divergence. Idle must replay exactly; a two-fighter melee is reported
## (contacts and joint limits make it chaotic, so engine state the snapshot cannot reach shows up there).

const FIGHTER: String = "res://game/fighter/fighter.gd"
const TICKS: int = 600

var _fs: Array = []


func run() -> Array:
	var idle: Array = await _replay(1, false)
	var melee: Array = await _replay(2, true)
	return [
		row("fighter_replay_idle", float(idle[0]) < 0.01, "max_divergence=%.4f m over 10 s" % idle[0]),
		row("fighter_replay_melee", null, "max_divergence=%.4f m over 10 s, %.4f m after 1 s, hits %d vs %d" % melee),
	]


func _input_at(t: int, side: int, active: bool) -> FighterInput:
	var i := FighterInput.new()
	if not active:
		return i
	var ph: float = t * 0.05 + side
	i.move_y = int(500 * sin(ph * 0.7))
	i.move_x = int(400 * cos(ph * 0.3))
	i.aim_x = int(1000 * sin(ph * 2.0))
	i.aim_y = int(600 * cos(ph * 1.3))
	i.buttons = FighterInput.SWING if (t / 30) % 2 == 0 else 0
	return i


func _positions() -> Array:
	var out: Array = []
	for f: Node3D in _fs:
		var parts: Dictionary = f.get("parts")
		for n: String in parts:
			out.append((parts[n] as Node3D).global_position)
	return out


func _drive(t: int, active: bool) -> void:
	for k: int in range(_fs.size()):
		_fs[k].apply_input(_input_at(t, k, active))


func _replay(count: int, active: bool) -> Array:
	await sandbox()
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)
	_fs = []
	for side: int in range(count):
		var f: Node3D = (load(FIGHTER) as GDScript).new()
		world.add_child(f)
		f.position = Vector3(0, 0, 1.0 if side == 0 else -1.0)
		f.rotation.y = 0.0 if side == 0 else PI
		var wid: String = "longsword" if side == 0 else "club"
		f.setup({"weapon": wid, "offhand": "" if side == 0 else "shield_round", "armor": {"head": "helm_iron"}}, side, Tuning.new())
		_fs.append(f)
	if count == 2:
		_fs[0].set("opponent", _fs[1])
		_fs[1].set("opponent", _fs[0])
	var hits: Array = [0]
	for f: Node3D in _fs:
		f.connect("hit", func(_e: Dictionary) -> void: hits[0] += 1)
	for t: int in range(60):
		await step(1)
		_drive(t, active)
	var snaps: Array = []
	for f: Node3D in _fs:
		snaps.append(f.call("snapshot"))
	var first: Array = []
	for t: int in range(60, 60 + TICKS):
		await step(1)
		_drive(t, active)
		first.append(_positions())
	var hits_a: int = hits[0]
	hits[0] = 0
	for k: int in range(_fs.size()):
		_fs[k].call("restore", snaps[k])
	var worst: float = 0.0
	var after_1s: float = 0.0
	for t: int in range(60, 60 + TICKS):
		await step(1)
		_drive(t, active)
		var now: Array = _positions()
		var was: Array = first[t - 60]
		for i: int in range(now.size()):
			worst = maxf(worst, (now[i] as Vector3).distance_to(was[i]))
		if t == 120:
			after_1s = worst
	await clear()
	return [worst, after_1s, hits_a, hits[0]]
