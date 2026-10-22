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
const HEAVY_SHORT_SHAPES: PackedStringArray = ["axe", "club"]
const HEAVY_LOW_LIMIT: float = -0.3  ## axe/club aim floor on the weapon side: the head swings down through the own shin
const HEAVY_LOW_X0: float = 0.35  ## the floor eases in between these aim x values (leg attacks on a foe in front stay)
const HEAVY_LOW_X1: float = 0.6
const SLEW_RECOVER: float = 0.045
const SLEW_GUARD: float = 0.2
const DISARM_SCALE: float = 0.3  ## share of the personality's disarm_aim actually used (round 1 over-disarmed: 57 per 24 matches)
const GROUND_PROP_Y: float = 0.5  ## props lower than this are picked up by crouching
const GRAB_REACH: float = 0.45  ## the hand reaches about this far ahead of the torso at full downward aim
const STAMINA_FLOOR: float = 0.15  ## below this the weapon arm's carry cost cancels stamina recovery (a fighter at 0 never recovers)
const REST_FAIL_TICKS: int = 300  ## ticks at near-zero stamina after which resting is abandoned
const BEHEAD_BIAS: float = 3.0  ## finisher choice: an edged weapon prefers the neck over the gut (foes usually bleed out before a second try)
const NECK_LIFT: float = 0.05  ## aim offset from the head centre for neck cuts: negative aims at the neck, but the swung tip sags about 0.15 m below its aim at full speed
const STALE_START: int = 360  ## ticks without decisive damage before the brain starts forcing the issue (long: footwork between bursts is not a stalemate)
const STALE_RAMP: int = 480  ## further ticks until it is fully desperate
const REPOS_DESPERATE: float = 0.5  ## above this desperation the brain stops breaking off and presses
const WALL_SOFT: float = 6.5  ## steering starts bending toward the arena centre beyond this radius (m)
const PIN_RADIUS: float = 7.0  ## a foe farther out than this can be pinned against the wall
const BURST_TICKS: int = 150  ## committed attacking after a footwork phase (a re-engagement, not a slow drift in)
const LONG_REACH: float = 2.5  ## weapons reaching farther than this (spear, rake) sidestep little while guarding
const LONG_GUARD_SCALE: float = 0.5
const TIP_GAIN_X: float = 3.0  ## metres the blade line moves at the foe per metre of hand travel sideways (pole)
const TIP_GAIN_Y: float = 2.0  ## the same, vertically (the blade pitches up as the hand rises, less than it yaws)
const SPEAR_SERVO_GAIN: float = 0.12  # TUNING: share of the blade line's miss closed per tick by the pole servo
const SPEAR_AIM_SLEW: float = 0.2  ## max aim travel per tick while a spear tracks its target
const SPEAR_ALIGN_TOL: float = 0.18  # TUNING: blade line miss (m) under which a spear thrust is let go
const SPEAR_WINDUP: int = 10  ## ticks a spear waits for its point to line up before it thrusts anyway
const SPEAR_READY_DIST: float = 4.5  ## inside this distance a spear holds its pole stance (blade level, point on the foe)
const SPEAR_STRIKE_MAX: float = 3.4  # TUNING: a spear thrust is started only inside this distance (pelvis to pelvis, m)
const SPEAR_THRUST_MIN: float = 2.75  # TUNING: closer than this the levelled point is already past the foe's front
const SPEAR_HOLD_MIN: float = 2.9  # TUNING: the spear's standing distance band (pelvis to pelvis, m)
const SPEAR_HOLD_MAX: float = 3.3  # TUNING
const SPEAR_MIN_RANGE: float = 2.3  # TUNING: inside this a spear gives ground until there is room for the point
const SPEAR_BACKSTEP: int = 800  ## backward move input while a spear gives ground
const SPEAR_LUNGE_MIN: float = 2.2  # TUNING: a thrust steps in only while farther than this (m, pelvis to pelvis)
const SPEAR_STRIKE_TICKS: int = 28  # TUNING: a spear thrust's length (the step in that carries the point)
const SPEAR_NOISE_M: float = 1.2  ## metres of point offset per unit of plan aim noise (the noise is in hand-aim units)
const REPOS_ORBIT: int = 0
const REPOS_BACK: int = 1
const REPOS_GOAL: int = 2
const GOAL_RADIUS_MAX: float = 8.0  ## repositioning goals stay inside this radius
const STALE_HP_DROP: float = 1.5  ## head/torso/pelvis hp loss that counts as decisive damage
const STALE_CONSC_DROP: float = 0.03
const ROLL_MIN_STAMINA: float = 0.45  ## the brain only rolls with stamina to spare (a roll costs Tuning roll_stamina)
const ROLL_RANGE: float = 2.6  ## pelvis distance inside which a roll is an escape
const ROLL_THREAT_CHANCE: float = 0.012  ## per tick while a fast blow is coming in
const ROLL_ESCAPE_CHANCE: float = 0.003  ## per tick while breaking off
const ROLL_COOLDOWN_TICKS: int = 240
const CLOSE_COOLDOWN_TICKS: int = 300  ## between the brain's shoves, kicks and grabs (used sparingly)
const CLOSE_MIN_STAMINA: float = 0.4
const SHOVE_RANGE: float = 1.25  ## pelvis distance inside which a shove can reach
const SHOVE_CHANCE: float = 0.006  ## per tick in range
const SHOVE_STUMBLE_CHANCE: float = 0.05  ## per tick in range while the foe stumbles (a shove floors them)
const KICK_MIN: float = 1.0  ## front kick distance band (pelvis to pelvis, m)
const KICK_MAX: float = 1.3
const KICK_CHANCE: float = 0.004
const GRAB_RANGE: float = 1.2
const GRAB_CHANCE: float = 0.005  ## only with a free left hand
const HOLD_TICKS_MIN: int = 45  ## how long the brain keeps a hold (it keeps attacking with the weapon meanwhile)
const HOLD_TICKS_MAX: int = 110
const STRUGGLE_SHOVE_CHANCE: float = 0.05  ## per tick while held: shove the holder off (pulling back all the while)
const BRAWLER_LEN_RATIO: float = 2.0  ## foe weapon length over fist length that sends a fist fighter rushing in
const FIST_HEAD_BIAS: float = 2.5  ## extra on top of the blunt bias for bare fists: brawlers go for the jaw (concussion, bloody nose)
const BLUNT_HEAD_BIAS: float = 4.0  ## blunt weapons do not bleed: they win by knocking the head (consciousness)

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
		"retreat_blood": 0.15, "feint": 0.05, "cripple": 0.0, "disarm_aim": 0.08, "commit_ticks": 70,
		"engage": [240, 440], "repos": [150, 320], "disengage": 0.25, "orbit_r": [1.8, 3.0], "repos_goal": 0.55},
	"duelist": {"aggression": 0.5, "patience": 0.8, "reaction_ms": 140.0, "aim_noise": 0.1,
		"preferred_attacks": ["diag", "thrust", "horizontal"], "risk": 0.3, "range_frac": 0.9,
		"retreat_stamina": 0.3, "retreat_blood": 0.3, "feint": 0.35, "cripple": 0.5, "disarm_aim": 0.4,
		"commit_ticks": 120,
		"engage": [180, 340], "repos": [270, 480], "disengage": 0.5, "orbit_r": [2.0, 3.6], "repos_goal": 0.55},
	"coward": {"aggression": 0.2, "patience": 0.9, "reaction_ms": 200.0, "aim_noise": 0.25,
		"preferred_attacks": ["thrust", "low"], "risk": 0.05, "range_frac": 1.3, "retreat_stamina": 0.45,
		"retreat_blood": 0.6, "feint": 0.1, "cripple": 1.0, "disarm_aim": 0.15,
		"commit_ticks": 150,
		"engage": [140, 260], "repos": [400, 700], "disengage": 0.7, "orbit_r": [3.5, 5.5], "repos_goal": 0.6},
	"berserker": {"aggression": 1.0, "patience": 0.0, "reaction_ms": 220.0, "aim_noise": 0.4,
		"preferred_attacks": ["horizontal", "diag"], "risk": 1.0, "range_frac": 0.7, "retreat_stamina": 0.06,
		"retreat_blood": 0.0, "feint": 0.0, "cripple": 0.0, "disarm_aim": 0.0, "commit_ticks": 40,
		"engage": [340, 560], "repos": [90, 200], "disengage": 0.1, "orbit_r": [1.5, 2.5], "repos_goal": 0.45},
}

