class_name KillCam
extends Node
## Instant replay of the finishing blow. While a match is shown it records, every physics tick, the pose of every body
## on screen (both fighters' parts, their weapons, knocked-off armor) into a ReplayRing, together with the hit, gore
## and death events of that tick and the blood effects' RNG state at each event. After the match, `play(result)`
## replays the last few seconds before the killing blow kinematically (physics paused, bodies posed from the ring),
## with a slow-motion section at the impact and three shots (KillcamPlan: low hero angle, orbit round the impact,
## close on the head or guts). Cuts, armor coming off and blood are re-run at their recorded ticks: the stump caps are
## taken off and put back at the cut, and the blood bursts re-fire with the recorded RNG state, so the spray of each
## blow is the same droplets. Any button, key or tap skips; `finished` fires either way, with the live scene restored.
##
## It records what this machine showed, so it needs nothing from the simulation: offline it is the real bodies, on an
## online client the snapshot-posed puppets (the client's own buffer, no extra traffic). Never part of the state hash.
## Owned by MatchPresenter (presentation only); MenuFlow plays it between match_over and the result panel.

signal finished

const PRIORITY: int = 50  ## after the client driver (-10), the Match (0) and the fighters (10) for the tick
const SKIP_GUARD_S: float = 0.3  ## a press this soon after the start is the end of the fight, not a skip
const FOV: Array = [50.0, 42.0, 38.0]  ## per shot: hero, orbit, close
const POS_FOLLOW: float = 6.0
const LOOK_FOLLOW: float = 9.0

var presenter: Node = null  ## MatchPresenter (duck-typed: blood, sfx, hud, aim, camera)
var ring: ReplayRing = ReplayRing.new(600)
var playing: bool = false
var plan: Dictionary = {}
var arena_radius: float = 11.0
var fired: int = 0  ## events re-run by the last replay
var last_real_s: float = 0.0  ## real seconds the last replay ran
var skipped: bool = false
var keepalive_sent: int = 0  ## keep-alive packets sent by the last replay (online)

var _fighters: Array = []
var _bodies: Array[RigidBody3D] = []
var _index: Dictionary = {}  ## body instance id -> index in the frames
var _part_idx: Array = [{}, {}]
var _tick: int = 0
var _pos: float = 0.0
var _params: Dictionary = {}
var _events: Array = []
var _next_event: int = 0
var _saved: Array = []  ## per body [transform, lin vel, ang vel, freeze, freeze mode, visible]
var _paused: Array = []  ## [node, was physics processing]
var _cuts: Array = []  ## [fighter, part] cut inside the window (caps taken off for the replay)
var _armor: Array = []  ## [tick, MeshInstance3D] armor knocked off inside the window (shown until its tick)
var _cam: Camera3D = null
var _prev_cam: Camera3D = null
var _overlay: KillcamOverlay = null
var _shot: int = -1
var _shot_t: float = 0.0
var _hero_side: float = 1.0
var _orbit_a0: float = 0.0
var _orbit_turn: float = 1.0
var _close_dir: Vector3 = Vector3.BACK
var _wound: Dictionary = {}  ## the close shot's wound: {"idx": body index of its part, "point", "out"} (part-local)
var _wound_side: float = 1.0
var _cam_pos: Vector3 = Vector3.ZERO
var _cam_look: Vector3 = Vector3.ZERO
var _real_t: float = 0.0
var _blood_proc: bool = true
var _time_scale: float = 1.0
var _hud_vis: bool = true
var _aim_vis: bool = true
var _rec_us: int = 0
var _rec_us_max: int = 0
var _rec_n: int = 0
var _play_us: int = 0
var _play_us_max: int = 0
var _play_n: int = 0
var _rec_samples: PackedInt32Array = PackedInt32Array()  ## the last record costs (µs), for the median
var _play_samples: PackedInt32Array = PackedInt32Array()
var _pose_samples: PackedInt32Array = PackedInt32Array()  ## posing the bodies only (no blood, no camera)
var _sessions: Array = []  ## online sessions whose driver the replay paused
var _keep_tick: int = 0
var _blood_live: Dictionary = {}  ## the live blood state, put aside while the replay plays
var _dirty: bool = true  ## a body may have appeared (a hit knocked armor off): rescan before the next sample
const RESCAN_TICKS: int = 30
const COST_SAMPLES: int = 600
const KEEPALIVE_TICKS: int = 20
const BLOOD_LISTS: Array = ["_spurts", "_jets", "_wounds"]  ## BloodFx's live emitters, swapped out for the replay
const KEEPALIVE: PackedByteArray = [0]  ## a message type no build routes: it only tells the other side we are here


