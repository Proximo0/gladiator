class_name NetClientDriver
extends Node
## Client side of an online match, a child of the Match. The Match was built from the host's START like the host's
## (same seed and loadouts), then switched to a puppet show: no simulation (Match and Fighter physics off, bodies
## kinematic), fighters posed from interpolated snapshots, hit and gore events re-emitted on the fighters at their
## tick (so blood, sound and sand react as in an offline match), HUD and camera on side 1. Every physics tick it
## reads the local device, records it and sends the last few inputs to the host. The weapon-hand cursor is drawn
## from the local aim at once (NetCursor). The own fighter gets cosmetic leads drawn over the snapshot pose: the weapon
## hand moves with the local aim the same tick (NetHandLead) and a roll's opening dip starts on the press
## (NetRollLead); both hand over to the host's pose without a jump. A hit event that involves this side pulses the
## cursor and emits `hit_confirmed` the tick it arrives; its blood, sound and camera still play at its tick, in step
## with the picture. Everything else waits for the host.
## Runs before the Match and the fighters (priority -10), after NetSession has delivered this tick's packets.

const PRIORITY: int = -10
const SIDE: int = 1
const CURSOR_RADIUS: float = 0.035
const CURSOR_COLOR: Color = Color(1.0, 0.85, 0.4, 0.85)
const OVER_WAIT_TICKS: int = 60
const CURSOR_FLASH_COLOR: Color = Color(1.0, 0.25, 0.15, 1.0)
const CURSOR_FLASH_SCALE: float = 1.8  ## extra cursor size at a full-strength hit confirm

## A hit that involves this side arrived from the host (before its tick plays): an instant confirm for HUD or sound.
signal hit_confirmed(ev: Dictionary, tick: int)

var session: NetSession = null
var match_node: Match = null
var interp: NetInterpBuffer = NetInterpBuffer.new()
var packer: NetInputPacker = NetInputPacker.new()
var cursor: NetCursor = NetCursor.new()
var hand_lead: NetHandLead = NetHandLead.new()
var roll_lead: NetRollLead = NetRollLead.new()
var leads_enabled: bool = true  ## cosmetic hand and roll leads on the own fighter (sims switch them off to compare)
var hit_confirms: int = 0
var input_source: Callable = Callable()  ## optional () -> FighterInput, replaces the device (sims, bots)
var shown: NetSnapshot = null  ## the state on screen this tick
var snapshots_received: int = 0
var events_played: int = 0
var result: Dictionary = {}
var local_input: FighterInput = FighterInput.new()
var lag_sum: int = 0  ## sum over shown ticks of (local input tick - input tick the shown snapshot had applied)
var lag_count: int = 0
var lag_sum_older: int = 0  ## same, counting the older snapshot's ack (the meter before the pose's ack was blended)

var _armor: Array = [[], []]
var _cursor_mesh: MeshInstance3D = null
var _input_tick: int = 0
var _time_scale: float = 1.0
var _over_wait: int = 0
var _cursor_mat: StandardMaterial3D = null
var _shown_hand: Vector3 = Vector3.ZERO  ## the own hand where the last snapshot pose put it (before the lead)
var _have_shown_hand: bool = false


func _init() -> void:
	process_physics_priority = PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS


func attach(m: Match) -> void:
	match_node = m
	m.set_physics_process(false)
	for side: int in 2:
		var f: Fighter = m.fighters[side]
		_armor[side] = NetWorld.armor_order(f)
		NetWorld.make_puppet(f)
	var me: Fighter = m.fighters[SIDE]
	var foe: Fighter = m.fighters[1 - SIDE]
	if m.presenter != null:
		var p: MatchPresenter = m.presenter
		p.hud.track(me.health, foe.health, str(m.names[SIDE]), str(m.names[1 - SIDE]))
		p.camera.target = me.parts["pelvis"]
		p.camera.look_at_node = foe.parts["pelvis"]
		p.camera.snap()
		_cursor_mesh = _make_cursor()
		add_child(_cursor_mesh)
		if p.has_method("hit_confirm") and not hit_confirmed.is_connected(Callable(p, "hit_confirm")):
			hit_confirmed.connect(Callable(p, "hit_confirm"))  # an instant HUD or sound confirm, when the presenter has one


func _make_cursor() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = CURSOR_RADIUS
	sm.height = CURSOR_RADIUS * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = CURSOR_COLOR
	mi.material_override = mat
	_cursor_mat = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	return mi


## Average ticks from pressing something to seeing the host's answer on screen (round trip, the host's input
## buffer and the interpolation delay together).
func input_to_screen_ticks() -> float:
	return float(lag_sum) / float(maxi(lag_count, 1))


