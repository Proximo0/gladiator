class_name SfxDirector
extends Node
## Sound for the fight: tracks fighters, plays pooled spatial sounds, runs the crowd. Add one to main and call
## `track(fighter)` for each fighter. Selection rules live in SfxLogic and CrowdModel (pure, unit-tested); this node
## owns players, streams, timing and the polling of `Fighter.debug_frame()`.
##
## Buses (assets/audio/default_bus_layout.tres): Master > SFX, Crowd, Voice, Music. Missing buses fall back to Master.

## A crowd reaction just played ("gasp", "boo", "cheer", "roar", "finisher"): the stands can jump with it.
signal crowd_reacted(kind: String)

const POOL_SIZE: int = 28
const POOL_2D_SIZE: int = 8
const MAX_DISTANCE: float = 45.0
const PITCH_JITTER: float = 0.05
const GORE_GAP: float = 0.2
const SAND_TIP_Y: float = 0.07
const SAND_MIN_SPEED: float = 2.5
const SAND_GAP: float = 0.25
const SPURT_SECONDS: float = 4.5
const MAX_PENDING: int = 96
const LOG_SIZE: int = 48
const LAYOUT_PATH: String = "res://assets/audio/default_bus_layout.tres"

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var crowd: CrowdModel = CrowdModel.new()
var muted: bool = false
## Total sounds started, and the most recent keys (for tests and the debug overlay).
var played_count: int = 0
var recent_keys: PackedStringArray = PackedStringArray()

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next: int = 0
var _next_2d: int = 0
var _streams: Dictionary = {}
var _last_variant: Dictionary = {}
var _gore_last: Dictionary = {}
var _clock: float = 0.0
var _pending: Array[Dictionary] = []
var _tracked: Array[Dictionary] = []
var _amb_low: AudioStreamPlayer = null
var _amb_high: AudioStreamPlayer = null
var _stall_check: float = 0.0


func _init() -> void:
	rng.seed = 7741


func _ready() -> void:
	SfxDirector.ensure_buses()
	for i: int in range(POOL_SIZE):
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.max_distance = MAX_DISTANCE
		p.unit_size = 6.0
		p.attenuation_filter_cutoff_hz = 16000.0
		add_child(p)
		_pool.append(p)
	for i: int in range(POOL_2D_SIZE):
		var q: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(q)
		_pool_2d.append(q)
	_amb_low = _make_loop("crowd/amb_low")
	_amb_high = _make_loop("crowd/amb_high")


## Install the bus layout when the project did not (so the director still works without the project setting).
static func ensure_buses() -> void:
	if AudioServer.get_bus_index("SFX") >= 0:
		return
	var layout: AudioBusLayout = load(LAYOUT_PATH) as AudioBusLayout
	if layout != null:
		AudioServer.set_bus_layout(layout)


func track(f: Node3D) -> void:
	for t: Dictionary in _tracked:
		if t["f"] == f:
			return
	_tracked.append({
		"f": f, "whoosh": SfxWhooshGate.new(), "steps": SfxStepTracker.new(), "state": "standing",
		"last_sand": -10.0, "spurts": [],
	})
	f.hit.connect(on_hit.bind(f))
	f.gore.connect(on_gore.bind(f))
	f.died.connect(on_died.bind(f))


## 0..1: how worked up the crowd is. Swells on action, decays when the fight goes quiet.
func crowd_excitement() -> float:
	return crowd.level


func _physics_process(delta: float) -> void:
	_clock += delta
	var action: float = 0.0
	var i: int = _tracked.size() - 1
	while i >= 0:
		var t: Dictionary = _tracked[i]
		if not is_instance_valid(t["f"]):
			_tracked.remove_at(i)
		else:
			action = maxf(action, _poll(t, delta))
		i -= 1
	crowd.tick(delta, action)
	_run_pending()
	_update_ambience(delta)
	if crowd.take_stall_boo():
		_crowd_play("boo")


# ---------------------------------------------------------------- events

