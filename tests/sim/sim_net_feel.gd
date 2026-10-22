extends "res://tests/sim/sim_base.gd"
## Online feel: how soon the client sees its own input answered. Host and client in one process over real ENet on
## 127.0.0.1 with a fake link both ways (latency, jitter, loss). The host's side 0 stands idle; the client's side 1
## runs a script: guard aim steps, swing aim steps and dodge rolls, one every CYCLE ticks. For each one it records, on
## the client's screen and on the host, the ticks from the press to the first visible move (hand 3 cm, or pelvis
## 3 cm / torso 0.1 rad for a roll) and to half the move, the largest one-tick jump and the largest step back
## against the move (a correction that snaps or a lead that is taken back shows here).
## In the suite (no arguments): 150 ms RTT, 3% loss, 24 s, checks response, jumps and backtracking.
## Alone: godot --headless --fixed-fps 60 --path . -s res://tests/sim/sim_net_solo.gd -- sim_net_feel <rtt_ms> <loss> <secs>
## prints `FEEL ...` lines (tools/net_soak.sh --feel).

var _port: int = net_port(46)
const SEED: int = 9300
const CYCLE: int = 90
const MOVE_EPS: float = 0.03  ## m: hand or pelvis moved this far = visible response
const TILT_EPS: float = 0.1  ## rad: torso tilted this far = visible roll response
const AIM_A: Vector2i = Vector2i(700, 500)
const AIM_B: Vector2i = Vector2i(-700, -300)
const KINDS: Array[String] = ["guard", "swing", "guard", "roll"]
const SWING_TICKS: int = 30  ## a swing step holds SWING this long
const FIRST_MAX_TICKS: float = 3.0  ## suite check: mean ticks from press to the first visible move on the client
const JUMP_RATIO: float = 1.5  ## ... largest one-tick move at most this times the host's, plus JUMP_SLACK_M
const JUMP_SLACK_M: float = 0.03
const BACK_SLACK_M: float = 0.03  ## ... and step back against the move at most the host's plus this

var rtt_ms: int = 150
var loss: float = 0.03
var secs: float = 24.0
var suite: bool = true
var leads: bool = true  ## the client's cosmetic leads (`nolead` as the 4th argument measures without them)
var out: Array = []

var _host: NetSession
var _client: NetSession
var _vp: SubViewport
var _hm: Match = null
var _cm: Match = null
var _frame: int = 0
var _src_n: int = 0
var _aim: Vector2i = AIM_B
var _roll_side: int = 1
var _cycle_kind: String = ""
var _cycle_start: int = -1  ## frame the cycle's input was recorded
var _press_input_tick: int = -1
var _samples: Array = []  ## per frame: [client hand, host hand, client pelvis, host pelvis, client torso up, host torso up, host rolling, host applied]
var _res: Dictionary = {}  ## kind -> Array of per-press Dictionaries


func _on_args() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() > 1 and a[0] == "sim_net_feel" and a[1].is_valid_int():
		suite = false
		rtt_ms = int(a[1])
		if a.size() > 2:
			loss = float(a[2])
		if a.size() > 3:
			secs = float(a[3])
		leads = not (a.size() > 4 and a[4] == "nolead")


func _say(line: String) -> void:
	if not suite:
		print("FEEL " + line)
	out.append(["net_feel_info", null, line])


## The client's scripted input: one action per CYCLE ticks.
func _client_input() -> FighterInput:
	var n: int = _src_n
	_src_n += 1
	var phase: int = n % CYCLE
	var kind: String = KINDS[(n / CYCLE) % KINDS.size()]
	if phase == 0:
		_close_cycle()
		_cycle_kind = kind
		_cycle_start = _frame
		_press_input_tick = _client.client_driver.get("_input_tick") if _client.client_driver != null else -1
		_samples.clear()
		if kind != "roll":
			_aim = AIM_A if _aim == AIM_B else AIM_B
		else:
			_roll_side = -_roll_side
	var inp := FighterInput.new()
	inp.aim_x = _aim.x
	inp.aim_y = _aim.y
	if kind == "swing" and phase < SWING_TICKS:
		inp.buttons |= FighterInput.SWING
	if kind == "roll":
		if phase < 24:
			inp.move_x = 1000 * _roll_side
		if phase < 3:
			inp.buttons |= FighterInput.ROLL
	return inp


func _hand(f: Fighter) -> Vector3:
	return (f.parts["forearm_r"] as Node3D).global_transform * FighterRig.HAND_LOCAL


func _sample() -> void:
	if _cycle_start < 0 or _hm == null or _cm == null:
		return
	var cf: Fighter = _cm.fighters[1]
	var hf: Fighter = _hm.fighters[1]
	var applied: bool = _host.host_driver != null and _host.host_driver.inputs.last_applied_tick >= _press_input_tick
	_samples.append([_hand(cf), _hand(hf), (cf.parts["pelvis"] as Node3D).global_position, (hf.parts["pelvis"] as Node3D).global_position,
		(cf.parts["torso"] as Node3D).global_transform.basis.y, (hf.parts["torso"] as Node3D).global_transform.basis.y, hf.rolling(), applied])


