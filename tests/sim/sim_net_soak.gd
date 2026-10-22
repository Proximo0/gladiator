extends "res://tests/sim/sim_base.gd"
## Online soak: host and client in one process over real ENet sockets on 127.0.0.1, both ends driven by the CPU
## brain (host side 0 by its own brain; client side 1 by the client match's brain reading the interpolated puppets,
## so it sees the world as late as a human would), a fake link on both directions, several full matches in a row.
## Not in the suite (long). Run with tools/net_soak.sh; each match prints `SOAK key=value ...` lines that the tool
## turns into a table. Arguments (after the sim name): rtt_ms loss matches time_limit_s.

const PORT: int = 17961
const BASE_SEED: int = 9100
const WEAPONS: Array = [["gladius", "spear"], ["dai_katana", "mace"], ["halberd", "longsword"], ["warhammer", "machete"],
	["laser_sword", "falchion"], ["axe", "shield_round"], ["sledgehammer", "rake"], ["fists", "bat"]]
const ARMOR_SETS: Array = [{}, {"torso": "cuirass_iron", "head": "helm_iron"}, {"torso": "mail", "legs": "greaves_leather"}]

var rtt_ms: int = 150
var loss: float = 0.03
var matches: int = 3
var drill: bool = false  ## scripted gore (gut, sever, behead) with full presentation, instead of bot matches
var time_limit_s: float = 30.0
var port: int = PORT
var out: Array = []  ## printed key=value lines are also returned as INFO rows

var _host: NetSession
var _client: NetSession
var _vp: SubViewport
var _hm: Match = null
var _cm: Match = null
var _rec: Dictionary = {}  ## host tick -> PackedVector3Array [pelvis0, hand0, tip0, pelvis1, hand1, tip1]
var _counts: Dictionary = {}  ## "h_behead" / "c_behead" ... -> int
var _roll_edges: Array = [0, 0]
var _client_roll_presses: int = 0
var _prev_input_roll: bool = false
var _roll_prev: Array = [false, false]


func _on_args() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() > 1:
		rtt_ms = int(a[1])
	if a.size() > 2:
		loss = float(a[2])
	if a.size() > 3:
		matches = int(a[3])
	if a.size() > 4:
		time_limit_s = float(a[4])
	if a.size() > 5:
		drill = a[5] == "drill"


func _client_input() -> FighterInput:
	var me: Fighter = _cm.fighters[1]
	var foe: Fighter = _cm.fighters[0]
	var inp: FighterInput = (_cm.brains[1] as FighterBrain).think(me.debug_frame(), foe.debug_frame(), 1.0 / 60.0)
	var roll: bool = inp.has(FighterInput.ROLL)
	if roll and not _prev_input_roll:
		_client_roll_presses += 1
	_prev_input_roll = roll
	return inp


func _count(k: String) -> void:
	_counts[k] = int(_counts.get(k, 0)) + 1


func _watch(prefix: String, m: Match) -> void:
	for side: int in 2:
		var f: Fighter = m.fighters[side]
		f.hit.connect(func(ev: Dictionary) -> void:
			if m.over:
				return
			_count(prefix + "_hit")
			if str(ev.get("finisher", "")) != "" and not bool(ev.get("hit_on_weapon", false)):
				_count(prefix + "_finisher"))
		f.gore.connect(func(ev: Dictionary) -> void:
			if m.over:
				return
			_count(prefix + "_gore_" + str(ev.get("kind", "?"))))


func _on_host_start(start: Dictionary) -> void:
	var m := Match.new()
	m.name = "HostMatch"
	world.add_child(m)
	m.setup(NetLobby.match_config(start, drill))
	var r: Variant = m.readers[0]
	if r != null:
		m.remove_child(r as Node)
		(r as Node).free()
	m.readers[0] = null
	m.brains[0] = FighterBrain.new(int(start.get("seed", 1)) * 31 + 5, (m.config["personalities"] as Array)[0])
	_host.attach_match(m)
	_host.host_driver.keep_history = false
	_hm = m
	_watch("h", m)


