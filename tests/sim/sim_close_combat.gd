extends "res://tests/sim/sim_base.gd"
## Close range: a shove pushes and staggers a standing foe and floors one already stumbling, a front kick lands with
## real foot speed and pushes the foe back, a whiffed kick staggers the kicker, a grab of the weapon arm holds it in
## and a struggling foe breaks free. Two fighters face each other on a flat floor.

const FIGHTER: String = "res://game/fighter/fighter.gd"


func run() -> Array:
	var rows: Array = []
	rows.append_array(await _shove(false))
	rows.append_array(await _shove(true))
	rows.append_array(await _kick(0.95))
	rows.append_array(await _kick(3.0))
	rows.append_array(await _grab())
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


## Fighter 0 at the origin facing -Z, the foe `gap` m ahead facing back.
func _pair(w0: String, w1: String, gap: float) -> Array:
	var out: Array = []
	for side: int in range(2):
		var f: Node3D = (load(FIGHTER) as GDScript).new()
		world.add_child(f)
		f.position = Vector3(0, 0, -gap * side)
		f.rotation.y = PI * side
		f.setup({"weapon": w0 if side == 0 else w1, "offhand": "", "armor": {}}, side, Tuning.new())
		out.append(f)
	out[0].opponent = out[1]
	out[1].opponent = out[0]
	return out


func _inp(buttons: int = 0, move_y: int = 0, aim_y: int = 0) -> FighterInput:
	var i := FighterInput.new()
	i.buttons = buttons
	i.move_y = move_y
	i.aim_y = aim_y
	return i


## SHOVE pressed at tick 60 against a foe 0.85 m away; `stumbling` gives the foe a stagger first.
func _shove(stumbling: bool) -> Array:
	await sandbox()
	_floor()
	var fs: Array = _pair("gladius", "gladius", 0.85)
	var f: Node3D = fs[0]
	var foe: Node3D = fs[1]
	var z0: float = 0.0
	var st0: float = 0.0
	var st_min: float = 1.0
	var states: Dictionary = {}
	var landed: bool = false
	var max_push: float = 0.0
	for i: int in range(150):
		await step(1)
		f.apply_input(_inp(FighterInput.SHOVE) if i >= 60 and i < 64 else _inp())
		foe.apply_input(_inp())
		if i == 58:
			z0 = (foe.parts["pelvis"] as RigidBody3D).global_position.z
			st0 = f.health.stamina
			if stumbling:
				foe._stagger = 0.5
		if i >= 60:
			states[foe.state()] = true
			landed = landed or f._close.shove_landed
			st_min = minf(st_min, f.health.stamina)
			max_push = maxf(max_push, z0 - (foe.parts["pelvis"] as RigidBody3D).global_position.z)
	var cost: float = st0 - st_min
	var ok: bool = landed and max_push > 0.15 and states.has("stumbling") and cost > 0.05
	if stumbling:
		ok = landed and states.has("down")
	var nm: String = "close_shove_floors_stumbling" if stumbling else "close_shove_pushes"
	await clear()
	return [row(nm, ok, "landed=%s pushed=%.2f m foe_states=%s stamina_cost=%.2f" % [landed, max_push, states.keys(), cost])]


## KICK pressed at tick 60 with the foe `gap` m away: close, it lands (foot speed, damage, push, foe staggers); far,
## it whiffs and the kicker is left staggered.
func _kick(gap: float) -> Array:
	await sandbox()
	_floor()
	var fs: Array = _pair("fists", "fists", gap)
	var f: Node3D = fs[0]
	var foe: Node3D = fs[1]
	var hits: Array = []
	foe.hit.connect(func(ev: Dictionary) -> void: hits.append(ev))
	var z0: float = 0.0
	var max_push: float = 0.0
	var foot_v: float = 0.0
	var foot_hi: float = 0.0
	var my_states: Dictionary = {}
	var foe_states: Dictionary = {}
	for i: int in range(160):
		await step(1)
		f.apply_input(_inp(FighterInput.KICK) if i >= 60 and i < 63 else _inp())
		foe.apply_input(_inp())
		if i == 59:
			z0 = (foe.parts["pelvis"] as RigidBody3D).global_position.z
		if i >= 60:
			var shin: RigidBody3D = f.parts["shin_l"]
			foot_v = maxf(foot_v, shin.linear_velocity.length())
			foot_hi = maxf(foot_hi, f._foot_point("shin_l").y)
			max_push = maxf(max_push, z0 - (foe.parts["pelvis"] as RigidBody3D).global_position.z)
			my_states[f.state()] = true
			foe_states[foe.state()] = true
	var kick_hits: int = 0
	var dmg: float = 0.0
	for ev: Dictionary in hits:
		if bool(ev.get("kick", false)):
			kick_hits += 1
			dmg += float(ev.get("total", 0.0))
	var detail: String = "kick_hits=%d damage=%.1f foot_speed_max=%.1f m/s foot_high=%.2f m pushed=%.2f m kicker=%s foe=%s" % [
		kick_hits, dmg, foot_v, foot_hi, max_push, my_states.keys(), foe_states.keys()]
	var ok: bool
	var nm: String
	if gap < 2.0:
		nm = "close_kick_lands"
		ok = kick_hits == 1 and dmg > 0.0 and max_push > 0.1 and foot_hi > 0.35 and f.state() == "standing"
	else:
		nm = "close_kick_whiff_staggers"
		ok = kick_hits == 0 and my_states.has("stumbling") and foot_hi > 0.35 and not my_states.has("down")
	await clear()
	return [row(nm, ok, detail)]


## CLINCH held from tick 60 with the aim low: the free hand latches on the foe's weapon forearm, holds it; the foe
## pulls back and swings, and breaks free within a few seconds.
func _grab() -> Array:
	await sandbox()
	_floor()
	var fs: Array = _pair("gladius", "gladius", 0.8)
	var f: Node3D = fs[0]
	var foe: Node3D = fs[1]
	var held_at: int = -1
	var broke_at: int = -1
	var held_ticks: int = 0
	var states: Dictionary = {}
	for i: int in range(360):
		await step(1)
		f.apply_input(_inp(FighterInput.CLINCH) if i >= 60 else _inp())
		# The foe fights the hold from a second in: pulls away and swings.
		foe.apply_input(_inp(FighterInput.SWING, -1000) if held_at >= 0 and i >= held_at + 60 else _inp())
		if f._close.holding():
			held_ticks += 1
			if held_at < 0:
				held_at = i
		elif held_at >= 0 and broke_at < 0:
			broke_at = i
		states[f.state()] = true
	var breaks: int = int(f._close.counts["breaks"])
	var ok: bool = held_at >= 0 and held_at < 90 and held_ticks > 60 and breaks == 1 and f.state() == "standing"
	await clear()
	return [row("close_grab_holds_and_breaks", ok, "latched_tick=%d held=%.2f s broke_tick=%d breaks=%d grabber=%s" % [
		held_at, held_ticks / 60.0, broke_at, breaks, states.keys()])]