func input_to_screen_older_ticks() -> float:
	return float(lag_sum_older) / float(maxi(lag_count, 1))


func on_snapshot(bytes: PackedByteArray) -> void:
	var s: NetSnapshot = NetSnapshot.decode(bytes)
	if s == null:
		return
	snapshots_received += 1
	interp.push(s, session.local_tick if session != null else 0)


func on_events(bytes: PackedByteArray) -> void:
	if match_node != null and match_node.over:
		return  # after the result: late events are dropped
	for r: Array in NetEvents.decode(bytes):
		interp.push_event(int(r[0]), int(r[1]), str(r[2]), r[3] as Dictionary)
		_confirm(r)


## A hit this side dealt or took: confirm it now, ahead of its tick (the pose and the gore still wait for the tick).
func _confirm(r: Array) -> void:
	if str(r[2]) != "hit":
		return
	var ev: Dictionary = r[3]
	var mine: bool = int(ev.get("attacker", -1)) == SIDE
	if not mine and int(ev.get("target", -1)) != SIDE:
		return
	hit_confirms += 1
	if mine and not bool(ev.get("hit_on_weapon", false)):
		cursor.hit(clampf(float(ev.get("total", 0.0)) / 40.0, 0.3, 1.0))
	hit_confirmed.emit(ev, int(r[0]))


## True while a cosmetic lead moves the own fighter away from the snapshot pose.
func lead_active() -> bool:
	return hand_lead.offset.length() > 0.005 or roll_lead.active()


func on_over(d: Dictionary) -> void:
	result = {"winner": clampi(NetLobby.int_of(d.get("winner"), -1), -1, 1), "reason": str(d.get("reason", "")),
		"ticks": maxi(NetLobby.int_of(d.get("ticks"), 0), 0), "seed": NetLobby.int_of(d.get("seed"), 0)}
	result["fight_ticks"] = maxi(int(result["ticks"]) - (match_node.fight_start_tick if match_node != null else 0), 0)


func _physics_process(delta: float) -> void:
	if match_node == null or not is_instance_valid(match_node) or match_node.fighters.size() < 2:
		return
	_send_input()
	var lt: int = session.local_tick if session != null else 0
	if interp.advance(lt):
		shown = interp.sample()
		if shown != null:
			_show(shown, delta)
			if shown.ack_input_tick >= 0:
				lag_sum += (_input_tick - 1) - shown.ack_input_tick
				lag_sum_older += (_input_tick - 1) - (shown.ack_older if shown.ack_older >= 0 else shown.ack_input_tick)
				lag_count += 1
	for e: Array in interp.take_due_events():
		if not match_node.over:
			_play_event(e)
	if not result.is_empty() and not match_node.over:
		# End when the picture reaches the host's last tick (or a moment later if snapshots stopped).
		_over_wait += 1
		if interp.render_tick >= float(result.get("ticks", 0)) or _over_wait > OVER_WAIT_TICKS:
			_finish()


func _send_input() -> void:
	if session != null and session.input_blocked:
		local_input = FighterInput.new()  # the Esc menu is open: nothing from the keys reaches the fight
		var rd: Variant = match_node.readers[0]
		if rd != null and is_instance_valid(rd):
			(rd as InputReader).read()  # keeps its mouse delta from piling up behind the menu
	elif input_source.is_valid():
		local_input = input_source.call() as FighterInput
	else:
		var r: Variant = match_node.readers[0]
		local_input = (r as InputReader).read() if r != null and is_instance_valid(r) else FighterInput.new()
	if local_input == null:
		local_input = FighterInput.new()
	packer.record(_input_tick, local_input)
	_input_tick += 1
	if session != null:
		session.send(packer.pack(), false)