## A resolved weapon contact on `victim` (a Fighter, or null in tests). `ev` is Fighter.hit's event.
func on_hit(ev: Dictionary, victim: Object = null) -> void:
	var atk_def: Dictionary = CombatData.weapon(str(ev.get("weapon_id", "")))
	var atk_mat: String = SfxLogic.weapon_material(atk_def)
	var other_mat: String = ""
	var on_weapon: bool = bool(ev.get("hit_on_weapon", false))
	if on_weapon and victim != null:
		var held: Variant = victim.get("offhand") if str(ev.get("part", "")) == "forearm_l" else victim.get("weapon")
		if held != null and (held as Object).get("weapon_id") != null:
			other_mat = SfxLogic.weapon_material(CombatData.weapon(str((held as Object).get("weapon_id"))))
		else:
			other_mat = "wood"
	var kind: String = SfxLogic.armor_kind_for(ev.get("armor_ids", []) as Array)
	var pos: Vector3 = ev.get("point", Vector3.ZERO)
	for l: Dictionary in SfxLogic.impact_plan(ev, atk_mat, other_mat, kind):
		_queue_layer(l, pos, "SFX")
	if on_weapon:
		_crowd_react(ev)
		return
	for l: Dictionary in SfxLogic.voice_plan(ev):
		var pitch: float = float(l["pitch"]) * (1.0 + 0.08 * (1.0 if int(ev.get("target", 0)) == 0 else -1.0))
		_queue(str(l["key"]), pos, float(l["gain_db"]), pitch, float(l["delay"]), "Voice")
	var total: float = float(ev.get("total", 0.0))
	if total >= SfxLogic.SPLATTER_MIN_TOTAL and not on_weapon:
		_queue("gore/blood_spatter_sand", Vector3(pos.x, 0.0, pos.z), -2.0, 1.0, SfxLogic.spatter_delay(pos.y) + 0.1, "SFX")
	if bool(ev.get("disarmed", false)):
		var metal: bool = SfxLogic.weapon_material(atk_def) == "steel"
		_queue("impact/drop_sand_metal" if metal else "impact/drop_sand", Vector3(pos.x, 0.0, pos.z), -2.0, 1.0, 0.45, "SFX")
	_crowd_react(ev)


## Gore stingers: sever, behead, gut, run-through, plus an arterial spurt after a sever, behead or gut.
func on_gore(ge: Dictionary, f: Object = null) -> void:
	var kind: String = str(ge.get("kind", ""))
	var pos: Vector3 = ge.get("point", Vector3.ZERO)
	var key: String = SfxLogic.gore_key(kind)
	if key != "" and _clock - float(_gore_last.get(key, -10.0)) >= GORE_GAP:
		_gore_last[key] = _clock
		_queue(key, pos, 0.0, 1.0, 0.0, "SFX")
	if kind == "skull_crush":
		_queue("impact/bone_crack", pos, 2.0, 0.9, 0.0, "SFX")
	if kind == "sever" or kind == "behead" or kind == "gut" or kind == "bleed":
		var t: Dictionary = _track_of(f)
		if not t.is_empty():
			(t["spurts"] as Array).append({"part": str(ge.get("part", "torso")), "age": 0.0, "next": 0.25, "pos": pos})


func on_died(f: Object = null) -> void:
	var pos: Vector3 = _head_pos(f)
	_queue("voice/death_gurgle", pos, 0.0, 1.0 + 0.06 * _side_sign(f), 0.15, "Voice")
	crowd.add(0.5)
	_crowd_play("roar")


func _crowd_react(ev: Dictionary) -> void:
	crowd.add(CrowdModel.hit_impulse(ev))
	_crowd_play(CrowdModel.reaction_for(ev))


