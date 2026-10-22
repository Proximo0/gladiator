class_name CloseCombat
extends RefCounted
## Half Sword-style close-range moves for one fighter: a shove with the free hand (or shield, or shoulder), a front
## kick with the lead leg, and a grab of the foe's weapon arm or head with the free hand. This holds their timing,
## gating and the pure shape math; the fighter turns them into physics (a hand or foot driven by a capped PD force,
## impulses on contact, a capped spring between the holding hand and the held part). Each move starts on the press
## of its button, costs stamina and has a cooldown. No nodes, no clock: `tick` takes delta.
##
## p keys (from Tuning): shove_time, shove_cooldown, kick_time, kick_cooldown, clinch_time, clinch_max,
## clinch_cooldown.

const SHOVE_HIT0: float = 0.2  ## share of the shove from which the hand (or shoulder) can land
const SHOVE_HIT1: float = 0.75  ## share after which a shove that has not landed has missed
const KICK_CHAMBER: float = 0.3  ## share of the kick spent lifting the knee (foot up under the knee)
const KICK_EXTEND: float = 0.45  ## share by which the leg has snapped fully out
const KICK_HOLD: float = 0.6  ## the leg stays out (driving through) until here, then snaps back
const KICK_RECHAMBER: float = 0.8  ## share by which the foot is back under the raised knee; then it comes down
const KICK_HIT0: float = 0.3  ## share from which the foot can land
const KICK_HIT1: float = 0.8  ## share after which a kick that has not landed has missed

var shove_t: float = -1.0  ## time into the current shove, -1 = none
var shove_cd: float = 0.0
var shove_landed: bool = false
var kick_t: float = -1.0  ## time into the current kick, -1 = none
var kick_cd: float = 0.0
var kick_landed: bool = false
var kick_missed: bool = false  ## the miss has been paid for (once per kick)
var reach_t: float = -1.0  ## time into a grab's reach, -1 = not reaching
var hold_part: String = ""  ## foe part held ("forearm_r" or "head"), "" = not holding
var hold_local: Vector3 = Vector3.ZERO  ## the held point in that part's frame
var hold_t: float = 0.0  ## seconds held so far
var struggle: float = 0.0  ## the held foe's break-free progress, 0..1
var grab_cd: float = 0.0
var grab_head: bool = false  ## the current reach goes for the head (else the weapon arm)
## Cumulative counts for the match stats.
var counts: Dictionary = {"shoves": 0, "shoves_landed": 0, "kicks": 0, "kicks_landed": 0, "grabs": 0, "holds": 0,
	"breaks": 0}
var _held: int = 0  ## buttons held last tick (moves start on the press)


## Press edges of `buttons` against last tick's (bits that are down now and were up before).
func edges(buttons: int) -> int:
	var e: int = buttons & ~_held
	_held = buttons
	return e


## A shove may start: able to act, not mid kick or shove, off cooldown, stamina to pay `cost`.
func can_shove(able: bool, stamina: float, cost: float) -> bool:
	return able and shove_t < 0.0 and kick_t < 0.0 and shove_cd <= 0.0 and stamina >= cost


## A kick may start: standing (`able`) on both legs, nothing else under way, off cooldown, stamina to pay `cost`.
func can_kick(able: bool, legs_ok: bool, stamina: float, cost: float) -> bool:
	return able and legs_ok and kick_t < 0.0 and shove_t < 0.0 and reach_t < 0.0 and hold_part == "" \
		and kick_cd <= 0.0 and stamina >= cost


## A grab may start: able to act, a free left hand, not already reaching or holding, off cooldown.
func can_grab(able: bool, hand_free: bool) -> bool:
	return able and hand_free and reach_t < 0.0 and hold_part == "" and shove_t < 0.0 and grab_cd <= 0.0


func start_shove() -> void:
	shove_t = 0.0
	shove_landed = false
	counts["shoves"] = int(counts["shoves"]) + 1


func start_kick() -> void:
	kick_t = 0.0
	kick_landed = false
	kick_missed = false
	counts["kicks"] = int(counts["kicks"]) + 1


func start_grab(head: bool) -> void:
	reach_t = 0.0
	grab_head = head
	counts["grabs"] = int(counts["grabs"]) + 1


## The reaching hand closed on the foe: hold `part` at `local` (that part's frame).
func latch(part: String, local: Vector3) -> void:
	reach_t = -1.0
	hold_part = part
	hold_local = local
	hold_t = 0.0
	struggle = 0.0
	counts["holds"] = int(counts["holds"]) + 1


