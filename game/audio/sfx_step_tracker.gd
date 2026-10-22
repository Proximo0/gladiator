class_name SfxStepTracker
extends RefCounted
## Footsteps from distance travelled (a step every stride) or from explicit foot-contact edges when the fighter
## reports them. `update` returns 0 for nothing, -1 for a left step and 1 for a right step.

const MIN_SPEED: float = 0.4
const STRIDE_BASE: float = 0.62
const STRIDE_PER_SPEED: float = 0.1
const STRIDE_MAX: float = 1.3

var travelled: float = 0.0
var next_side: int = -1
var prev_l: bool = false
var prev_r: bool = false


static func stride_for(speed: float) -> float:
	return minf(STRIDE_MAX, STRIDE_BASE + STRIDE_PER_SPEED * speed)


## Step from ground speed (m/s) over `delta`; `grounded` false (falling, down) pauses and resets.
func update(speed: float, delta: float, grounded: bool) -> int:
	if not grounded or speed < MIN_SPEED:
		travelled = minf(travelled, stride_for(speed) * 0.5)
		return 0
	travelled += speed * delta
	var stride: float = stride_for(speed)
	if travelled < stride:
		return 0
	travelled -= stride
	var s: int = next_side
	next_side = -s
	return s


## Step from the gait's own cadence (steps per second): the sound keeps time with the legs at any speed.
func update_cadence(cadence: float, speed: float, delta: float, grounded: bool) -> int:
	if not grounded or speed < MIN_SPEED:
		travelled = minf(travelled, 0.5)
		return 0
	travelled += cadence * delta
	if travelled < 1.0:
		return 0
	travelled -= 1.0
	var s: int = next_side
	next_side = -s
	return s


## Step from foot-contact booleans: a foot touching down this tick (false -> true) is a step.
func update_contacts(left: bool, right: bool) -> int:
	var out: int = 0
	if left and not prev_l:
		out = -1
	elif right and not prev_r:
		out = 1
	prev_l = left
	prev_r = right
	return out