var _rng := RandomNumberGenerator.new()
var _drng := RandomNumberGenerator.new()  ## difficulty rolls only, so "normal" draws exactly what it always drew
var _roll_rng := RandomNumberGenerator.new()  ## dodge-roll choices only (own stream: the rest of the brain draws as before)
var _roll_cd: int = 0  ## ticks before the brain considers another dodge roll
var _close_rng := RandomNumberGenerator.new()  ## shove, kick and grab choices only (own stream)
var _close_cd: int = 0
var _hold_left: int = 0  ## ticks the brain keeps CLINCH held
var _hold_grace: int = 0
var _p: Dictionary = {}
var _d: Dictionary = {}  ## AiDifficulty parameters
var _finish_ok: bool = true  ## difficulty: the brain currently notices that the foe is beaten
var _finish_t: int = 0
var _opp_ok: bool = true  ## difficulty: the brain currently notices openings
var _opp_t: int = 0
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
var _heavy_short: bool = false  ## the held weapon is an axe or club (see HEAVY_LOW_LIMIT)
var _last_aim: Vector2 = Vector2(0.0, 0.15)  ## aim sent last tick (the hand is eased, not snapped, after a strike)
var _stale_ticks: int = 0  ## ticks since either fighter lost blood, consciousness or core hp (a stalemate clock)
var _stale_prev: Dictionary = {}
var _low_ticks: int = 0  ## ticks spent tired with stamina near zero
var _no_rest_until: int = 0
var _idle_ticks: int = 0  ## ticks spent circling in approach without starting an attack
var _phase: int = 0  ## 0 = engage burst, 1 = footwork between bursts (circle, back off, reposition)
var _phase_t: int = 0
var _repos_style: int = REPOS_ORBIT
var _repos_goal: Vector3 = Vector3.ZERO
var _orbit_r: float = 3.0
var _flip_t: int = 0
var _range_off: float = 0.0  ## range work: how far past the base hold distance the fighter stands right now (m)
var _range_t: int = 0
var _was_down: bool = false
var _venue: Vector3 = Vector3.ZERO  ## where this fighter would like the duel to drift to; steps back and circling lean toward it
var _venue_t: int = 0
var _burst_t: int = 0  ## ticks left of a committed attack burst after re-engaging
var _seen: Dictionary = {}  ## own 1 m grid cells visited (Vector2i -> ticks), so repositioning goals favour unused sand
var _mp: Vector3 = Vector3.ZERO
var _fp: Vector3 = Vector3.ZERO

# Per-tick geometry (set by _geometry).
var _fwd: Vector3 = Vector3(0.0, 0.0, -1.0)
var _right: Vector3 = Vector3(1.0, 0.0, 0.0)
var _dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var _dist: float = 5.0
var _origin: Vector3 = Vector3.ZERO
var _reach: float = 1.5
var _spear: bool = false  ## the held weapon is a spear (thrusts with the whole body)


static func preset(preset_name: String) -> Dictionary:
	if PRESETS.has(preset_name):
		return (PRESETS[preset_name] as Dictionary).duplicate(true)
	return (PRESETS["duelist"] as Dictionary).duplicate(true)


## `personality` may name a preset ({"preset": "brute"}) and/or override knobs: aggression, patience (0..1),
## reaction_ms, aim_noise (0..1), preferred_attacks (Array of kinds or {kind: weight}), risk (0..1), range_frac,
## retreat_stamina, retreat_blood, feint, cripple.
func _init(seed: int, personality: Dictionary = {}) -> void:
	_rng.seed = seed
	_roll_rng.seed = seed * 7919 + 17
	_close_rng.seed = seed * 104729 + 31
	_p = preset(str(personality.get("preset", "duelist")))
	for k: Variant in personality:
		if str(k) != "preset":
			_p[k] = personality[k]
	_apply_difficulty(seed)
	_ring.resize(RING)
	_circle_dir = 1 if _rng.randf() < 0.5 else -1
	_wait = _new_wait()
	_phase_t = _span("engage")


## Fold the AiDifficulty table into the personality (knobs scaled once) and keep the table for the runtime hooks.
func _apply_difficulty(seed: int) -> void:
	_d = AiDifficulty.params(str(_p.get("difficulty", AiDifficulty.DEFAULT_ID)))
	_drng.seed = seed ^ 0x5bd1e995
	if float(_d["aggr_add"]) != 0.0:
		_p["aggression"] = clampf(_pf("aggression") + float(_d["aggr_add"]), 0.0, 1.0)
	if float(_d["aim_noise_scale"]) != 1.0:
		_p["aim_noise"] = _pf("aim_noise") * float(_d["aim_noise_scale"])
	if float(_d["stamina_mgmt"]) != 1.0:
		_p["retreat_stamina"] = clampf(_pf("retreat_stamina") * float(_d["stamina_mgmt"]), 0.0, 0.8)
	if float(_d["wait_scale"]) != 1.0:
		_p["commit_ticks"] = roundi(_pf("commit_ticks") * float(_d["wait_scale"]))


