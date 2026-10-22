extends "res://tests/sim/sim_base.gd"
## Instant replay of the finishing blow in a presented match: two bots fight with longswords for a few seconds, then a
## beheading lands (the hit is fed straight to the victim, as a real blade contact would be). After match_over the
## KillCam must pick that blow, rewind the scene (head cap off, physics paused), play the window with the slow motion
## and its three shots, put the cut back at the right tick, re-fire the blood with the live RNG state (same droplets),
## skip on demand, and restore the live scene. Reports ring memory and record / playback cost per frame.

const SEED: int = 4242
const FIGHT_TICKS: int = 200
const AFTER_TICKS: int = 110
const GUARD_FRAMES: int = 1200


func _behead(m: Match) -> Dictionary:
	var victim: Fighter = m.fighters[1]
	var atk: Fighter = m.fighters[0]
	var head: RigidBody3D = victim.parts["head"]
	var nrm: Vector3 = (head.global_position - (atk.parts["torso"] as Node3D).global_position)
	nrm = Vector3(nrm.x, 0.0, nrm.z).normalized()
	var ev: Dictionary = {
		"part": "head", "point": head.global_position - nrm * 0.08 + Vector3(0, -0.08, 0), "normal": nrm,
		"knockback": nrm * 6.0, "total": 60.0, "cut": 60.0, "pierce": 0.0, "blunt": 0.0, "bleed": 0.5,
		"sever": true, "behead": true, "finisher": "behead", "contact": "edge", "rel_vel": nrm.cross(Vector3.UP) * 9.0,
		"attacker": 0, "target": 1, "weapon_id": "longsword", "energy": 240.0, "stagger": 0.5,
	}
	victim.call("_take_hit", ev, head, atk.weapon, atk)
	return ev


static func _drops(sim: BloodSim, from: int) -> Array:
	var out: Array = []
	for i: int in range(from, sim.count):
		var o: int = i * BloodSim.STRIDE
		out.append(Vector3(sim.buf[o + BloodSim.C_VX], sim.buf[o + BloodSim.C_VY], sim.buf[o + BloodSim.C_VZ]))
	return out


static func _has_cap(f: Fighter, key: String) -> bool:
	var art: Object = f.get("_art")
	return art != null and (art.get("_caps") as Dictionary).has(key)


