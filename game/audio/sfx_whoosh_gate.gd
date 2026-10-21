class_name SfxWhooshGate
extends RefCounted
## Decides when a swing earns a whoosh. Fires on the rising edge through the minimum speed, with a cooldown,
## and returns the predicted peak speed (current speed plus a short look-ahead on its acceleration) so the sound
## is chosen for the swing that is coming, not the speed at the edge.

const COOLDOWN: float = 0.32
const LOOKAHEAD: float = 0.09
const MAX_SPEED: float = 26.0
const REARM_FRACTION: float = 0.75

var prev_speed: float = 0.0
var last_time: float = -100.0
var armed: bool = true


## Returns the predicted peak speed when a whoosh should start now, else 0.
func update(speed: float, delta: float, now: float) -> float:
	var accel: float = (speed - prev_speed) / maxf(delta, 0.0001)
	prev_speed = speed
	if speed < SfxLogic.WHOOSH_MIN_SPEED * REARM_FRACTION:
		armed = true
		return 0.0
	if not armed or speed < SfxLogic.WHOOSH_MIN_SPEED or now - last_time < COOLDOWN:
		return 0.0
	armed = false
	last_time = now
	return clampf(speed + maxf(accel, 0.0) * LOOKAHEAD, speed, MAX_SPEED)
