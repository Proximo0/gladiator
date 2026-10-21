class_name FighterBrain
extends RefCounted
## CPU fighter brain. Pure: feed it two Fighter.debug_frame() dictionaries every physics tick and it returns a
## FighterInput, the way a human would drive the mouse: wind up, sweep the hand target through the foe, guard by
## putting the weapon between the foe's tip and itself, back off when tired, finish the fallen.
## No Nodes, no wall clock, no global random: one seeded RandomNumberGenerator, so a bot match replays by seed.
##
## Optional debug_frame keys it uses when present (it copes with their absence):
##   me/foe "blood_frac" (0..1, FighterHealth.blood_frac()), foe "armor" ({part: armor id or kind or bool}),
##   me "offhand_id" (String), "props" (Array of {"pos": Vector3, "weapon_id": String}) on either frame.
## Timers are in ticks at 60 Hz.

const RING: int = 64
const GUARD_W: float = 0.55  ## half width of the guard plane (m), mirrors Tuning guard_width
const GUARD_H: float = 0.45  ## half height of the guard plane (m), mirrors Tuning guard_height
const WINDUP_AMP: float = 0.85
const SPAWN_HOLD_TICKS: int = 24  ## stand still while the spawn pose settles (a lunging start whips the weapon into the own body)
const FINISH_STRIKE_SCALE: float = 0.8  ## finisher strikes sweep this much faster (shorter strike)
const SLEW_NEUTRAL: float = 0.07  ## max aim travel per tick when returning to the neutral guard (no whip-back through the body)
const AIM_LEFT_LIMIT: float = -0.55  ## aim x below this sweeps the weapon through the own offhand arm (self hits)
const AIM_LOW_LIMIT: float = -0.75
const SLEW_RECOVER: float = 0.045
const SLEW_GUARD: float = 0.2
const BLUNT_HEAD_BIAS: float = 2.0  ## blunt weapons do not bleed: they win by knocking the head (consciousness)

const ST_APPROACH: int = 0
const ST_FEINT: int = 1
const ST_WINDUP: int = 2
const ST_STRIKE: int = 3
const ST_RECOVER: int = 4
const ST_GUARD: int = 5
const ST_RETREAT: int = 6
const ST_FINISH: int = 7
const ST_WEAPON: int = 8
const STATE_NAMES: Array = ["approach", "feint", "windup", "strike", "recover", "guard", "retreat", "finish", "weapon"]

const PART_BASE: Dictionary = {
	"head": 1.0, "torso": 1.3, "pelvis": 0.5, "forearm_r": 0.7, "upper_arm_r": 0.4, "upper_arm_l": 0.3,
	"forearm_l": 0.2, "thigh_l": 0.5, "thigh_r": 0.5, "shin_l": 0.35, "shin_r": 0.35,
}
const ARMOR_KIND: Dictionary = {"cloth": 0.1, "leather": 0.3, "mail": 0.65, "plate": 0.95}

const PRESETS: Dictionary = {
	"brute": {"aggression": 0.7, "patience": 0.2, "reaction_ms": 260.0, "aim_noise": 0.3,
		"preferred_attacks": ["overhead", "horizontal"], "risk": 0.6, "range_frac": 0.8, "retreat_stamina": 0.2,
		"retreat_blood": 0.15, "feint": 0.05, "cripple": 0.0, "disarm_aim": 0.08, "commit_ticks": 70},
	"duelist": {"aggression": 0.5, "patience": 0.8, "reaction_ms": 140.0, "aim_noise": 0.1,
		"preferred_attacks": ["diag", "thrust", "horizontal"], "risk": 0.3, "range_frac": 0.9,
		"retreat_stamina": 0.3, "retreat_blood": 0.3, "feint": 0.35, "cripple": 0.5, "disarm_aim": 0.4,
		"commit_ticks": 120},
	"coward": {"aggression": 0.2, "patience": 0.9, "reaction_ms": 200.0, "aim_noise": 0.25,
		"preferred_attacks": ["thrust", "low"], "risk": 0.05, "range_frac": 1.3, "retreat_stamina": 0.45,
		"retreat_blood": 0.6, "feint": 0.1, "cripple": 1.0, "disarm_aim": 0.15,
		"commit_ticks": 150},
	"berserker": {"aggression": 1.0, "patience": 0.0, "reaction_ms": 220.0, "aim_noise": 0.4,
		"preferred_attacks": ["horizontal", "diag"], "risk": 1.0, "range_frac": 0.7, "retreat_stamina": 0.06,
		"retreat_blood": 0.0, "feint": 0.0, "cripple": 0.0, "disarm_aim": 0.0, "commit_ticks": 40},
}

