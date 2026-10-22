class_name UiTones
extends RefCounted
## Menu sounds synthesised in code (no files): a bronze focus tick, a metallic select "shing", a wooden back knock,
## a soft sand swoosh for screen changes and a dull clunk for a locked pick. Pure and deterministic: every kind has
## its own fixed noise seed, so the same kind always gives the same samples.

const RATE: int = 44100
const KINDS: PackedStringArray = ["focus", "select", "back", "swoosh", "locked"]
## Length in seconds per kind.
const LENGTHS: Dictionary = {"focus": 0.045, "select": 0.32, "back": 0.14, "swoosh": 0.2, "locked": 0.16}
## Peak level per kind (0..1) before the player's volume.
const PEAKS: Dictionary = {"focus": 0.32, "select": 0.6, "back": 0.45, "swoosh": 0.22, "locked": 0.5}
const FADE_S: float = 0.004  ## fade at both ends so no kind starts or stops with a click


## Mono samples in -1..1 for `kind` ("" kinds give an empty array).
static func samples(kind: String, rate: int = RATE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not LENGTHS.has(kind) or rate <= 0:
		return out
	var n: int = int(float(LENGTHS[kind]) * float(rate))
	out.resize(n)
	var seed_state: int = 0x2545F491 ^ kind.hash()
	var lp: float = 0.0
	var bp: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(rate)
		seed_state = (seed_state * 1103515245 + 12345) & 0x7fffffff
		var nz: float = float(seed_state) / float(0x3fffffff) - 1.0
		var v: float = 0.0
		match kind:
			"focus":
				# Two short inharmonic partials, like a fingernail on a bronze rim.
				v = (sin(TAU * 1760.0 * t) * 0.7 + sin(TAU * 2637.0 * t) * 0.35) * exp(-t / 0.011)
				v += nz * 0.25 * exp(-t / 0.0015)
			"select":
				# A blade drawn and struck: bright modal ring, a low thump and a noisy scrape at the start.
				var ring: float = sin(TAU * 1318.5 * t) * exp(-t / 0.11) * 0.5
				ring += sin(TAU * 1975.5 * t * 1.003) * exp(-t / 0.08) * 0.35
				ring += sin(TAU * 3135.0 * t) * exp(-t / 0.05) * 0.25
				var thump: float = sin(TAU * (120.0 - 50.0 * minf(t / 0.08, 1.0)) * t) * exp(-t / 0.05) * 0.6
				bp += (nz - bp) * 0.35
				v = ring + thump + (nz - bp) * exp(-t / 0.02) * 0.35
			"back":
				# A wooden knock: falling tone and a soft body.
				var f: float = 520.0 - 220.0 * minf(t / 0.1, 1.0)
				v = sin(TAU * f * t) * exp(-t / 0.035) * 0.8 + sin(TAU * 180.0 * t) * exp(-t / 0.05) * 0.4
				v += nz * 0.2 * exp(-t / 0.004)
			"swoosh":
				# Low-passed noise swelling and fading: sand blown across stone.
				var cut: float = 0.04 + 0.22 * sin(PI * t / float(LENGTHS[kind]))
				lp += (nz - lp) * cut
				v = lp * sin(PI * t / float(LENGTHS[kind]))
			"locked":
				# A dull iron clunk: a low square-ish tone that dies fast.
				var sq: float = sign(sin(TAU * 140.0 * t)) * 0.4 + sin(TAU * 280.0 * t) * 0.3
				lp += (sq + nz * 0.3 - lp) * 0.2
				v = lp * exp(-t / 0.045)
		out[i] = v
	return _finish(out, float(PEAKS[kind]), rate)


## Normalises to `peak` and fades the ends.
static func _finish(x: PackedFloat32Array, peak: float, rate: int) -> PackedFloat32Array:
	var mean: float = 0.0
	for v: float in x:
		mean += v
	mean /= maxf(float(x.size()), 1.0)
	var fade: int = maxi(1, int(FADE_S * float(rate)))
	var top: float = 0.0
	for i: int in x.size():
		var g: float = minf(1.0, minf(float(i) / float(fade), float(x.size() - 1 - i) / float(fade)))
		x[i] = (x[i] - mean) * g
		top = maxf(top, absf(x[i]))
	if top > 0.0:
		for i: int in x.size():
			x[i] = x[i] / top * peak
	return x


## 16-bit little-endian PCM bytes for AudioStreamWAV.
static func pcm16(x: PackedFloat32Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(x.size() * 2)
	for i: int in x.size():
		b.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
	return b
