class_name FinisherCine
extends RefCounted
## Timeline of a finisher's cinematic, in real seconds from the killing blow. A behead, gut or run through gets the
## deep slow motion (`feel_cine_scale`, held `feel_cine_hold_s`, eased back over `feel_cine_ramp_s`), the muffled
## crowd and effects that open up again as time returns, and a crowd roar at that release. Any other match end with
## slow motion (skull crush, knock-out) keeps the plain `match_slowmo_*` step. Match drives Engine.time_scale from
## `time_scale_at` on the host (online clients mirror it from the snapshot); the presenter side (FeelDirector) runs
## the same timeline for sound and screen. Pure. Unit-tested in test_finisher_cine.gd.

const CINE_KINDS: PackedStringArray = ["behead", "gut", "run_through"]
const ROAR_LEAD_S: float = 0.08  ## the roar starts just before time comes back, so its attack lands on the release


static func is_cine(kind: String) -> bool:
	return CINE_KINDS.has(kind)


## Total slow-motion length, real s.
static func length_s(kind: String, tun: Tuning) -> float:
	if is_cine(kind):
		return maxf(tun.feel_cine_hold_s, 0.0) + maxf(tun.feel_cine_ramp_s, 0.0)
	return maxf(tun.match_slowmo_s, 0.0)


## Engine time scale `t` real seconds after the blow.
static func time_scale_at(kind: String, t: float, tun: Tuning) -> float:
	if t < 0.0:
		return 1.0
	if not is_cine(kind):
		return clampf(tun.match_slowmo_scale, 0.05, 1.0) if t < tun.match_slowmo_s else 1.0
	var low: float = clampf(tun.feel_cine_scale, 0.05, 1.0)
	if t < tun.feel_cine_hold_s:
		return low
	var r: float = (t - tun.feel_cine_hold_s) / maxf(tun.feel_cine_ramp_s, 0.001)
	if r >= 1.0:
		return 1.0
	return lerpf(low, 1.0, smoothstep(0.0, 1.0, r))


## 0..1 depth of the muffle (low-pass on crowd and effects): full through the hold, opening over the ramp.
static func muffle_at(kind: String, t: float, tun: Tuning) -> float:
	if not is_cine(kind) or t < 0.0:
		return 0.0
	if t < tun.feel_cine_hold_s:
		return clampf(t / 0.05, 0.0, 1.0)  # a 50 ms slide in, so the cut is not a click
	var r: float = (t - tun.feel_cine_hold_s) / maxf(tun.feel_cine_ramp_s * 0.6, 0.001)
	return clampf(1.0 - r, 0.0, 1.0)


## Low-pass cutoff for a muffle depth (exponential between `feel_cine_lpf_hz` and open, 20 kHz).
static func cutoff_hz(depth: float, tun: Tuning) -> float:
	var lo: float = clampf(tun.feel_cine_lpf_hz, 50.0, 20000.0)
	return lo * pow(20000.0 / lo, 1.0 - clampf(depth, 0.0, 1.0))


## When the crowd roar fires, real s after the blow (-1 for none).
static func roar_at(kind: String, tun: Tuning) -> float:
	if not is_cine(kind):
		return -1.0
	return maxf(tun.feel_cine_hold_s - ROAR_LEAD_S, 0.0)


## 0..1 cinematic vignette and desaturation on screen: in with the blow, out with the ramp.
static func grade_at(kind: String, t: float, tun: Tuning) -> float:
	if not is_cine(kind) or t < 0.0:
		return 0.0
	var total: float = length_s(kind, tun)
	if t >= total:
		return 0.0
	var fade_in: float = clampf(t / 0.12, 0.0, 1.0)
	if t < tun.feel_cine_hold_s:
		return fade_in
	return fade_in * (1.0 - smoothstep(0.0, 1.0, (t - tun.feel_cine_hold_s) / maxf(tun.feel_cine_ramp_s, 0.001)))
