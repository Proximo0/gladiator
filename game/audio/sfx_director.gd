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
const MAX_SPURTS: int = 3
const MAX_PENDING: int = 96
const LOG_SIZE: int = 48
const DUCK_BUS: String = "CrowdDuck"
const DUCK_DEPTH_DB: float = -10.0
const DUCK_ATTACK: float = 0.06
const DUCK_HOLD: float = 0.5
const DUCK_RELEASE: float = 1.2
const LAYOUT_PATH: String = "res://assets/audio/default_bus_layout.tres"

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var crowd: CrowdModel = CrowdModel.new()
var muted: bool = false
## Total sounds started, and the most recent keys (for tests and the debug overlay).
var played_count: int = 0
## Sounds skipped because the pool was full of higher-priority voices (low-priority beds already yield when it is
## nearly full; they never steal a slot).
var dropped_count: int = 0
var recent_keys: PackedStringArray = PackedStringArray()

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next: int = 0
var _next_2d: int = 0
var _streams: Dictionary = {}
var _last_variant: Dictionary = {}
var _gore_last: Dictionary = {}
var _clock: float = 0.0
## Unscaled seconds (Engine.time_scale divided out). Sound plays in real time, so crowd reaction delays, the duck
## envelope, length cuts and voice ageing use this clock; delays tied to the world (spatter landing, a pain cry after
## the blow) stay on the game clock. A 0.2x finisher slow motion otherwise pushed the crowd roar ~1 s late.
var _real_clock: float = 0.0
## True when another node (the FeelDirector's finisher cinematic) plays the finisher crowd roar: then this director
## plays none, so there is one roar. Set it, or let `_finisher_roar_is_external` find a FeelDirector next to this node.
var finisher_roar_external: bool = false
var _pending: Array[Dictionary] = []
var _tracked: Array[Dictionary] = []
var _amb_low: AudioStreamPlayer = null
var _amb_high: AudioStreamPlayer = null
var _stall_check: float = 0.0
var _meta: Array[Dictionary] = []
var _meta_2d: Array[Dictionary] = []
var _duck_age: float = 99.0
var _duck_base_db: float = 0.0
## Sounds stopped early to make room for a higher-priority one (for tests and the debug overlay).
var stolen_count: int = 0
## Sounds skipped because their group was at its cap with higher-priority voices, and which keys were dropped
## either way (for tests).
var capped_count: int = 0
var dropped_keys: Dictionary = {}
## Important sounds (SfxLogic.is_important) that were dropped, or stolen while still important: key -> count.
var lost_important: Dictionary = {}
## The last few losses in words (key, priority, tier, why, what took the voice): for the sim and the overlay.
var lost_log: PackedStringArray = PackedStringArray()
## Steals where the stopped sound outranked the new one (should stay 0).
var inversions: int = 0
## Sounds started with a finisher boost (for the sim).
var finisher_plays: int = 0


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
		_meta.append({})
	for i: int in range(POOL_2D_SIZE):
		var q: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(q)
		_pool_2d.append(q)
		_meta_2d.append({})
	_amb_low = _make_loop("crowd/amb_low")
	_amb_high = _make_loop("crowd/amb_high")
	var di: int = AudioServer.get_bus_index(DUCK_BUS)
	if di >= 0:
		_duck_base_db = AudioServer.get_bus_volume_db(di)


func _exit_tree() -> void:
	var di: int = AudioServer.get_bus_index(DUCK_BUS)
	if di >= 0:
		AudioServer.set_bus_volume_db(di, _duck_base_db)


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
		"last_sand": -10.0, "spurts": [], "gushes": [], "rolling": false,
	})
	f.hit.connect(on_hit.bind(f))
	f.gore.connect(on_gore.bind(f))
	f.died.connect(on_died.bind(f))


## 0..1: how worked up the crowd is. Swells on action, decays when the fight goes quiet.
func crowd_excitement() -> float:
	return crowd.level


