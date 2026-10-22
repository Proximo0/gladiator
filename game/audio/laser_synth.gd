class_name LaserSynth
extends RefCounted
## Procedural sounds for the laser sword, built in code (no files, no samples, no licence): a seamless looping hum, a
## crackling clash and a short flesh-sizzle. Deterministic: every sound seeds its own RandomNumberGenerator.
## SfxLogic names them "synth/laser_clash" and "synth/laser_cut"; SfxDirector asks `stream_for` for the stream.

const RATE: int = 22050
const HUM_HZ: float = 110.0  ## whole cycles per second, so the 1 s loop is seamless
const HUM_SECONDS: float = 1.0
const CLASH_SECONDS: float = 0.4
const CUT_SECONDS: float = 0.22
const CLASH_VARIANTS: int = 3
const CUT_VARIANTS: int = 2

static var _cache: Dictionary = {}


static func is_synth_key(key: String) -> bool:
	return key.begins_with("synth/")


static func variant_count(key: String) -> int:
	match key:
		"synth/laser_clash":
			return CLASH_VARIANTS
		"synth/laser_cut":
			return CUT_VARIANTS
	return 0


## The (cached) stream for a synth key and variant index.
static func stream_for(key: String, variant: int) -> AudioStreamWAV:
	var n: int = variant_count(key)
	if n <= 0:
		return null
	var v: int = posmod(variant, n)
	var ck: String = "%s#%d" % [key, v]
	if not _cache.has(ck):
		var samples: PackedFloat32Array = clash_samples(v) if key == "synth/laser_clash" else cut_samples(v)
		_cache[ck] = to_stream(samples, false)
	return _cache[ck]


static func hum() -> AudioStreamWAV:
	if not _cache.has("hum"):
		_cache["hum"] = to_stream(hum_samples(), true)
	return _cache["hum"]


## 16-bit mono PCM stream from float samples (-1..1).
static func to_stream(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## A 1 s hum: 110 Hz and its harmonics with a slow wobble and a faint 113 Hz beat, all whole cycles per second.
static func hum_samples() -> PackedFloat32Array:
	var n: int = int(HUM_SECONDS * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var parts: Array = [[1.0, 0.55], [2.0, 0.35], [3.0, 0.2], [5.0, 0.08]]
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var v: float = 0.0
		for p: Array in parts:
			v += float(p[1]) * sin(TAU * HUM_HZ * float(p[0]) * t)
		v += 0.12 * sin(TAU * 113.0 * t)
		v *= 0.8 + 0.2 * sin(TAU * 7.0 * t)
		out[i] = v * 0.45
	return out


## A zap: a downward sine sweep with a metallic ring, over crackle bursts of noise.
static func clash_samples(variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + variant
	var n: int = int(CLASH_SECONDS * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	var f0: float = 2300.0 - 300.0 * float(variant)
	var crackle: float = 0.0
	var prev: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		var f: float = 260.0 + (f0 - 260.0) * exp(-t * 14.0)
		phase += TAU * f / float(RATE)
		var zap: float = sin(phase) * exp(-t * 9.0)
		if rng.randf() < 0.012 * exp(-t * 5.0) * 4.0:
			crackle = rng.randf_range(0.6, 1.0)
		crackle *= 0.9
		var noise: float = rng.randf_range(-1.0, 1.0)
		var hp: float = noise - prev  # crude high-pass
		prev = noise
		out[i] = clampf(0.55 * zap + 0.5 * hp * crackle + 0.18 * sin(TAU * 140.0 * t) * exp(-t * 12.0), -1.0, 1.0)
	return out


## A short sizzle for the blade passing through flesh.
static func cut_samples(variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9300 + variant
	var n: int = int(CUT_SECONDS * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev: float = 0.0
	var gate: float = 0.0
	for i: int in n:
		var t: float = float(i) / float(RATE)
		if rng.randf() < 0.02:
			gate = 1.0
		gate *= 0.93
		var noise: float = rng.randf_range(-1.0, 1.0)
		var hp: float = noise - prev
		prev = noise
		out[i] = clampf(hp * gate * exp(-t * 11.0) * 0.8 + 0.25 * sin(TAU * 420.0 * t) * exp(-t * 20.0), -1.0, 1.0)
	return out