func _show(s: NetSnapshot, delta: float) -> void:
	for side: int in mini(2, s.fighters.size()):
		var a: Array[String] = []
		a.assign(_armor[side])
		NetWorld.apply(match_node.fighters[side] as Fighter, s.fighters[side], a)
	if s.fighters.size() > SIDE:
		_lead(match_node.fighters[SIDE] as Fighter, s.fighters[SIDE], s.ack_input_tick, delta)
	match_node.tick = s.tick
	if not is_equal_approx(s.time_scale, _time_scale) and s.time_scale > 0.05:
		_time_scale = s.time_scale
		Engine.time_scale = _time_scale
	var frames: Array = [(match_node.fighters[0] as Fighter).debug_frame(), (match_node.fighters[1] as Fighter).debug_frame()]
	for i: int in 2:
		frames[i]["blood"] = (match_node.fighters[i] as Fighter).health.blood
	if match_node.presenter != null:
		match_node.presenter.tick(frames, delta)
	if _cursor_mesh != null and s.fighters.size() > SIDE:
		var me: Fighter = match_node.fighters[SIDE]
		var torso: RigidBody3D = me.parts["torso"]
		var half_ok: bool = me.weapon != null and bool(me.weapon.def.get("half_sword", false))
		var alive: bool = me.state() == "standing" or me.state() == "stumbling"
		_cursor_mesh.visible = alive
		if alive:
			var want: Vector3 = NetCursor.predict(local_input, torso.global_transform, s.fighters[SIDE].yaw, half_ok, Tuning.shared())
			_cursor_mesh.global_position = cursor.follow(want, delta)
		var fl: float = cursor.flash_step(delta)
		_cursor_mesh.scale = Vector3.ONE * (1.0 + CURSOR_FLASH_SCALE * fl)
		if _cursor_mat != null:
			_cursor_mat.albedo_color = CURSOR_COLOR.lerp(CURSOR_FLASH_COLOR, fl)


## The own fighter's cosmetic leads, drawn over the pose apply() just set (the next apply() starts from the snapshot).
func _lead(me: Fighter, ms: NetFighterSnap, ack: int, delta: float) -> void:
	var tun: Tuning = Tuning.shared()
	var st: String = me.state()
	var standing: bool = st == "standing"
	var on: bool = leads_enabled and (session == null or not session.input_blocked)
	var input_tick: int = _input_tick - 1
	roll_lead.press(on and local_input.has(FighterInput.ROLL), local_input.move(), input_tick, standing, ms.stamina, tun)
	var rl: Vector2 = roll_lead.step(ms.rolling, ack, standing, delta, tun)
	var torso: RigidBody3D = me.parts["torso"]
	var w: Weapon = me.weapon
	var half_ok: bool = w != null and bool(w.def.get("half_sword", false))
	var raw: Vector3 = NetCursor.predict(local_input, torso.global_transform, ms.yaw, half_ok, tun)
	var pelvis: Vector3 = (me.parts["pelvis"] as Node3D).global_position
	var arms: bool = on and (standing or st == "stumbling" or st == "getting_up")
	var fast: bool = local_input.has(FighterInput.SWING) or local_input.has(FighterInput.THRUST)
	var hand: Vector3 = NetWorld.hand_point(me, "r")
	var moved: Vector3 = hand - _shown_hand if _have_shown_hand else Vector3.ZERO
	_shown_hand = hand
	_have_shown_hand = true
	var lead: Vector3 = hand_lead.step(raw, pelvis, ms.hand_target, input_tick, ack, fast, arms, delta, tun, moved)
	var two_hand: bool = w != null and (bool(w.def.get("two_handed", false)) or (half_ok and local_input.has(FighterInput.HALF_SWORD)))
	NetWorld.lead_hand(me, lead, two_hand)
	NetWorld.lead_roll(me, rl.x, rl.y, ms.yaw, roll_lead.dir, tun)


func _play_event(e: Array) -> void:
	var side: int = int(e[1])
	if side < 0 or side > 1:
		return
	var f: Fighter = match_node.fighters[side]
	var ev: Dictionary = e[3]
	events_played += 1
	if str(e[2]) == "gore":
		f.gore.emit(ev)
		return
	f.hit.emit(ev)
	var fin: String = str(ev.get("finisher", ""))
	if fin != "" and not bool(ev.get("hit_on_weapon", false)) and match_node.presenter != null:
		match_node.presenter.announce(MatchJudge.finisher_banner(fin))
	if match_node.presenter != null:
		match_node.presenter.on_hit(ev)


## The host's result: play what is left of the events, then end the match like an offline one.
func _finish() -> void:
	var last_tick: int = int(result.get("ticks", 0))
	for e: Array in interp.take_all_events():
		if int(e[0]) <= last_tick:  # anything stamped after the host's last tick belongs to the end pause: dropped
			_play_event(e)
	match_node.over = true
	var full: Dictionary = result.duplicate()
	full["loadouts"] = (match_node.config.get("loadouts", []) as Array).duplicate(true)
	var why: String = NetResultCheck.check(result, interp.first_at_or_after(last_tick), float(match_node.config.get("time_limit_s", 180.0)))
	if why != "":
		full["suspect"] = why  # the host's result does not fit its own snapshots: reported as a draw (disputed)
		push_warning("NetClientDriver: host result looks forged (%s)" % why)
	match_node.result = full
	if match_node.presenter != null:
		match_node.presenter.announce(MatchJudge.result_banner(full, match_node.names))
	match_node.match_over.emit(full)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
