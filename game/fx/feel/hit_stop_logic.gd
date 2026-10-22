class_name HitStopLogic
extends RefCounted
## Hit-stop as a presentation clock, never a physics pause: a resolved hit asks for a brief hold, during which the
## shown pose runs at `feel_hitstop_rate` and so falls behind physics (`lag`, real seconds); after the hold the
## shown pose plays faster (`feel_hitstop_catchup`) until it is back on physics. Physics, inputs, state hashes and
## the online stream never see it. Anti-stall rules: a new hold replaces the remaining one when longer (holds never
## add up), `lag` is capped at `feel_hitstop_lag_max`, and a debt that drains over `feel_hitstop_budget_tau` shrinks
## the holds of a flurry (finishers ignore the debt). Pure: no nodes, no clock. Unit-tested in test_hit_stop_logic.gd.

const CLASS_NONE: String = "none"
const CLASS_LIGHT: String = "light"
const CLASS_MEDIUM: String = "medium"
const CLASS_HEAVY: String = "heavy"
const CLASS_CLASH: String = "clash"
const CLASS_SEVER: String = "sever"
const CLASS_FINISHER: String = "finisher"
const CLASSES: PackedStringArray = ["light", "medium", "heavy", "clash", "sever", "finisher"]
const MEDIUM_IMPACT: float = 0.45  ## impact from which an ordinary hit counts as medium (for logs and rumble)
const HEAVY_IMPACT: float = 0.75  ## and from which it counts as heavy
const GLANCE_MULT: float = 0.6  ## a glancing blow skids off: a shorter stop
const DONE_LAG: float = 0.0005  ## lag under which the shown pose counts as back on physics, s

var lag: float = 0.0  ## how far the shown pose trails physics, real s
var hold_left: float = 0.0  ## real s left of the current hold
var debt: float = 0.0  ## recent hold time, drains with `feel_hitstop_budget_tau`
var stops: int = 0  ## holds started or extended (for logs)
var last_class: String = CLASS_NONE
var last_s: float = 0.0  ## length of the last applied hold, real s


## Class of a hit for hit-stop, rumble and logs: none (a tap), light, medium, heavy, clash (weapon on weapon), sever
## (cuts a limb off or guts without ending the fight) or finisher.
static func hit_class(ev: Dictionary, imp: float, tun: Tuning) -> String:
	if FeelLogic.is_finisher(ev):
		return CLASS_FINISHER
	if imp < tun.feel_hitstop_min:
		return CLASS_NONE
	if bool(ev.get("hit_on_weapon", false)):
		return CLASS_CLASH
	if bool(ev.get("sever", false)) or bool(ev.get("behead", false)) or bool(ev.get("gut", false)):
		return CLASS_SEVER
	if imp >= HEAVY_IMPACT:
		return CLASS_HEAVY
	if imp >= MEDIUM_IMPACT:
		return CLASS_MEDIUM
	return CLASS_LIGHT


## Hold length a hit asks for before the anti-stall debt, real s. Scales with impact between the light and heavy
## lengths; severs and finishers have their own floors; clashes and glances are shorter.
static func request_s(ev: Dictionary, imp: float, tun: Tuning) -> float:
	var cls: String = hit_class(ev, imp, tun)
	if cls == CLASS_NONE:
		return 0.0
	if cls == CLASS_FINISHER:
		return clampf(tun.feel_hitstop_finisher_s, 0.0, tun.feel_hitstop_lag_max / maxf(1.0 - tun.feel_hitstop_rate, 0.01))
	var span: float = maxf(1.0 - tun.feel_hitstop_min, 0.001)
	var t: float = clampf((imp - tun.feel_hitstop_min) / span, 0.0, 1.0)
	var s: float = lerpf(tun.feel_hitstop_light_s, tun.feel_hitstop_heavy_s, t)
	if cls == CLASS_CLASH:
		s *= tun.feel_hitstop_clash_mult
	elif cls == CLASS_SEVER:
		s = maxf(s, tun.feel_hitstop_sever_s)
	if bool(ev.get("glanced", false)):
		s *= GLANCE_MULT
	return maxf(s, 0.0)


## Share of a requested hold that the debt still allows (1 when rested, 0 once the budget is spent).
static func budget_factor(p_debt: float, tun: Tuning) -> float:
	return clampf(1.0 - p_debt / maxf(tun.feel_hitstop_budget_s, 0.001), 0.0, 1.0)


## A resolved hit. Returns the hold it started (0 when none): the longer of the remaining hold and this one.
func request(ev: Dictionary, imp: float, tun: Tuning) -> float:
	var cls: String = hit_class(ev, imp, tun)
	var want: float = request_s(ev, imp, tun)
	if cls != CLASS_FINISHER:
		want *= budget_factor(debt, tun)
	if want <= hold_left or want <= 0.0:
		return 0.0
	debt += want - hold_left
	hold_left = want
	stops += 1
	last_class = cls
	last_s = want
	return want


## Advances by real seconds `dt`. Returns the presentation speed for this frame (1 = in step with physics, under 1
## while holding, over 1 while catching up).
func step(dt: float, tun: Tuning) -> float:
	if dt <= 0.0 or not is_finite(dt):
		return 1.0
	debt *= exp(-dt / maxf(tun.feel_hitstop_budget_tau, 0.01))
	if hold_left > 0.0:
		var used: float = minf(dt, hold_left)
		hold_left = maxf(hold_left - dt, 0.0)
		var room: float = maxf(tun.feel_hitstop_lag_max - lag, 0.0)
		var grow: float = minf(used * (1.0 - clampf(tun.feel_hitstop_rate, 0.0, 1.0)), room)
		lag += grow
		if room <= 0.0:
			hold_left = 0.0  # at the cap: the hold is spent, never a longer stall
		return 1.0 - grow / dt
	if lag > 0.0:
		var drain: float = minf(lag, dt * maxf(tun.feel_hitstop_catchup, 0.01))
		lag -= drain
		if lag < DONE_LAG:
			lag = 0.0
		return 1.0 + drain / dt
	return 1.0


## Holding or catching up: the shown pose is not physics'.
func active() -> bool:
	return hold_left > 0.0 or lag > 0.0


func reset() -> void:
	lag = 0.0
	hold_left = 0.0
	debt = 0.0
	last_class = CLASS_NONE
	last_s = 0.0