func _on_client_start(start: Dictionary) -> void:
	var m := Match.new()
	m.name = "ClientMatch"
	_vp.add_child(m)
	m.setup(NetLobby.match_config(start, drill))
	_client.attach_match(m)
	_client.client_driver.input_source = _client_input
	_cm = m
	_watch("c", m)


func _poses(m: Match) -> PackedVector3Array:
	var a := PackedVector3Array()
	for side: int in 2:
		var f: Fighter = m.fighters[side]
		a.append((f.parts["pelvis"] as Node3D).global_position)
		a.append((f.parts["forearm_r"] as Node3D).global_position)
		a.append(f.weapon.tip_position() if f.weapon != null and is_instance_valid(f.weapon) else (f.parts["forearm_r"] as Node3D).global_position)
	return a


func _host_at(t_in: float) -> PackedVector3Array:
	var t: float = t_in
	var t0: int = floori(t)
	if not _rec.has(t0) or not _rec.has(t0 + 1):
		return PackedVector3Array()
	var a: PackedVector3Array = _rec[t0]
	var b: PackedVector3Array = _rec[t0 + 1]
	var o := PackedVector3Array()
	for i: int in range(a.size()):
		o.append(a[i].lerp(b[i], t - float(t0)))
	return o


static func _pct(v: Array, p: float) -> float:
	if v.is_empty():
		return 0.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[mini(int(float(s.size()) * p), s.size() - 1)])


static func _mean(v: Array) -> float:
	var t: float = 0.0
	for x: Variant in v:
		t += float(x)
	return t / float(maxi(v.size(), 1))


func _say(line: String) -> void:
	print("SOAK " + line)
	out.append(["soak", null, line])


func run() -> Array:
	_on_args()
	await sandbox()
	var one_way_ticks: float = float(rtt_ms) / 2.0 * 60.0 / 1000.0
	var jit: int = clampi(roundi(one_way_ticks * 0.3), 0, 4)  ## jitter 0..jit, mean jit/2
	var lag: int = maxi(roundi(one_way_ticks - float(jit) / 2.0), 0)
	_say("profile rtt_ms=%d loss=%.3f lag_ticks=%d jitter_ticks=0..%d (link rtt about %.0f ms)" % [
		rtt_ms, loss, lag, jit, 2.0 * (float(lag) + float(jit) / 2.0) * 1000.0 / 60.0])
	for mi: int in range(matches):
		await _one_match(mi, lag, jit)
	return out


func _setup(mi: int, lag: int, jit: int, seed_value: int) -> bool:
	_counts.clear()
	_rec.clear()
	_roll_edges = [0, 0]
	_client_roll_presses = 0
	_prev_input_roll = false
	_roll_prev = [false, false]
	_hm = null
	_cm = null
	_host = NetSession.new()
	_host.name = "HostSession"
	world.add_child(_host)
	_client = NetSession.new()
	_client.name = "ClientSession"
	world.add_child(_client)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.add_child(_vp)
	_host.set_link(lag, jit, loss, 100 + mi)
	_client.set_link(lag, jit, loss, 200 + mi)
	var w: Array = WEAPONS[mi % WEAPONS.size()]
	var hw: String = str(w[0])
	var cw: String = str(w[1])
	var ho: String = "shield_round" if cw == "shield_round" else ""
	_host.set_local("Host", {"weapon": hw if hw != "shield_round" else "gladius", "offhand": "", "armor": ARMOR_SETS[mi % ARMOR_SETS.size()]})
	_client.set_local("Client", {"weapon": cw if cw != "shield_round" else "gladius", "offhand": ho, "armor": ARMOR_SETS[(mi + 1) % ARMOR_SETS.size()]})
	_host.match_requested.connect(_on_host_start)
	_client.match_requested.connect(_on_client_start)
	var err: Error = _host.host(port + mi, "127.0.0.1")
	if err == OK:
		err = _client.join("127.0.0.1", port + mi)
	var n: int = 0
	while err == OK and n < 600 and not (_host.remote_joined and _client.remote_joined):
		await host.get_tree().physics_frame
		n += 1
	if not (_host.remote_joined and _client.remote_joined):
		return false
	_host.start_match(seed_value, time_limit_s)
	return true