func _init() -> void:
	process_physics_priority = PRIORITY


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "KillcamCamera"
	_cam.current = false
	add_child(_cam)
	_overlay = KillcamOverlay.new()
	_overlay.name = "KillcamOverlay"
	add_child(_overlay)


## Starts recording a fresh pair of fighters (call before the blood effects connect to them, so the RNG state of each
## event is read before the blood uses it).
func track(fighters: Array) -> void:
	if playing:
		_finish()
	for i: int in _fighters.size():
		var old: Object = _fighters[i]
		if is_instance_valid(old):
			for s: String in ["hit", "gore", "died"]:
				for c: Dictionary in old.get_signal_connection_list(s):
					if (c["callable"] as Callable).get_object() == self:
						old.disconnect(s, c["callable"] as Callable)
	_fighters = fighters.duplicate()
	var hz: int = Engine.physics_ticks_per_second
	ring = ReplayRing.new(roundi(KillcamPlan._f(Tuning.shared(), "killcam_buffer_s", 8.0) * float(hz)))
	_bodies.clear()
	_index.clear()
	_part_idx = [{}, {}]
	_tick = 0
	for i: int in _fighters.size():
		var f: Fighter = _fighters[i]
		f.hit.connect(_on_hit.bind(i))
		f.gore.connect(_on_gore.bind(i))
		f.died.connect(_on_died.bind(i))
	_refresh_bodies()


func _blood() -> BloodFx:
	return presenter.get("blood") as BloodFx if presenter != null else null


func _rng_state() -> int:
	var b: BloodFx = _blood()
	return b.rng.state if b != null else 0


func _on_hit(ev: Dictionary, side: int) -> void:
	if not playing:
		ring.push_event(_tick, side, "hit", ev.duplicate(), _rng_state())
		_dirty = true


func _on_gore(ev: Dictionary, side: int) -> void:
	if not playing:
		ring.push_event(_tick, side, "gore", ev.duplicate(), _rng_state())


func _on_died(side: int) -> void:
	if playing or side >= _fighters.size() or not is_instance_valid(_fighters[side]):
		return
	var f: Fighter = _fighters[side]
	ring.push_event(_tick, side, "died", {"point": (f.parts["pelvis"] as Node3D).global_position}, 0)


## Registers bodies that appeared since the last tick (knocked-off armor, client props). Fighters' own bodies first.
func _refresh_bodies() -> void:
	for i: int in _fighters.size():
		var f: Fighter = _fighters[i]
		if not is_instance_valid(f) or f.parts.is_empty():
			continue
		for b: RigidBody3D in NetWorld.bodies(f):
			_register(b)
		for b: RigidBody3D in NetWorld.armor_props(f):
			_register(b)
		if (_part_idx[i] as Dictionary).is_empty():
			for n: String in FighterRig.names():
				_part_idx[i][n] = _index.get((f.parts[n] as Object).get_instance_id(), -1)


func _register(b: RigidBody3D) -> void:
	if b == null or _index.has(b.get_instance_id()):
		return
	_index[b.get_instance_id()] = _bodies.size()
	_bodies.append(b)


