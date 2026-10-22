class_name MatchStats
extends RefCounted
## Pure per-match numbers. Fed from the fighters' hit and gore events and from both debug_frames every tick; the
## Match owns one and puts `to_dict()` into its result. No Nodes, no wall clock (the Match sets `wall_time_s`).
##
## Definitions: a "hit" is a resolved weapon contact on a body (weapon-on-weapon contacts count as `parries`).
## A "blow" is what the player sees as one strike: hits by one fighter on the other, where contacts closer than
## `combo_merge_s` to that fighter's last counted blow (one swing touching several parts) count once. A combo is a run
## of blows by one fighter with no blow landed back, each within `combo_gap_s` of the previous one. `blows_by_side`
## and `longest_combo` are the results screen's "Hits landed" and "Longest combo" (the Match sets both windows from
## Tuning); `hits_by_side` stays the raw contact count.
## "Swinging" is a tip speed of SWING_SPEED or more. "Stuck" is both fighters' pelvis speed under STUCK_SPEED and
## both tips slower than STUCK_TIP; `stuck_s` is the time spent stuck beyond STUCK_GRACE_S, summed over the match.
## An "explosion" is a tick where any body part moves faster than EXPLODE_SPEED, is NaN/inf, or falls below FALL_Y.
## Weapons: `disarms` are weapons knocked out of a hand by a hit (hit events with "disarmed"); `arm_drops` are
## weapons let go because the holding arm got too hurt or was cut off, and `rearms` are weapons picked up, both from
## the fighters' cumulative "weapon_log" in debug_frame (`rearms_after_disarm`: pickups that replaced a weapon
## knocked out of hand). `stamina0_max_s` is the longest run any fighter spent at
## zero stamina; `getup_fails` counts get-ups that fell back down.
## Arena movement (horizontal pelvis x/z, from the two debug_frames in side order): `dist_sum` is the summed distance
## between the fighters over `_dist_ticks` ticks (`mean_dist()`); a "strike tick" is one where the fighters are within
## STRIKE_MARGIN times the longer reach of the two weapons (`strike_share()`); `travel` is each side's summed pelvis
## step length in metres; `cells` is the set of Vector2i(floori(x), floori(z)) cells either pelvis stood in.
## Fight clock: every duration and movement number (`ticks`, `time_down_s`, `stuck_s`, `stamina0_max_s`, distance,
## strike ticks, `travel`, `cells`) only counts frames fed with `clock_on` true, so the pre-fight intro (fighters held
## at their spawns, the Match's fight clock not yet running) never pads them; `ticks` is then the fight-clock tick
## count. Held frames still update the per-side history (states, rolls, logs, last positions), so the release frame
## counts no false knockdown, roll or travel jump; explosions count on every frame. Hit times passed to `on_hit` are fight-clock seconds too.

const SWING_SPEED: float = 2.5
const STUCK_SPEED: float = 0.2
const STUCK_TIP: float = 1.5
const STUCK_GRACE_S: float = 3.0
const EXPLODE_SPEED: float = 40.0
const FALL_Y: float = -3.0
const FINISHERS: PackedStringArray = ["run_through", "gut", "behead", "skull_crush", "pummel"]
const DOWN_STATES: PackedStringArray = ["down", "ko", "getting_up"]
const STAMINA_ZERO: float = 0.005
const REACH_BASE: float = 0.9
const REACH_PER_LENGTH: float = 0.9
const DEFAULT_LENGTH: float = 0.3
const STRIKE_MARGIN: float = 1.05

var ticks: int = 0
var hits: int = 0
var hits_by_side: Array = [0, 0]
var blows_by_side: Array = [0, 0]
var longest_combo: Array = [0, 0]
var combo_gap_s: float = 1.5
var combo_merge_s: float = 0.15
var contact_kinds: Dictionary = {"edge": 0, "point": 0, "flat": 0, "blunt": 0}
var parries: int = 0
var max_tip_speed: float = 0.0
var severs: int = 0
var finisher: String = ""
var disarms: int = 0
var stamina0_max_s: float = 0.0
var getup_fails: int = 0
var armor_dislodged: int = 0
var self_hits: int = 0
var knockdowns: int = 0
var rolls: int = 0  ## dodge rolls started (both fighters)
var _prev_rolling: Array[bool] = [false, false]
var time_down_s: float = 0.0
var stuck_s: float = 0.0
var explosions: int = 0
var wall_time_s: float = 0.0
var blood_left: Array = [5.0, 5.0]
var dist_sum: float = 0.0
var strike_ticks: int = 0
var travel: Array = [0.0, 0.0]
var cells: Dictionary = {}