func difficulty() -> String:
	return AiDifficulty.normalize(str(_p.get("difficulty", AiDifficulty.DEFAULT_ID)))


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
		var ms: float = maxf(_pf("reaction_ms") * float(_d["reaction_scale"]), float(_d["reaction_min_ms"]))
		_delay = clampi(roundi(ms / 1000.0 / maxf(delta, 0.0001)), 0, RING - 8)
	_ring[_ring_n % RING] = foe.duplicate()  # shallow: callers may reuse and mutate their dict
	_ring_n += 1
	var out := FighterInput.new()
	var obs: Dictionary = _lagged(_delay)
	if _main_weapon == "":
		_main_weapon = str(me.get("weapon_id", "fists"))
	_heavy_short = HEAVY_SHORT_SHAPES.has(str(CombatData.weapon(str(me.get("weapon_id", "fists"))).get("shape", "fist")))
	var my_state: String = str(me.get("state", "standing"))
	if my_state == "down" or my_state == "getting_up" or my_state == "ko" or my_state == "dead":
		_enter(ST_APPROACH, 0)
		_wait = 20
		_was_down = true
		return out
	if _was_down:  # back on my feet: take some room before re-engaging
		_was_down = false
		_begin_repos(REPOS_BACK, 90 + _rng.randi_range(0, 90))
	if _phase_t > 0:
		_phase_t -= 1
	if _burst_t > 0:
		_burst_t -= 1
	_venue_t -= 1
	if _venue_t <= 0 or Vector2(_venue.x - _mp.x, _venue.z - _mp.z).length() < 1.5:
		_venue_t = _rng.randi_range(360, 800)
		_venue = _pick_spot()
	if str(obs.get("state", "standing")) == "dead":
		return out
	_geometry(me, obs)
	_track_stale(me, foe)
	_notice_rolls()
	if _tick <= int(_p.get("spawn_hold", SPAWN_HOLD_TICKS)):
		_neutral_aim(out)
		return out
	if _tick == int(_p.get("spawn_hold", SPAWN_HOLD_TICKS)) + 1 and _rng.randf() < 0.75 * (1.0 - _pf("aggression")) + 0.1:
		_begin_repos(-1, 0)  # size the foe up instead of rushing into the middle
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
	_maybe_roll(me, obs, out)
	_maybe_close(me, obs, out)
	return out