func _physics_process(_delta: float) -> void:
	if playing:
		_keepalive()
		return
	if _fighters.size() < 2 or not is_instance_valid(_fighters[0]) or not is_instance_valid(_fighters[1]):
		return
	var t0: int = Time.get_ticks_usec()
	if _dirty or _tick % RESCAN_TICKS == 0:
		_dirty = false
		_refresh_bodies()
	var frame := PackedFloat32Array()
	frame.resize(_bodies.size() * ReplayRing.STRIDE)
	for i: int in _bodies.size():
		var b: RigidBody3D = _bodies[i]
		if is_instance_valid(b) and b.is_inside_tree():
			ReplayRing.write_pose(frame, i, b.global_transform)
		else:
			ReplayRing.write_absent(frame, i)
	ring.push(_tick, frame)
	_tick += 1
	var us: int = Time.get_ticks_usec() - t0
	_rec_us += us
	_rec_us_max = maxi(_rec_us_max, us)
	_rec_n += 1
	_sample(_rec_samples, us)


static func _sample(arr: PackedInt32Array, us: int) -> void:
	if arr.size() >= COST_SAMPLES:
		arr.remove_at(0)
	arr.append(us)


static func _median(arr: PackedInt32Array) -> float:
	if arr.is_empty():
		return 0.0
	var c: PackedInt32Array = arr.duplicate()
	c.sort()
	return float(c[c.size() / 2])


## Recording memory and frame cost: ring frames and bytes, bodies, record µs per tick (mean, max), playback µs per frame.
func stats() -> Dictionary:
	return {
		"frames": ring.size(), "bytes": ring.frame_bytes(), "bodies": _bodies.size(), "events": ring.events.size(),
		"record_us_mean": float(_rec_us) / float(maxi(_rec_n, 1)), "record_us_max": _rec_us_max,
		"play_us_mean": float(_play_us) / float(maxi(_play_n, 1)), "play_us_max": _play_us_max,
		"record_us_median": _median(_rec_samples), "play_us_median": _median(_play_samples),
		"pose_us_median": _median(_pose_samples),
	}


func _enabled() -> bool:
	return KillcamPlan._f(Tuning.shared(), "killcam_on", 1.0) > 0.5


## The replay plan for this result ({} = nothing worth replaying).
func plan_for(result: Dictionary) -> Dictionary:
	var p: Dictionary = KillcamPlan.params(Tuning.shared())
	var hz: float = float(Engine.physics_ticks_per_second)
	return KillcamPlan.pick(ring.events, int(result.get("winner", -1)), ring.oldest_tick(), ring.newest_tick(),
			roundi(float(p["lead_s"]) * hz), roundi(float(p["tail_s"]) * hz))


## Plays the replay of `result`'s killing blow. False (and no `finished`) when there is nothing to replay.
func play(result: Dictionary) -> bool:
	if playing or not _enabled() or _fighters.size() < 2:
		return false
	plan = plan_for(result)
	if plan.is_empty():
		return false
	_params = KillcamPlan.params(Tuning.shared())
	playing = true
	skipped = false
	fired = 0
	keepalive_sent = 0
	_play_us = 0
	_play_us_max = 0
	_play_n = 0
	_play_samples.clear()
	_pose_samples.clear()
	_events = ring.events_in(int(plan["start_tick"]), ring.newest_tick())
	_next_event = 0
	_freeze()
	_rewind_visuals()
	_prev_cam = get_viewport().get_camera_3d() if get_viewport() != null else null
	_cam.make_current()
	_time_scale = Engine.time_scale
	Engine.time_scale = 1.0
	for key: String in ["hud", "aim"]:
		var n: Variant = presenter.get(key) if presenter != null else null
		if n is CanvasLayer:
			if key == "hud":
				_hud_vis = (n as CanvasLayer).visible
			else:
				_aim_vis = (n as CanvasLayer).visible
			(n as CanvasLayer).visible = false
	_overlay.show_replay(DisplayServer.is_touchscreen_available() or Flags.args.has("touch"))
	_pos = float(plan["start_tick"])
	_real_t = 0.0
	_shot = -1
	var hz: int = Engine.physics_ticks_per_second
	var kill_f: PackedFloat32Array = ring.frame(int(plan["kill_tick"]))
	_hero_side = KillcamPlan.hero_side(_part_pos(kill_f, int(plan["attacker"]), "pelvis"),
			_part_pos(kill_f, int(plan["victim"]), "pelvis"), arena_radius)
	_wound = _wound_of(kill_f)
	_fire_until(_pos)
	_apply_pose()
	_update_camera(0.0, float(hz))
	return true