## Ticks from the press (the frame the input was recorded) to the first sample where `moved` is true; -1 = never.
static func _first(vals: Array, limit: float) -> int:
	for k: int in range(1, vals.size()):
		if float(vals[k]) >= limit:
			return k - 1
	return -1


func _close_cycle() -> void:
	if _cycle_start < 0 or _samples.size() < 70 or _cycle_kind == "":
		return
	var s: Array = _samples
	var r: Dictionary = {}
	var applied_at: int = -1
	for k: int in range(s.size()):
		if bool(s[k][7]):
			applied_at = k - 1
			break
	r["applied"] = applied_at
	if _cycle_kind == "roll":
		var rolled: bool = false
		for k: int in range(s.size()):
			rolled = rolled or bool(s[k][6])
		r["rolled"] = rolled
		for who: int in 2:
			var mv: Array = []
			var jump: float = 0.0
			for k: int in range(s.size()):
				var p0: Vector3 = s[0][2 + who]
				var drop: float = p0.y - (s[k][2 + who] as Vector3).y
				var tilt: float = (s[0][4 + who] as Vector3).angle_to(s[k][4 + who] as Vector3)
				mv.append(maxf(drop / MOVE_EPS, tilt / TILT_EPS))
				if k > 0:
					jump = maxf(jump, (s[k][2 + who] as Vector3).distance_to(s[k - 1][2 + who] as Vector3))
			var tag: String = "c" if who == 0 else "h"
			r[tag + "_first"] = _first(mv, 1.0)
			r[tag + "_jump"] = jump
	else:
		var total: Vector3 = (s[mini(60, s.size() - 1)][1] as Vector3) - (s[0][1] as Vector3)
		if total.length() < 0.06:
			return
		var d: Vector3 = total.normalized()
		r["dist"] = total.length()
		for who: int in 2:
			var proj: Array = []
			var jump: float = 0.0
			var back: float = 0.0
			var best: float = -INF
			# A swing step ends with SWING let go (phase 30), a new command that pulls the hand back in: step back is
			# only counted until that release shows (at once on the client's leading hand, a round trip later on the host).
			var until: int = s.size()
			if _cycle_kind == "swing":
				until = SWING_TICKS + (maxi(applied_at, 0) if who == 1 else 0)
			for k: int in range(s.size()):
				var p: float = ((s[k][who] as Vector3) - (s[0][who] as Vector3)).dot(d)
				proj.append(p)
				best = maxf(best, p)
				if k < until:
					back = maxf(back, best - p)
				if k > 0:
					jump = maxf(jump, (s[k][who] as Vector3).distance_to(s[k - 1][who] as Vector3))
			var tag: String = "c" if who == 0 else "h"
			r[tag + "_first"] = _first(proj, MOVE_EPS)
			r[tag + "_half"] = _first(proj, 0.5 * total.length())
			r[tag + "_jump"] = jump
			r[tag + "_back"] = back
	if not _res.has(_cycle_kind):
		_res[_cycle_kind] = []
	(_res[_cycle_kind] as Array).append(r)


func _on_host_start(start: Dictionary) -> void:
	var m := Match.new()
	m.name = "FeelHostMatch"
	world.add_child(m)
	m.setup(NetLobby.match_config(start, false))
	var r: Variant = m.readers[0]
	if r != null:
		m.remove_child(r as Node)
		(r as Node).free()
	m.readers[0] = null
	m.brains[0] = NetRemoteBrain.new(NetInputBuffer.new())  ## never fed: side 0 stands still
	_host.attach_match(m)
	_hm = m


func _on_client_start(start: Dictionary) -> void:
	var m := Match.new()
	m.name = "FeelClientMatch"
	_vp.add_child(m)
	m.setup(NetLobby.match_config(start, false))
	_client.attach_match(m)
	_client.client_driver.input_source = _client_input
	_client.client_driver.leads_enabled = leads
	_cm = m


static func _stat(rows: Array, key: String) -> Array:
	var v: Array = []
	for r: Dictionary in rows:
		if r.has(key) and (typeof(r[key]) != TYPE_INT or int(r[key]) >= 0):
			v.append(float(r[key]))
	return v


static func _mean(v: Array) -> float:
	var t: float = 0.0
	for x: Variant in v:
		t += float(x)
	return t / float(maxi(v.size(), 1))


static func _max(v: Array) -> float:
	return float(v.max()) if not v.is_empty() else 0.0


