extends "res://tests/sim/sim_base.gd"
## Practice mode: a headless practice Match with a scripted player. The script reads only what a player sees (the
## current step, the dummy's distance) and sends keyboard-style inputs; every guided step must complete by observed
## state, never by skip, then free practice must start, swap weapons and reset the dummy. Also checks the dummy never
## attacks and that scripted runs write no player data.

const STEP_CAP_S: float = 40.0
const RESET_SEED: int = 11


## A reader whose output the sim sets each tick.
class ScriptReader extends InputReader:
	var next: FighterInput = FighterInput.new()

	func read() -> FighterInput:
		return next


func _dist(m: Match) -> float:
	var a: Vector3 = (m.fighters[0] as Fighter).parts["pelvis"].global_position
	var b: Vector3 = (m.fighters[1] as Fighter).parts["pelvis"].global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _input_for(sess: PracticeSession, m: Match, t: int) -> FighterInput:
	var i := FighterInput.new()
	var id: String = sess.logic.step_id()
	var near: bool = _dist(m) < 1.4
	if id != "grab" and id != "move" and id != "aim" and (m.fighters[0] as Fighter).weapon == null:
		return _fetch(m, t)  # lost it in a fall: walk to it and pick it up
	match id:
		"move":
			i.move_y = 1000
		"aim":
			var ph: int = (t / 25) % 3
			i.aim_x = [-1000, 1000, 0][ph]
			i.aim_y = [0, 0, 1000][ph]
		"swing":
			i.buttons = FighterInput.SWING
			i.aim_x = 1000 if (t / 12) % 2 == 0 else -1000
		"thrust":
			i.aim_y = 0
			i.buttons = FighterInput.THRUST if (t / 20) % 2 == 0 else 0
		"strike", "finish":
			if not near:
				i.move_y = 1000
			i.buttons = FighterInput.SWING | (FighterInput.THRUST if (t / 40) % 3 == 0 else 0)
			i.aim_x = 700 if (t / 20) % 2 == 0 else -700
			i.aim_y = [0, 250, 500, 250][(t / 40) % 4]  # sweep the heights so some blows reach the neck and head
		"shove":
			if _dist(m) > 1.0:
				i.move_y = 1000
			i.buttons = FighterInput.SHOVE if (t % 60) < 3 and _dist(m) < 1.3 else 0
		"kick":
			# A stride off: step in when far, back off when too close, kick inside the band.
			var d: float = _dist(m)
			if d > 1.25:
				i.move_y = 1000
			elif d < 1.0:
				i.move_y = -1000
			elif (t % 100) < 3:
				i.buttons = FighterInput.KICK
		"hold":
			if _dist(m) > 1.05:
				i.move_y = 1000
			i.buttons = FighterInput.CLINCH if (t % 150) >= 5 else 0  # let go now and then to grab again
		"roll":
			i.move_y = 1000
			i.buttons = FighterInput.ROLL if (t / 90) % 2 == 0 and (t % 90) < 3 else 0
		"grab":
			return _fetch(m, t)
	return i


## Walks toward the nearest free weapon on the sand, then crouches and presses GRAB.
func _fetch(m: Match, t: int) -> FighterInput:
	var i := FighterInput.new()
	var f0: Fighter = m.fighters[0]
	var pel: RigidBody3D = f0.parts["pelvis"]
	var best: Node3D = null
	var best_d: float = 1e9
	for n: Node in host.get_tree().get_nodes_in_group(Weapon.PROP_GROUP):
		var w: Weapon = n as Weapon
		if w == null or w.is_fist or w.holder != null:
			continue
		var d: float = Vector2(w.global_position.x - pel.global_position.x, w.global_position.z - pel.global_position.z).length()
		if d < best_d:
			best_d = d
			best = w
	if best == null:
		return i
	var delta: Vector3 = best.global_position - pel.global_position
	delta.y = 0.0
	var fwd: Vector3 = -pel.global_basis.z
	fwd.y = 0.0
	var right: Vector3 = pel.global_basis.x
	right.y = 0.0
	var goal: Vector3 = best.global_position - fwd.normalized() * 0.55  # stand so the weapon lies just ahead of the toes
	var to_goal: Vector3 = goal - pel.global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.2:
		var dir: Vector3 = to_goal.normalized()
		i.move_x = int(clampf(dir.dot(right.normalized()), -1.0, 1.0) * 1000.0)
		i.move_y = int(clampf(dir.dot(fwd.normalized()), -1.0, 1.0) * 1000.0)
	else:
		i.buttons = FighterInput.CROUCH | (FighterInput.GRAB if (t / 15) % 2 == 0 else 0)
	return i