func _physics_process(delta: float) -> void:
	_clock += delta
	var real_dt: float = SfxLogic.real_delta(delta, Engine.time_scale)
	_real_clock += real_dt
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
	_update_cuts()
	_update_duck(real_dt)
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
	var boost: float = SfxLogic.hit_boost_db(ev)
	for l: Dictionary in SfxLogic.limit_layers(SfxLogic.impact_plan(ev, atk_mat, other_mat, kind)):
		_queue_layer(l, pos, "SFX", boost)
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
		_duck()
		_queue(key, pos, 0.0, 1.0, 0.0, "SFX")
	if kind == "skull_crush" or kind == "pummel":
		_queue("impact/bone_crack", pos, 2.0, 0.9, 0.0, "SFX", SfxLogic.FINISHER_BOOST_DB)
	var t: Dictionary = _track_of(f)
	if (kind == "behead" or kind == "gut") and not t.is_empty():
		var tn: Tuning = Tuning.shared()
		var gush: SfxGush = SfxGush.new()
		if kind == "behead":
			gush.setup(SfxGush.KIND_FOUNTAIN, pos, tn.fountain_dur, tn.fountain_hold, rng)
		else:
			gush.setup(SfxGush.KIND_GUT, pos, tn.gut_dur, tn.gut_hold, rng)
		(t["gushes"] as Array).append(gush)
	elif SfxLogic.spurts_for(kind, float(ge.get("amount", 0.0))) and not t.is_empty():
		if (t["spurts"] as Array).size() >= MAX_SPURTS:
			(t["spurts"] as Array).remove_at(0)
		(t["spurts"] as Array).append({"part": str(ge.get("part", "torso")), "age": 0.0, "next": 0.25, "pos": pos})


func on_died(f: Object = null) -> void:
	var pos: Vector3 = _head_pos(f)
	_duck()
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
			_duck()
			if not _finisher_roar_is_external():
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
	var peak: float = (t["whoosh"] as SfxWhooshGate).update(speed if upright else 0.0, delta, _clock,
		SfxLogic.whoosh_min_speed(wid), SfxLogic.whoosh_cooldown(wid))
	if peak > 0.0:
		var wk: String = SfxLogic.whoosh_key_for(peak, wid)
		if wk != "":
			_queue(wk, tip, SfxLogic.whoosh_gain_db(peak), SfxLogic.whoosh_pitch(peak, mass), 0.0, "SFX")
			if rng.randf() < SfxLogic.grunt_chance(peak, mass):
				_queue("voice/grunt", _head_pos_of(parts, pelvis), 0.0, 1.0 + 0.08 * (1.0 if side == 0 else -1.0), 0.03, "Voice")
	# Dodge roll: a whoosh going in and a thud into the sand on coming out.
	var rolling: bool = bool(fr.get("rolling", false))
	if rolling != bool(t["rolling"]):
		t["rolling"] = rolling
		var rp: Vector3 = Vector3(pelvis.x, 0.0, pelvis.z)
		if rolling:
			_queue("move/roll_whoosh", rp, 0.0, 1.0, 0.0, "SFX")
			_queue("move/roll_thud", rp, -6.0, 1.1, 0.12, "SFX")
		else:
			_queue("move/roll_thud", rp, 0.0, 1.0, 0.0, "SFX")
			_queue("move/sand_impact", rp, -6.0, 1.0, 0.03, "SFX")
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
		var tn2: Tuning = Tuning.shared()
		var gv: Vector2 = Vector2(vel.x, vel.z)
		var yb_x: Vector3 = Basis(Vector3.UP, float(fr.get("facing_yaw", 0.0))).x
		var cad: float = tn2.cadence_base + tn2.cadence_per_speed * gv.length() + tn2.cadence_lateral * absf(vel.dot(yb_x))
		step = steps.update_cadence(cad, gv.length(), delta, upright and not rolling)
	if step != 0 and upright and not rolling:
		var shin: String = "shin_l" if step < 0 else "shin_r"
		var fp: Vector3 = pelvis
		if parts.has(shin):
			fp = (parts[shin] as Dictionary).get("pos", pelvis)
		var g: Vector3 = Vector3(fp.x, 0.0, fp.z)
		var sp: float = Vector2(vel.x, vel.z).length()
		var lat: float = 0.0
		if sp > 0.1:
			lat = absf(vel.dot(Basis(Vector3.UP, float(fr.get("facing_yaw", 0.0))).x)) / sp
		var sp_plan: Dictionary = SfxLogic.footstep_plan(sp, Tuning.shared().sprint_speed, lat)
		_queue(str(sp_plan["key"]), g, float(sp_plan["gain_db"]), 1.0, 0.0, "SFX")
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
			# The body leaves a crater: a deep sand thump under the fall, louder for a faster drop.
			_queue("move/roll_thud", gp, clampf(absf(vel.y) * 1.5 - 8.0, -8.0, 0.0), 0.8, 0.04, "SFX")
			if _wears_heavy_armor(f):
				_queue("move/armor_rattle", gp, 0.0, 0.9, 0.05, "SFX")
			if state == "ko":
				crowd.add(0.35)
				_crowd_play("gasp")
		elif prev == "down" and state == "getting_up":
			_queue("move/armor_rattle", Vector3(pelvis.x, 0.0, pelvis.z), -4.0, 0.9, 0.0, "SFX")
			_queue("voice/grunt", _head_pos_of(parts, pelvis), -2.0, 0.9, 0.05, "Voice")
	_tick_spurts(t, f, delta)
	_tick_gushes(t, f, delta)
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