var _rng := RandomNumberGenerator.new()
var _p: Dictionary = {}
var _ring: Array = []
var _ring_n: int = 0
var _delay: int = -1
var _tick: int = 0

var _state: int = ST_APPROACH
var _st_ticks: int = 0
var _st_len: int = 0
var _wait: int = 20
var _circle_dir: int = 1
var _circle_t: int = 60
var _plan: Dictionary = {}
var _tired: bool = false
var _thr_prev: bool = false
var _reflex_ok: bool = true
var _grab_ticks: int = 0
var _weapon_giveup: int = 0  ## tick before which the brain does not go for a prop again (a grab that never worked)
var _main_weapon: String = ""
var _last_aim: Vector2 = Vector2(0.0, 0.15)  ## aim sent last tick (the hand is eased, not snapped, after a strike)
var _idle_ticks: int = 0  ## ticks spent circling in approach without starting an attack

# Per-tick geometry (set by _geometry).
var _fwd: Vector3 = Vector3(0.0, 0.0, -1.0)
var _right: Vector3 = Vector3(1.0, 0.0, 0.0)
var _dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var _dist: float = 5.0
var _origin: Vector3 = Vector3.ZERO
var _reach: float = 1.5


static func preset(preset_name: String) -> Dictionary:
	if PRESETS.has(preset_name):
		return (PRESETS[preset_name] as Dictionary).duplicate(true)
	return (PRESETS["duelist"] as Dictionary).duplicate(true)


## `personality` may name a preset ({"preset": "brute"}) and/or override knobs: aggression, patience (0..1),
## reaction_ms, aim_noise (0..1), preferred_attacks (Array of kinds or {kind: weight}), risk (0..1), range_frac,
## retreat_stamina, retreat_blood, feint, cripple.
func _init(seed: int, personality: Dictionary = {}) -> void:
	_rng.seed = seed
	_p = preset(str(personality.get("preset", "duelist")))
	for k: Variant in personality:
		if str(k) != "preset":
			_p[k] = personality[k]
	_ring.resize(RING)
	_circle_dir = 1 if _rng.randf() < 0.5 else -1
	_wait = _new_wait()


func state_name() -> String:
	return STATE_NAMES[_state]


## The attack currently planned or last executed: {kind, part, dir, noise, half, neck, finishing}.
func plan() -> Dictionary:
	return _plan.duplicate(true)


func personality() -> Dictionary:
	return _p.duplicate(true)


func think(me: Dictionary, foe: Dictionary, delta: float) -> FighterInput:
	_tick += 1
	if _delay < 0:
		_delay = clampi(roundi(_pf("reaction_ms") / 1000.0 / maxf(delta, 0.0001)), 0, RING - 8)
	_ring[_ring_n % RING] = foe.duplicate()  # shallow: callers may reuse and mutate their dict
	_ring_n += 1
	var out := FighterInput.new()
	var obs: Dictionary = _lagged(_delay)
	if _main_weapon == "":
		_main_weapon = str(me.get("weapon_id", "fists"))
	var my_state: String = str(me.get("state", "standing"))
	if my_state == "down" or my_state == "getting_up" or my_state == "ko" or my_state == "dead":
		_enter(ST_APPROACH, 0)
		_wait = 20
		return out
	if str(obs.get("state", "standing")) == "dead":
		return out
	_geometry(me, obs)
	if _tick <= int(_p.get("spawn_hold", SPAWN_HOLD_TICKS)):
		_neutral_aim(out)
		return out
	_update_state(me, obs)
	match _state:
		ST_APPROACH, ST_FINISH:
			_do_approach(me, obs, out)
		ST_FEINT:
			_do_feint(me, obs, out)
		ST_WINDUP:
			_do_windup(me, obs, out)
		ST_STRIKE:
			_do_strike(me, obs, out)
		ST_RECOVER:
			_do_recover(me, obs, out)
		ST_GUARD:
			_do_guard(me, obs, out)
		ST_RETREAT:
			_do_retreat(me, obs, out)
		ST_WEAPON:
			_do_weapon(me, obs, out)
	_st_ticks += 1
	if out.move_y < 300:
		_wall_adjust(me, out)
	return out


# ---------------------------------------------------------------- state selection