## Replaces the match's side-0 device reader with a scripted one.
func _install(m: Match) -> ScriptReader:
	var rd := ScriptReader.new()
	rd.name = "ScriptReader"
	var old: Node = m.readers[0]
	m.remove_child(old)
	old.free()
	m.add_child(rd)
	m.readers[0] = rd
	return rd


func run() -> Array:
	var rows: Array = []
	await sandbox()
	PracticeSave.open_shared(false)  # a scripted run never persists
	var m := Match.new()
	world.add_child(m)
	m.setup({"mode": "practice", "seed": RESET_SEED, "presentation": false, "time_limit_s": 100000.0,
			"loadouts": [PracticeSession.PLAYER_LOADOUT.duplicate(true), PracticeSession.DUMMY_LOADOUT.duplicate(true)]})
	var rd: ScriptReader = _install(m)
	var sess := PracticeSession.new()
	world.add_child(sess)
	sess.attach(m, null)
	var dummy_hits: Array = [0]
	(m.fighters[1] as Fighter).hit.connect(func(ev: Dictionary) -> void:
		if int(ev.get("attacker", -1)) == 1 and float(ev.get("total", 0.0)) > 0.0:
			dummy_hits[0] += 1)
	var done: Array = []
	sess.step_done.connect(func(id: String) -> void: done.append(id))
	var enters_free: Array = [false]
	sess.completed.connect(func() -> void: enters_free[0] = true)
	var t: int = 0
	var step_started: int = 0
	var last_step: String = ""
	var stuck_at: String = ""
	var cap: int = int(STEP_CAP_S * 60.0)
	while not sess.logic.complete and stuck_at == "":
		if m.readers[0] != rd:
			rd = _install(m)  # a bout reset rebuilt the readers
		rd.next = _input_for(sess, m, t)
		await host.get_tree().physics_frame
		t += 1
		var cur: String = sess.logic.step_id()
		if cur != last_step:
			last_step = cur
			step_started = t
		elif t - step_started > cap:
			stuck_at = cur
	var detail: String = "done=%s ticks=%d hits=%d finishers=%d" % [",".join(PackedStringArray(done)), t, sess.hits, sess.finishers]
	rows.append(row("practice_steps_complete_by_state", stuck_at == "" and sess.logic.complete and sess.logic.skipped.is_empty(), "%s stuck_at=%s" % [detail, stuck_at]))
	rows.append(row("practice_step_order", done == Array(PracticeLogic.STEP_IDS), ",".join(PackedStringArray(done))))
	rows.append(row("practice_scripted_run_writes_nothing", not PracticeSave.shared().persist and not FileAccess.file_exists("user://practice.json"), "persist=%s" % PracticeSave.shared().persist))
	# The dummy never attacked: the player took no damage from anything.
	var f0: Fighter = m.fighters[0]
	rows.append(row("practice_dummy_never_hits_back", dummy_hits[0] == 0, "damaging hits by the dummy=%d" % dummy_hits[0]))
	# Free practice: let the deferred switch happen, then swap the weapon and reset the dummy.
	await step(3)
	rows.append(row("practice_free_mode_starts", sess.free_mode and enters_free[0], "free=%s" % sess.free_mode))
	var before: String = str(m.config["loadouts"][0]["weapon"])
	sess.cycle_weapon()
	await step(2)
	var after: String = str(m.config["loadouts"][0]["weapon"])
	rows.append(row("practice_free_weapon_cycles", before != after and (m.fighters[0] as Fighter).loadout.get("weapon") == after, "%s -> %s" % [before, after]))
	(m.fighters[1] as Fighter).health.blood = 3.0
	sess.reset_bout()
	await step(2)
	rows.append(row("practice_dummy_reset_refills", (m.fighters[1] as Fighter).health.blood > 4.9, "blood=%.2f" % (m.fighters[1] as Fighter).health.blood))
	await clear()
	return rows