## Now and then a shove, a front kick or a grab at close range, sparingly (a cooldown, a small chance per tick);
## a shove is likelier on a stumbling foe, since it floors them. Held by the foe, it pulls back and shoves.
func _maybe_close(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var cl: Dictionary = me.get("close", {})
	if str(cl.get("held", "")) != "":
		out.move_y = -1000
		if _close_rng.randf() < STRUGGLE_SHOVE_CHANCE:
			out.buttons |= FighterInput.SHOVE
		return
	if _hold_left > 0:
		if str(cl.get("holding", "")) != "" or bool(cl.get("reaching", false)) or _hold_grace > 0:
			_hold_left -= 1
			_hold_grace -= 1
			out.buttons |= FighterInput.CLINCH
			return
		_hold_left = 0
	if _close_cd > 0:
		_close_cd -= 1
		return
	if bool(me.get("rolling", false)) or str(me.get("state", "standing")) != "standing":
		return
	if _state == ST_WINDUP or _state == ST_STRIKE or _state == ST_FINISH or _state == ST_WEAPON:
		return
	var foe_state: String = str(obs.get("state", "standing"))
	if float(me.get("stamina", 1.0)) < CLOSE_MIN_STAMINA or (foe_state != "standing" and foe_state != "stumbling"):
		return
	# One draw, stacked chances: shove, then kick, then grab (each only in its own range).
	var r: float = _close_rng.randf()
	var shove_p: float = (SHOVE_STUMBLE_CHANCE if foe_state == "stumbling" else SHOVE_CHANCE) if _dist < SHOVE_RANGE else 0.0
	var kick_p: float = shove_p + (KICK_CHANCE if _dist >= KICK_MIN and _dist <= KICK_MAX else 0.0)
	var grab_p: float = kick_p + (GRAB_CHANCE if _dist < GRAB_RANGE and str(me.get("offhand_id", "")) == "" else 0.0)
	if r < shove_p:
		out.buttons |= FighterInput.SHOVE
	elif r < kick_p:
		out.buttons |= FighterInput.KICK
	elif r < grab_p:
		out.buttons |= FighterInput.CLINCH
		_hold_left = _close_rng.randi_range(HOLD_TICKS_MIN, HOLD_TICKS_MAX)
		_hold_grace = 3  # the reach shows in the frame from the next tick
	else:
		return
	_close_cd = CLOSE_COOLDOWN_TICKS


## Now and then a dodge roll out of trouble: a fast blow coming in at close range, or a hurt or tired fighter
## breaking off. Back and to one side, away from the foe; never while attacking, and not when too tired to pay for it.
func _maybe_roll(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	if _roll_cd > 0:
		_roll_cd -= 1
		return
	if bool(me.get("rolling", false)) or str(me.get("state", "standing")) != "standing":
		return
	if _state == ST_WINDUP or _state == ST_STRIKE or _state == ST_FINISH or _state == ST_WEAPON:
		return
	if float(me.get("stamina", 1.0)) < ROLL_MIN_STAMINA or _dist > ROLL_RANGE:
		return
	var chance: float = 0.0
	if _threat(me, obs):
		chance = ROLL_THREAT_CHANCE
	elif _state == ST_RETREAT:
		chance = ROLL_ESCAPE_CHANCE
	if chance <= 0.0 or _roll_rng.randf() >= chance:
		return
	var side: float = 1.0 if _roll_rng.randf() < 0.5 else -1.0
	out.move_x = int(side * 950.0)
	out.move_y = -300
	out.buttons |= FighterInput.ROLL
	_roll_cd = ROLL_COOLDOWN_TICKS


# ---------------------------------------------------------------- state selection

## Stalemate clock: reset by decisive damage on either side (blood, consciousness, core hp), read as `_desperation()`.
func _track_stale(me: Dictionary, foe: Dictionary) -> void:
	var cur: Dictionary = {}
	var decisive: bool = false
	var i: int = 0
	for f: Dictionary in [me, foe]:
		var blood: float = float(f.get("blood_frac", 1.0))
		var consc: float = float(f.get("consciousness", 1.0))
		var core: float = 0.0
		var parts: Dictionary = f.get("parts", {})
		for n: String in ["head", "torso", "pelvis"]:
			if parts.has(n) and parts[n] is Dictionary:
				core += float((parts[n] as Dictionary).get("hp", 0.0))
		cur[i] = [blood, consc, core]
		if _stale_prev.has(i):
			var pv: Array = _stale_prev[i]
			if blood < float(pv[0]) - 0.002 or consc < float(pv[1]) - STALE_CONSC_DROP or core < float(pv[2]) - STALE_HP_DROP:
				decisive = true
		i += 1
	_stale_prev = cur
	_stale_ticks = 0 if decisive else _stale_ticks + 1


## 0 while fights produce decisive damage, ramping to 1 once nothing decisive has happened for a while.
func _desperation() -> float:
	return clampf(float(_stale_ticks - STALE_START) / float(STALE_RAMP), 0.0, 1.0)

func _update_state(me: Dictionary, obs: Dictionary) -> void:
	var stamina: float = float(me.get("stamina", 1.0))
	var rs: float = maxf(_pf("retreat_stamina"), STAMINA_FLOOR)
	_low_ticks = _low_ticks + 1 if (_tired and stamina < STAMINA_FLOOR * 0.7) else 0
	if _low_ticks > REST_FAIL_TICKS:  # resting does not refill the bar (seeds 5007, 9008, 9019): fight on exhausted
		_low_ticks = 0
		_no_rest_until = _tick + REST_FAIL_TICKS * 3
	var stamina_low: bool = stamina < rs and _tick >= _no_rest_until
	if stamina_low or float(me.get("blood_frac", 1.0)) < _pf("retreat_blood"):
		_tired = true
	elif _tick < _no_rest_until:
		_tired = float(me.get("blood_frac", 1.0)) < _pf("retreat_blood")
	elif stamina > rs + 0.3 and float(me.get("blood_frac", 1.0)) >= _pf("retreat_blood") + 0.05:
		_tired = false
	var finishing: bool = _want_finish(obs)
	var busy: bool = _state == ST_STRIKE or _state == ST_GUARD

	# Disarmed with a weapon to pick up: go for it rather than guard with bare fists (round 3: disarmed bots stood
	# in a fist guard next to their sword until the match ended). Only a strike already under way finishes first.
	if _state != ST_STRIKE and _disarmed(me) and _tick >= _weapon_giveup and _arm_can_hold(me) and not _props(me, obs).is_empty():
		if _state != ST_WEAPON:
			_enter(ST_WEAPON, 0)
			_grab_ticks = 0
		_thr_prev = _threat(me, obs)
		return
	var thr: bool = _threat(me, obs)
	if thr and not _thr_prev:
		_reflex_ok = _rng.randf() <= clampf(1.0 - _pf("risk") * 0.7, 0.2, 1.0) * (1.0 - 0.7 * _desperation())
		if float(_d["guard_miss"]) > 0.0 and _drng.randf() < float(_d["guard_miss"]):
			_reflex_ok = false
		elif float(_d["guard_boost"]) > 0.0 and not _reflex_ok and _drng.randf() < float(_d["guard_boost"]):
			_reflex_ok = true
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
	if _state == ST_WEAPON:
		_enter(ST_APPROACH, 0)
	# Round 2 trace: seeds 5007 and 9019 sat at stamina 0.00 for 40 s after pressing on below STAMINA_FLOOR.
	var press: bool = (finishing or _desperation() > 0.5) and ((_pf("risk") > 0.5 and stamina > STAMINA_FLOOR + 0.03) or (stamina > STAMINA_FLOOR + 0.08 and float(me.get("blood_frac", 1.0)) > 0.3))
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
	var p_rip: float = clampf(_pf("patience") * 0.6 + _pf("aggression") * 0.2 + float(_d["riposte"]), 0.0, 1.0)
	if _want_finish(obs):
		p_rip = maxf(p_rip, 0.9)  # the foe is beaten: answer his last swing with the killing blow
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


## Difficulty: whether the brain notices a beaten foe / an opening, re-rolled every so often (never when always).
func _notice_rolls() -> void:
	_finish_t -= 1
	if _finish_t <= 0:
		_finish_t = 90
		_finish_ok = float(_d["finish_seek"]) >= 1.0 or _drng.randf() < float(_d["finish_seek"])
	_opp_t -= 1
	if _opp_t <= 0:
		_opp_t = 30
		_opp_ok = float(_d["opp_seek"]) >= 1.0 or _drng.randf() < float(_d["opp_seek"])


func _want_finish(obs: Dictionary) -> bool:
	return _finish_ok and _beaten(obs)


func _beaten(obs: Dictionary) -> bool:
	var st: String = str(obs.get("state", "standing"))
	if st == "down" or st == "ko" or st == "getting_up":
		return true
	if float(obs.get("consciousness", 1.0)) < Tuning.shared().finisher_consc:
		return true  # dazed: a killing blow lands at any blood level
	return _foe_blood(obs) < Tuning.shared().finisher_blood_frac


func _foe_blood(obs: Dictionary) -> float:
	if obs.has("blood_frac"):
		return float(obs["blood_frac"])
	if obs.has("blood"):
		return clampf((float(obs["blood"]) - 2.5) / 2.5, 0.0, 1.0)
	return 1.0


## True when the foe's tip is fast, close to me and not moving away.
func _threat(me: Dictionary, obs: Dictionary) -> bool:
	if float(obs.get("tip_speed", 0.0)) < float(_d["threat_speed"]):
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
	if not _opp_ok or float(obs.get("tip_speed", 0.0)) > 2.0:
		return false
	var j: int = 0
	while j <= 45 and j < _ring_n - _delay:
		if float(_lagged(_delay + j).get("tip_speed", 0.0)) > 4.0:
			return true
		j += 3
	return false


func _disarmed(me: Dictionary) -> bool:
	return str(me.get("weapon_id", "fists")) == "fists" and _main_weapon != "fists" and _main_weapon != ""


## False when the weapon arm is so hurt that the fighter drops whatever it picks up (it would re-grab and re-drop forever).
func _arm_can_hold(me: Dictionary) -> bool:
	var parts: Dictionary = me.get("parts", {})
	var worst: float = 1.0
	for n: String in ["forearm_r", "upper_arm_r"]:
		var pd: Dictionary = parts.get(n, {}) if parts.get(n, {}) is Dictionary else {}
		var hp0: float = float(CombatData.part_info(n).get("hp", 0.0))
		if hp0 > 0.0 and pd.has("hp"):
			worst = minf(worst, float(pd["hp"]) / hp0)
		if bool(pd.get("severed", false)):
			return false
	return worst >= Tuning.shared().weapon_drop_hp * 1.5


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

## True for a fist fighter facing a foe whose weapon outreaches fists by a wide margin.
func _brawler_rush(me: Dictionary, obs: Dictionary) -> bool:
	var mine: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	if str(mine.get("shape", "fist")) != "fist":
		return false
	var foe_len: float = float(CombatData.weapon(str(obs.get("weapon_id", "fists"))).get("length", 0.3))
	return foe_len > float(mine.get("length", 0.3)) * BRAWLER_LEN_RATIO


func _do_approach(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var finishing: bool = _state == ST_FINISH
	var hold: float = _reach * _pf("range_frac")
	_idle_ticks += 1
	var committed: bool = _idle_ticks > int(_pf("commit_ticks")) or _desperation() > 0.0 or _burst_t > 0
	if _brawler_rush(me, obs):
		committed = true  # bare fists against a longer weapon: waiting outside its reach only gets cut, so close in
	if committed:
		hold = minf(hold, _reach * 0.85)  # waited long enough: step into striking range
	if finishing:
		hold = _reach * 0.85
	var stamina: float = float(me.get("stamina", 1.0))
	if _spear and _dist < SPEAR_READY_DIST:
		_spear_ready(me, _spear_target(obs), out)
	else:
		_neutral_aim(out)
	_shield_up(me, out)
	if not finishing:
		if _phase == 0 and _phase_t <= 0 and _desperation() < REPOS_DESPERATE:
			_begin_repos(-1, 0)
		elif _phase == 1 and (_phase_t <= 0 or _desperation() >= REPOS_DESPERATE):
			_end_repos()
		if _phase == 1:
			if _opportunity(obs) and _dist <= _reach * 1.4:  # the foe just whiffed: dart in
				_end_repos()
			else:
				_do_reposition(me, obs, out)
				return
	else:
		_phase = 0
		_phase_t = maxi(_phase_t, 60)
	_range_t -= 1
	if _range_t <= 0:  # range work: drift the standing distance in and out
		_range_t = _rng.randi_range(50, 140)
		_range_off = _rng.randf_range(-0.1, 1.0) * _reach * (1.0 - _pf("aggression") * 0.5)
	if not finishing:
		hold += _range_off
	if _spear:
		hold = clampf(hold, SPEAR_HOLD_MIN, SPEAR_HOLD_MAX)
	if _dist > hold + 0.25:
		if not _pin_target(hold, out):
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
			_circle_dir = _pick_side()
		_steer(_tangent() * 0.7 + _dir * clampf((_dist - hold) * 1.5, -0.6, 0.6) + _venue_lean() * 0.9, 0.7, out)
		_wait = maxi(_wait - 1, 0)
	if finishing or committed:
		_wait = 0
	if _wait > 0:
		return
	if _spear and _dist < SPEAR_MIN_RANGE and not finishing:
		out.move_y = -SPEAR_BACKSTEP  # inside the point: give ground until there is room to thrust
		return
	var opp: bool = _opportunity(obs)
	var p: float = lerpf(0.3, 1.0, _pf("aggression")) + (float(_d["punish"]) if opp else 0.0)
	if not opp and not finishing:
		p *= lerpf(1.0, 0.25, _pf("patience"))
	if committed:
		p = maxf(p, 0.5)
	p *= float(_d["p_scale"])
	var in_reach: bool = _dist <= _reach * 1.05
	var lunge: bool = _dist <= _reach * (1.3 if finishing else 1.9) and (_pf("aggression") > 0.5 or opp or finishing or committed)
	if _spear:  # the point lands only from a run-up: start a thrust from the stance band, never from close in
		in_reach = _dist <= SPEAR_STRIKE_MAX and _dist >= SPEAR_THRUST_MIN
		lunge = false
	if _rng.randf() <= p and (in_reach or lunge):
		_plan = _make_plan(me, obs, finishing)
		if not finishing and _rng.randf() < _pf("feint") and not _spear:  # a pole feint only drags the point off line
			_enter(ST_FEINT, 12 + _rng.randi_range(0, 6))
		else:
			_enter(ST_WINDUP, _windup_len(me))
	else:
		_wait = _rng.randi_range(8, 24)


## Start a footwork phase. style < 0 picks one at random; ticks <= 0 draws the length from the personality.
func _begin_repos(style: int, ticks: int) -> void:
	_phase = 1
	_phase_t = ticks if ticks > 0 else _span("repos")
	if style >= 0:
		_repos_style = style
	else:
		var wg: float = _pf("repos_goal")
		var r: float = _rng.randf()
		_repos_style = REPOS_GOAL if r < wg else (REPOS_BACK if r < wg + 0.25 else REPOS_ORBIT)
	var rr: Array = _p.get("orbit_r", [2.0, 3.5])
	_orbit_r = _rng.randf_range(float(rr[0]), float(rr[1]))
	_circle_dir = _pick_side()
	_flip_t = _rng.randi_range(90, 220)
	if _repos_style == REPOS_GOAL:
		_pick_goal()


func _end_repos() -> void:
	_phase = 0
	_phase_t = _span("engage")
	_wait = 0
	_burst_t = BURST_TICKS


## The least-visited of a few random spots, so fights range over the whole sand; never on top of the foe.
func _pick_goal() -> void:
	_repos_goal = _pick_spot()
	_venue = _repos_goal


func _pick_spot() -> Vector3:
	var spot: Vector3 = Vector3.ZERO
	var best: float = 1.0e9
	for k: int in 5:
		var a: float = _rng.randf() * TAU
		var rad: float = _rng.randf_range(1.0, GOAL_RADIUS_MAX)
		var g := Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var score: float = float(_seen.get(Vector2i(floori(g.x), floori(g.z)), 0)) + _rng.randf() * 30.0
		if Vector2(g.x - _mp.x, g.z - _mp.z).length() < 3.0 or Vector2(g.x - _fp.x, g.z - _fp.z).length() < _reach * 1.5:
			score += 100000.0
		if score < best:
			best = score
			spot = g
	return spot


## Unit vector toward the venue (zero when already there), for leaning footwork toward it.
func _venue_lean() -> Vector3:
	var v: Vector3 = _venue - _mp
	v.y = 0.0
	return v.normalized() * (float(_d["footwork"]) * 2.0) if v.length() > 1.5 else Vector3.ZERO


func _span(key: String) -> int:
	var a: Array = _p.get(key, [200, 400])
	return _rng.randi_range(int(a[0]), int(a[1]))


## Circling direction (+1 / -1) toward the side that takes me off the wall; random when roomy.
func _pick_side() -> int:
	var r: float = Vector2(_mp.x, _mp.z).length()
	if r > PIN_RADIUS:
		var sgn: int = _circle_dir
		_circle_dir = 1
		var t: Vector3 = _tangent()
		_circle_dir = sgn
		var out_rate: float = (_mp.x * t.x + _mp.z * t.z) / r  # radius change per unit step along +tangent
		if absf(out_rate) > 0.2:
			return -1 if out_rate > 0.0 else 1
	return 1 if _rng.randf() < 0.5 else -1


## World direction at 90 degrees to the line to the foe, signed by the circling direction.
func _tangent() -> Vector3:
	return Vector3(-_dir.z, 0.0, _dir.x) * float(_circle_dir)


## Walk along `wdir` (world, need not be unit) at `speed`, bending toward the arena centre near the wall.
func _steer(wdir: Vector3, speed: float, out: FighterInput) -> void:
	var v: Vector3 = wdir
	v.y = 0.0
	var r: float = Vector2(_mp.x, _mp.z).length()
	if r > WALL_SOFT:
		var w: float = clampf((r - WALL_SOFT) / 3.0, 0.0, 1.0)
		var c: Vector3 = Vector3(-_mp.x, 0.0, -_mp.z) / r
		v = v.normalized() * (1.0 - w * 0.5) + c * w * 1.4
	if v.length() < 0.001:
		return
	_move_world(v.normalized(), speed, out)


## Chasing a foe who stands near the wall from inside: head for the point on the centre side of him, so he is pinned.
func _pin_target(hold: float, out: FighterInput) -> bool:
	var fr: float = Vector2(_fp.x, _fp.z).length()
	var mr: float = Vector2(_mp.x, _mp.z).length()
	if float(_d["footwork"]) < 0.5 or fr < PIN_RADIUS or mr > fr - 1.0 or _dist < hold + 1.0:
		return false
	var inward: Vector3 = Vector3(-_fp.x, 0.0, -_fp.z) / fr
	var goal: Vector3 = _fp + inward * hold
	var go: Vector3 = goal - _mp
	go.y = 0.0
	if go.length() < 0.3:
		return false
	_move_world(go.normalized(), 1.0, out)
	return true


func _do_reposition(me: Dictionary, _obs: Dictionary, out: FighterInput) -> void:
	_flip_t -= 1
	if _flip_t <= 0:
		_flip_t = _rng.randi_range(90, 220)
		_circle_dir = _pick_side()
	var stamina: float = float(me.get("stamina", 1.0))
	match _repos_style:
		REPOS_GOAL:
			var go: Vector3 = _repos_goal - _mp
			go.y = 0.0
			var gl: float = go.length()
			if gl < 0.8:
				_phase_t = mini(_phase_t, 20)  # arrived: the next burst starts here
			else:
				_steer(go / gl, 1.0 if gl > 2.0 else 0.5, out)
				if gl > 5.0 and stamina > 0.6 and _dist > _reach * 2.0 and _reach < LONG_REACH:
					out.buttons |= FighterInput.SPRINT
		REPOS_BACK:
			if _dist < _orbit_r + 1.0:
				_steer(-_dir + _tangent() * 0.3, 0.9, out)
			else:
				_steer(_tangent(), 0.35, out)
		_:
			var e: float = _dist - _orbit_r
			_steer(_tangent() + _dir * clampf(e * 0.8, -0.8, 0.8), 0.8, out)


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
	if _dist > (SPEAR_STRIKE_MAX + 1.0 if _spear else _reach * 2.2):
		_enter(ST_APPROACH, 0)
		return
	if _spear and _plan.get("kind", "") == "thrust":
		# Pole stance: no wind-up swing at all. Keep the point on the chest and let the thrust go the moment the
		# blade's line runs through it (or after SPEAR_WINDUP ticks, before the foe walks past the point).
		var tgt: Vector3 = _spear_target(obs)
		_spear_ready(me, tgt, out)
		_spear_footwork(out)
		if _dist < SPEAR_MIN_RANGE:
			_enter(ST_APPROACH, 0)  # the foe walked inside the point: make room first
		elif (_st_ticks >= 1 and _spear_aligned(me, tgt)) or _st_ticks + 1 >= _st_len:
			_enter(ST_STRIKE, _strike_len(me))
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
	var pole: bool = _spear and _plan["kind"] == "thrust"
	if pole:
		_spear_ready(me, _spear_target(obs), out)  # keep steering the point onto the target while it drives in
		if _dist > SPEAR_LUNGE_MIN:
			# The arms are at full reach in the pole stance (THRUST adds next to nothing), and a contact under
			# damage_min_speed does nothing: the run-up carries the point, sprinting while there is breath.
			out.move_y = 1000
			if float(me.get("stamina", 1.0)) > 0.2:
				out.buttons |= FighterInput.SPRINT
	else:
		var t: Vector2 = _plan_target(me, obs)
		var wind: Vector2 = _windup_aim(t)
		var u: float = clampf(float(_st_ticks + 1) / maxf(float(_st_len), 1.0), 0.0, 1.0)
		var end: Vector2 = t if _plan["kind"] == "thrust" else _clamp_aim(t + (_plan["dir"] as Vector2) * WINDUP_AMP)
		_set_aim(out, wind.lerp(end, u * u))
		_advance(out)
	out.buttons |= FighterInput.SWING
	if _plan["kind"] == "thrust":
		out.buttons |= FighterInput.THRUST
	if bool(_plan.get("half", false)) and not pole:
		out.buttons |= FighterInput.HALF_SWORD
	if _st_ticks + 1 >= _st_len:
		var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
		var rec: float = (14.0 + float(def.get("mass", 1.0)) * 8.0) * (1.3 - _pf("aggression") * 0.6)
		_enter(ST_RECOVER, clampi(roundi(rec * float(_d["recover_scale"])), 8, 65))


func _do_recover(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	if _spear and _dist < SPEAR_READY_DIST:
		_spear_ready(me, _spear_target(obs), out)  # draw back (THRUST released) with the point kept in line
	else:
		_neutral_aim(out, SLEW_RECOVER)
	_shield_up(me, out)
	if _spear and not _want_finish(obs):
		_spear_footwork(out)
	elif _want_finish(obs):
		out.move_y = roundi(-300.0 * (1.0 - _pf("aggression")))
	else:
		_steer(-_dir * (1.0 - _pf("aggression")) + _tangent() * 0.5 + _venue_lean() * 0.6, 0.35 + 0.35 * (1.0 - _pf("aggression")), out)
	if _st_ticks + 1 >= _st_len:
		var finishing: bool = _want_finish(obs)
		var stamina: float = float(me.get("stamina", 1.0))
		var room: bool = not _spear or (_dist >= SPEAR_THRUST_MIN and _dist <= SPEAR_STRIKE_MAX)
		if not _tired and room and _dist <= _reach * 1.1 and _rng.randf() <= maxf(_pf("aggression") * 0.6 * minf(stamina * 1.5, 1.0), 0.8 if finishing else 0.0):
			_plan = _make_plan(me, obs, finishing)
			_enter(ST_WINDUP, roundi(float(_windup_len(me)) * 0.7))
		else:
			_enter(ST_APPROACH, 0)
			_wait = _new_wait()
			if not finishing and _phase == 0 and _desperation() < REPOS_DESPERATE and _rng.randf() < _pf("disengage"):
				_begin_repos(-1, 0)


func _do_guard(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	var tip: Vector3 = obs.get("tip_pos", Vector3.ZERO)
	var a: Vector2 = _clamp_aim(Vector2((tip - _origin).dot(_right) / GUARD_W * 0.7, (tip.y - _origin.y) / GUARD_H * 0.7))
	if _reach > LONG_REACH:
		a *= LONG_GUARD_SCALE  # a spear parried far off centre swings its butt and shaft through the own body
	_set_aim(out, _last_aim.move_toward(a, SLEW_GUARD * float(_d["guard_slew"])))
	out.buttons |= FighterInput.SWING | FighterInput.OFFHAND
	# Guard on the move: slip back and to the side rather than standing in the foe's swing. A long weapon swung round
	# by footwork hits the own body (spear self hits), so it only gives ground.
	if _dist < _reach * 1.4:
		if _reach > LONG_REACH:
			out.move_y = -SPEAR_BACKSTEP if _spear and _dist < SPEAR_MIN_RANGE else -250
		else:
			_steer(-_dir * (0.2 + 0.3 * (1.0 - _pf("risk"))) + _tangent() * 0.7 + _venue_lean() * 0.4, 0.55, out)
	elif not _spear and str(CombatData.weapon(str(obs.get("weapon_id", "fists"))).get("shape", "")) == "spear":
		# Out of my own reach behind a levelled spear point: standing in guard only waits for the next thrust.
		# Close in on a slant, past the point, as a spearman's foe must.
		_steer(_dir * 0.6 + _tangent() * 0.8, 0.8, out)


func _do_retreat(me: Dictionary, obs: Dictionary, out: FighterInput) -> void:
	_set_aim(out, _last_aim.move_toward(Vector2(0.0, 0.2), SLEW_NEUTRAL * float(_d["hand_return"])))
	_shield_up(me, out)
	# Breaking off to recover: keep well out of reach, circling slowly rather than backing into the wall.
	var keep: float = _reach * 2.2 + 1.0 - _pf("risk") + (1.0 if _pf("range_frac") > 1.0 else 0.0)
	_flip_t -= 1
	if _flip_t <= 0:
		_flip_t = _rng.randi_range(80, 200)
		_circle_dir = _pick_side()
	if _dist < keep:
		_steer(-_dir + _tangent() * 0.6, 0.9 if _dist < keep - 1.0 else 0.6, out)
	elif _dist < keep + 1.5:
		_steer(_tangent(), 0.3, out)


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
	if best.y >= GROUND_PROP_Y:
		# A prop in the air or in a hand-high rack: steer the hand at it and walk over.
		_set_aim(out, _clamp_aim(_aim_for(best)))
		if near > 0.35:
			_move_world(to / maxf(near, 0.001), 1.0 if near > 1.0 else 0.4, out)
			if near > 4.0 and float(me.get("stamina", 1.0)) > 0.4:
				out.buttons |= FighterInput.SPRINT
		if near < 1.2 and _grab_ticks % 12 < 6:  # the fighter grabs on a rising edge: pulse the button
			out.buttons |= FighterInput.GRAB
		return
	# A prop on the ground: the hand only reaches y~0.5 at full downward aim and a crouch, GRAB_REACH ahead of the
	# torso, so walk to the spot GRAB_REACH behind the prop (the body faces the foe, not the prop), crouch, reach down.
	var tp: Vector3 = _part_pos(me, "torso", mp)
	var stand: Vector3 = best - _fwd * GRAB_REACH
	var go: Vector3 = stand - tp
	go.y = 0.0
	var gl: float = go.length()
	var hand: Vector3 = me.get("hand_pos", Vector3(0.0, 1.0, 0.0))
	var hand_d: float = hand.distance_to(best)
	if gl > 0.1:
		_move_world(go / gl, 1.0 if gl > 1.0 else clampf(gl * 2.0, 0.25, 0.6), out)
		if gl > 4.0 and float(me.get("stamina", 1.0)) > 0.4:
			out.buttons |= FighterInput.SPRINT
	if gl < 1.0:
		out.buttons |= FighterInput.CROUCH
		var c := Vector2(0.0, -1.0)  # straight down: skips _set_aim's low limit on purpose (the hand holds no weapon)
		_last_aim = c
		out.aim_x = 0
		out.aim_y = -1000
	else:
		_set_aim(out, _last_aim.move_toward(Vector2(0.0, -0.5), 0.1))
	if gl < 0.6 or hand_d < GRAB_REACH:
		if _grab_ticks % 12 < 6:
			out.buttons |= FighterInput.GRAB


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
	if float(_d["aim_err"]) > 0.0:
		noise += Vector2(_drng.randf_range(-1.0, 1.0), _drng.randf_range(-1.0, 1.0)) * float(_d["aim_err"])
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
				opts["behead"] = head_open * BEHEAD_BIAS
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
		part = _pick_part(obs, armor, kind, blunt, shape == "fist")
		if kind != "thrust" and kind != "low" and _rng.randf() < _pf("disarm_aim") * DISARM_SCALE:
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
			if shape == "spear":
				dir = Vector2.ZERO  # a pole thrust is drawn back along its own line, never swept across the foe
	return {"kind": kind, "part": part, "dir": dir, "noise": noise, "half": half, "neck": neck, "finishing": finishing}


func _kind_weights(def: Dictionary) -> Dictionary:
	var w: Dictionary = {}
	match str(def.get("shape", "fist")):
		"spear":
			w = {"thrust": 1.0}  # a sweep of the shaft only touches (blunt 0.1); the point is the weapon
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


func _pick_part(obs: Dictionary, armor: Dictionary, kind: String, blunt: bool, fist: bool = false) -> String:
	var parts: Dictionary = obs.get("parts", {})
	var w: Dictionary = {}
	var skill: float = float(_d["target_skill"])
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
				wt *= 1.6 if n == "torso" else ((0.0 if _spear else 0.3) if leg else (0.4 if arm else 1.0))
		if n == "head" or n == "torso" or n == "pelvis":
			wt *= float(_d["core_bias"])
		if leg:
			wt *= 1.0 + _pf("cripple") * 2.5
		if blunt and n == "head":
			wt *= BLUNT_HEAD_BIAS * (FIST_HEAD_BIAS if fist else 1.0)
		var sc: float = _armor_score(armor, n, blunt)
		var armor_w: float = 1.3 if sc <= 0.0 else (1.0 - 0.85 * sc)
		wt *= armor_w if skill == 1.0 else pow(armor_w, skill)
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
	_mp = mp
	_fp = fp
	var cell := Vector2i(floori(mp.x), floori(mp.z))
	_seen[cell] = int(_seen.get(cell, 0)) + 1
	_dist = d.length()
	_dir = d / _dist if _dist > 0.001 else _fwd
	_origin = _part_pos(me, "torso", mp + Vector3(0.0, 0.5, 0.0)) + Vector3(0.0, 0.05, 0.0)
	var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	_reach = 0.9 + float(def.get("length", 0.3)) * 0.9
	_spear = str(def.get("shape", "")) == "spear"
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
		p.y += NECK_LIFT
	var wob: float = sin(float(_tick) * 0.07) * 0.05 * _pf("aim_noise")
	return _clamp_aim(_aim_for(p) + (_plan.get("noise", Vector2.ZERO) as Vector2) + Vector2(wob, 0.0))


## The point a spear aims at: always the chest (the servo needs a good third of a second to move the point, too slow
## to switch targets within a thrust), offset by the plan's aim noise while a thrust is under way.
func _spear_target(obs: Dictionary) -> Vector3:
	var fallback: Vector3 = (obs.get("pelvis_pos", Vector3.ZERO) as Vector3) + Vector3(0.0, 0.35, 0.0)
	var p: Vector3 = _part_pos(obs, "torso", fallback)
	if _state == ST_WINDUP or _state == ST_STRIKE:
		var n: Vector2 = _plan.get("noise", Vector2.ZERO)
		p += (_right * n.x + Vector3.UP * n.y) * SPEAR_NOISE_M
	return p


## Perpendicular miss (right, up) of `target` from the blade line running from `hand` through `tip`.
static func pole_miss(hand: Vector3, tip: Vector3, target: Vector3, right: Vector3) -> Vector2:
	var axis: Vector3 = tip - hand
	if axis.length() < 0.05:
		return Vector2.ZERO
	axis = axis.normalized()
	var rel: Vector3 = target - hand
	var off: Vector3 = rel - axis * rel.dot(axis)
	return Vector2(off.dot(right), off.y)


## Pole servo: a long blade turns a small hand offset into a large one at the foe and its rest angle depends on the
## hand height, so no open-loop aim map lands the point. Close the loop on the real blade instead: nudge the aim
## each tick by a share of the blade line's miss at the target.
func _pole_servo(me: Dictionary, target: Vector3) -> Vector2:
	if not me.has("tip_pos") or not me.has("hand_pos"):
		return _clamp_aim(_aim_for(target))
	var miss: Vector2 = pole_miss(me["hand_pos"], me["tip_pos"], target, _right)
	var step := Vector2(miss.x / (GUARD_W * TIP_GAIN_X), miss.y / (GUARD_H * TIP_GAIN_Y)) * SPEAR_SERVO_GAIN
	return _clamp_aim(_last_aim + step.limit_length(SPEAR_AIM_SLEW))


## True when the spear points ahead and its blade line passes within SPEAR_ALIGN_TOL of `target`.
func _spear_aligned(me: Dictionary, target: Vector3) -> bool:
	if not me.has("tip_pos") or not me.has("hand_pos"):
		return true
	var hand: Vector3 = me["hand_pos"]
	var tip: Vector3 = me["tip_pos"]
	if (tip - hand).normalized().dot(_dir) < 0.85:
		return false
	return pole_miss(hand, tip, target, _right).length() <= SPEAR_ALIGN_TOL


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
	if float(_d["aim_slew"]) < 5.0:  # a slower hand (easy): it cannot jump or whip across the aim plane
		c = _last_aim.move_toward(c, float(_d["aim_slew"]))
	c.x = maxf(c.x, AIM_LEFT_LIMIT)
	c.y = maxf(c.y, heavy_low_limit(c.x, _heavy_short))
	# a hand driven to the lowest aim drags the blade through the own thigh and pelvis  # the weapon hand stays off the offhand arm/shield side of the body
	_last_aim = c
	out.aim_x = roundi(c.x * 1000.0)
	out.aim_y = roundi(c.y * 1000.0)


## Lowest aim y allowed at aim x. Axes and clubs aimed low on the weapon side swing the head through the own shin
## (seed 7000: aim 750, -450); aimed low in front, at the foe's legs, they keep the normal floor.
static func heavy_low_limit(x: float, heavy_short: bool) -> float:
	if not heavy_short:
		return AIM_LOW_LIMIT
	var u: float = smoothstep(HEAVY_LOW_X0, HEAVY_LOW_X1, x)
	return lerpf(AIM_LOW_LIMIT, HEAVY_LOW_LIMIT, u)


func _neutral_aim(out: FighterInput, step: float = SLEW_NEUTRAL) -> void:
	var s: float = sin(float(_tick) * 0.05) * 0.08 * _pf("aim_noise")
	_set_aim(out, _last_aim.move_toward(Vector2(s, 0.15), step * float(_d["hand_return"])))


func _shield_up(me: Dictionary, out: FighterInput) -> void:
	if str(me.get("offhand_id", "")).contains("shield") and _dist < _reach + 1.5:
		out.buttons |= FighterInput.OFFHAND


## Pole stance: blade levelled (SWING; the wrist needs a good half second to bring it down from the guard's upward
## slant, far longer than a thrust takes) and its point kept on `target`, so a thrust only has to drive in.
func _spear_ready(me: Dictionary, target: Vector3, out: FighterInput) -> void:
	_set_aim(out, _pole_servo(me, target))
	out.buttons |= FighterInput.SWING


## Range work while the point is up: give ground when the foe is inside the point, otherwise stand.
func _spear_footwork(out: FighterInput) -> void:
	if _dist < SPEAR_MIN_RANGE:
		out.move_y = -SPEAR_BACKSTEP
	elif _dist < SPEAR_HOLD_MIN:
		out.move_y = -SPEAR_BACKSTEP / 2


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
	if _spear:
		return SPEAR_WINDUP
	return clampi(roundi((8.0 + m * 7.0) * (1.15 - _pf("aggression") * 0.5)), 8, 36)


func _strike_len(me: Dictionary) -> int:
	var def: Dictionary = CombatData.weapon(str(me.get("weapon_id", "fists")))
	var m: float = float(def.get("mass", 1.0))
	var fast: float = FINISH_STRIKE_SCALE if bool(_plan.get("finishing", false)) else 1.0  # a killing blow wants speed
	if _spear and _plan.get("kind", "") == "thrust":
		return SPEAR_STRIKE_TICKS
	if _plan.get("kind", "") == "thrust":
		return clampi(roundi((8.0 + m * 2.0) * fast * float(_d["swing_scale"])), 6, 26)
	return clampi(roundi((12.0 + m * 5.0) * fast * float(_d["swing_scale"])), 9, 48)


func _new_wait() -> int:
	var base: float = _rng.randf_range(20.0, 70.0)
	return roundi(base * (0.4 + _pf("patience") * 1.4) * (1.35 - _pf("aggression") * 0.9) * float(_d["wait_scale"]))


func _lagged(k: int) -> Dictionary:
	var avail: int = mini(_ring_n, RING)
	var kk: int = clampi(k, 0, maxi(avail - 1, 0))
	return _ring[posmod(_ring_n - 1 - kk, RING)]


func _pf(key: String) -> float:
	return float(_p.get(key, 0.5))