func _update_state(me: Dictionary, obs: Dictionary) -> void:
	var stamina: float = float(me.get("stamina", 1.0))
	var rs: float = _pf("retreat_stamina")
	if stamina < rs or float(me.get("blood_frac", 1.0)) < _pf("retreat_blood"):
		_tired = true
	elif stamina > rs + 0.3 and float(me.get("blood_frac", 1.0)) >= _pf("retreat_blood") + 0.05:
		_tired = false
	var finishing: bool = _want_finish(obs)
	var busy: bool = _state == ST_STRIKE or _state == ST_GUARD

	var thr: bool = _threat(me, obs)
	if thr and not _thr_prev:
		_reflex_ok = _rng.randf() <= clampf(1.0 - _pf("risk") * 0.7, 0.2, 1.0)
	_thr_prev = thr
	if thr and _reflex_ok and _state != ST_GUARD:
		if not (_state == ST_STRIKE and _pf("risk") > 0.5):
			_enter(ST_GUARD, roundi(18.0 + _pf("patience") * 20.0))
			return
	if _state == ST_GUARD:
		if thr and _st_ticks > _st_len - 6:
			_st_ticks = maxi(_st_len - 6, 0)  # still under threat: keep the guard up
		if _st_ticks < _st_len:
			return
		_after_guard(me, obs)
		return
	if busy:
		return
	if _disarmed(me) and _tick >= _weapon_giveup and not _props(me, obs).is_empty():
		if _state != ST_WEAPON:
			_enter(ST_WEAPON, 0)
			_grab_ticks = 0
		return
	if _state == ST_WEAPON:
		_enter(ST_APPROACH, 0)
	var press: bool = finishing and (_pf("risk") > 0.5 or (stamina > 0.12 and float(me.get("blood_frac", 1.0)) > 0.3))
	if _tired and not press:
		if _state != ST_RETREAT:
			_enter(ST_RETREAT, 0)
		return
	if _state == ST_RETREAT:
		_enter(ST_APPROACH, 0)
		_wait = _new_wait()
	if _state == ST_APPROACH and finishing:
		_state = ST_FINISH
	elif _state == ST_FINISH and not finishing:
		_state = ST_APPROACH


func _after_guard(me: Dictionary, obs: Dictionary) -> void:
	var p_rip: float = _pf("patience") * 0.6 + _pf("aggression") * 0.2
	if not _tired and _dist <= _reach * 1.15 and _rng.randf() <= p_rip:
		_plan = _make_plan(me, obs, _want_finish(obs))
		_enter(ST_WINDUP, roundi(float(_windup_len(me)) * 0.5))
	else:
		_enter(ST_APPROACH, 0)
		_wait = roundi(float(_new_wait()) * 0.5)


func _enter(s: int, len_ticks: int) -> void:
	if s == ST_WINDUP or s == ST_FEINT:
		_idle_ticks = 0
	_state = s
	_st_ticks = 0
	_st_len = len_ticks


func _want_finish(obs: Dictionary) -> bool:
	var st: String = str(obs.get("state", "standing"))
	if st == "down" or st == "ko" or st == "getting_up":
		return true
	return _foe_blood(obs) < Tuning.shared().finisher_blood_frac


func _foe_blood(obs: Dictionary) -> float:
	if obs.has("blood_frac"):
		return float(obs["blood_frac"])
	if obs.has("blood"):
		return clampf((float(obs["blood"]) - 2.5) / 2.5, 0.0, 1.0)
	return 1.0


## True when the foe's tip is fast, close to me and not moving away.
func _threat(me: Dictionary, obs: Dictionary) -> bool:
	if float(obs.get("tip_speed", 0.0)) < 4.0:
		return false
	var torso: Vector3 = _part_pos(me, "torso", Vector3(0.0, 1.2, 0.0))
	var tip: Vector3 = obs.get("tip_pos", Vector3.ZERO)
	var td: float = tip.distance_to(torso)
	var fdef: Dictionary = CombatData.weapon(str(obs.get("weapon_id", "fists")))
	var window: float = float(fdef.get("length", 0.3)) + 1.0
	if td > window:
		return false
	if _ring_n > _delay + 5:
		var prev: Vector3 = _lagged(_delay + 4).get("tip_pos", tip)
		if prev.distance_to(torso) < td - 0.02:
			return false
	return true


## True when the foe swung hard in the last 45 ticks and is now slow (an opening).
func _opportunity(obs: Dictionary) -> bool:
	if float(obs.get("tip_speed", 0.0)) > 2.0:
		return false
	var j: int = 0
	while j <= 45 and j < _ring_n - _delay:
		if float(_lagged(_delay + j).get("tip_speed", 0.0)) > 4.0:
			return true
		j += 3
	return false