func run() -> Array:
	_on_args()
	await sandbox()
	var one_way: float = float(rtt_ms) / 2.0 * 60.0 / 1000.0
	var jit: int = clampi(roundi(one_way * 0.3), 0, 4)
	var lag: int = maxi(roundi(one_way - float(jit) / 2.0), 0)
	_host = NetSession.new()
	_host.name = "FeelHost"
	world.add_child(_host)
	_client = NetSession.new()
	_client.name = "FeelClient"
	world.add_child(_client)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.add_child(_vp)
	_host.set_link(lag, jit, loss, 301)
	_client.set_link(lag, jit, loss, 302)
	_host.set_local("Host", {"weapon": "gladius", "offhand": "", "armor": {}})
	_client.set_local("Client", {"weapon": "longsword", "offhand": "", "armor": {}})
	_host.match_requested.connect(_on_host_start)
	_client.match_requested.connect(_on_client_start)
	var err: Error = _host.host(_port, "127.0.0.1")
	if err == OK:
		err = _client.join("127.0.0.1", _port)
	var n: int = 0
	while err == OK and n < 600 and not (_host.remote_joined and _client.remote_joined):
		await host.get_tree().physics_frame
		n += 1
	var rows: Array = []
	if not (_host.remote_joined and _client.remote_joined):
		rows.append(row("net_feel_lobby", false, "no connection (port %d)" % _port))
		await _teardown()
		return rows
	_host.start_match(SEED, secs + 30.0)
	var cap: int = int(secs * 60.0) + 120
	while _frame < cap:
		await host.get_tree().physics_frame
		_frame += 1
		_sample()
		if _hm != null and _hm.over:
			break
	_close_cycle()
	var cd: NetClientDriver = _client.client_driver
	var its: float = cd.input_to_screen_ticks() if cd != null else 0.0
	_say("profile rtt_ms=%d loss=%.3f lag_ticks=%d jitter_ticks=0..%d secs=%.0f input_to_screen_ticks=%.1f" % [rtt_ms, loss, lag, jit, secs, its])
	var summary: Dictionary = {}
	for kind: String in ["guard", "swing", "roll"]:
		var rs: Array = _res.get(kind, [])
		var line: String = "%s n=%d applied=%.1f" % [kind, rs.size(), _mean(_stat(rs, "applied"))]
		for tag: String in ["c", "h"]:
			line += " %s_first=%.1f/%.0f %s_jump=%.3f" % [tag, _mean(_stat(rs, tag + "_first")), _max(_stat(rs, tag + "_first")), tag, _max(_stat(rs, tag + "_jump"))]
			if kind != "roll":
				line += " %s_half=%.1f %s_back=%.3f" % [tag, _mean(_stat(rs, tag + "_half")), tag, _max(_stat(rs, tag + "_back"))]
		if kind == "roll":
			var rolled: int = 0
			for r: Dictionary in rs:
				rolled += 1 if bool(r.get("rolled", false)) else 0
			line += " host_rolled=%d" % rolled
		_say(line)
		summary[kind] = rs
	if not suite:
		await _teardown()
		return out
	rows.append_array(out)
	for kind: String in ["guard", "swing", "roll"]:
		var rs2: Array = summary[kind]
		var cf: Array = _stat(rs2, "c_first")
		var hf: Array = _stat(rs2, "h_first")
		var ok: bool = rs2.size() >= 2 and cf.size() == rs2.size() and _mean(cf) <= FIRST_MAX_TICKS
		rows.append(row("net_feel_%s_response" % kind, ok, "client first move %.1f ticks (host %.1f, n=%d, want <= %.0f)" % [
			_mean(cf), _mean(hf), rs2.size(), FIRST_MAX_TICKS]))
		var cj: float = _max(_stat(rs2, "c_jump"))
		var hj: float = _max(_stat(rs2, "h_jump"))
		var jump_ok: bool = cj <= hj * JUMP_RATIO + JUMP_SLACK_M
		var detail: String = "client max one-tick move %.1f cm (host %.1f)" % [cj * 100.0, hj * 100.0]
		if kind != "roll":
			var cb: float = _max(_stat(rs2, "c_back"))
			var hb: float = _max(_stat(rs2, "h_back"))
			jump_ok = jump_ok and cb <= hb + BACK_SLACK_M
			detail += ", step back %.1f cm (host %.1f)" % [cb * 100.0, hb * 100.0]
		rows.append(row("net_feel_%s_smooth" % kind, jump_ok, detail))
	await _teardown()
	return rows


func _teardown() -> void:
	if _client != null:
		_client.leave("done")
	if _host != null:
		_host.leave("done")
	Engine.time_scale = 1.0
	await host.get_tree().physics_frame
	for nd: Node in [_host, _client, _vp, _hm]:
		if nd != null and is_instance_valid(nd):
			if nd.get_parent() != null:
				nd.get_parent().remove_child(nd)
			nd.free()
	_host = null
	_client = null
	_vp = null
	await clear()
