class_name NetClientDriver
extends Node
## Client side of an online match, a child of the Match. The Match was built from the host's START like the host's
## (same seed and loadouts), then switched to a puppet show: no simulation (Match and Fighter physics off, bodies
## kinematic), fighters posed from interpolated snapshots, hit and gore events re-emitted on the fighters at their
## tick (so blood, sound and sand react as in an offline match), HUD and camera on side 1. Every physics tick it
## reads the local device, records it and sends the last few inputs to the host. The weapon-hand cursor is drawn
## from the local aim at once (NetCursor); everything else waits for the host.
## Runs before the Match and the fighters (priority -10), after NetSession has delivered this tick's packets.

const PRIORITY: int = -10
const SIDE: int = 1
const CURSOR_RADIUS: float = 0.035
const CURSOR_COLOR: Color = Color(1.0, 0.85, 0.4, 0.85)
const OVER_WAIT_TICKS: int = 60

var session: NetSession = null
var match_node: Match = null
var interp: NetInterpBuffer = NetInterpBuffer.new()
var packer: NetInputPacker = NetInputPacker.new()
var cursor: NetCursor = NetCursor.new()
var input_source: Callable = Callable()  ## optional () -> FighterInput, replaces the device (sims, bots)
var shown: NetSnapshot = null  ## the state on screen this tick
var snapshots_received: int = 0
var events_played: int = 0
var result: Dictionary = {}
var local_input: FighterInput = FighterInput.new()
var lag_sum: int = 0  ## sum over shown ticks of (local input tick - input tick the shown snapshot had applied)
var lag_count: int = 0

var _armor: Array = [[], []]
var _cursor_mesh: MeshInstance3D = null
var _input_tick: int = 0
var _time_scale: float = 1.0
var _over_wait: int = 0


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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	return mi


## Average ticks from pressing something to seeing the host's answer on screen (round trip, the host's input
## buffer and the interpolation delay together).
func input_to_screen_ticks() -> float:
	return float(lag_sum) / float(maxi(lag_count, 1))


func on_snapshot(bytes: PackedByteArray) -> void:
	var s: NetSnapshot = NetSnapshot.decode(bytes)
	if s == null:
		return
	snapshots_received += 1
	interp.push(s, session.local_tick if session != null else 0)


func on_events(bytes: PackedByteArray) -> void:
	for r: Array in NetEvents.decode(bytes):
		interp.push_event(int(r[0]), int(r[1]), str(r[2]), r[3] as Dictionary)


func on_over(d: Dictionary) -> void:
	result = {"winner": int(d.get("winner", -1)), "reason": str(d.get("reason", "")), "ticks": int(d.get("ticks", 0)),
		"seed": int(d.get("seed", 0))}


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
				lag_sum += _input_tick - shown.ack_input_tick
				lag_count += 1
	for e: Array in interp.take_due_events():
		_play_event(e)
	if not result.is_empty() and not match_node.over:
		# End when the picture reaches the host's last tick (or a moment later if snapshots stopped).
		_over_wait += 1
		if interp.render_tick >= float(result.get("ticks", 0)) or _over_wait > OVER_WAIT_TICKS:
			_finish()


func _send_input() -> void:
	if input_source.is_valid():
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
	for e: Array in interp.take_all_events():
		_play_event(e)
	match_node.over = true
	var full: Dictionary = result.duplicate()
	full["loadouts"] = (match_node.config.get("loadouts", []) as Array).duplicate(true)
	match_node.result = full
	if match_node.presenter != null:
		match_node.presenter.announce(MatchJudge.result_banner(full, match_node.names))
	match_node.match_over.emit(full)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