## Lets go of a hold (or abandons a reach) and starts the grab cooldown. `broken`: the foe broke free.
func release(p: Dictionary, broken: bool = false) -> void:
	if hold_part != "" or reach_t >= 0.0:
		grab_cd = float(p["clinch_cooldown"])
	if broken and hold_part != "":
		counts["breaks"] = int(counts["breaks"]) + 1
	hold_part = ""
	reach_t = -1.0
	struggle = 0.0


func landed_shove() -> void:
	shove_landed = true
	counts["shoves_landed"] = int(counts["shoves_landed"]) + 1


func landed_kick() -> void:
	kick_landed = true
	counts["kicks_landed"] = int(counts["kicks_landed"]) + 1


## Advances the timers. Ends a shove or kick after its time (then its cooldown runs) and a reach that found nothing.
func tick(delta: float, p: Dictionary) -> void:
	if shove_t >= 0.0:
		shove_t += delta
		if shove_t >= float(p["shove_time"]):
			shove_t = -1.0
			shove_cd = float(p["shove_cooldown"])
	else:
		shove_cd = maxf(shove_cd - delta, 0.0)
	if kick_t >= 0.0:
		kick_t += delta
		if kick_t >= float(p["kick_time"]):
			kick_t = -1.0
			kick_cd = float(p["kick_cooldown"])
	else:
		kick_cd = maxf(kick_cd - delta, 0.0)
	if reach_t >= 0.0:
		reach_t += delta
		if reach_t >= float(p["clinch_time"]):
			release(p)
	elif hold_part != "":
		hold_t += delta
		if hold_t >= float(p["clinch_max"]):
			release(p)
	else:
		grab_cd = maxf(grab_cd - delta, 0.0)


func shoving() -> bool:
	return shove_t >= 0.0


func kicking() -> bool:
	return kick_t >= 0.0


func reaching() -> bool:
	return reach_t >= 0.0


func holding() -> bool:
	return hold_part != ""


## 0..1 through a move lasting `duration` seconds at time `t` (0 when not under way).
static func progress(t: float, duration: float) -> float:
	if t < 0.0:
		return 0.0
	return clampf(t / maxf(duration, 0.01), 0.0, 1.0)


