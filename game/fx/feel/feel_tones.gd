class_name FeelTones
extends RefCounted
## Procedural low-end for impact feel, built once in code (no asset): a short sub-bass thump under heavy hits and a
## long bass drop for a finisher, a sine sweeping down in pitch with a fast attack, a soft-clip drive for body and
## an exponential decay. Pure sample maths plus a wrapper to AudioStreamWAV. Unit-tested in test_feel_tones.gd.

const RATE: int = 22050
const ATTACK_S: float = 0.004


## Mono samples in -1..1: a sine sweeping from `f0` to `f1` Hz over `dur` s, decaying with time constant `decay` s,
## soft-clipped by `drive` (1 = clean).
static func sweep(f0: float, f1: float, dur: float, decay: float, drive: float, rate: int = RATE) -> PackedFloat32Array:
	var n: int = maxi(int(dur * float(rate)), 1)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	var norm: float = tanh(maxf(drive, 0.01))
	for i: int in n:
		var t: float = float(i) / float(rate)
		var k: float = t / maxf(dur, 0.0001)
		var f: float = f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), k)  # exponential sweep sounds even
		phase += TAU * f / float(rate)
		var env: float = minf(t / ATTACK_S, 1.0) * exp(-t / maxf(decay, 0.001))
		var tail: float = clampf((1.0 - k) / 0.1, 0.0, 1.0)  # fade the last 10 percent so it never clicks
		out[i] = tanh(sin(phase) * maxf(drive, 0.01)) / norm * env * tail
	return out


## The finisher's bass drop: 72 Hz falling to 34 Hz over 1.4 s, driven.
static func finisher_samples() -> PackedFloat32Array:
	return sweep(72.0, 34.0, 1.4, 0.45, 2.2)


## The heavy-hit thump: 95 Hz falling to 48 Hz, 0.22 s.
static func thump_samples() -> PackedFloat32Array:
	return sweep(95.0, 48.0, 0.22, 0.07, 1.6)


## 16-bit mono AudioStreamWAV for `samples`.
static func to_wav(samples: PackedFloat32Array, rate: int = RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