func skip() -> void:
	if playing:
		skipped = true
		_finish()


## Physics pause: every recorded body frozen (kinematic, still), the fighters, the Match and a net driver stopped.
func _freeze() -> void:
	_saved.clear()
	for b: RigidBody3D in _bodies:
		if not is_instance_valid(b):
			_saved.append([])
			continue
		_saved.append([b.global_transform, b.linear_velocity, b.angular_velocity, b.freeze, b.freeze_mode, b.visible])
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	_paused.clear()
	_sessions.clear()
	var nodes: Array = _fighters.duplicate()
	var m: Node = presenter.get_parent() if presenter != null else null
	if m != null:
		nodes.append(m)
		for c: Node in m.get_children():
			if c is NetClientDriver or c is NetHostDriver:
				nodes.append(c)
				var ses: Variant = c.get("session")
				if ses is NetSession:
					_sessions.append(ses)
	for n: Variant in nodes:
		if is_instance_valid(n):
			_paused.append([n, (n as Node).is_physics_processing()])
			(n as Node).set_physics_process(false)


## Online, the paused driver sends nothing, and 5 s without a packet ends the session (NetConfig.DISCONNECT_TICKS):
## a one-byte packet a few times a second keeps it open. The replay itself never goes over the network.
func _keepalive() -> void:
	_keep_tick += 1
	if _keep_tick % KEEPALIVE_TICKS != 0:
		return
	for s: Variant in _sessions:
		if is_instance_valid(s) and (s as NetSession).is_open():
			(s as NetSession).send(KEEPALIVE, false)
			keepalive_sent += 1


func _thaw() -> void:
	for i: int in mini(_saved.size(), _bodies.size()):
		var s: Array = _saved[i]
		var b: RigidBody3D = _bodies[i]
		if s.is_empty() or not is_instance_valid(b):
			continue
		b.freeze = bool(s[3])
		b.freeze_mode = s[4]
		_place(b, s[0])
		b.visible = bool(s[5])
		b.linear_velocity = s[1]
		b.angular_velocity = s[2]
	_saved.clear()
	for p: Array in _paused:
		if is_instance_valid(p[0]):
			(p[0] as Node).set_physics_process(bool(p[1]))
	_paused.clear()


## Puts the scene back to how it looked at the window's start: stump caps of cuts made inside it come off, armor
## knocked off inside it is worn again, and the live blood (drops, mist, fountains, jets, drips, guts) is set aside
## for the end. Stains on the sand and bodies stay. The replay steps its own blood from here on.
func _rewind_visuals() -> void:
	_cuts.clear()
	_armor.clear()
	for e: Variant in _events:
		var row: Array = e
		var f: Fighter = _fighters[int(row[1])] if int(row[1]) < _fighters.size() else null
		if f == null or not is_instance_valid(f):
			continue
		var ev: Dictionary = row[3]
		if str(row[2]) == "gore":
			var part: String = _cut_part(ev)
			if part != "" and f.is_limb_cut(part):
				var art: Object = f.get("_art")
				if art != null:
					art.call("uncut", part)
				_cuts.append([f, part])
		elif str(row[2]) == "hit" and bool(ev.get("dislodge", false)):
			var aid: String = str(ev.get("dislodged_id", ""))
			var body: Variant = f.parts.get(str(ev.get("part", "")))
			for mi: Variant in (f.get("_armor_meshes") as Dictionary).get(aid, []):
				if mi is MeshInstance3D and is_instance_valid(mi) and not (mi as MeshInstance3D).visible \
						and (mi as Node).get_parent() != null and (mi as Node).get_parent().get_parent() == body:
					(mi as MeshInstance3D).visible = true
					_armor.append([int(row[0]), mi])
	var b: BloodFx = _blood()
	if b != null:
		_blood_proc = b.is_processing()
		b.set_process(false)
		# The live blood (drops and mist in flight, fountains, jets, drips, guts) is put aside whole and given back at the
		# end, so the scene resumes exactly as it was; the replay runs on fresh, empty ones.
		_blood_live = {"sim": b.sim, "mist": b.mist, "guts": b.guts, "rng": b.rng.state}
		for key: String in BLOOD_LISTS:
			_blood_live[key] = b.get(key)
			b.set(key, [])
		b.sim = BloodSim.new(b.sim.capacity)
		b.mist = BloodMist.new(b.mist.capacity)
		var old_guts: GutSim = _blood_live["guts"]
		var g := GutSim.new()
		g.set_caps(old_guts.rope_cap, old_guts.blob_cap)
		var mm: Variant = b.get("_mm_guts")
		if mm is MultiMeshInstance3D:
			g.reserve((mm as MultiMeshInstance3D).multimesh.instance_count)
		b.guts = g