func _tick_gushes(t: Dictionary, f: Object, delta: float) -> void:
	var gushes: Array = t["gushes"]
	var blood: float = 1.0
	var h: Variant = f.get("health")
	if h != null and (h as Object).has_method("blood_frac"):
		blood = float((h as Object).call("blood_frac"))
	var i: int = gushes.size() - 1
	while i >= 0:
		var g: SfxGush = gushes[i]
		for ev: Dictionary in g.tick(delta, blood):
			var gpos: Vector3 = g.pos
			if str(ev["key"]) == "gore/gut_flop":
				gpos = Vector3(g.pos.x, 0.0, g.pos.z)
			_queue(str(ev["key"]), gpos, float(ev["gain_db"]), float(ev["pitch"]), 0.0, "SFX")
		if g.finished():
			gushes.remove_at(i)
		i -= 1


# ---------------------------------------------------------------- playing

func _queue_layer(l: Dictionary, pos: Vector3, bus: String, boost: float = 0.0) -> void:
	_queue(str(l["key"]), pos, float(l["gain_db"]), float(l["pitch"]), float(l["delay"]), bus, boost)


func _queue(key: String, pos: Vector3, gain_db: float, pitch: float, delay: float, bus: String, boost: float = 0.0) -> void:
	if delay <= 0.004:
		play_key(key, pos, gain_db, pitch, bus, boost)
	else:
		_add_pending({"at": _clock + delay, "key": key, "pos": pos, "gain_db": gain_db, "pitch": pitch,
			"bus": bus, "two_d": false, "boost": boost, "real": false})


func _queue_2d(key: String, gain_db: float, pitch: float, delay: float) -> void:
	if delay <= 0.004:
		play_2d(key, gain_db, pitch, "Crowd")
	else:
		_add_pending({"at": _real_clock + delay, "key": key, "pos": Vector3.ZERO, "gain_db": gain_db, "pitch": pitch,
			"bus": "Crowd", "two_d": true, "boost": 0.0, "real": true})


## Queue a delayed sound. When the queue is full the lowest-priority entry gives way (or the new one, if it is lowest).
func _add_pending(e: Dictionary) -> void:
	if _pending.size() < MAX_PENDING:
		_pending.append(e)
		return
	var prios: PackedFloat32Array = PackedFloat32Array()
	for q: Dictionary in _pending:
		prios.append(SfxLogic.priority(str(q["key"]), float(q["gain_db"]), float(q["boost"])))
	var prio: float = SfxLogic.priority(str(e["key"]), float(e["gain_db"]), float(e["boost"]))
	var v: int = SfxLogic.steal_victim(prios, prio)
	if v < 0:
		_drop(str(e["key"]), prio, "pending queue full")
		return
	_drop(str(_pending[v]["key"]), prios[v], "bumped from pending queue by %s" % str(e["key"]))
	_pending[v] = e