func _crowd_play(kind: String) -> void:
	if not crowd.try_reaction(kind):
		return
	crowd_reacted.emit(kind)
	match kind:
		"gasp":
			_queue_2d("crowd/gasp", 0.0, 1.0, 0.1)
		"cheer":
			_queue_2d("crowd/cheer", 0.0, 1.0, 0.25)
		"boo":
			_queue_2d("crowd/boo", 0.0, 1.0, 0.0)
		"roar":
			_queue_2d("crowd/gasp", -4.0, 1.0, 0.0)
			_queue_2d("crowd/roar", 0.0, 1.0, 0.45)
		"finisher":
			_queue_2d("crowd/finisher_roar", 0.0, 1.0, 0.2)
			_queue_2d("crowd/chant", -2.0, 1.0, 2.4)


# ---------------------------------------------------------------- polling

## Per-tick sounds for one fighter. Returns its action level (0..1) for the crowd.
func _poll(t: Dictionary, delta: float) -> float:
	var f: Object = t["f"]
	if not f.has_method("debug_frame"):
		return 0.0
	var fr: Dictionary = f.call("debug_frame")
	var parts: Dictionary = fr.get("parts", {})
	var state: String = str(fr.get("state", "standing"))
	var speed: float = float(fr.get("tip_speed", 0.0))
	var wid: String = str(fr.get("weapon_id", ""))
	var wdef: Dictionary = CombatData.weapon(wid)
	var mass: float = float(wdef.get("mass", 1.0))
	var side: int = int(fr.get("side", 0))
	var pelvis: Vector3 = fr.get("pelvis_pos", Vector3.ZERO)
	var tip: Vector3 = fr.get("tip_pos", pelvis)
	var upright: bool = state == "standing" or state == "stumbling"
	# Swing whoosh (and sometimes an effort grunt).
	var peak: float = (t["whoosh"] as SfxWhooshGate).update(speed if upright else 0.0, delta, _clock)
	if peak > 0.0:
		var wk: String = SfxLogic.whoosh_key(peak)
		if wk != "":
			_queue(wk, tip, SfxLogic.whoosh_gain_db(peak), SfxLogic.whoosh_pitch(peak, mass), 0.0, "SFX")
			if rng.randf() < SfxLogic.grunt_chance(peak, mass):
				_queue("voice/grunt", _head_pos_of(parts, pelvis), 0.0, 1.0 + 0.08 * (1.0 if side == 0 else -1.0), 0.03, "Voice")
	# Weapon tip into the sand.
	if tip.y < SAND_TIP_Y and speed > SAND_MIN_SPEED and _clock - float(t["last_sand"]) > SAND_GAP:
		t["last_sand"] = _clock
		_queue("move/sand_impact", Vector3(tip.x, 0.0, tip.z), clampf((speed - 2.5) * 1.0, 0.0, 8.0) - 8.0, 1.0, 0.0, "SFX")
	# Footsteps.
	var vel: Vector3 = fr.get("pelvis_vel", Vector3.ZERO)
	var steps: SfxStepTracker = t["steps"]
	var step: int = 0
	if fr.has("foot_contacts"):
		var fc: Dictionary = fr["foot_contacts"]
		step = steps.update_contacts(bool(fc.get("l", false)), bool(fc.get("r", false)))
	else:
		step = steps.update(Vector2(vel.x, vel.z).length(), delta, upright)
	if step != 0 and upright:
		var shin: String = "shin_l" if step < 0 else "shin_r"
		var fp: Vector3 = pelvis
		if parts.has(shin):
			fp = (parts[shin] as Dictionary).get("pos", pelvis)
		var g: Vector3 = Vector3(fp.x, 0.0, fp.z)
		var sp: float = Vector2(vel.x, vel.z).length()
		_queue("move/footstep_sand", g, SfxLogic.step_gain_db(sp), 1.0, 0.0, "SFX")
		if _wears_heavy_armor(f):
			_queue("move/armor_rattle", g, -2.0 + minf(sp, 5.0), 1.0, 0.02, "SFX")
	# Falling down and getting up.
	var prev: String = str(t["state"])
	if state != prev:
		t["state"] = state
		var was_up: bool = prev == "standing" or prev == "stumbling" or prev == "getting_up"
		if was_up and (state == "down" or state == "ko" or state == "dead"):
			var gp: Vector3 = Vector3(pelvis.x, 0.0, pelvis.z)
			_queue("move/body_fall_sand", gp, 0.0, 1.0, 0.0, "SFX")
			if _wears_heavy_armor(f):
				_queue("move/armor_rattle", gp, 0.0, 0.9, 0.05, "SFX")
			if state == "ko":
				crowd.add(0.35)
				_crowd_play("gasp")
		elif prev == "down" and state == "getting_up":
			_queue("move/armor_rattle", Vector3(pelvis.x, 0.0, pelvis.z), -4.0, 0.9, 0.0, "SFX")
			_queue("voice/grunt", _head_pos_of(parts, pelvis), -2.0, 0.9, 0.05, "Voice")
	_tick_spurts(t, f, delta)
	return clampf(speed / 14.0, 0.0, 1.0)


