class_name RollLogic
extends RefCounted
## Dodge roll timing for one fighter: when a roll may start (standing, enough stamina, off cooldown, on the press of
## ROLL), its direction, and the shape of the motion over time. The fighter turns these into physics: a tuck (legs
## folded, pelvis low), one turn of the body about the axis across the roll direction, and an opening back into the
## stance. Protection is limited to a glancing share of a blow's effective mass while tucked, never immunity.
## No nodes, no clock: `tick` takes delta.

const DIP_END: float = 0.3  ## share of the roll spent dipping (feet planted, legs folding, leaning in) before the tuck
const TUCK_IN: float = 0.4  ## share where the tuck has closed (knees to chest, body a ball on the sand)
const OPEN_START: float = 0.78  ## share where the body has come round and the legs open to land the feet
const LEAN_IN: float = 0.45  ## body lean into the roll (rad) by the end of the dip

var t: float = -1.0  ## time into the current roll, -1 = not rolling
var dir: Vector2 = Vector2(0.0, -1.0)  ## roll direction in the facing frame (x right, y forward), unit
var cooldown: float = 0.0
var _held: bool = false  ## ROLL was held last tick (a roll starts on the press, not the hold)
var leg_tuck: float = 0.0  ## leg tuck reached so far this roll (the feet do not come back down mid-turn)


## A roll may start: standing, not rolling, off cooldown, with at least `cost` stamina.
func can_start(standing: bool, stamina: float, cost: float) -> bool:
	return standing and t < 0.0 and cooldown <= 0.0 and stamina >= cost


## Reads this tick's ROLL button. Returns true when a roll should start now (press edge and can_start).
func press(held: bool, standing: bool, stamina: float, cost: float) -> bool:
	var edge: bool = held and not _held
	_held = held
	return edge and can_start(standing, stamina, cost)


## Starts a roll toward local direction `move` (x right, y forward); with no direction it rolls backward.
func start(move: Vector2) -> void:
	dir = move.normalized() if move.length() > 0.2 else Vector2(0.0, -1.0)
	t = 0.0
	leg_tuck = 0.0


## Advances the roll. `duration` and `cool` in seconds. Returns true on the tick the roll ends.
func tick(delta: float, duration: float, cool: float) -> bool:
	if t < 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
		return false
	t += delta
	if t >= duration:
		t = -1.0
		cooldown = cool
		return true
	return false


func active() -> bool:
	return t >= 0.0


## 0..1 through the roll (0 when not rolling).
func progress(duration: float) -> float:
	if t < 0.0:
		return 0.0
	return clampf(t / maxf(duration, 0.01), 0.0, 1.0)


## How far the body has turned over (0..TAU) at progress `u`: a lean of LEAN_IN while dipping (the shoulder goes
## toward the sand), then the rest of one eased turn from DIP_END to OPEN_START, then still.
static func spin(u: float) -> float:
	if u < DIP_END:
		return LEAN_IN * smoothstep(0.0, DIP_END, u)
	var k: float = clampf((u - DIP_END) / (OPEN_START - DIP_END), 0.0, 1.0)
	return LEAN_IN + (TAU - LEAN_IN) * _turn(k)


## Rate of spin() (rad/s) at progress `u` for a roll lasting `duration` seconds.
static func spin_rate(u: float, duration: float) -> float:
	var d: float = maxf(duration, 0.01)
	if u <= 0.0 or u >= OPEN_START:
		return 0.0
	if u < DIP_END:
		var x: float = u / DIP_END
		return LEAN_IN * 6.0 * x * (1.0 - x) / (DIP_END * d)
	var span: float = OPEN_START - DIP_END
	var k: float = (u - DIP_END) / span
	return (TAU - LEAN_IN) * (0.5 + 3.0 * k * (1.0 - k)) / (span * d)