func _disarmed(me: Dictionary) -> bool:
	return str(me.get("weapon_id", "fists")) == "fists" and _main_weapon != "fists" and _main_weapon != ""


func _props(me: Dictionary, obs: Dictionary) -> Array:
	var out: Array = []
	for src: Dictionary in [me, obs]:
		var a: Variant = src.get("props", null)
		if a is Array:
			for it: Variant in a:
				if it is Dictionary and (it as Dictionary).has("pos"):
					out.append(it)
	return out


# ---------------------------------------------------------------- states

func _do_approach(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var finishing: bool = _state == ST_FINISH
	var hold: float = _reach * _pf("range_frac")
	_idle_ticks += 1
	var committed: bool = _idle_ticks > int(_pf("commit_ticks"))
	if committed:
		hold = minf(hold, _reach * 0.85)  # waited long enough: step into striking range
	if finishing:
		hold = _reach * 0.85
	var stamina: float = float(me.get("stamina", 1.0))
	_neutral_aim(out)
	_shield_up(me, out)
	if _dist > hold + 0.25:
		out.move_y = 1000 if _dist > hold + 1.0 else 600
		var sprint_from: float = hold + (2.0 if _pf("risk") > 0.7 else 3.5)
		if (_dist > sprint_from and stamina > 0.5) or (finishing and _dist > hold + 1.5 and stamina > 0.25):
			out.buttons |= FighterInput.SPRINT
		if _dist <= hold + 0.8:
			_wait = maxi(_wait - 1, 0)
	else:
		_circle_t -= 1
		if _circle_t <= 0:
			_circle_t = _rng.randi_range(40, 110)
			_circle_dir = 1 if _rng.randf() < 0.5 else -1
		out.move_x = _circle_dir * 600
		out.move_y = roundi(clampf((_dist - hold) * 1.5, -0.6, 0.6) * 1000.0)
		_wait = maxi(_wait - 1, 0)
	if finishing or committed:
		_wait = 0
	if _wait > 0:
		return
	var opp: bool = _opportunity(obs)
	var p: float = lerpf(0.3, 1.0, _pf("aggression")) + (0.3 if opp else 0.0)
	if not opp and not finishing:
		p *= lerpf(1.0, 0.25, _pf("patience"))
	if committed:
		p = maxf(p, 0.5)
	var in_reach: bool = _dist <= _reach * 1.05
	var lunge: bool = _dist <= _reach * (1.3 if finishing else 1.9) and (_pf("aggression") > 0.5 or opp or finishing or committed)
	if _rng.randf() <= p and (in_reach or lunge):
		_plan = _make_plan(me, obs, finishing)
		if not finishing and _rng.randf() < _pf("feint"):
			_enter(ST_FEINT, 12 + _rng.randi_range(0, 6))
		else:
			_enter(ST_WINDUP, _windup_len(me))
	else:
		_wait = _rng.randi_range(8, 24)


func _do_feint(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var t: Vector2 = _plan_target(me, obs)
	var dir: Vector2 = _plan["dir"]
	var wind: Vector2 = _clamp_aim(t - dir * WINDUP_AMP)
	_set_aim(out, wind.lerp(Vector2(0.0, 0.15), 0.25))
	_shield_up(me, out)
	_advance(out)
	if _st_ticks >= _st_len:
		_plan = _make_plan(me, obs, false)
		_enter(ST_WINDUP, roundi(float(_windup_len(me)) * 0.6))


func _do_windup(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	if _dist > _reach * 2.2:
		_enter(ST_APPROACH, 0)
		return
	var t: Vector2 = _plan_target(me, obs)
	var wind: Vector2 = _windup_aim(t)
	var u: float = clampf(float(_st_ticks) / maxf(float(_st_len) * 0.6, 1.0), 0.0, 1.0)
	_set_aim(out, Vector2(0.0, 0.15).lerp(wind, u))
	if float(_st_ticks) >= float(_st_len) * 0.5:
		out.buttons |= FighterInput.SWING
	if bool(_plan.get("half", false)):
		out.buttons |= FighterInput.HALF_SWORD
	_advance(out)
	if _st_ticks + 1 >= _st_len:
		_enter(ST_STRIKE, _strike_len(me))


func _do_strike(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var t: Vector2 = _plan_target(me, obs)
	var wind: Vector2 = _windup_aim(t)
	var u: float = clampf(float(_st_ticks + 1) / maxf(float(_st_len), 1.0), 0.0, 1.0)
	var e: float = u * u
	var end: Vector2 = t if _plan["kind"] == "thrust" else _clamp_aim(t + (_plan["dir"] as Vector2) * WINDUP_AMP)
	_set_aim(out, wind.lerp(end, e))
	out.buttons |= FighterInput.SWING
	if _plan["kind"] == "thrust":
		out.buttons |= FighterInput.THRUST
	if bool(_plan.get("half", false)):
		out.buttons |= FighterInput.HALF_SWORD
	_advance(out)
	if _st_ticks + 1 >= _st_len:
		var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
		var rec: float = (14.0 + float(def.get("mass", 1.0)) * 8.0) * (1.3 - _pf("aggression") * 0.6)
		_enter(ST_RECOVER, clampi(roundi(rec), 10, 50))


func _do_recover(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	_neutral_aim(out, SLEW_RECOVER)
	_shield_up(me, out)
	out.move_y = roundi(-300.0 * (1.0 - _pf("aggression")))
	if _st_ticks + 1 >= _st_len:
		var finishing: bool = _want_finish(obs)
		var stamina: float = float(me.get("stamina", 1.0))
		if not _tired and _dist <= _reach * 1.1 and _rng.randf() <= _pf("aggression") * 0.6 * minf(stamina * 1.5, 1.0):
			_plan = _make_plan(me, obs, finishing)
			_enter(ST_WINDUP, roundi(float(_windup_len(me)) * 0.7))
		else:
			_enter(ST_APPROACH, 0)
			_wait = _new_wait()


func _do_guard(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var tip: Vector3 = obs.get("tip_pos", Vector3.ZERO)
	var a: Vector2 = _clamp_aim(Vector2((tip - _origin).dot(_right) / GUARD_W * 0.7, (tip.y - _origin.y) / GUARD_H * 0.7))
	_set_aim(out, _last_aim.move_toward(a, SLEW_GUARD))
	out.buttons |= FighterInput.SWING | FighterInput.OFFHAND
	out.move_y = -250 if _dist < _reach * 1.2 else 0


func _do_retreat(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	_set_aim(out, _last_aim.move_toward(Vector2(0.0, 0.2), SLEW_NEUTRAL))
	_shield_up(me, out)
	if _dist < _reach * 2.2:
		out.move_y = -800
		out.move_x = _circle_dir * 200


func _do_weapon(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var props: Array = _props(me, obs)
	if props.is_empty():
		_enter(ST_APPROACH, 0)
		return
	var mp: Vector3 = me.get("pelvis_pos", Vector3.ZERO)
	var best: Vector3 = Vector3.ZERO
	var bd: float = 1.0e9
	for it: Variant in props:
		var pp: Vector3 = (it as Dictionary)["pos"]
		var d: float = Vector2(pp.x - mp.x, pp.z - mp.z).length()
		if d < bd:
			bd = d
			best = pp
	_grab_ticks += 1
	if _grab_ticks > 240:  # the prop cannot be picked up (or the foe stands on it): fight with fists for a while
		_weapon_giveup = _tick + 600
		_enter(ST_APPROACH, 0)
		return
	var to: Vector3 = best - mp
	to.y = 0.0
	var near: float = to.length()
	_set_aim(out, _clamp_aim(_aim_for(best)))
	if near > 0.35:
		_move_world(to / maxf(near, 0.001), 1.0 if near > 1.0 else 0.4, out)
		if near > 4.0 and float(me.get("stamina", 1.0)) > 0.4:
			out.buttons |= FighterInput.SPRINT
	if near < 1.2:
		if _grab_ticks % 12 < 6:  # the fighter grabs on a rising edge: pulse the button
			out.buttons |= FighterInput.GRAB
		if best.y < 0.5:
			out.buttons |= FighterInput.CROUCH


# ---------------------------------------------------------------- attack planning

func _make_plan(me: Dictionary, obs: Dictionary, finishing: bool) -> Dictionary:
	var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	var armor: Dictionary = obs.get("armor", {}) if obs.get("armor", {}) is Dictionary else {}
	var st: String = str(obs.get("state", "standing"))
	var down: bool = st == "down" or st == "ko" or st == "getting_up"
	var shape: String = str(def.get("shape", "fist"))
	var pointy: bool = bool(def.get("point", false))
	var edged: bool = float(def.get("edge_len", 0.0)) >= 0.15 and (shape == "sword" or shape == "axe")
	var blunt: bool = not edged and not pointy
	var mirror: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var noise := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * (_pf("aim_noise") * 0.45)
	var kind: String = ""
	var part: String = ""
	var neck: bool = false
	var half: bool = false
	var avg_armor: float = _avg_armor(armor, blunt)
	var can_half: bool = bool(def.get("half_sword", false))

	if finishing:
		if down:
			if edged or blunt:
				kind = "overhead"
				part = "head"
				neck = edged
			else:
				kind = "thrust"
				part = "torso"
		else:
			# Pick the killing blow the weapon can deliver (core brief: behead / gut / run through / skull crush),
			# weighted toward the least armored target.
			var opts: Dictionary = {}
			var head_open: float = 1.0 - _armor_score(armor, "head", blunt)
			var torso_open: float = 1.0 - _armor_score(armor, "torso", blunt)
			var belly_open: float = 1.0 - _armor_score(armor, "pelvis", blunt)
			if edged:
				opts["behead"] = head_open * 1.2
				opts["gut"] = maxf(torso_open, belly_open) * 1.0
			if pointy:
				opts["run_through"] = torso_open * (2.0 if shape == "spear" else 1.0)
			if blunt and shape != "fist":
				opts["skull_crush"] = head_open
			if opts.is_empty():
				opts["skull_crush"] = 1.0
			match _pick(opts):
				"behead":
					kind = "horizontal"
					part = "head"
					neck = true
				"gut":
					kind = "horizontal"
					part = "pelvis" if belly_open >= torso_open else "torso"
				"run_through":
					kind = "thrust"
					part = "torso"
				_:
					kind = "overhead"
					part = "head"
		half = can_half and kind == "thrust" and _armor_score(armor, part, false) >= 0.4
	else:
		kind = _pick(_kind_weights(def))
		if can_half and avg_armor >= 0.5 and pointy:
			kind = "thrust"
			half = true
		part = _pick_part(obs, armor, kind, blunt)
		if kind != "thrust" and kind != "low" and _rng.randf() < _pf("disarm_aim"):
			part = "forearm_r"  # knock the weapon out of the hand: strike the holding forearm
			if kind == "overhead":
				kind = "diag"
		neck = part == "head" and edged and (kind == "horizontal" or kind == "diag")
	var dir := Vector2.ZERO
	match kind:
		"diag":
			dir = Vector2(-mirror, -0.8)
		"horizontal", "low":
			dir = Vector2(-mirror, 0.0)
		"overhead":
			dir = Vector2(0.0, -1.0)
		_:
			dir = Vector2(mirror * 0.45, -0.25)  # thrust: wind up off line, then drive onto the target
	return {"kind": kind, "part": part, "dir": dir, "noise": noise, "half": half, "neck": neck, "finishing": finishing}


func _kind_weights(def: Dictionary) -> Dictionary:
	var w: Dictionary = {}
	match str(def.get("shape", "fist")):
		"spear":
			w = {"thrust": 5.0, "horizontal": 0.6, "overhead": 0.6}
		"rake":
			w = {"thrust": 2.0, "overhead": 2.0, "horizontal": 1.0}
		"sword":
			var stab: float = 2.0 if float(def.get("length", 1.0)) < 0.8 else 0.8
			w = {"diag": 2.0, "horizontal": 1.6, "overhead": 1.0, "thrust": stab, "low": 0.5}
		"axe", "club", "bat":
			w = {"diag": 2.0, "horizontal": 1.5, "overhead": 1.5, "low": 0.6}
		"fist":
			w = {"thrust": 2.0, "horizontal": 1.5, "overhead": 0.5}
		_:
			w = {"horizontal": 1.0, "overhead": 1.0}
	var pref: Variant = _p.get("preferred_attacks", [])
	if (pref is Array and not (pref as Array).is_empty()) or (pref is Dictionary and not (pref as Dictionary).is_empty()):
		for k: Variant in w.keys():
			var f: float = 0.25
			if pref is Array and (pref as Array).has(k):
				f = 3.0
			elif pref is Dictionary and (pref as Dictionary).has(k):
				f = float((pref as Dictionary)[k])
			w[k] = float(w[k]) * f
	return w


func _pick_part(obs: Dictionary, armor: Dictionary, kind: String, blunt: bool) -> String:
	var parts: Dictionary = obs.get("parts", {})
	var w: Dictionary = {}
	for name: Variant in PART_BASE:
		var n: String = str(name)
		var wt: float = float(PART_BASE[n])
		var pd: Dictionary = parts.get(n, {}) if parts.get(n, {}) is Dictionary else {}
		if bool(pd.get("severed", false)):
			continue
		var leg: bool = n.begins_with("thigh") or n.begins_with("shin")
		var arm: bool = n.begins_with("upper_arm") or n.begins_with("forearm")
		match kind:
			"low":
				wt *= 6.0 if leg else 0.1
			"overhead":
				wt *= 1.8 if n == "head" else (1.2 if n == "torso" else (0.3 if leg else 1.0))
			"horizontal":
				wt *= 0.4 if leg else (1.2 if (arm or n == "head") else 1.0)
			"diag":
				wt *= 0.4 if leg else 1.2
			"thrust":
				wt *= 1.6 if n == "torso" else (0.3 if leg else (0.4 if arm else 1.0))
		if leg:
			wt *= 1.0 + _pf("cripple") * 2.5
		if blunt and n == "head":
			wt *= BLUNT_HEAD_BIAS
		var sc: float = _armor_score(armor, n, blunt)
		wt *= 1.3 if sc <= 0.0 else (1.0 - 0.85 * sc)
		var info: Dictionary = CombatData.part_info(n)
		var hp0: float = float(info.get("hp", 0.0))
		if hp0 > 0.0 and pd.has("hp"):
			var frac: float = clampf(float(pd["hp"]) / hp0, 0.0, 1.0)
			wt *= 1.0 + (1.0 - frac)
		w[n] = maxf(wt, 0.001)
	if w.is_empty():
		return "torso"
	return _pick(w)


func _armor_score(armor: Dictionary, part: String, blunt: bool) -> float:
	var v: Variant = armor.get(part, "")
	var base: float = 0.0
	if v is bool:
		base = 0.6 if v else 0.0
	else:
		var s: String = str(v)
		if s == "":
			return 0.0
		var kind: String = str(CombatData.armor(s).get("kind", s))
		base = float(ARMOR_KIND.get(kind, 0.4))
		if blunt:
			base *= 0.4 if kind == "plate" else (0.5 if kind == "mail" else 1.0)
	return base


func _avg_armor(armor: Dictionary, blunt: bool) -> float:
	if armor.is_empty():
		return 0.0
	var tot: float = 0.0
	for n: Variant in PART_BASE:
		tot += _armor_score(armor, str(n), blunt)
	return tot / float(PART_BASE.size())


func _pick(w: Dictionary) -> String:
	var total: float = 0.0
	for k: Variant in w:
		total += float(w[k])
	var r: float = _rng.randf() * total
	var last: String = ""
	for k: Variant in w:
		last = str(k)
		r -= float(w[k])
		if r <= 0.0:
			return last
	return last


# ---------------------------------------------------------------- geometry and helpers

func _geometry(me: Dictionary, obs: Dictionary) -> void:
	var yaw: float = float(me.get("facing_yaw", 0.0))
	_fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	_right = Vector3(cos(yaw), 0.0, -sin(yaw))
	var mp: Vector3 = me.get("pelvis_pos", Vector3.ZERO)
	var fp: Vector3 = obs.get("pelvis_pos", Vector3(0.0, 0.0, -5.0))
	var d: Vector3 = fp - mp
	d.y = 0.0
	_dist = d.length()
	_dir = d / _dist if _dist > 0.001 else _fwd
	_origin = _part_pos(me, "torso", mp + Vector3(0.0, 0.5, 0.0)) + Vector3(0.0, 0.05, 0.0)
	var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	_reach = 0.9 + float(def.get("length", 0.3)) * 0.9
	if str(me.get("grip", "normal")) == "half":
		_reach -= 0.25


func _part_pos(d: Dictionary, part: String, fallback: Vector3) -> Vector3:
	var parts: Dictionary = d.get("parts", {})
	if parts.has(part) and parts[part] is Dictionary:
		return (parts[part] as Dictionary).get("pos", fallback)
	return fallback


## Where in aim space the planned strike should pass through, noise included.
func _plan_target(me: Dictionary, obs: Dictionary) -> Vector2:
	var part: String = str(_plan.get("part", "torso"))
	var fallback: Vector3 = (obs.get("pelvis_pos", Vector3.ZERO) as Vector3) + Vector3(0.0, 1.0, 0.0)
	var parts: Dictionary = obs.get("parts", {})
	if parts.has(part) and bool((parts[part] as Dictionary).get("severed", false)):
		part = "torso"
	var p: Vector3 = _part_pos(obs, part, fallback)
	if bool(_plan.get("neck", false)) and part == "head":
		p.y -= 0.12
	var wob: float = sin(float(_tick) * 0.07) * 0.05 * _pf("aim_noise")
	return _clamp_aim(_aim_for(p) + (_plan.get("noise", Vector2.ZERO) as Vector2) + Vector2(wob, 0.0))


func _windup_aim(t: Vector2) -> Vector2:
	return _clamp_aim(t - (_plan["dir"] as Vector2) * WINDUP_AMP)


func _aim_for(p: Vector3) -> Vector2:
	var rel: Vector3 = p - _origin
	var fd: float = maxf(rel.dot(_fwd), 0.5)
	return Vector2(rel.dot(_right) / fd * 1.3, rel.y / fd * 1.55)


func _clamp_aim(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))


func _set_aim(out: FighterInput, v: Vector2) -> void:
	var c: Vector2 = _clamp_aim(v)
	c.x = maxf(c.x, AIM_LEFT_LIMIT)
	c.y = maxf(c.y, AIM_LOW_LIMIT)  # a hand driven to the lowest aim drags the blade through the own thigh and pelvis  # the weapon hand stays off the offhand arm/shield side of the body
	_last_aim = c
	out.aim_x = roundi(c.x * 1000.0)
	out.aim_y = roundi(c.y * 1000.0)


func _neutral_aim(out: FighterInput, step: float = SLEW_NEUTRAL) -> void:
	var s: float = sin(float(_tick) * 0.05) * 0.08 * _pf("aim_noise")
	_set_aim(out, _last_aim.move_toward(Vector2(s, 0.15), step))


func _shield_up(me: Dictionary, out: FighterInput) -> void:
	if str(me.get("offhand_id", "")).contains("shield") and _dist < _reach + 1.5:
		out.buttons |= FighterInput.OFFHAND


## Lunge toward the foe while winding up or striking when out of comfortable reach.
func _advance(out: FighterInput) -> void:
	if _dist > _reach * 0.85:
		out.move_y = 800
		if _pf("risk") > 0.7 and _dist > _reach * 1.3:
			out.buttons |= FighterInput.SPRINT
	elif _dist < _reach * 0.45:
		out.move_y = -300


func _move_world(dir: Vector3, speed: float, out: FighterInput) -> void:
	out.move_x = roundi(clampf(dir.dot(_right) * speed, -1.0, 1.0) * 1000.0)
	out.move_y = roundi(clampf(dir.dot(_fwd) * speed, -1.0, 1.0) * 1000.0)


## Near the wall, bend backing-off and circling toward the arena centre.
func _wall_adjust(me: Dictionary, out: FighterInput) -> void:
	var mp: Vector3 = me.get("pelvis_pos", Vector3.ZERO)
	var r: float = Vector2(mp.x, mp.z).length()
	if r <= 8.8:
		return
	var w: float = clampf((r - 8.8) / 2.0, 0.0, 1.0)
	var c: Vector3 = Vector3(-mp.x, 0.0, -mp.z) / r
	out.move_x = roundi(lerpf(float(out.move_x), c.dot(_right) * 1000.0, w))
	out.move_y = roundi(lerpf(float(out.move_y), c.dot(_fwd) * 1000.0, w))


func _windup_len(me: Dictionary) -> int:
	var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	var m: float = float(def.get("mass", 1.0))
	return clampi(roundi((8.0 + m * 7.0) * (1.15 - _pf("aggression") * 0.5)), 8, 36)


func _strike_len(me: Dictionary) -> int:
	var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	var m: float = float(def.get("mass", 1.0))
	var fast: float = FINISH_STRIKE_SCALE if bool(_plan.get("finishing", false)) else 1.0  # a killing blow wants speed
	if _plan.get("kind", "") == "thrust":
		return clampi(roundi((8.0 + m * 2.0) * fast), 6, 16)
	return clampi(roundi((12.0 + m * 5.0) * fast), 9, 30)


func _new_wait() -> int:
	var base: float = _rng.randf_range(20.0, 70.0)
	return roundi(base * (0.4 + _pf("patience") * 1.4) * (1.35 - _pf("aggression") * 0.9))


func _lagged(k: int) -> Dictionary:
	var avail: int = mini(_ring_n, RING)
	var kk: int = clampi(k, 0, maxi(avail - 1, 0))
	return _ring[posmod(_ring_n - 1 - kk, RING)]


func _pf(key: String) -> float:
	return float(_p.get(key, 0.5))
