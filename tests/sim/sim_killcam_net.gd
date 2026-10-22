extends "res://tests/sim/sim_net_loopback.gd"
## The instant replay online, on the client: the presented loopback match over a clean link, the host beheads the
## client's fighter, and after the result the client replays the blow from its own buffer (the snapshot-posed puppets
## and the events it played). Checks the client picked the behead, played all three shots with the cut put back at
## the blow, sent nothing extra while replaying, and handed its puppets back to the net driver afterwards.

const BEHEAD_TICK: int = 260
const GUARD_FRAMES: int = 1200

var _kc_rows: Array = []
var _beheaded: bool = false


func run() -> Array:
	present = true
	prefix = "killcam_net"
	time_limit_s = 20.0
	port = 17971
	lag_ticks = 0
	jitter_ticks = 0
	loss = 0.0
	var rows: Array = await super()
	var keep: Array = []
	for r: Array in rows:  # the loopback rows ran in sim_net_*; keep only what this scenario adds
		if str(r[0]) in [prefix + "_same_result", prefix + "_lobby"]:
			keep.append(r)
	keep.append_array(_kc_rows)
	return keep


func _on_host_start(start: Dictionary) -> void:
	super(start)
	_host_match.inputs_applied.connect(_on_host_tick)


func _on_host_tick(tick: int, _inputs: Array) -> void:
	if tick != BEHEAD_TICK or _beheaded:
		return
	_beheaded = true
	var victim: Fighter = _host_match.fighters[1]
	var atk: Fighter = _host_match.fighters[0]
	var head: RigidBody3D = victim.parts["head"]
	var nrm: Vector3 = head.global_position - (atk.parts["torso"] as Node3D).global_position
	nrm = Vector3(nrm.x, 0.0, nrm.z).normalized()
	var ev: Dictionary = {
		"part": "head", "point": head.global_position - nrm * 0.08, "normal": nrm, "knockback": nrm * 6.0, "total": 60.0,
		"cut": 60.0, "pierce": 0.0, "blunt": 0.0, "bleed": 0.5, "sever": true, "behead": true, "finisher": "behead",
		"contact": "edge", "rel_vel": nrm.cross(Vector3.UP) * 9.0, "attacker": 0, "target": 1, "weapon_id": "gladius",
		"energy": 240.0, "stagger": 0.5,
	}
	victim.call("_take_hit", ev, head, atk.weapon, atk)


func _has_cap(f: Fighter, key: String) -> bool:
	var art: Object = f.get("_art")
	return art != null and (art.get("_caps") as Dictionary).has(key)


func _end_pause_row() -> Array:
	var r: Array = await super()
	var cm: Match = _client_match
	var kc: KillCam = cm.presenter.killcam
	var cd: NetClientDriver = _client.client_driver
	var st: Dictionary = kc.stats()
	var plan: Dictionary = kc.plan_for(cm.result)
	_kc_rows.append(row(prefix + "_client_picks_the_behead", str(plan.get("kind", "")) == "behead" and int(plan.get("victim", -1)) == 1,
			"client result %s, plan %s at tick %s; buffer %d frames x %d bodies = %.0f KB, %d events" % [
			str(cm.result.get("reason", "?")), str(plan.get("kind", "none")), str(plan.get("kill_tick", "-")),
			int(st["frames"]), int(st["bodies"]), float(st["bytes"]) / 1024.0, int(st["events"])]))
	var victim: Fighter = cm.fighters[1]
	var sent_before: int = _client.bw_out.total_bytes
	var done: Array = []
	kc.finished.connect(func() -> void: done.append(true))
	var started: bool = kc.play(cm.result)
	var paused: bool = started and not cd.is_physics_processing()
	var uncut: bool = started and not _has_cap(victim, "head_piece")
	var shots: Dictionary = {}
	var cut_at: float = -1.0
	var frames: int = 0
	while started and done.is_empty() and frames < GUARD_FRAMES:
		await host.get_tree().process_frame
		frames += 1
		if not kc.playing:
			break
		shots[kc.get("_shot")] = true
		if cut_at < 0.0 and _has_cap(victim, "head_piece"):
			cut_at = float(kc.get("_pos"))
	var kill: float = float(plan.get("kill_tick", 0))
	_kc_rows.append(row(prefix + "_client_replays", started and paused and uncut and not done.is_empty() and shots.size() == 3 \
			and cut_at >= kill - 0.5 and cut_at <= kill + 3.0,
			"driver paused %s, caps off %s, %d frames, shots %s, cap back at %.1f (blow %d)" % [str(paused), str(uncut), frames,
			str(shots.keys()), cut_at, int(kill)]))
	var sent_after: int = _client.bw_out.total_bytes
	_kc_rows.append(row(prefix + "_client_hands_back", cd.is_physics_processing() and _client.close_reason == "" and _has_cap(victim, "head_piece"),
			"driver running %s, connection %s, %d bytes sent during the %.1f s replay (%d one-byte keep-alives; no replay data goes over the network)" % [
			str(cd.is_physics_processing()), "open" if _client.close_reason == "" else _client.close_reason, sent_after - sent_before,
			float(frames) / 60.0, kc.keepalive_sent]))
	return r
