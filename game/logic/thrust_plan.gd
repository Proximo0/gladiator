class_name ThrustPlan
extends RefCounted
## Pure helpers for the CPU's committed thrust and for a short weapon closing on a longer one (FighterBrain).
## A committed thrust: set (the point held on the target, the body still), drive (the body steps or runs in with the
## arms at swing reach, THRUST punched out only in the last moment so the arms' speed adds to the body's), recover.
## A point contact needs the blade's motion along its own axis, so the drive is straight in, never swept across.
## Closing plan: a fighter whose reach is well short of the foe's waits just outside the foe's reach, rushes inside
## when the foe has just swung or slips in on a slant, and stays inside once there.
## No Nodes, no clock.

const CLOSE_NONE: int = 0  ## not outreached (or already inside): fight as usual
const CLOSE_SLIP: int = 1  ## in the foe's reach but outside mine: step in on a slant, guard up
const CLOSE_RUSH: int = 2  ## the foe just swung or is slow: run straight in and strike
const CLOSE_INSIDE: int = 3  ## inside the foe's point: keep the distance short, never back off into his reach


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
static func close_step(dist: float, mine: float, foe: float, opening: bool, margin: float, out_band: float) -> int:
	if foe - mine < margin:
		return CLOSE_NONE
	if dist <= mine * 1.05:
		return CLOSE_INSIDE
	if dist > foe + out_band:
		return CLOSE_NONE  # out of both reaches: walk up as usual
	return CLOSE_RUSH if opening else CLOSE_SLIP
