class_name LaserHumLogic
extends RefCounted
## Pure maths for the laser sword's hum: pitch and level follow the blade's speed (the classic Doppler-like swing
## swell), smoothed so the pitch glides instead of stepping. Presentation only. Unit-tested in test_laser_synth.gd.

const PITCH_IDLE: float = 0.85
const PITCH_MAX: float = 1.7
const PITCH_PER_MPS: float = 0.045
const GAIN_IDLE_DB: float = -26.0
const GAIN_FAST_DB: float = -8.0
const FAST_SPEED: float = 14.0
const GLIDE_PER_S: float = 6.0


## Target pitch scale for a blade moving at `speed` m/s.
static func pitch_for(speed: float) -> float:
	return clampf(PITCH_IDLE + PITCH_PER_MPS * maxf(speed, 0.0), PITCH_IDLE, PITCH_MAX)


## Hum level in dB: quiet at rest, loud in a fast swing.
static func gain_db_for(speed: float) -> float:
	return lerpf(GAIN_IDLE_DB, GAIN_FAST_DB, clampf(speed / FAST_SPEED, 0.0, 1.0))


## One smoothing step toward `target` (exponential glide).
static func glide(current: float, target: float, delta: float) -> float:
	return lerpf(current, target, clampf(GLIDE_PER_S * maxf(delta, 0.0), 0.0, 1.0))