func _tick_spurts(t: Dictionary, f: Object, delta: float) -> void:
	var spurts: Array = t["spurts"]
	var blood: float = 1.0
	var h: Variant = f.get("health")
	if h != null and (h as Object).has_method("blood_frac"):
		blood = float((h as Object).call("blood_frac"))
	var i: int = spurts.size() - 1
	while i >= 0:
		var s: Dictionary = spurts[i]
		s["age"] = float(s["age"]) + delta
		if float(s["age"]) > SPURT_SECONDS:
			spurts.remove_at(i)
		elif float(s["age"]) >= float(s["next"]):
			s["next"] = float(s["age"]) + SfxLogic.spurt_interval(blood)
			_queue("gore/spurt_hiss", s["pos"], SfxLogic.spurt_gain_db(float(s["age"]), blood), 1.0, 0.0, "SFX")
		i -= 1


# ---------------------------------------------------------------- playing

func _queue_layer(l: Dictionary, pos: Vector3, bus: String) -> void:
	_queue(str(l["key"]), pos, float(l["gain_db"]), float(l["pitch"]), float(l["delay"]), bus)


func _queue(key: String, pos: Vector3, gain_db: float, pitch: float, delay: float, bus: String) -> void:
	if delay <= 0.004:
		play_key(key, pos, gain_db, pitch, bus)
	elif _pending.size() < MAX_PENDING:
		_pending.append({"at": _clock + delay, "key": key, "pos": pos, "gain_db": gain_db, "pitch": pitch,
			"bus": bus, "two_d": false})


func _queue_2d(key: String, gain_db: float, pitch: float, delay: float) -> void:
	if delay <= 0.004:
		play_2d(key, gain_db, pitch, "Crowd")
	elif _pending.size() < MAX_PENDING:
		_pending.append({"at": _clock + delay, "key": key, "pos": Vector3.ZERO, "gain_db": gain_db, "pitch": pitch,
			"bus": "Crowd", "two_d": true})


func _run_pending() -> void:
	var i: int = _pending.size() - 1
	var due: Array[Dictionary] = []
	while i >= 0:
		if float(_pending[i]["at"]) <= _clock:
			due.push_front(_pending[i])
			_pending.remove_at(i)
		i -= 1
	for p: Dictionary in due:
		if bool(p["two_d"]):
			play_2d(str(p["key"]), float(p["gain_db"]), float(p["pitch"]), str(p["bus"]))
		else:
			play_key(str(p["key"]), p["pos"], float(p["gain_db"]), float(p["pitch"]), str(p["bus"]))