var _dist_ticks: int = 0
var _prev_xz: Array = [null, null]
var _swing_sum: float = 0.0
var _swing_ticks: int = 0
var _stuck_run: float = 0.0
var _prev_pos: Dictionary = {}
var _prev_state: Array = ["", ""]
var _weapon_log: Array = [{}, {}]
var _close_log: Array = [{}, {}]  ## each fighter's latest debug_frame "close_log" (shoves, kicks, grabs)
var _stamina0_run: Array = [0.0, 0.0]
var _run_side: int = -1
var _run_len: int = 0
var _last_blow_t: float = -1.0e9


## A resolved hit event (Fighter.hit payload) at fight time `t_s` (seconds; only blows and combos use it).
func on_hit(ev: Dictionary, t_s: float = 0.0) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		if bool(ev.get("disarmed", false)):
			disarms += 1
		parries += 1
		return
	hits += 1
	var att: int = int(ev.get("attacker", 0))
	var tgt: int = int(ev.get("target", 1 - att))
	if att == 0 or att == 1:
		hits_by_side[att] = int(hits_by_side[att]) + 1
	if att == tgt:
		self_hits += 1
	elif att == 0 or att == 1:
		_on_blow(att, t_s)
	var kind: String = str(ev.get("contact", ""))
	if contact_kinds.has(kind):
		contact_kinds[kind] = int(contact_kinds[kind]) + 1
	if bool(ev.get("disarmed", false)):
		disarms += 1
	if bool(ev.get("dislodge", false)):
		armor_dislodged += 1
	var fin: String = str(ev.get("finisher", ""))
	if fin != "":
		finisher = fin


## One contact by `att` on the other fighter at `t_s`: a new blow unless it is the same swing as the last blow.
func _on_blow(att: int, t_s: float) -> void:
	var dt: float = t_s - _last_blow_t
	if att == _run_side and dt < combo_merge_s:
		return
	blows_by_side[att] = int(blows_by_side[att]) + 1
	if att == _run_side and dt <= combo_gap_s:
		_run_len += 1
	else:
		_run_side = att
		_run_len = 1
	_last_blow_t = t_s
	longest_combo[att] = maxi(int(longest_combo[att]), _run_len)


## A Fighter.gore payload.
func on_gore(ev: Dictionary) -> void:
	var kind: String = str(ev.get("kind", ""))
	if kind == "sever" or kind == "behead":
		severs += 1
	if finisher == "" and FINISHERS.has(kind) and kind != "gut":
		finisher = kind


## Both fighters' debug_frame() dictionaries (side order), once per physics tick. `clock_on` false (the intro, the
## fight clock held) keeps the history current but adds no time, distance or travel.
func on_frames(frames: Array, dt: float, clock_on: bool = true) -> void:
	if clock_on:
		ticks += 1
	else:
		_stuck_run = 0.0
		_stamina0_run = [0.0, 0.0]
	_on_arena(frames, clock_on)
	var still: bool = true
	for fr: Dictionary in frames:
		var side: int = int(fr.get("side", 0))
		var tip: float = float(fr.get("tip_speed", 0.0))
		if tip == tip:
			max_tip_speed = maxf(max_tip_speed, tip)
			if tip >= SWING_SPEED:
				_swing_sum += tip
				_swing_ticks += 1
		var state: String = str(fr.get("state", "standing"))
		if DOWN_STATES.has(state) and clock_on:
			time_down_s += dt
		if side >= 0 and side < 2:
			var prev: String = _prev_state[side]
			if state == "down" and prev != "" and prev != "down" and prev != "ko":
				knockdowns += 1
			if state == "down" and prev == "getting_up":
				getup_fails += 1
			_prev_state[side] = state
			var rl: bool = bool(fr.get("rolling", false))
			if rl and not _prev_rolling[side]:
				rolls += 1
			_prev_rolling[side] = rl
			var wl: Variant = fr.get("weapon_log", null)
			if wl is Dictionary:
				_weapon_log[side] = (wl as Dictionary).duplicate()
			var cl: Variant = fr.get("close_log", null)
			if cl is Dictionary:
				_close_log[side] = (cl as Dictionary).duplicate()
			var dead: bool = state == "dead"
			if float(fr.get("stamina", 1.0)) <= STAMINA_ZERO and not dead and clock_on:
				_stamina0_run[side] = float(_stamina0_run[side]) + dt
				stamina0_max_s = maxf(stamina0_max_s, float(_stamina0_run[side]))
			else:
				_stamina0_run[side] = 0.0
		var pv: Vector3 = fr.get("pelvis_vel", Vector3.ZERO)
		if not (pv.length() < STUCK_SPEED) or not (tip < STUCK_TIP):
			still = false
		if _check_explosion(fr, dt):
			explosions += 1
	if still and frames.size() >= 2 and clock_on:
		_stuck_run += dt
		if _stuck_run > STUCK_GRACE_S:
			stuck_s += dt
	else:
		_stuck_run = 0.0


