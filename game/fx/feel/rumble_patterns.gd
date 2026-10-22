class_name RumblePatterns
extends RefCounted
## Gamepad rumble and phone vibration as short patterns per hit class, so hits are told apart by feel: a light hit
## ticks, a heavy hit thumps and rolls off, a clash buzzes twice on the light motor, a sever thumps then pulses wet,
## a finisher hits hard, falls silent through the slow motion and swells again with the crowd roar. A pattern is an
## Array of pulses {"at" s, "weak" 0..1, "strong" 0..1, "dur" s}, strengths from FeelLogic.rumble. Pure.
## Unit-tested in test_rumble_patterns.gd.

const MAX_PULSES: int = 6
const PHONE_MIN_MS: int = 12


## Pulses for one pad. `taken` is true for the fighter who was hit. Empty when switched off or a tap.
static func pattern(cls: String, imp: float, taken: bool, tun: Tuning, scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: Dictionary = FeelLogic.rumble(imp, taken, tun, scale)
	var dur: float = float(base["dur"])
	if dur <= 0.0 or cls == HitStopLogic.CLASS_NONE:
		return out
	var w: float = float(base["weak"])
	var s: float = float(base["strong"])
	match cls:
		HitStopLogic.CLASS_LIGHT:
			out.append(_pulse(0.0, w * 0.8, s * 0.35, minf(dur, 0.07)))
		HitStopLogic.CLASS_MEDIUM:
			out.append(_pulse(0.0, w, s * 0.75, dur * 0.7))
		HitStopLogic.CLASS_HEAVY:
			out.append(_pulse(0.0, w, s, dur * 0.55))
			out.append(_pulse(dur * 0.55, w * 0.5, s * 0.35, dur * 0.6))
		HitStopLogic.CLASS_CLASH:
			out.append(_pulse(0.0, minf(w * 1.3, 1.0), s * 0.15, 0.045))
			out.append(_pulse(0.075, w * 0.7, s * 0.1, 0.04))
		HitStopLogic.CLASS_SEVER:
			out.append(_pulse(0.0, w, s, dur * 0.5))
			for i: int in 3:
				var k: float = 0.55 - 0.15 * float(i)
				out.append(_pulse(dur * 0.5 + 0.14 * float(i + 1), w * k, s * k * 0.6, 0.06))
		HitStopLogic.CLASS_FINISHER:
			out.append(_pulse(0.0, 1.0 * scale_of(taken, scale), 1.0 * scale_of(taken, scale), 0.32))
			var roar: float = maxf(tun.feel_cine_hold_s - FinisherCine.ROAR_LEAD_S, 0.4)
			out.append(_pulse(roar, 0.55 * scale_of(taken, scale), 0.4 * scale_of(taken, scale), 0.5))
			out.append(_pulse(roar + 0.5, 0.35 * scale_of(taken, scale), 0.15 * scale_of(taken, scale), 0.45))
	if out.size() > MAX_PULSES:
		out.resize(MAX_PULSES)
	return out


## Strength multiplier of a finisher pulse: the master scale, softer for the one who landed it.
static func scale_of(taken: bool, scale: float) -> float:
	return clampf(scale, 0.0, 1.0) * (1.0 if taken else FeelLogic.RUMBLE_DEALER_MULT)


## The same pattern as phone vibrations: [{"at" s, "ms" int, "amp" 0..1}]. Phones have one motor, so a pulse's
## strength is the larger of its two motors, and pulses under PHONE_MIN_MS are dropped.
static func phone(pulses: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in pulses:
		var ms: int = mini(int(float(p["dur"]) * 1000.0), FeelLogic.VIBRATE_MAX_MS)
		var amp: float = clampf(maxf(float(p["weak"]), float(p["strong"])), 0.0, 1.0)
		if ms >= PHONE_MIN_MS and amp > 0.0:
			out.append({"at": float(p["at"]), "ms": ms, "amp": amp})
	return out


## Total length of a pattern, s.
static func span_s(pulses: Array[Dictionary]) -> float:
	var end: float = 0.0
	for p: Dictionary in pulses:
		end = maxf(end, float(p["at"]) + float(p["dur"]))
	return end


static func _pulse(at: float, weak: float, strong: float, dur: float) -> Dictionary:
	return {"at": maxf(at, 0.0), "weak": clampf(weak, 0.0, 1.0), "strong": clampf(strong, 0.0, 1.0), "dur": maxf(dur, 0.0)}