## Play a spatial one-shot now. Returns false when muted, the sound is unknown or its file is missing.
func play_key(key: String, pos: Vector3, gain_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> bool:
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return false
	_note(key)
	if muted or _pool.is_empty():
		return true
	var p: AudioStreamPlayer3D = _free_player()
	p.stop()
	p.stream = stream
	p.global_position = pos if is_inside_tree() else Vector3.ZERO
	p.volume_db = SfxLogic.base_db(key) + gain_db
	p.pitch_scale = clampf(pitch * (1.0 + rng.randf_range(-PITCH_JITTER, PITCH_JITTER)), 0.5, 2.0)
	p.bus = _bus_or_master(bus)
	p.play()
	return true


## Play a non-positional one-shot (crowd reactions).
func play_2d(key: String, gain_db: float = 0.0, pitch: float = 1.0, bus: String = "Crowd") -> bool:
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return false
	_note(key)
	if muted or _pool_2d.is_empty():
		return true
	var p: AudioStreamPlayer = _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	for q: AudioStreamPlayer in _pool_2d:
		if not q.playing:
			p = q
			break
	p.stop()
	p.stream = stream
	p.volume_db = SfxLogic.base_db(key) + gain_db
	p.pitch_scale = clampf(pitch * (1.0 + rng.randf_range(-0.02, 0.02)), 0.5, 2.0)
	p.bus = _bus_or_master(bus)
	p.play()
	return true


func _note(key: String) -> void:
	played_count += 1
	recent_keys.append(key)
	if recent_keys.size() > LOG_SIZE:
		recent_keys.remove_at(0)


func _free_player() -> AudioStreamPlayer3D:
	for i: int in range(_pool.size()):
		var p: AudioStreamPlayer3D = _pool[(_next + i) % _pool.size()]
		if not p.playing:
			_next = (_next + i + 1) % _pool.size()
			return p
	var s: AudioStreamPlayer3D = _pool[_next]  # all busy: steal the oldest slot
	_next = (_next + 1) % _pool.size()
	return s


func _bus_or_master(bus: String) -> String:
	return bus if AudioServer.get_bus_index(bus) >= 0 else "Master"


func _stream_for(key: String) -> AudioStream:
	var n: int = SfxLogic.variant_count(key)
	if n <= 0:
		return null
	var idx: int = SfxLogic.pick_variant(key, rng, int(_last_variant.get(key, -1)))
	_last_variant[key] = idx
	var path: String = SfxLogic.path_for(key, idx)
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	_streams[path] = s
	return s


# ---------------------------------------------------------------- crowd ambience

func _make_loop(key: String) -> AudioStreamPlayer:
	var stream: AudioStream = null
	var path: String = SfxLogic.path_for(key, 0)
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = _bus_or_master("Crowd")
	p.volume_db = -60.0
	if stream is AudioStreamWAV:
		var w: AudioStreamWAV = stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2  # 16-bit mono
	p.stream = stream
	add_child(p)
	if stream != null and not muted:
		p.play()
	return p


func _update_ambience(delta: float) -> void:
	if _amb_low == null:
		return
	var g: Vector2 = CrowdModel.ambience_gains(crowd.level)
	_amb_low.volume_db = move_toward(_amb_low.volume_db, g.x + SfxLogic.base_db("crowd/amb_low"), 30.0 * delta)
	_amb_high.volume_db = move_toward(_amb_high.volume_db, g.y + SfxLogic.base_db("crowd/amb_high"), 30.0 * delta)


# ---------------------------------------------------------------- duck-typed helpers

func _track_of(f: Object) -> Dictionary:
	for t: Dictionary in _tracked:
		if t["f"] == f:
			return t
	return {}


func _head_pos_of(parts: Dictionary, fallback: Vector3) -> Vector3:
	if parts.has("head"):
		return (parts["head"] as Dictionary).get("pos", fallback)
	return fallback


func _head_pos(f: Object) -> Vector3:
	if f != null and f.has_method("debug_frame"):
		var fr: Dictionary = f.call("debug_frame")
		return _head_pos_of(fr.get("parts", {}), fr.get("pelvis_pos", Vector3.ZERO))
	return Vector3.ZERO


func _side_sign(f: Object) -> float:
	if f != null and f.get("side") != null:
		return 1.0 if int(f.get("side")) == 0 else -1.0
	return 1.0


func _wears_heavy_armor(f: Object) -> bool:
	if not f.has_method("armor_on"):
		return false
	var kind: String = SfxLogic.armor_kind_for(f.call("armor_on", "torso") as Array)
	return kind == "mail" or kind == "plate"
