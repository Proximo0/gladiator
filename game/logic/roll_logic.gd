class_name RollLogic
extends RefCounted
## Dodge roll timing for one fighter: when a roll may start (standing, enough stamina, off cooldown, on the press of
## ROLL), its direction, and the shape of the motion over time. The fighter turns these into physics: a tuck (legs
## folded, pelvis low), one turn of the body about the axis across the roll direction, and an opening back into the
## stance. Protection is limited to a glancing share of a blow's effective mass while tucked, never immunity.
## No nodes, no clock: `tick` takes delta.

const TUCK_END: float = 0.3  ## share of the roll spent tucking down before the body turns over
const OPEN_START: float = 0.78  ## share of the roll where the body has come round and opens into the stance

var t: float = -1.0  ## time into the current roll, -1 = not rolling
var dir: Vector2 = Vector2(0.0, -1.0)  ## roll direction in the facing frame (x right, y forward), unit
var cooldown: float = 0.0
var _held: bool = false  ## ROLL was held last tick (a roll starts on the press, not the hold)


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


## How far the body has turned over (0..TAU) at progress `u`: still while tucking, an eased full turn, then still.
static func spin(u: float) -> float:
	var k: float = clampf((u - TUCK_END) / (OPEN_START - TUCK_END), 0.0, 1.0)
	return TAU * k * k * (3.0 - 2.0 * k)


## Rate of spin() (rad/s) at progress `u` for a roll lasting `duration` seconds.
static func spin_rate(u: float, duration: float) -> float:
	var span: float = OPEN_START - TUCK_END
	var k: float = (u - TUCK_END) / span
	if k <= 0.0 or k >= 1.0:
		return 0.0
	return TAU * 6.0 * k * (1.0 - k) / (span * maxf(duration, 0.01))


## Tuck amount 0..1 at progress `u`: folds in fast, holds through the turn, unfolds at the end.
static func tuck(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < TUCK_END:
		return smoothstep(0.0, TUCK_END, u)
	if u < OPEN_START:
		return 1.0
	return 1.0 - smoothstep(OPEN_START, 1.0, u)


## Speed share 0..1 along the roll at progress `u`: a push off the tuck, carried through the turn, easing out.
static func drive(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < TUCK_END:
		return 0.6 + 0.4 * u / TUCK_END
	if u < OPEN_START:
		return 1.0
	return 1.0 - smoothstep(OPEN_START, 1.0, u)


## Share of an incoming blow's effective mass at progress `u`: `guard` inside [g0, g1] while rolling, else 1.
static func guard_scale(rolling: bool, u: float, guard: float, g0: float, g1: float) -> float:
	if not rolling or u < g0 or u > g1:
		return 1.0
	return clampf(guard, 0.0, 1.0)


## World axis the body turns about for a roll along world direction `d` (the top of the body goes toward `d`).
static func axis(d: Vector3) -> Vector3:
	var a: Vector3 = Vector3.UP.cross(Vector3(d.x, 0.0, d.z))
	return a.normalized() if a.length_squared() > 0.000001 else Vector3.RIGHT


func to_array() -> Array:
	return [t, dir, cooldown, _held]


func from_array(a: Array) -> void:
	if a.size() < 4:
		t = -1.0
		cooldown = 0.0
		_held = false
		return
	t = float(a[0])
	dir = a[1]
	cooldown = float(a[2])
	_held = bool(a[3])