## Distance, strike ticks, pelvis travel and visited cells from the two frames (side order). Skips a tick whose
## pelvis position is not finite, so one NaN never poisons the sums. With `clock_on` false only the last positions move.
func _on_arena(frames: Array, clock_on: bool = true) -> void:
	if frames.size() < 2:
		return
	var xz: Array = [Vector2.ZERO, Vector2.ZERO]
	var reach: Array = [0.0, 0.0]
	for i: int in 2:
		var fr: Dictionary = frames[i]
		var p: Vector3 = fr.get("pelvis_pos", Vector3.ZERO)
		if not (is_finite(p.x) and is_finite(p.z)):
			return
		xz[i] = Vector2(p.x, p.z)
		var w: Dictionary = CombatData.weapon(str(fr.get("weapon_id", "fists")))
		reach[i] = REACH_BASE + REACH_PER_LENGTH * float(w.get("length", DEFAULT_LENGTH))
	if not clock_on:
		_prev_xz = [xz[0], xz[1]]
		return
	var d: float = (xz[0] as Vector2).distance_to(xz[1] as Vector2)
	dist_sum += d
	_dist_ticks += 1
	if d <= STRIKE_MARGIN * maxf(float(reach[0]), float(reach[1])):
		strike_ticks += 1
	for i: int in 2:
		var p2: Vector2 = xz[i]
		if _prev_xz[i] != null:
			travel[i] = float(travel[i]) + p2.distance_to(_prev_xz[i] as Vector2)
		_prev_xz[i] = p2
		cells[Vector2i(floori(p2.x), floori(p2.y))] = true


func mean_dist() -> float:
	return dist_sum / float(_dist_ticks) if _dist_ticks > 0 else 0.0


func strike_share() -> float:
	return float(strike_ticks) / float(_dist_ticks) if _dist_ticks > 0 else 0.0


func _check_explosion(fr: Dictionary, dt: float) -> bool:
	var bad: bool = false
	var side: int = int(fr.get("side", 0))
	var parts: Dictionary = fr.get("parts", {})
	for n: Variant in parts:
		var p: Vector3 = (parts[n] as Dictionary).get("pos", Vector3.ZERO)
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)) or p.y < FALL_Y:
			bad = true
			continue
		var key: String = "%d/%s" % [side, n]
		if _prev_pos.has(key) and dt > 0.0:
			var spd: float = ((_prev_pos[key] as Vector3).distance_to(p)) / dt
			if not (spd <= EXPLODE_SPEED):
				bad = true
		_prev_pos[key] = p
	var pel: Vector3 = fr.get("pelvis_vel", Vector3.ZERO)
	if not (pel.length() <= EXPLODE_SPEED):
		bad = true
	return bad


## Sum over both sides of a counter from the fighters' latest "weapon_log".
func _log_sum(key: String) -> int:
	var n: int = 0
	for wl: Dictionary in _weapon_log:
		n += int(wl.get(key, 0))
	return n


## Sum over both sides of a counter from the fighters' latest "close_log".
func _close_sum(key: String) -> int:
	var n: int = 0
	for cl: Dictionary in _close_log:
		n += int(cl.get(key, 0))
	return n


func mean_tip_speed() -> float:
	return _swing_sum / float(_swing_ticks) if _swing_ticks > 0 else 0.0


func to_dict() -> Dictionary:
	return {
		"ticks": ticks, "hits": hits, "hits_by_side": hits_by_side.duplicate(),
		"blows_by_side": blows_by_side.duplicate(), "longest_combo": longest_combo.duplicate(),
		"contact_kinds": contact_kinds.duplicate(), "parries": parries,
		"max_tip_speed": max_tip_speed, "mean_tip_speed": mean_tip_speed(), "severs": severs, "finisher": finisher,
		"disarms": disarms, "arm_drops": _log_sum("arm_drops"), "rearms": _log_sum("rearms"),
		"rearms_after_disarm": _log_sum("rearms_after_disarm"),
		"stamina0_max_s": stamina0_max_s, "getup_fails": getup_fails, "armor_dislodged": armor_dislodged, "self_hits": self_hits, "knockdowns": knockdowns, "rolls": rolls,
		"shoves": _close_sum("shoves"), "shoves_landed": _close_sum("shoves_landed"), "kicks": _close_sum("kicks"),
		"kicks_landed": _close_sum("kicks_landed"), "grabs": _close_sum("grabs"), "holds": _close_sum("holds"),
		"hold_breaks": _close_sum("breaks"),
		"time_down_s": time_down_s, "stuck_s": stuck_s, "explosions": explosions, "wall_time_s": wall_time_s,
		"blood_left": blood_left.duplicate(),
		"mean_dist": mean_dist(), "strike_share": strike_share(),
		"travel0": float(travel[0]), "travel1": float(travel[1]), "cells": cells.size(),
	}
