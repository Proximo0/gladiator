class_name ThrustPlan
extends RefCounted
## Pure helpers for the CPU's committed thrust and for a short weapon closing on a longer one (FighterBrain).
## A committed thrust: set (the point held on the target, the body still), drive (the body steps or runs in with the
## arms at swing reach, THRUST punched out only in the last moment so the arms' speed adds to the body's), recover.
## A point contact needs the blade's motion along its own axis, so the drive is straight in, never swept across.
## Closing plan: a fighter whose reach is well short of the foe's stands off just outside the foe's reach (walking in
## under a longer blade only gets cut) and rushes inside when the foe has just swung, had a blow parried or is off
## balance. Once inside it commits (CLOSE_PRESS): it keeps stepping in under the point, shoves, and chases a foe who
## backs off instead of drifting back out to its usual standing distance.
## No Nodes, no clock.

const CLOSE_NONE: int = 0  ## not outreached (or already inside): fight as usual
const CLOSE_WAIT: int = 1  ## at the foe's range but outside mine: stand off just outside his reach, wait for an opening
const CLOSE_RUSH: int = 2  ## the foe just swung or is off balance: run straight in and strike
const CLOSE_INSIDE: int = 3  ## inside my own reach: fight as usual
const CLOSE_PRESS: int = 4  ## got in after an opening: stay in, step inside the point, chase him if he backs off


## True when THRUST should be pressed now: the point reaches the target within `lead_s` at the closing speed, or it is
## already within `near_d`. A point that is not closing waits for the body (the press then only reaches past it).
static func press_now(tip_dist: float, closing: float, lead_s: float, near_d: float) -> bool:
	if tip_dist <= near_d:
		return true
	if closing <= 0.05:
		return false
	return tip_dist / closing <= lead_s


## How fast the two fighters close along `dir` (unit, from me to the foe), m/s; negative while they part.
static func closing_speed(my_vel: Vector3, foe_vel: Vector3, dir: Vector3) -> float:
	var rel: Vector3 = my_vel - foe_vel
	return rel.x * dir.x + rel.z * dir.z


## True when the foe faces me square-on: his facing (yaw, forward is -Z turned by yaw) points at me within the
## cosine `cos_tol`. A square-on foe shows his whole chest, the target a thrust needs.
static func square_on(foe_yaw: float, foe_pos: Vector3, my_pos: Vector3, cos_tol: float) -> bool:
	var to_me := Vector2(my_pos.x - foe_pos.x, my_pos.z - foe_pos.z)
	if to_me.length() < 0.001:
		return false
	var fwd := Vector2(-sin(foe_yaw), -cos(foe_yaw))
	return fwd.dot(to_me.normalized()) >= cos_tol


## True when a drive is over: the point arrived (`hit_d`), went past the target (its distance grew `past_d` beyond the
## closest it came), or the drive ran `max_ticks`.
static func drive_done(tip_dist: float, best_dist: float, ticks: int, max_ticks: int, hit_d: float, past_d: float) -> bool:
	return tip_dist <= hit_d or tip_dist > best_dist + past_d or ticks >= max_ticks


## A weapon's reach as the brain counts it (pelvis to pelvis, m): arm plus most of the weapon.
static func reach_of(length: float) -> float:
	return 0.9 + length * 0.9


## The closing step for a fighter of reach `mine` against a foe of reach `foe` at pelvis distance `dist`.
## `margin`: how much longer the foe's reach must be before it is worth a plan. `opening`: the foe just swung and
## is slow, or is off balance. `out_band`: distance beyond the foe's reach that still counts as at his range.
## `pressing`: a rush got inside a moment ago (the press timer runs), so the fighter stays committed: inside or at
## the foe's range it presses rather than waits.
static func close_step(dist: float, mine: float, foe: float, opening: bool, margin: float, out_band: float,
		pressing: bool = false) -> int:
	if foe - mine < margin:
		return CLOSE_NONE
	if dist <= mine * 1.05:
		return CLOSE_PRESS if pressing else CLOSE_INSIDE
	if dist > foe + out_band:
		return CLOSE_NONE  # out of both reaches: walk up as usual
	if pressing:
		return CLOSE_PRESS  # he gave ground: go after him rather than stand off again
	return CLOSE_RUSH if opening else CLOSE_WAIT


## True when one of this tick's contacts (debug_frame "contacts") is the foe's blow meeting my weapon or shield: his
## swing or thrust was parried and his weapon is held off, the moment to step inside it.
static func foe_parried(contacts: Array, my_side: int) -> bool:
	for c: Variant in contacts:
		if not c is Dictionary:
			continue
		var d: Dictionary = c
		if bool(d.get("hit_on_weapon", false)) and int(d.get("target", -1)) == my_side and int(d.get("attacker", my_side)) != my_side:
			return true
	return false


## A countdown window (ticks): restarts at `length` on `trigger`, otherwise runs down to 0.
static func window_tick(left: int, trigger: bool, length: int) -> int:
	return length if trigger else maxi(left - 1, 0)


## True when a pressing fighter is inside the foe's point: closer than `frac` of his reach, where his weapon's
## striking part is already past me and a shove or a step in beats backing out.
static func inside_point(dist: float, foe: float, frac: float) -> bool:
	return dist < foe * frac


## How fast the foe moves away from me along `dir` (unit, from me to him), m/s; negative while he comes in.
static func away_speed(foe_vel: Vector3, dir: Vector3) -> float:
	return foe_vel.x * dir.x + foe_vel.z * dir.z


## Chase gait: sprint after a foe who backs off (moving away faster than `min_away`, m/s) while I am still farther
## than the distance I want (`hold`) and have more than `min_stamina` to spend. Walking after a kiting foe never
## catches him.
static func chase_gait(dist: float, hold: float, away: float, stamina: float, min_away: float, min_stamina: float) -> bool:
	return dist > hold and away > min_away and stamina > min_stamina


## True when a bleeding fighter should fight on rather than back off to recover: the foe outreaches it by at least
## `margin` (`reach_gap` = his reach minus mine) and it has less blood left than he does. Retreating from a longer
## weapon never gets inside it, and the time limit goes to the fighter with more blood.
static func fight_on_bleeding(reach_gap: float, margin: float, my_blood: float, foe_blood: float) -> bool:
	return reach_gap >= margin and my_blood < foe_blood


## True when backing off is the foe's winning move, so the chase gait applies: his reach beats mine by `margin`
## (`reach_gap` = his reach minus mine), or I carry at least `kite_gap` more armor load (`load_gap` = mine minus his,
## ArmorLoad) and he can kite me. Between even fighters a foe who steps back is only making room.
static func chase_case(reach_gap: float, margin: float, load_gap: float, kite_gap: float) -> bool:
	return reach_gap >= margin or load_gap >= kite_gap