func _restore_blood() -> void:
	var b: BloodFx = _blood()
	if b == null or _blood_live.is_empty():
		return
	b.sim = _blood_live["sim"]
	b.mist = _blood_live["mist"]
	b.guts = _blood_live["guts"]
	b.guts.dirty = true
	b.rng.state = int(_blood_live["rng"])
	for key: String in BLOOD_LISTS:
		b.set(key, _blood_live[key])
	_blood_live = {}
	b.set_process(_blood_proc)


## The part a gore event cuts off ("" for none).
static func _cut_part(ev: Dictionary) -> String:
	var k: String = str(ev.get("kind", ""))
	if k == "behead":
		return "head"
	if k == "sever":
		return str(ev.get("part", ""))
	return ""


func _fire_until(pos: float) -> void:
	while _next_event < _events.size() and float((_events[_next_event] as Array)[0]) <= pos:
		_fire(_events[_next_event] as Array, true)
		_next_event += 1


## Re-runs one recorded event: blood (same RNG state as live), sound, the cut and the armor coming off.
func _fire(row: Array, with_blood: bool) -> void:
	var side: int = int(row[1])
	if side >= _fighters.size() or not is_instance_valid(_fighters[side]):
		return
	var f: Fighter = _fighters[side]
	var ev: Dictionary = row[3]
	var kind: String = str(row[2])
	var b: BloodFx = _blood()
	var sfx: Object = presenter.get("sfx") if presenter != null else null
	fired += 1
	if kind == "hit":
		for a: Array in _armor:
			if int(a[0]) == int(row[0]) and is_instance_valid(a[1]):
				(a[1] as MeshInstance3D).visible = false
		if with_blood:
			if b != null:
				b.rng.state = int(row[4])
				b.on_hit(ev, f)
			if sfx != null and sfx.has_method("on_hit"):
				sfx.call("on_hit", ev, f)
	elif kind == "gore":
		var part: String = _cut_part(ev)
		if part != "":
			var art: Object = f.get("_art")
			if art != null:
				art.call("cut", f.parts, part)
		if with_blood:
			if b != null:
				b.rng.state = int(row[4])
				b.on_gore(ev, f)
			if sfx != null and sfx.has_method("on_gore"):
				sfx.call("on_gore", ev, f)


func _process(delta: float) -> void:
	if not playing:
		return
	var t0: int = Time.get_ticks_usec()
	var real_dt: float = delta / maxf(Engine.time_scale, 0.001)
	var hz: float = float(Engine.physics_ticks_per_second)
	var kill: float = float(plan["kill_tick"])
	var end: float = float(plan["end_tick"])
	var rate: float = KillcamPlan.rate_at((_pos - kill) / hz, _params)
	var npos: float = minf(_pos + real_dt * hz * rate, end)
	_fire_until(npos)
	_pos = npos
	var tp: int = Time.get_ticks_usec()
	_apply_pose()
	_sample(_pose_samples, Time.get_ticks_usec() - tp)
	var b: BloodFx = _blood()
	if b != null:
		b.step(real_dt * rate)
	_real_t += real_dt
	_update_camera(real_dt, hz)
	var us: int = Time.get_ticks_usec() - t0
	_play_us += us
	_play_us_max = maxi(_play_us_max, us)
	_play_n += 1
	_sample(_play_samples, us)
	if _pos >= end:
		_finish()