func _run_pending() -> void:
	var i: int = _pending.size() - 1
	var due: Array[Dictionary] = []
	while i >= 0:
		if float(_pending[i]["at"]) <= (_real_clock if bool(_pending[i].get("real", false)) else _clock):
			due.push_front(_pending[i])
			_pending.remove_at(i)
		i -= 1
	for p: Dictionary in due:
		if bool(p["two_d"]):
			play_2d(str(p["key"]), float(p["gain_db"]), float(p["pitch"]), str(p["bus"]))
		else:
			play_key(str(p["key"]), p["pos"], float(p["gain_db"]), float(p["pitch"]), str(p["bus"]), float(p.get("boost", 0.0)))


## Play a spatial one-shot now. Returns false when the sound is unknown or its file is missing (true when it was
## dropped by the voice limits or muted). `boost` raises its priority (SfxLogic.hit_boost_db).
## Voice limits: low-priority beds yield to a nearly full pool or a busy one (SOFT_TOTAL_CAP), never exceed their
## group cap and never steal. Anything else plays freely while its group is under its cap and fewer than
## SOFT_TOTAL_CAP voices are busy. Past either limit it replaces the lowest-priority voice (in its group, or anywhere
## past the soft cap) if that one ranks lower and is not itself important. An important sound (SfxLogic.is_important)
## that would otherwise have to cut another important one, or be dropped, takes one of the reserve voices instead
## (above the group cap or the soft cap); only a completely full pool makes it steal or drop. So bursts of heavy hits
## no longer cut each other 30 ms in (the group cap of 9 is for spam, not for nine real blows), and normal play
## stays under the soft cap.
func play_key(key: String, pos: Vector3, gain_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX", boost: float = 0.0) -> bool:
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return false
	_note(key)
	var prio: float = SfxLogic.priority(key, gain_db, boost)
	if boost >= SfxLogic.FINISHER_BOOST_DB:
		finisher_plays += 1
	if muted or _pool.is_empty():
		return true
	var low: bool = SfxLogic.is_low_priority(key)
	var group: String = SfxLogic.group_of(key)
	var total: int = _total_playing()
	var over_group: bool = _group_count(group) >= SfxLogic.group_cap(group)
	if low:
		var why: String = ""
		if _free_count() <= SfxLogic.POOL_RESERVE:
			dropped_count += 1
			why = "pool reserve (low priority)"
		elif total >= SfxLogic.SOFT_TOTAL_CAP or over_group:
			capped_count += 1
			why = "soft total cap (low priority)" if not over_group else "group %s full (low priority)" % group
		if why != "":
			_drop(key, prio, why)
			return true
	var slot: int = -1
	if over_group or total >= SfxLogic.SOFT_TOTAL_CAP:
		var v: int = _victim(prio, group if over_group else "")
		var free: int = _free_slot() if SfxLogic.is_important(prio) else -1
		if v >= 0 and (not SfxLogic.is_important(_decayed(v)) or free < 0):
			slot = v  # a lesser voice gives way (or the pool is full and only an important one ranks lower)
		elif free >= 0:
			slot = free  # an important sound takes a reserve voice rather than cut another or be lost
		else:
			if over_group:
				capped_count += 1
			else:
				dropped_count += 1
			_drop(key, prio, ("group %s" % group if over_group else "soft cap") + " full of louder voices")
			return true
	else:
		slot = _free_slot()
	if slot < 0:
		slot = _victim(prio, "")
		if slot < 0:
			dropped_count += 1
			_drop(key, prio, "pool full of louder voices")
			return true
	if _pool[slot].playing:
		_steal(slot, prio, key)
	var p: AudioStreamPlayer3D = _pool[slot]
	p.stop()
	p.stream = stream
	p.global_position = pos if is_inside_tree() else Vector3.ZERO
	p.volume_db = SfxLogic.base_db(key) + gain_db
	p.pitch_scale = clampf(pitch * (1.0 + rng.randf_range(-PITCH_JITTER, PITCH_JITTER)), 0.5, 2.0)
	p.bus = _bus_or_master(bus)
	p.play()
	_meta[slot] = {"group": group, "key": key, "prio": prio, "start": _real_clock, "cut": SfxLogic.max_len(key), "db": p.volume_db}
	return true


## Play a non-positional one-shot (crowd reactions). A full 2D pool gives the lowest-priority voice to the newcomer
## if it ranks higher (the finisher roar and chant outrank every other reaction).
func play_2d(key: String, gain_db: float = 0.0, pitch: float = 1.0, bus: String = "Crowd") -> bool:
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return false
	_note(key)
	if muted or _pool_2d.is_empty():
		return true
	var prio: float = SfxLogic.priority(key, gain_db)
	var slot: int = -1
	for i: int in range(_pool_2d.size()):
		if not _pool_2d[i].playing:
			slot = i
			break
	if slot < 0:
		var prios: PackedFloat32Array = PackedFloat32Array()
		for i: int in range(_pool_2d.size()):
			prios.append(SfxLogic.decayed_priority(float(_meta_2d[i].get("prio", -1.0e7)), _real_clock - float(_meta_2d[i].get("start", _real_clock))))
		slot = SfxLogic.steal_victim(prios, prio)
		if slot < 0:
			dropped_count += 1
			_drop(key, prio, "2d pool full of louder voices")
			return true
		if SfxLogic.is_important(prios[slot]):
			_note_lost(str(_meta_2d[slot].get("key", "?")), prios[slot], "stolen 2d by %s (%.1f)" % [key, prio])
		stolen_count += 1
	var p: AudioStreamPlayer = _pool_2d[slot]
	p.stop()
	p.stream = stream
	p.volume_db = SfxLogic.base_db(key) + gain_db
	p.pitch_scale = clampf(pitch * (1.0 + rng.randf_range(-0.02, 0.02)), 0.5, 2.0)
	p.bus = _bus_or_master(bus if key == "crowd/finisher_roar" or bus != "Crowd" else DUCK_BUS)
	p.play()
	_meta_2d[slot] = {"key": key, "prio": prio, "start": _real_clock}
	return true

## Playing 3D voices per group (for tests and the debug overlay).
func group_use() -> Dictionary:
	var out: Dictionary = {}
	for i: int in range(_pool.size()):
		if _pool[i].playing:
			var g: String = str(_meta[i].get("group", "?"))
			out[g] = int(out.get(g, 0)) + 1
	return out


func _total_playing() -> int:
	return _pool.size() - _free_count()


func _group_count(group: String) -> int:
	var n: int = 0
	for i: int in range(_pool.size()):
		if _pool[i].playing and str(_meta[i].get("group", "")) == group:
			n += 1
	return n


## Slot of the lowest-priority playing voice (in `group`, or anywhere for ""), if it ranks below `prio`; else -1.
func _victim(prio: float, group: String) -> int:
	var prios: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(_pool.size()):
		var m: Dictionary = _meta[i]
		if not _pool[i].playing or m.is_empty() or (group != "" and str(m.get("group", "")) != group):
			prios.append(-1.0e9)
		else:
			prios.append(SfxLogic.decayed_priority(float(m.get("prio", 0.0)), _real_clock - float(m["start"])))
	return SfxLogic.steal_victim(prios, prio)


## Priority of the playing voice in `slot` now (aged).
func _decayed(slot: int) -> float:
	var m: Dictionary = _meta[slot]
	if m.is_empty():
		return -1.0e9
	return SfxLogic.decayed_priority(float(m.get("prio", 0.0)), _real_clock - float(m["start"]))


## Stop the voice in `slot` for a newcomer of priority `prio`, counting what was lost.
func _steal(slot: int, prio: float, by: String = "?") -> void:
	var m: Dictionary = _meta[slot]
	if not m.is_empty():
		var dp: float = SfxLogic.decayed_priority(float(m.get("prio", 0.0)), _real_clock - float(m["start"]))
		if dp > prio:
			inversions += 1
		if SfxLogic.is_important(dp):
			_note_lost(str(m.get("key", "?")), dp, "stolen by %s (%.1f) at age %.2f" % [by, prio, _real_clock - float(m["start"])])
	_pool[slot].stop()
	_meta[slot] = {}
	stolen_count += 1


func _drop(key: String, prio: float, why: String = "dropped") -> void:
	dropped_keys[key] = int(dropped_keys.get(key, 0)) + 1
	if SfxLogic.is_important(prio):
		_note_lost(key, prio, why)


func _note_lost(key: String, prio: float, why: String) -> void:
	lost_important[key] = int(lost_important.get(key, 0)) + 1
	if lost_log.size() < 16:
		lost_log.append("%s prio=%.1f tier=%d %s busy=%d use=%s" % [key, prio, SfxLogic.priority_tier(key), why,
			_total_playing() if not _pool.is_empty() else 0, str(group_use())])


## Fade out and stop sounds that outlive their allowed length, so long tails do not hold voices.
func _update_cuts() -> void:
	for i: int in range(_pool.size()):
		var m: Dictionary = _meta[i]
		if m.is_empty() or not _pool[i].playing:
			continue
		var cut: float = float(m["cut"])
		if cut <= 0.0:
			continue
		var age: float = _real_clock - float(m["start"])
		if age >= cut:
			_pool[i].stop()
			_meta[i] = {}
		elif age > cut - SfxLogic.CUT_FADE:
			_pool[i].volume_db = float(m["db"]) - 30.0 * (age - (cut - SfxLogic.CUT_FADE)) / SfxLogic.CUT_FADE


## True when the finisher crowd roar belongs to someone else: `finisher_roar_external`, or a FeelDirector (by class
## name or the "feel_director" group) among this node's siblings.
func _finisher_roar_is_external() -> bool:
	if finisher_roar_external:
		return true
	var parent: Node = get_parent()
	if parent == null:
		return false
	for n: Node in parent.get_children():
		if n == self:
			continue
		if n.is_in_group("feel_director"):
			return true
		var scr: Script = n.get_script() as Script
		if scr != null and scr.get_global_name() == &"FeelDirector":
			return true
	return false


## A gore or finisher stinger: restart the crowd duck envelope.
func _duck() -> void:
	_duck_age = 0.0


func _update_duck(delta: float) -> void:
	_duck_age += delta
	var di: int = AudioServer.get_bus_index(DUCK_BUS)
	if di < 0:
		return
	AudioServer.set_bus_volume_db(di, _duck_base_db + duck_level_db())


## Current duck amount (dB, 0 or negative).
func duck_level_db() -> float:
	return SfxLogic.duck_db(_duck_age, DUCK_DEPTH_DB, DUCK_ATTACK, DUCK_HOLD, DUCK_RELEASE)


func _note(key: String) -> void:
	played_count += 1
	recent_keys.append(key)
	if recent_keys.size() > LOG_SIZE:
		recent_keys.remove_at(0)


func _free_count() -> int:
	var n: int = 0
	for p: AudioStreamPlayer3D in _pool:
		if not p.playing:
			n += 1
	return n


func _free_slot() -> int:
	for i: int in range(_pool.size()):
		var j: int = (_next + i) % _pool.size()
		if not _pool[j].playing:
			_next = (j + 1) % _pool.size()
			return j
	return -1


func _bus_or_master(bus: String) -> String:
	return bus if AudioServer.get_bus_index(bus) >= 0 else "Master"


func _stream_for(key: String) -> AudioStream:
	var n: int = SfxLogic.variant_count(key)
	if n <= 0:
		return null
	var idx: int = SfxLogic.pick_variant(key, rng, int(_last_variant.get(key, -1)))
	_last_variant[key] = idx
	if LaserSynth.is_synth_key(key):
		return LaserSynth.stream_for(key, idx)
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
	p.bus = _bus_or_master(DUCK_BUS if AudioServer.get_bus_index(DUCK_BUS) >= 0 else "Crowd")
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