func run() -> Array:
	await sandbox()
	var rows: Array = []
	var m := Match.new()
	var overs: Array = []
	m.match_over.connect(func(r: Dictionary) -> void: overs.append(r))
	world.add_child(m)
	var lo: Dictionary = {"weapon": "longsword", "offhand": "", "armor": {}}
	m.setup({"mode": "bot_vs_bot", "seed": SEED, "presentation": true, "loop": false, "time_limit_s": 60.0,
		"loadouts": [lo.duplicate(true), lo.duplicate(true)]})
	await step(FIGHT_TICKS)
	var kc: KillCam = m.presenter.killcam
	var blood: BloodFx = m.presenter.blood
	var victim: Fighter = m.fighters[1]
	if overs.is_empty():
		var c0: int = blood.sim.count
		var rng_before: int = blood.rng.state
		var hits_before: int = kc.ring.events.size()
		_behead(m)
		var live_drops: Array = _drops(blood.sim, c0)
		var rec_rng: int = -1
		for e: Variant in kc.ring.events.slice(hits_before):
			if str((e as Array)[2]) == "hit":
				rec_rng = int((e as Array)[4])
		rows.append(row("killcam_records_blood_rng", rec_rng == rng_before, "recorded %d live %d" % [rec_rng, rng_before]))
		rows.append(row("killcam_live_burst", live_drops.size() > 50, "%d drops" % live_drops.size()))
		# The same two calls the replay makes, from the recorded rows: the same droplets.
		var kill_rows: Array = kc.ring.events.slice(hits_before)
		blood.sim.count = 0
		for e: Variant in kill_rows:
			var r: Array = e
			blood.rng.state = int(r[4])
			if str(r[2]) == "hit":
				blood.on_hit(r[3] as Dictionary, victim)
			elif str(r[2]) == "gore":
				blood.on_gore(r[3] as Dictionary, victim)
		var again: Array = _drops(blood.sim, 0)
		rows.append(row("killcam_blood_same_droplets", again == live_drops, "%d vs %d drops" % [again.size(), live_drops.size()]))
	var guard: int = 0
	while overs.is_empty() and guard < 120:
		await step(1)
		guard += 1
	rows.append(row("killcam_match_ends_on_the_behead", not overs.is_empty() and str(m.result.get("reason", "")) == "behead",
			"reason %s" % str(m.result.get("reason", "none"))))
	await step(AFTER_TICKS)
	var st: Dictionary = kc.stats()
	rows.append(row("killcam_ring_memory", null, "%d frames x %d bodies = %.0f KB (%d events), record %.0f us/tick median, %.0f mean, %d max" % [
		int(st["frames"]), int(st["bodies"]), float(st["bytes"]) / 1024.0, int(st["events"]), float(st["record_us_median"]),
		float(st["record_us_mean"]), int(st["record_us_max"])]))
	var plan: Dictionary = kc.plan_for(m.result)
	rows.append(row("killcam_picks_the_behead", str(plan.get("kind", "")) == "behead" and int(plan.get("victim", -1)) == 1,
			"plan %s" % str(plan.get("kind", "none"))))
	var head: RigidBody3D = victim.parts["head"]
	var live_head: Transform3D = head.global_transform
	var live_cam: Camera3D = m.get_viewport().get_camera_3d()
	var live_sim: BloodSim = blood.sim
	var live_drops_n: int = blood.sim.count
	var done: Array = []
	kc.finished.connect(func() -> void: done.append(true))
	var started: bool = kc.play(m.result)
	rows.append(row("killcam_plays", started and kc.playing, ""))
	var start_head: Transform3D = ReplayRing.pose(kc.ring.frame(int(plan.get("start_tick", 0))), int((kc.get("_index") as Dictionary)[head.get_instance_id()]))
	rows.append(row("killcam_rewinds_pose", head.global_transform.origin.distance_to(start_head.origin) < 0.001 and head.freeze,
			"head %.3f m from the window start, frozen %s" % [head.global_transform.origin.distance_to(start_head.origin), str(head.freeze)]))
	rows.append(row("killcam_rewinds_cut", not _has_cap(victim, "head_piece") and not _has_cap(victim, "head_stump"), "caps off before the blow"))
	rows.append(row("killcam_own_camera", m.get_viewport().get_camera_3d() != live_cam, ""))
	var shots: Dictionary = {}
	var cut_at: float = -1.0
	var drops_after_kill: int = 0
	var frames: int = 0
	var kill: float = float(plan.get("kill_tick", 0))
	var bad_cam: int = 0
	while done.is_empty() and frames < GUARD_FRAMES:
		await host.get_tree().process_frame
		frames += 1
		if not kc.playing:
			break
		shots[kc.get("_shot")] = true
		var pos: float = float(kc.get("_pos"))
		if cut_at < 0.0 and _has_cap(victim, "head_piece"):
			cut_at = pos
		if pos > kill and pos < kill + 6.0:
			drops_after_kill = maxi(drops_after_kill, blood.sim.count)
		var cp: Vector3 = (kc.get("_cam") as Camera3D).global_position
		if not FightCamera.is_finite_v3(cp) or cp.y < 0.2 or Vector2(cp.x, cp.z).length() > 11.0:
			bad_cam += 1
	rows.append(row("killcam_finishes", not done.is_empty() and not kc.playing, "%d frames (%.1f s real at 60 fps)" % [frames, float(frames) / 60.0]))
	rows.append(row("killcam_three_shots", shots.size() == 3, "shots %s" % str(shots.keys())))
	rows.append(row("killcam_cut_at_the_blow", cut_at >= kill - 0.5 and cut_at <= kill + 2.0, "cap back at tick %.1f, blow at %d" % [cut_at, int(kill)]))
	rows.append(row("killcam_blood_replays", drops_after_kill > 50, "%d drops in flight after the blow" % drops_after_kill))
	rows.append(row("killcam_camera_sane", bad_cam == 0, "%d bad camera frames" % bad_cam))
	var st2: Dictionary = kc.stats()
	rows.append(row("killcam_playback_cost", null, "%.0f us/frame median (posing %.0f, rest is the blood step), %.0f mean, %d max; %d events re-run" % [
			float(st2["play_us_median"]), float(st2["pose_us_median"]), float(st2["play_us_mean"]), int(st2["play_us_max"]), kc.fired]))
	rows.append(row("killcam_restores_scene", head.global_transform.origin.distance_to(live_head.origin) < 0.001 and not head.freeze \
			and m.get_viewport().get_camera_3d() == live_cam and _has_cap(victim, "head_piece") and m.is_physics_processing() \
			and victim.is_physics_processing() and blood.sim == live_sim and blood.sim.count == live_drops_n and blood.is_processing(),
			"head back %.4f m, frozen %s, live blood back %s (%d drops)" % [head.global_transform.origin.distance_to(live_head.origin),
			str(head.freeze), str(blood.sim == live_sim), blood.sim.count]))
	await step(5)
	live_head = head.global_transform
	# A second replay, skipped after half a second: lands on the end state at once.
	done.clear()
	kc.play(m.result)
	await step(40)
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	var waited: int = 0
	while done.is_empty() and waited < 30:
		await host.get_tree().process_frame
		waited += 1
	rows.append(row("killcam_skip", not done.is_empty() and kc.skipped and _has_cap(victim, "head_piece") and not head.freeze,
			"skipped after %d frames" % waited))
	await step(5)
	var pel: RigidBody3D = victim.parts["pelvis"]
	rows.append(row("killcam_physics_resumes", head.global_transform.origin.distance_to(live_head.origin) < 2.0 and FightCamera.is_finite_v3(head.global_position),
			"head moved %.2f m, speed %.2f, pelvis speed %.2f" % [head.global_transform.origin.distance_to(live_head.origin), head.linear_velocity.length(), pel.linear_velocity.length()]))
	await clear()
	return rows