func _apply_pose() -> void:
	var a: int = floori(_pos)
	var fa: PackedFloat32Array = ring.frame(a)
	var fb: PackedFloat32Array = ring.frame(a + 1)
	var t: float = _pos - float(a)
	for i: int in _bodies.size():
		var body: RigidBody3D = _bodies[i]
		if not is_instance_valid(body):
			continue
		var r: Dictionary = ReplayRing.blend(fa, fb, i, t)
		if bool(r["ok"]):
			_place(body, r["xf"])
			body.visible = i >= _saved.size() or (_saved[i] as Array).is_empty() or bool((_saved[i] as Array)[5])
		else:
			body.visible = false


## Moves a body on screen and in the physics server at once. The node's transform alone reaches the server only at
## the next transform flush, and a physics step before that syncs the old server pose back onto the node: a replay
## skipped from an input event left a severed head 3.4 m off, back on its pose from early in the replay.
static func _place(b: RigidBody3D, xf: Transform3D) -> void:
	b.global_transform = xf
	PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)


func _part_pos(frame: PackedFloat32Array, side: int, part: String) -> Vector3:
	var i: int = int((_part_idx[side] as Dictionary).get(part, -1))
	return ReplayRing.pose(frame, i).origin if ReplayRing.has_pose(frame, i) else Vector3.ZERO


func _live_pos(side: int, part: String) -> Vector3:
	var i: int = int((_part_idx[side] as Dictionary).get(part, -1))
	if i < 0 or i >= _bodies.size() or not is_instance_valid(_bodies[i]):
		return Vector3.ZERO
	return _bodies[i].global_position


## The wound the close shot films, fixed to its body part at the killing blow: the gut or run-through wound on the
## torso or pelvis, or the stump a cut left on the parent part; {} for a beheading, a crushed skull, a KO or a death
## (those frame the head or the body).
func _wound_of(kill_f: PackedFloat32Array) -> Dictionary:
	var v: int = int(plan["victim"])
	var part: String = str(plan.get("part", ""))
	var kind: String = str(plan["kind"])
	var anchor: String = ""
	var wf: Dictionary = {}
	if kind == "gut" or kind == "run_through":
		anchor = part if part == "torso" or part == "pelvis" else "torso"
		var i: int = int((_part_idx[v] as Dictionary).get(anchor, -1))
		if not ReplayRing.has_pose(kill_f, i):
			return {}
		var att: Vector3 = _part_pos(kill_f, int(plan["attacker"]), "torso")
		wf = KillcamPlan.wound_frame(ReplayRing.pose(kill_f, i), plan["point"] as Vector3, att)
	elif kind == "sever" and part != "head":
		anchor = str(FighterRig.part(part).get("parent", ""))
		wf = KillcamPlan.stump_frame(part)
	if wf.is_empty() or anchor == "":
		return {}
	var idx: int = int((_part_idx[v] as Dictionary).get(anchor, -1))
	if idx < 0:
		return {}
	return {"idx": idx, "point": wf["point"], "out": wf["out"]}


## The wound now, in world space: [point, facing direction].
func _wound_now() -> Array:
	var b: RigidBody3D = _bodies[int(_wound["idx"])]
	var xf: Transform3D = b.global_transform if is_instance_valid(b) else Transform3D()
	var basis: Basis = xf.basis.orthonormalized()
	return [xf.origin + basis * (_wound["point"] as Vector3), basis * (_wound["out"] as Vector3)]


## The close shot's subject: the severed head, the gut wound, or the victim's head.
func _close_target() -> Vector3:
	var v: int = int(plan["victim"])
	match str(plan["kind"]):
		"gut", "run_through":
			return _live_pos(v, "torso").lerp(_live_pos(v, "pelvis"), 0.4)
		"death":
			return _live_pos(v, "torso")
	return _live_pos(v, "head")


