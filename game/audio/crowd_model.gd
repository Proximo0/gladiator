class_name CrowdModel
extends RefCounted
## Crowd excitement and reaction selection (pure). `level` is 0..1: it jumps when things happen, decays with a
## half-life, and drives the ambience mix. Reactions have tiers and cooldowns so the crowd does not babble.

const BASELINE: float = 0.08
const HALF_LIFE: float = 5.0
const ACTION_GAIN: float = 0.05
const STALL_LEVEL: float = 0.12
const STALL_SECONDS: float = 14.0
const TIERS: Dictionary = {"": 0, "gasp": 1, "boo": 1, "cheer": 2, "roar": 3, "finisher": 4}
const COOLDOWNS: Dictionary = {"gasp": 1.0, "boo": 6.0, "cheer": 1.8, "roar": 3.0, "finisher": 9.0}

var level: float = BASELINE
var cooldown: float = 0.0
var last_tier: int = 0
var stall: float = 0.0


## Saturating add: several small impulses approach but never pass 1.
func add(impulse: float) -> void:
	level = clampf(1.0 - (1.0 - level) * (1.0 - clampf(impulse, 0.0, 1.0)), 0.0, 1.0)
	stall = 0.0


## Advance by `delta`; `action` (0..1) is how much the fighters are moving their weapons right now.
func tick(delta: float, action: float) -> void:
	level = CrowdModel.decayed(level, delta, HALF_LIFE)
	level = minf(1.0, level + clampf(action, 0.0, 1.0) * ACTION_GAIN * delta)
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown <= 0.0:
		last_tier = 0
	if level < STALL_LEVEL:
		stall += delta
	else:
		stall = 0.0


## True once and resets when the fight has been dull for a long time (the crowd boos).
func take_stall_boo() -> bool:
	if stall >= STALL_SECONDS and cooldown <= 0.0:
		stall = 0.0
		return true
	return false


## Ask to play a reaction; true when it may play (tier beats the one cooling down, or nothing is cooling).
func try_reaction(kind: String) -> bool:
	if kind == "":
		return false
	var tier: int = int(TIERS.get(kind, 0))
	if cooldown > 0.0 and tier <= last_tier:
		return false
	cooldown = float(COOLDOWNS.get(kind, 1.0))
	last_tier = tier
	return true


static func decayed(value: float, delta: float, half_life: float) -> float:
	var k: float = pow(0.5, delta / maxf(half_life, 0.001))
	return BASELINE + (value - BASELINE) * k


## How exciting one hit is, 0..1.
static func hit_impulse(ev: Dictionary) -> float:
	var v: float = SfxLogic.intensity(float(ev.get("energy", 0.0))) * 0.35
	if bool(ev.get("hit_on_weapon", false)):
		v *= 0.5
	if bool(ev.get("glanced", false)):
		v *= 0.4
	if bool(ev.get("sever", false)) or bool(ev.get("behead", false)) or bool(ev.get("gut", false)):
		v += 0.5
	if bool(ev.get("disarmed", false)):
		v += 0.3
	if bool(ev.get("dislodge", false)):
		v += 0.2
	if str(ev.get("finisher", "")) != "":
		v += 1.0
	return clampf(v, 0.0, 1.0)


## Seconds after a landed shove or kick within which the foe hitting the sand counts as floored by it.
const CLOSE_FLOOR_WINDOW: float = 1.5


## How exciting a close-range move is, 0..1 (Fighter.close's kind and landed).
static func close_impulse(kind: String, landed: bool) -> float:
	match kind:
		"shove":
			return 0.08 if landed else 0.0
		"kick":
			return 0.12 if landed else 0.0
		"hold":
			return 0.08
		"break":
			return 0.1
	return 0.0


## The crowd's reaction to a fighter going down `since_close` seconds after a landed shove or kick on them: a gasp
## inside the window, else "" (a fall of its own is left to the other rules).
static func floored_reaction(since_close: float) -> String:
	return "gasp" if since_close >= 0.0 and since_close <= CLOSE_FLOOR_WINDOW else ""


## Which crowd reaction a hit draws: "", "gasp", "cheer", "roar" or "finisher".
static func reaction_for(ev: Dictionary) -> String:
	if str(ev.get("finisher", "")) != "":
		return "finisher"
	if bool(ev.get("sever", false)) or bool(ev.get("behead", false)) or bool(ev.get("gut", false)):
		return "roar"
	if bool(ev.get("disarmed", false)):
		return "gasp"
	if bool(ev.get("dislodge", false)):
		return "cheer"
	var v: float = hit_impulse(ev)
	if v >= 0.25:
		return "cheer"
	if v >= 0.13:
		return "gasp"
	return ""


## Ambience loop levels in dB (x = calm loop, y = excited loop) for an excitement level.
static func ambience_gains(e: float) -> Vector2:
	var x: float = clampf(e, 0.0, 1.0)
	var hi: float = smoothstep(0.05, 0.75, x)
	var lo: float = 1.0 - smoothstep(0.2, 0.9, x) * 0.6
	var master: float = lerpf(-6.0, 0.0, x)
	return Vector2(linear_to_db(lo) - 3.0 + master, lerpf(-40.0, 0.0, hi) + master)
