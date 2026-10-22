class_name SfxGush
extends RefCounted
## One gushing wound's sound: the beheading fountain (multi-second, pulsing with the heartbeat) or a gut spill
## (squelch, then flops of the guts on the sand, then a weaker gush). Pure: `tick` returns the sounds due this step as
## {key, gain_db, pitch}; the caller plays them. Pulse timing follows BloodMath.heart_rate_bpm, so the sound and
## the blood jets beat together.

const KIND_FOUNTAIN: String = "fountain"
const KIND_GUT: String = "gut"
const MAX_PULSES: int = 14
const FLOP_TIMES: Array[float] = [0.32, 0.6, 0.95, 1.4, 2.0]

var kind: String = KIND_FOUNTAIN
var age: float = 0.0
var dur: float = 6.5
var hold: float = 1.6
var pos: Vector3 = Vector3.ZERO
var pulses: int = 0
var _next_pulse: float = 0.12
var _flops: int = 0
var _squelched: bool = false
var _flop_jitter: Array[float] = []


func setup(k: String, at: Vector3, duration: float, hold_s: float, rng: RandomNumberGenerator) -> SfxGush:
	kind = k
	pos = at
	dur = maxf(duration, 0.5)
	hold = clampf(hold_s, 0.0, dur)
	for i: int in range(FLOP_TIMES.size()):
		_flop_jitter.append(rng.randf_range(-0.07, 0.07))
	return self


func finished() -> bool:
	return age >= dur


## Strength 0..1 of the flow at the current age: full during `hold`, then tapering to nothing at `dur`.
func strength() -> float:
	if age <= hold:
		return 1.0
	return clampf(1.0 - (age - hold) / maxf(dur - hold, 0.01), 0.0, 1.0)


## Pulse gain in dB from the age and the blood left (fraction): fades out with the taper and as the blood drains.
static func pulse_gain_db(strength_now: float, blood_frac: float, gut: bool) -> float:
	var press: float = BloodMath.pressure(blood_frac)
	var s: float = clampf(strength_now, 0.0, 1.0) * lerpf(0.35, 1.0, press)
	return lerpf(-26.0, 0.0, pow(s, 0.7)) - (6.0 if gut else 0.0)


func tick(delta: float, blood_frac: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if finished():
		return out
	age += delta
	var gut: bool = kind == KIND_GUT
	if gut and not _squelched:
		_squelched = true
		out.append({"key": "gore/gut_squelch", "gain_db": 0.0, "pitch": 1.0})
	if gut:
		while _flops < FLOP_TIMES.size() and age >= FLOP_TIMES[_flops] + _flop_jitter[_flops]:
			out.append({"key": "gore/gut_flop", "gain_db": -2.0 * _flops, "pitch": 1.0 - 0.04 * _flops})
			_flops += 1
	if age >= _next_pulse and pulses < MAX_PULSES:
		var bpm: float = BloodMath.heart_rate_bpm(blood_frac)
		_next_pulse = age + 60.0 / maxf(bpm, 30.0)
		pulses += 1
		var g: float = pulse_gain_db(strength(), blood_frac, gut)
		if g > -24.0:
			out.append({"key": "gore/gush_pulse", "gain_db": g, "pitch": 1.0 + 0.1 * (1.0 - strength())})
	return out