func _one_match(mi: int, lag: int, jit: int) -> void:
	if not await _setup(mi, lag, jit, BASE_SEED + mi):
		_say("match=%d FAILED lobby" % mi)
		await _teardown()
		return
	var seed_value: int = BASE_SEED + mi
	var w: Array = WEAPONS[mi % WEAPONS.size()]
	var hw: String = str(w[0])
	var cw: String = str(w[1])
	var err_pelvis: Array = []
	var err_hand: Array = []
	var err_tip: Array = []
	var err_roll: Array = []
	var lag_pelvis: Array = []
	var snap_windows: Array = []
	var extrap_run: int = 0
	var extrap_max: int = 0
	var extrap_total: int = 0
	var last_snaps: int = 0
	var cap: int = int((time_limit_s + 12.0) * 60.0)
	var roll_min_up: Array = [1.0, 1.0]
	var host_roll_min_up: Array = [1.0, 1.0]
	var tick_n: int = 0
	var tip_dbg: int = 0
	while tick_n < cap:
		await host.get_tree().physics_frame
		tick_n += 1
		if _hm == null or _cm == null:
			continue
		var ht: int = _hm.tick
		if drill:
			_drill(ht)
			_blood_peak(_hm, "h")
			_blood_peak(_cm, "c")
		_rec[ht + 1] = _poses(_hm)  ## read before the match steps tick ht + 1: it is the pose a snapshot stamped ht + 1 shows (checked: a one-tick shift of this key raises every error 3x)
		_rec.erase(ht - 239)
		for side: int in 2:
			var rl: bool = (_hm.fighters[side] as Fighter).rolling()
			if rl and not _roll_prev[side]:
				_roll_edges[side] += 1
			_roll_prev[side] = rl
			if rl:
				var up_h: float = ((_hm.fighters[side] as Fighter).parts["pelvis"] as Node3D).global_transform.basis.y.dot(Vector3.UP)
				host_roll_min_up[side] = minf(host_roll_min_up[side], up_h)
		var cd: NetClientDriver = _client.client_driver
		if cd != null and cd.shown != null and not _cm.over and not _hm.over:
			var rt: float = cd.interp.render_tick
			var extrap: bool = rt > float(cd.interp.newest_tick())
			if extrap:
				extrap_run += 1
				extrap_total += 1
				extrap_max = maxi(extrap_max, extrap_run)
			else:
				extrap_run = 0
			var ref: PackedVector3Array = _host_at(rt)
			if not ref.is_empty():
				var cur: PackedVector3Array = _poses(_cm)
				for side: int in 2:
					var ep: float = cur[side * 3].distance_to(ref[side * 3])
					err_pelvis.append(ep)
					err_hand.append(cur[side * 3 + 1].distance_to(ref[side * 3 + 1]))
					var et: float = cur[side * 3 + 2].distance_to(ref[side * 3 + 2])
					var hw_ok: bool = (_hm.fighters[side] as Fighter).weapon != null  ## dropped weapon: the client keeps the reference, skip
					if hw_ok:
						err_tip.append(et)
					if hw_ok and et > 0.5 and tip_dbg < 6:
						tip_dbg += 1
						var hf: Fighter = _hm.fighters[side]
						var cf: Fighter = _cm.fighters[side]
						_say("tipdbg tick=%d side=%d err=%.2f host_w=%s client_w=%s host_state=%s hold=%s/%s" % [ht, side, et, str(hf.weapon.name if hf.weapon != null else "null"), str(cf.weapon.name if cf.weapon != null else "null"), hf.state(), str(hf.weapon.holder if hf.weapon != null else ""), str(cf.weapon.holder if cf.weapon != null else "")])
					if _roll_prev[side]:
						err_roll.append(ep)
						var up_c: float = ((_cm.fighters[side] as Fighter).parts["pelvis"] as Node3D).global_transform.basis.y.dot(Vector3.UP)
						roll_min_up[side] = minf(roll_min_up[side], up_c)
			var now_h: PackedVector3Array = _rec.get(ht, PackedVector3Array())
			if not now_h.is_empty():
				var cur2: PackedVector3Array = _poses(_cm)
				for side: int in 2:
					lag_pelvis.append(cur2[side * 3].distance_to(now_h[side * 3]))
		_host.bw_out.per_second(_host.local_tick)
		_client.bw_out.per_second(_client.local_tick)
		if tick_n % 60 == 0 and cd != null:
			snap_windows.append(cd.snapshots_received - last_snaps)
			last_snaps = cd.snapshots_received
		if _hm.over and _cm.over:
			break
	# let trailing reliable packets land
	for _i: int in range(30):
		await host.get_tree().physics_frame
	var hd: NetHostDriver = _host.host_driver
	var cd2: NetClientDriver = _client.client_driver
	var secs: float = float(maxi(_hm.tick, 1)) / 60.0
	var hr: Dictionary = _hm.result
	var cr: Dictionary = _cm.result
	var same: bool = _hm.over and _cm.over and int(hr.get("winner", -9)) == int(cr.get("winner", -8))
	var inner_snaps: Array = snap_windows.slice(1) if snap_windows.size() > 2 else snap_windows
	_say("match=%d seed=%d w=%s/%s secs=%.1f over=%s/%s same_result=%s winner=%s reason=%s" % [mi, seed_value, hw, cw, secs, _hm.over,
		_cm.over, same, hr.get("winner"), hr.get("reason")])
	_say("match=%d snaps host_sent=%d client_got=%d rate_hz=%.1f min_window=%d interp_delay_ms=%.0f extrap_ticks=%d extrap_max_run=%d held=%d resyncs=%d dropped_old=%d" % [
		mi, hd.snapshots_sent, cd2.snapshots_received, float(cd2.snapshots_received) / secs, int(inner_snaps.min()) if not inner_snaps.is_empty() else 0,
		cd2.interp.delay * 1000.0 / 60.0, extrap_total, extrap_max, cd2.interp.held_ticks, cd2.interp.resyncs, cd2.interp.dropped_old])
	_say("match=%d err_m pelvis mean=%.3f p95=%.3f max=%.3f | hand mean=%.3f p95=%.3f max=%.3f | tip mean=%.3f p95=%.3f max=%.3f | pelvis_vs_host_now mean=%.3f p95=%.3f" % [
		mi, _mean(err_pelvis), _pct(err_pelvis, 0.95), _pct(err_pelvis, 1.0), _mean(err_hand), _pct(err_hand, 0.95), _pct(err_hand, 1.0),
		_mean(err_tip), _pct(err_tip, 0.95), _pct(err_tip, 1.0), _mean(lag_pelvis), _pct(lag_pelvis, 0.95)])
	var ib: NetInputBuffer = hd.inputs
	_say("match=%d input_to_screen_ticks=%.1f (%.0f ms) host_inputs got=%d dup=%d late=%d underruns=%d skipped=%d carried_presses=%d stale_pops=%d" % [
		mi, cd2.input_to_screen_ticks(), cd2.input_to_screen_ticks() * 1000.0 / 60.0, ib.received, ib.duplicates, ib.late, ib.underruns, ib.skipped, ib.carried, ib.stale_pops])
	_say("match=%d rolls host_side0=%d host_side1=%d client_presses=%d roll_pelvis_err_mean=%.3f max=%.3f min_up host=%.2f/%.2f client=%.2f/%.2f" % [
		mi, _roll_edges[0], _roll_edges[1], _client_roll_presses, _mean(err_roll), _pct(err_roll, 1.0), host_roll_min_up[0], host_roll_min_up[1],
		roll_min_up[0], roll_min_up[1]])
	var kinds: Array = []
	for k: Variant in _counts.keys():
		var ks: String = str(k)
		if ks.begins_with("h_"):
			kinds.append("%s=%d/%d" % [ks.substr(2), int(_counts[k]), int(_counts.get("c_" + ks.substr(2), 0))])
	kinds.sort()
	_say("match=%d events (host/client played) %s" % [mi, " ".join(kinds)])
	var caps: Array = [_caps(_hm), _caps(_cm)]
	var sev: Array = [_severed(_hm), _severed(_cm)]
	_say("match=%d stumps host_caps=%s client_caps=%s severed host=%s client=%s" % [mi, str(caps[0]), str(caps[1]), str(sev[0]), str(sev[1])])
	var ms: Dictionary = _host.max_sent
	_say("match=%d bytes max_snap=%d max_events=%d max_input=%d (client max_input=%d) host_out_avg=%.1fKB/s peak=%.1f client_out_avg=%.1fKB/s peak=%.1f" % [
		mi, int(ms.get(NetConfig.MSG_SNAP, 0)), int(ms.get(NetConfig.MSG_EVENTS, 0)), int(ms.get(NetConfig.MSG_INPUT, 0)),
		int(_client.max_sent.get(NetConfig.MSG_INPUT, 0)), _host.bw_out.average(_host.local_tick) / 1000.0, _host.bw_out.peak_per_s / 1000.0,
		_client.bw_out.average(_client.local_tick) / 1000.0, _client.bw_out.peak_per_s / 1000.0])
	await _teardown()