func _update_camera(real_dt: float, hz: float) -> void:
	var off: float = (_pos - float(plan["kill_tick"])) / hz
	var shot: int = KillcamPlan.shot_at(off, _params)
	var cut: bool = shot != _shot
	if cut:
		_shot = shot
		_shot_t = 0.0
		if shot == KillcamPlan.ORBIT:
			var o: Array = KillcamPlan.orbit_start(_live_pos(int(plan["attacker"]), "pelvis"), plan["point"] as Vector3, arena_radius)
			_orbit_a0 = float(o[0])
			_orbit_turn = float(o[1])
		elif shot == KillcamPlan.CLOSE:
			_close_dir = _cam_pos - _close_target()
			if not _wound.is_empty():
				var w: Array = _wound_now()
				_wound_side = KillcamPlan.wound_side(w[0] as Vector3, w[1] as Vector3, _live_pos(int(plan["attacker"]), "torso"))
	else:
		_shot_t += real_dt
	var v: Array = []
	match shot:
		KillcamPlan.HERO:
			v = KillcamPlan.hero_view(_live_pos(int(plan["attacker"]), "pelvis"), _live_pos(int(plan["victim"]), "pelvis"),
					_hero_side, _shot_t, arena_radius)
		KillcamPlan.ORBIT:
			v = KillcamPlan.orbit_view(plan["point"] as Vector3, _orbit_a0, _shot_t, arena_radius, _orbit_turn)
		_:
			if _wound.is_empty():
				v = KillcamPlan.close_view(_close_target(), _close_dir, _shot_t, arena_radius)
			else:
				var w: Array = _wound_now()
				v = KillcamPlan.close_wound_view(w[0] as Vector3, w[1] as Vector3, _wound_side, _shot_t, arena_radius)
	var want_pos: Vector3 = v[0]
	var want_look: Vector3 = v[1]
	if cut:
		_cam_pos = want_pos
		_cam_look = want_look
	else:
		_cam_pos = _cam_pos.lerp(want_pos, 1.0 - exp(-POS_FOLLOW * real_dt))
		_cam_look = _cam_look.lerp(want_look, 1.0 - exp(-LOOK_FOLLOW * real_dt))
	_cam.fov = float(FOV[shot])
	if _cam_pos.distance_to(_cam_look) > 0.05:
		_cam.look_at_from_position(_cam_pos, _cam_look, Vector3.UP)


func _finish() -> void:
	if not playing:
		return
	# A skip lands on the end state: the rest of the window's cuts and armor happen at once (the blood comes back whole).
	while _next_event < _events.size():
		_fire(_events[_next_event] as Array, false)
		_next_event += 1
	for c: Array in _cuts:
		if is_instance_valid(c[0]):
			var art: Object = (c[0] as Object).get("_art")
			if art != null:
				art.call("cut", (c[0] as Fighter).parts, str(c[1]))
	for a: Array in _armor:
		if is_instance_valid(a[1]):
			(a[1] as MeshInstance3D).visible = false
	_thaw()
	_restore_blood()
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	_cam.current = false
	for key: String in ["hud", "aim"]:
		var n: Variant = presenter.get(key) if presenter != null else null
		if n is CanvasLayer:
			(n as CanvasLayer).visible = _hud_vis if key == "hud" else _aim_vis
	_overlay.hide_replay()
	Engine.time_scale = _time_scale
	last_real_s = _real_t
	playing = false
	finished.emit()


func _input(event: InputEvent) -> void:
	if not playing or _real_t < SKIP_GUARD_S:
		return
	if is_skip_event(event):
		get_viewport().set_input_as_handled()
		skip()


## A fresh press of anything: a key, a mouse or pad button, or a touch.
static func is_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	if event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch:
		return event.is_pressed()
	return false


func _exit_tree() -> void:
	if playing:
		_finish()