## Shove arm extension 0..1 at progress `u`: a fast push out to full reach by 40%, held, drawn back from 70%.
static func shove_extend(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < 0.4:
		return smoothstep(0.0, 0.4, u)
	if u < 0.7:
		return 1.0
	return 1.0 - smoothstep(0.7, 1.0, u)


## True while a shove at progress `u` can land.
static func shove_window(u: float) -> bool:
	return u >= SHOVE_HIT0 and u <= SHOVE_HIT1


## True while a kick at progress `u` can land.
static func kick_window(u: float) -> bool:
	return u >= KICK_HIT0 and u <= KICK_HIT1


## Kicking foot target in the facing frame at progress `u`, relative to the hip on the ground below it (x right,
## y up, z forward): from the planted spot `rest` the knee comes up (foot to `chamber` height under it, a little
## ahead), the leg snaps out to `reach` ahead at `height` and stays out a moment, snaps back under the raised knee
## (the re-chamber, so the kicker does not fall forward onto the leg) and the foot comes down on its spot.
static func kick_foot(u: float, rest: Vector3, chamber: float, reach: float, height: float) -> Vector3:
	var up := Vector3(rest.x, chamber, maxf(rest.z, 0.0) + 0.15)
	var out := Vector3(rest.x * 0.5, height, reach)
	if u <= 0.0 or u >= 1.0:
		return rest
	if u < KICK_CHAMBER:
		return rest.lerp(up, smoothstep(0.0, KICK_CHAMBER, u))
	if u < KICK_EXTEND:
		return up.lerp(out, smoothstep(KICK_CHAMBER, KICK_EXTEND, u))
	if u < KICK_HOLD:
		return out
	if u < KICK_RECHAMBER:
		return out.lerp(up, smoothstep(KICK_HOLD, KICK_RECHAMBER, u))
	return up.lerp(rest, smoothstep(KICK_RECHAMBER, 1.0, u))


## 0..1 how far the kicker leans the upper body back to balance the leg (counterweight) at kick progress `u`: in as
## the knee comes up, full while the leg is out, gone again as the foot comes down.
static func kick_lean(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < KICK_HOLD:
		return smoothstep(0.1, KICK_CHAMBER, u)
	return 1.0 - smoothstep(KICK_HOLD, KICK_RECHAMBER + 0.1, u)


## Where a holding hand draws the held point to, in the holder's frame (from the chest): a weapon arm is hauled
## across to the holder's free (left) side and down, which opens the foe's guard and turns them; a head is pulled
## down in front of the chest. `pull` is how far ahead of the chest, `side` and `down` the arm haul's offsets,
## `head_down` the head's.
static func hold_pull_goal(head: bool, chest: Vector3, fwd: Vector3, right: Vector3, up: Vector3, pull: float,
		side: float, down: float, head_down: float) -> Vector3:
	if head:
		return chest + fwd * pull - up * head_down
	return chest + fwd * pull - right * side - up * down


## The holding hand's target this tick: from the held point `held` toward `goal`, at most `step` metres ahead of it
## (the hand leads the held part; the grip's joint brings the part after it).
static func hold_pull_target(held: Vector3, goal: Vector3, step: float) -> Vector3:
	return held + (goal - held).limit_length(maxf(step, 0.0))


## Shove impulse magnitude (N·s): `base` scaled by the shover's strength (0..1) and the pushing arm's limb factor.
static func shove_impulse(base: float, strength: float, limb: float) -> float:
	return maxf(base, 0.0) * clampf(strength, 0.0, 1.0) * clampf(limb, 0.0, 1.0)


## Stagger a landed shove adds: `base`, plus `off` when the foe is already off balance (stumbling, mid kick or
## turning over), which is what floors them.
static func shove_stagger(base: float, off: float, off_balance: bool) -> float:
	return base + (off if off_balance else 0.0)


## Break-free progress per second for a held fighter: `rate` at full effort against an equal holder, scaled by
## strength over the holder's, and a passive share of it when not fighting the hold.
static func struggle_rate(rate: float, effort: float, held_strength: float, holder_strength: float) -> float:
	var e: float = lerpf(0.3, 1.0, clampf(effort, 0.0, 1.0))
	return rate * e * clampf(held_strength, 0.05, 2.0) / maxf(holder_strength, 0.05)


## How hard a held fighter is fighting the hold this tick (0..1), from its input: pulling away (`move_y` < 0, -1..1)
## and any action button held.
static func struggle_effort(move_y: float, any_button: bool) -> float:
	return clampf(maxf(-move_y, 0.0) + (0.7 if any_button else 0.0), 0.0, 1.0)


## Advances the held foe's struggle by `rate` * delta. Returns true when the foe has broken free.
func add_struggle(rate: float, delta: float) -> bool:
	struggle = minf(struggle + maxf(rate, 0.0) * delta, 1.0)
	return struggle >= 1.0


## A staggering blow on the holding arm breaks the hold only when the striking body itself moved at `striker_speed`
## of at least `min_speed` (m/s): the holding arm running into a still fist or blade is not a blow.
static func blow_breaks_hold(striker_speed: float, min_speed: float) -> bool:
	return striker_speed >= min_speed


## The hold is lost when the held point has been pulled `dist` away from the hand, past `max_dist`.
static func hold_slips(dist: float, max_dist: float) -> bool:
	return dist > max_dist


func to_array() -> Array:
	return [shove_t, shove_cd, shove_landed, kick_t, kick_cd, kick_landed, kick_missed, reach_t, hold_part,
		hold_local, hold_t, struggle, grab_cd, grab_head, _held, counts.duplicate()]


func from_array(a: Array) -> void:
	if a.size() < 16:
		shove_t = -1.0
		kick_t = -1.0
		reach_t = -1.0
		hold_part = ""
		shove_cd = 0.0
		kick_cd = 0.0
		grab_cd = 0.0
		_held = 0
		return
	shove_t = float(a[0])
	shove_cd = float(a[1])
	shove_landed = bool(a[2])
	kick_t = float(a[3])
	kick_cd = float(a[4])
	kick_landed = bool(a[5])
	kick_missed = bool(a[6])
	reach_t = float(a[7])
	hold_part = str(a[8])
	hold_local = a[9]
	hold_t = float(a[10])
	struggle = float(a[11])
	grab_cd = float(a[12])
	grab_head = bool(a[13])
	_held = int(a[14])
	counts = (a[15] as Dictionary).duplicate()