func _drill(t: int) -> void:
	var f0: Fighter = _hm.fighters[0]
	var f1: Fighter = _hm.fighters[1]
	if t == 120:
		var p: Vector3 = (f0.parts["torso"] as Node3D).global_position
		f0.gore.emit({"kind": "gut", "part": "torso", "amount": 1.0, "point": p + Vector3(0, 0, 0.12), "normal": Vector3(0, 0, 1)})
	elif t == 200 and not f1.is_limb_cut("forearm_l"):
		var p2: Vector3 = (f1.parts["forearm_l"] as Node3D).global_position
		f1.gore.emit({"kind": "sever", "part": "forearm_l", "amount": 1.0, "point": p2, "normal": Vector3(1, 0, 0)})
		f1.call("_sever", "forearm_l")
	elif t == 300 and not f0.is_limb_cut("head"):
		var p3: Vector3 = (f0.parts["head"] as Node3D).global_position - Vector3(0, 0.1, 0)
		f0.gore.emit({"kind": "behead", "part": "head", "amount": 1.0, "point": p3, "normal": Vector3(0, 0, 1)})
		f0.call("_sever", "head")


func _blood_peak(m: Match, pre: String) -> void:
	if m.presenter == null:
		return
	var b: BloodFx = (m.presenter as MatchPresenter).blood
	_counts[pre + "_zspurts_peak"] = maxi(int(_counts.get(pre + "_zspurts_peak", 0)), (b.get("_spurts") as Array).size())
	_counts[pre + "_zemitted"] = b.stat_emitted


func _caps(m: Match) -> Array:
	var r: Array = []
	for side: int in 2:
		var art: Variant = (m.fighters[side] as Fighter).get("_art")
		var c: Variant = art.get("_caps") if art != null else {}
		r.append((c as Dictionary).size() if c is Dictionary else -1)
	return r


func _severed(m: Match) -> Array:
	var r: Array = []
	for side: int in 2:
		r.append(((m.fighters[side] as Fighter).get("_severed") as Array).size())
	return r


func _teardown() -> void:
	if _client != null:
		_client.leave("done")
	if _host != null:
		_host.leave("done")
	Engine.time_scale = 1.0
	await host.get_tree().physics_frame
	for n: Node in [_host, _client, _vp, _hm]:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_host = null
	_client = null
	_vp = null
	await host.get_tree().physics_frame
