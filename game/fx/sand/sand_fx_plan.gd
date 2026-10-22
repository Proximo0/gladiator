class_name SandFxPlan
extends RefCounted
## How much sand each event throws: pure functions from an event's strength to grain and dust counts, scaled by the
## Tuning rows (group "Sand") and the graphics quality's share `mult` (GfxQuality.SAND_FX_MULT). Returns
## {"grains": int, "dust": int, "speed": float, "size": float} (grain speed m/s, dust sprite final width m).
## `frac` is a random 0..1 so fractional counts round without a wall clock or randf().

const FALL_MIN_DEPTH: float = 0.012  ## requested press depth below which a body press throws nothing special
const FALL_FULL_DEPTH: float = 0.062  ## requested depth of a full-impact fall (the presenter's maximum)
const SLIDE_SPEED_MIN: float = 0.9
const SLIDE_SPEED_MAX: float = 14.0


static func _n(x: float, frac: float) -> int:
	return maxi(int(x + frac), 0)


## Impact strength 0..1.5 of a press of requested depth `raw` (m).
static func impact_of(raw: float) -> float:
	return clampf((raw - FALL_MIN_DEPTH) / (FALL_FULL_DEPTH - FALL_MIN_DEPTH), 0.0, 1.5)


## A foot coming down: always a few grains and a puff; faster feet (push length 0..1) throw more and further.
static func step(t: Tuning, mult: float, push_len: float, frac: float) -> Dictionary:
	var k: float = 1.0 + clampf(push_len, 0.0, 1.5)
	return {
		"grains": _n(t.sand_step_grains * mult * k, frac),
		"dust": _n(t.sand_step_dust * mult * k, frac),
		"speed": 1.2 + 1.2 * k,
		"size": t.sand_dust_size * (0.7 + 0.3 * k),
	}


## A body part landing: scales with impact_of(raw) (a soft touch still puffs a little).
static func fall(t: Tuning, mult: float, raw: float, frac: float) -> Dictionary:
	var k: float = impact_of(raw)
	return {
		"grains": _n(t.sand_fall_grains * mult * k * k, frac),
		"dust": _n(2.0 * mult + t.sand_fall_dust * mult * k, frac),
		"speed": 1.4 + 2.2 * minf(k, 1.0),
		"size": t.sand_dust_size * (1.0 + 1.6 * minf(k, 1.0)),
	}


## Something sliding over the sand (foot, body roll, dragged weapon) at `speed` m/s with `radius` (m): a sprint
## spray of grains and a dust trail. Nothing below SLIDE_SPEED_MIN.
static func slide(t: Tuning, mult: float, speed: float, radius: float, frac: float) -> Dictionary:
	if speed < SLIDE_SPEED_MIN:
		return {"grains": 0, "dust": 0, "speed": 0.0, "size": 0.0}
	var s: float = clampf(speed, 0.0, SLIDE_SPEED_MAX)
	var body: float = 1.0 + clampf(radius / 0.1, 0.0, 2.5)
	return {
		"grains": _n((s - 0.5) * 0.9 * body * t.sand_slide_grains * mult, frac),
		"dust": _n((s - 0.8) * 0.22 * body * t.sand_slide_dust * mult, frac),
		"speed": 1.0 + s * 0.4,
		"size": t.sand_dust_size * (0.6 + 0.25 * body),
	}


## A weapon striking or stabbing the sand, `amount` 0..1.5.
static func strike(t: Tuning, mult: float, amount: float, frac: float) -> Dictionary:
	var a: float = clampf(amount, 0.0, 1.5)
	return {
		"grains": _n((6.0 + t.sand_strike_grains * a) * mult, frac),
		"dust": _n((1.0 + 0.2 * t.sand_strike_grains * a) * mult, frac),
		"speed": 2.5 + 3.5 * a,
		"size": t.sand_dust_size * (0.9 + 0.8 * a),
	}
