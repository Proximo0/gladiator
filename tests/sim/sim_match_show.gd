extends "res://tests/sim/sim_base.gd"
## The match wrapper through a real MenuFlow: the pre-fight intro holds both fighters (the player's reader reads no
## device, the CPU's brain is set aside) and lets them go on FIGHT!, a key press skips it, the fighters barely move
## while held, practice gets no intro, and a finished fight opens the results screen with its buttons and numbers.

const HOLD_CAP: int = 400
## Ticks from the bleed-out to the results: MenuFlow.RESULT_DELAY_S, then the instant replay (KillCam) when it plays.
const RESULT_CAP: int = 1800


func _wait_until(cond: Callable, cap: int) -> int:
	var n: int = 0
	while n < cap and not bool(cond.call()):
		await host.get_tree().physics_frame
		n += 1
	return n


func _pelvis(m: Match, side: int) -> Vector3:
	return ((m.fighters[side] as Fighter).parts["pelvis"] as Node3D).global_position


func run() -> Array:
	var rows: Array = []
	await sandbox()
	var root := Node3D.new()
	world.add_child(root)
	var flow := MenuFlow.new()
	root.add_child(flow)
	flow.setup(root)
	await step(2)

	# vs CPU: held through the plates, free on FIGHT!.
	flow.call("_begin_fight", "player_vs_cpu")
	var m: Match = flow.current_match
	var show: MatchShow = m.get_node_or_null("MatchShow") as MatchShow
	await step(2)
	var reader: InputReader = m.readers[0] as InputReader
	var held: bool = show != null and flow.intro_phase() == "plates" and reader.device == "none" and m.brains[1] == null
	var p0: Vector3 = _pelvis(m, 0)
	var p1: Vector3 = _pelvis(m, 1)
	var n: int = await _wait_until(func() -> bool: return flow.intro_phase() != "plates", HOLD_CAP)
	var drift: float = maxf(_pelvis(m, 0).distance_to(p0), _pelvis(m, 1).distance_to(p1))
	await step(2)
	var freed: bool = reader.device != "none" and m.brains[1] != null
	var want_ticks: int = roundi(Tuning.shared().intro_s * 60.0)
	rows.append(row("match_show_intro_hold", held and freed and absi(n - want_ticks) <= 12 and drift < 0.35,
		"held=%s for %d ticks (intro_s %d), drift %.2f m, then reader '%s' and brain back=%s" % [str(held), n, want_ticks,
		drift, reader.device, str(m.brains[1] != null)]))
	var hint_after: int = await _wait_until(func() -> bool: return flow.intro_phase() == "", 120)
	rows.append(row("match_show_intro_ends", flow.intro_phase() == "" and int(flow.screen) == MenuFlow.Screen.FIGHT,
		"stinger over %d ticks after release, screen %d" % [hint_after, int(flow.screen)]))

	# Results: bleed the CPU out after a scripted blow and a sever.
	var foe: Fighter = m.fighters[1]
	foe.hit.emit({"attacker": 0, "target": 1, "part": "torso", "contact": "edge", "total": 12.0,
		"point": _pelvis(m, 1), "normal": Vector3.UP, "rel_vel": Vector3.ZERO})
	foe.gore.emit({"kind": "sever", "part": "forearm_l", "point": _pelvis(m, 1), "normal": Vector3.UP, "amount": 1.0})
	foe.health.blood = 0.3
	n = await _wait_until(func() -> bool: return int(flow.screen) == MenuFlow.Screen.RESULT, RESULT_CAP)
	await step(2)
	var res: MatchResults = flow.get("_results") as MatchResults
	var data: Dictionary = show.report(m.result, 0, false, {}, "")
	var rows_ok: bool = (data["rows"] as Array).size() == 4 and str((data["rows"] as Array)[2][1]) == "1"
	var fight_s: float = show.fight_seconds(int(m.result.get("ticks", 0)))
	rows.append(row("match_show_results", res != null and res.button_count() == 3 and flow.get("_pause") == null and rows_ok
		and str(data["latin"]) == "VICTORIA" and fight_s > 0.5 and fight_s < float(m.tick) / 60.0 - 2.0,
		"results after %d ticks: %d buttons, %s, severs %s, fight %.2f s of %.2f s (the intro is not fight time)" % [n,
		res.button_count() if res != null else -1, str(data["latin"]), str((data["rows"] as Array)[2]), fight_s, float(m.tick) / 60.0]))
	var touch_hidden: bool = true
	for c: Node in reader.get_children():
		if c is CanvasLayer and (c as CanvasLayer).visible:
			touch_hidden = false
	rows.append(row("match_show_results_touch", touch_hidden, "touch buttons hidden under the results"))

	# Rematch from the results: a fresh intro; a key press skips straight to FIGHT!.
	if res != null:
		res.chosen.emit("rematch")
	else:
		flow.call("_begin_fight", "player_vs_cpu")  # no results screen (already a failed row): carry on with the rest
	await step(20)
	var ph0: String = flow.intro_phase()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await step(3)
	var ph1: String = flow.intro_phase()
	var m2: Match = flow.current_match
	rows.append(row("match_show_skip", ph0 == "plates" and ph1 != "plates" and (m2.readers[0] as InputReader).device != "none",
		"rematch intro '%s', after a key '%s', reader '%s'" % [ph0, ph1, (m2.readers[0] as InputReader).device]))
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)

	# Local 2P: both readers held.
	flow.call("_begin_fight", "local_2p")
	await step(2)
	var m3: Match = flow.current_match
	var both: bool = (m3.readers[0] as InputReader).device == "none" and (m3.readers[1] as InputReader).device == "none"
	rows.append(row("match_show_local_2p", both and flow.intro_phase() == "plates", "both players held during the plates"))

	# Practice: no intro, nothing held.
	flow.call("_begin_practice")
	await step(3)
	var mp: Match = flow.current_match
	rows.append(row("match_show_practice", flow.intro_phase() == "" and (mp.readers[0] as InputReader).device != "none",
		"practice intro '%s', reader '%s'" % [flow.intro_phase(), (mp.readers[0] as InputReader).device]))

	flow.call("_show_title")
	await step(2)
	Engine.time_scale = 1.0
	host.get_tree().paused = false
	await clear()
	return rows