## Share 0..1 of the turn at `k` (0..1): half even rate, half eased, so the rate peaks at 1.25x its mean instead of
## 1.5x (a fast peak throws the tucked legs straight).
static func _turn(k: float) -> float:
	return 0.5 * k + 0.5 * k * k * (3.0 - 2.0 * k)


## Dip amount 0..1 at progress `u`: the legs fold (feet still planted) while leaning in, held through the turn, and
## straightened back into the stance at the end.
static func dip(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < OPEN_START:
		return smoothstep(0.0, DIP_END, u)
	return 1.0 - smoothstep(OPEN_START, 0.95, u)


## Tuck amount 0..1 at progress `u`: none while dipping (the legs stand on the sand), closes after the dip, holds
## through the turn, opens fast at the end so the feet come down under the hips.
static func tuck(u: float) -> float:
	if u <= DIP_END or u >= 1.0:
		return 0.0
	if u < TUCK_IN:
		return smoothstep(DIP_END, TUCK_IN, u)
	if u < OPEN_START:
		return 1.0
	return 1.0 - smoothstep(OPEN_START, 0.88, u)


## Speed share 0..1 along the roll at progress `u`: none while dipping (the feet are planted), the push off the tuck, carried
## through the turn, easing out as the feet land.
static func drive(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < DIP_END:
		return 0.0
	if u < TUCK_IN:
		return smoothstep(DIP_END, TUCK_IN, u)
	if u < OPEN_START:
		return 1.0
	return 1.0 - smoothstep(OPEN_START, 1.0, u)


## True when progress passes `mark` during the tick that just ran (t is the time after it).
static func crossed(t_now: float, delta: float, duration: float, mark: float) -> bool:
	var d: float = maxf(duration, 0.01)
	return t_now >= 0.0 and (t_now - delta) / d < mark and t_now / d >= mark


## Leg tuck for this tick from the wanted amount `want` (the body tuck held back until the body is low): once the
## legs have tucked they stay tucked through the turn, and at the opening they follow the body tuck `tk` out.
func hold_leg_tuck(want: float, u: float, tk: float) -> float:
	if t < 0.0:
		leg_tuck = 0.0
		return 0.0
	if u >= OPEN_START:
		leg_tuck = minf(leg_tuck, tk)
		return leg_tuck
	leg_tuck = maxf(leg_tuck, want)
	return leg_tuck


## Share of an incoming blow's effective mass at progress `u`: `guard` inside [g0, g1] while rolling, else 1.
static func guard_scale(rolling: bool, u: float, guard: float, g0: float, g1: float) -> float:
	if not rolling or u < g0 or u > g1:
		return 1.0
	return clampf(guard, 0.0, 1.0)


## World axis the body turns about for a roll along world direction `d` (the top of the body goes toward `d`),
## tipped about `d` by `shoulder` rad so the turn runs diagonally over one shoulder instead of straight over the head.
static func axis(d: Vector3, shoulder: float = 0.0) -> Vector3:
	var h := Vector3(d.x, 0.0, d.z)
	var a: Vector3 = Vector3.UP.cross(h)
	if a.length_squared() <= 0.000001:
		return Vector3.RIGHT
	a = a.normalized()
	return a.rotated(h.normalized(), shoulder) if shoulder != 0.0 else a


## Which way the turn axis tips for a roll toward local `d` (x right): mirrored for right and left rolls, so each
## goes over its leading shoulder.
static func shoulder_side(d: Vector2) -> float:
	return -1.0 if d.x > 0.0 else 1.0


func to_array() -> Array:
	return [t, dir, cooldown, _held, leg_tuck]


func from_array(a: Array) -> void:
	if a.size() < 4:
		t = -1.0
		cooldown = 0.0
		_held = false
		leg_tuck = 0.0
		return
	t = float(a[0])
	dir = a[1]
	cooldown = float(a[2])
	_held = bool(a[3])
	leg_tuck = float(a[4]) if a.size() > 4 else 0.0
