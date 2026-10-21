class_name CameraShake
extends RefCounted
## Pure camera impact state: a spring-driven kick toward the blow, a decaying high-frequency shake and roll, and a
## field-of-view punch. `update(delta)` returns the offsets to add on top of the framed pose. Deterministic: the shake
## is a sum of sines driven by a phase, no random numbers. Unit-tested in test_camera_shake.gd.

const ZETA: float = 0.45  ## kick spring damping ratio
const SHAKE_HZ_A: float = 31.0
const SHAKE_HZ_B: float = 47.0
const SHAKE_HZ_C: float = 23.0
const KICK_SPEED_MULT: float = 1.6  ## initial speed factor; the spring amplitude is set by `kick_m`
const MAX_KICK_M: float = 0.5
const MAX_SHAKE: float = 1.0
const MAX_PUNCH_DEG: float = 20.0
const EPS: float = 0.0005

var kick: Vector3 = Vector3.ZERO
var kick_vel: Vector3 = Vector3.ZERO
var shake: float = 0.0  ## 0..1 trauma; displacement scales with its square
var punch_deg: float = 0.0
var _phase: float = 0.0
var _freq: float = 16.0
var _decay: float = 7.0
var _punch_decay: float = 5.0
var _shake_m: float = 0.035
var _roll_deg: float = 1.6


## Adds a blow. `strength` 0..1 (already scaled by impact and the master scale), `dir` the world direction it travelled.
func add_hit(dir: Vector3, strength: float, tun: Tuning, motion_scale: float) -> void:
	var s: float = clampf(strength, 0.0, 1.0) * maxf(motion_scale, 0.0)
	if s <= 0.0:
		return
	_freq = tun.feel_kick_freq
	_decay = tun.feel_shake_decay
	_punch_decay = tun.feel_zoom_decay
	_shake_m = tun.feel_shake_m
	_roll_deg = tun.feel_shake_roll_deg
	if dir.length() > 0.001:
		# A displacement x0 on a spring of stiffness w starts with velocity w*x0 so the first swing reaches ~x0.
		var amp: float = minf(tun.feel_kick_m * s, MAX_KICK_M)
		kick_vel += dir.normalized() * amp * _freq * KICK_SPEED_MULT
	shake = minf(shake + s, MAX_SHAKE)
	punch_deg = minf(punch_deg + tun.feel_zoom_hit_deg * s, MAX_PUNCH_DEG)


## Zoom punch for a finisher: field of view narrows by `deg * strength` then relaxes.
func add_zoom(deg: float, strength: float, tun: Tuning, motion_scale: float) -> void:
	var s: float = clampf(strength, 0.0, 1.0) * maxf(motion_scale, 0.0)
	if s <= 0.0:
		return
	_punch_decay = tun.feel_zoom_decay
	punch_deg = minf(punch_deg + deg * s, MAX_PUNCH_DEG)


func is_idle() -> bool:
	return shake < EPS and punch_deg < EPS and kick.length() < EPS and kick_vel.length() < EPS


func clear() -> void:
	kick = Vector3.ZERO
	kick_vel = Vector3.ZERO
	shake = 0.0
	punch_deg = 0.0


## Advances by `delta`; returns {"offset": Vector3 world metres (the kick),
## "jitter": Vector3 camera-local metres (the shake), "roll": radians, "fov": degrees to subtract}.
func update(delta: float) -> Dictionary:
	var d: float = clampf(delta, 0.0, 0.1)
	if is_idle():
		return {"offset": Vector3.ZERO, "jitter": Vector3.ZERO, "roll": 0.0, "fov": 0.0}
	# Semi-implicit damped spring toward zero.
	var acc: Vector3 = -kick * _freq * _freq - kick_vel * (2.0 * ZETA * _freq)
	kick_vel += acc * d
	kick += kick_vel * d
	_phase += d
	var tr: float = shake * shake
	var jitter: Vector3 = Vector3(
			sin(_phase * SHAKE_HZ_A * TAU) + 0.5 * sin(_phase * SHAKE_HZ_B * TAU + 1.3),
			sin(_phase * SHAKE_HZ_B * TAU + 0.7) + 0.5 * sin(_phase * SHAKE_HZ_C * TAU),
			0.0) * (0.66 * tr * _shake_m)
	var roll: float = deg_to_rad(_roll_deg) * tr * sin(_phase * SHAKE_HZ_C * TAU + 2.1)
	shake = maxf(shake - shake * _decay * d - 0.02 * d, 0.0)
	punch_deg = maxf(punch_deg - punch_deg * _punch_decay * d - 0.05 * d, 0.0)
	if shake < EPS:
		shake = 0.0
	if punch_deg < EPS:
		punch_deg = 0.0
	if kick.length() < EPS and kick_vel.length() < EPS:
		kick = Vector3.ZERO
		kick_vel = Vector3.ZERO
	return {"offset": kick, "jitter": jitter, "roll": roll, "fov": punch_deg}
