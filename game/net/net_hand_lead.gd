class_name NetHandLead
extends RefCounted
## Client-side cosmetic lead for the client's own weapon hand. The host steers the hand toward a goal that chases
## the aim at a limited speed (Fighter._arms), and the arm follows the goal with its own lag. The client runs the
## same goal from its local input every tick, plus a critically damped spring standing in for the arm, and keeps the
## modelled hand per input tick. The lead is the modelled hand now minus the modelled hand at the input the shown
## snapshot had applied (its ack): the part of the hand's move the host has not shown yet. It is zero whenever the
## aim has been still for one round trip, whatever the host did with the arm, and as the shown arm takes the move
## over, the lead shrinks by what the shown arm gains, so the hand starts moving the tick the mouse moves and nothing
## snaps when the host catches up. Visual only: the host stays authoritative and nothing here is sent.
## Pure: pelvis-relative goals, delta in.

const HISTORY: int = 120  ## input ticks kept (2 s: longer round trips just stop leading)

var goal: Vector3 = Vector3.ZERO  ## pelvis-relative hand goal for the newest input, the host's own maths
var arm: Vector3 = Vector3.ZERO  ## pelvis-relative modelled hand: a critically damped spring (NetConfig.HAND_LEAD_OMEGA) on `goal`
var arm_vel: Vector3 = Vector3.ZERO
var offset: Vector3 = Vector3.ZERO  ## the lead drawn this tick, world metres
var target: Vector3 = Vector3.ZERO  ## the lead `offset` follows (lightly smoothed over the ack's tick steps)
var _arms: Dictionary = {}  ## input tick -> modelled hand
var _have: bool = false
var _prev_arm: Vector3 = Vector3.ZERO
var _had_prev: bool = false
var _first: int = 0  ## input tick the history starts at (seeded from the shown hand target)


## One tick. `raw`: the unlimited hand goal for this tick's input (NetCursor.predict); `pelvis`: the shown pelvis;
## `host_target`: the shown snapshot's hand target (seeds the goal); `input_tick`: this tick's input index;
## `ack`: input index the shown snapshot had applied (-1 none); `fast`: SWING or THRUST held; `active`: the shown
## fighter steers its arms (standing, stumbling, getting up); `shown_move`: how far the shown (snapshot) hand moved
## since the last tick. Returns the lead to draw.
func step(raw: Vector3, pelvis: Vector3, host_target: Vector3, input_tick: int, ack: int, fast: bool, active: bool,
		delta: float, tun: Tuning, shown_move: Vector3 = Vector3.ZERO) -> Vector3:
	target = Vector3.ZERO
	if not active:
		_have = false
		_arms.clear()
	else:
		if not _have:
			goal = host_target - pelvis
			arm = goal
			arm_vel = Vector3.ZERO
			_have = true
			_first = input_tick
		var rate: float = tun.swing_hand_speed if fast else tun.guard_hand_speed
		goal = goal.move_toward(raw - pelvis, rate * delta)
		_spring(goal, NetConfig.HAND_LEAD_OMEGA, delta)
		_arms[input_tick] = arm
		_arms.erase(input_tick - HISTORY)
		# An ack from before the history (the start, or the arms came back after a fall) counts as its first
		# entry, so the lead grows from zero instead of appearing at once.
		var at: int = maxi(ack - NetConfig.HAND_LEAD_ACK_LAG, _first)
		if _arms.has(at):
			target = (arm - (_arms[at] as Vector3)).limit_length(NetConfig.HAND_LEAD_MAX)
	# What the modelled hand did this tick is a new command and shows at once; the rest of the way to `target` is the
	# host catching up (the ack moved on), smoothed over the ack's tick steps.
	var o: Vector3 = offset + (arm - _prev_arm if active and _had_prev else Vector3.ZERO)
	_prev_arm = arm
	_had_prev = active
	var next: Vector3 = o.lerp(target, _k(NetConfig.HAND_LEAD_SMOOTH_S, delta))
	if active and o.length_squared() > 1e-8:
		# Handing over: the lead may shrink along itself only as fast as the shown hand advances that way (plus a slow
		# release), so taking the lead back never pulls the drawn hand backward while the host's arm catches up.
		var d: Vector3 = o.normalized()
		var shrink: float = (o - next).dot(d)
		var allowed: float = maxf(shown_move.dot(d), 0.0) + o.length() * _k(NetConfig.HAND_LEAD_RELEASE_S, delta)
		if shrink > allowed:
			next += d * (shrink - allowed)
	next = next.limit_length(NetConfig.HAND_LEAD_MAX)
	offset = next
	return offset


## Exact critically damped step of `arm` toward a goal held still over `dt` (stable at any rate).
func _spring(g: Vector3, w: float, dt: float) -> void:
	var x0: Vector3 = arm - g
	var c: Vector3 = arm_vel + x0 * w
	var e: float = exp(-w * dt)
	arm = g + (x0 + c * dt) * e
	arm_vel = (arm_vel - c * (w * dt)) * e


static func _k(tau: float, delta: float) -> float:
	return 1.0 - exp(-delta / tau) if tau > 0.0 else 1.0


func reset() -> void:
	_have = false
	_arms.clear()
	_had_prev = false
	offset = Vector3.ZERO
	target = Vector3.ZERO


## The shortest rotation taking direction `u` to direction `v` (identity for tiny or zero vectors).
static func arc(u: Vector3, v: Vector3) -> Quaternion:
	if u.length_squared() < 1e-10 or v.length_squared() < 1e-10:
		return Quaternion.IDENTITY
	var a: Vector3 = u.normalized()
	var b: Vector3 = v.normalized()
	var c: Vector3 = a.cross(b)
	var d: float = a.dot(b)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var o: Vector3 = a.cross(Vector3.UP) if absf(a.y) < 0.9 else a.cross(Vector3.RIGHT)
		return Quaternion(o.normalized(), PI)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()


## Two-bone reach for a rigid arm: shoulder `s`, elbow `e`, hand `h`, wanted hand `want`. Keeps both bone lengths
## and the side the elbow bends to, and stops at full stretch or full fold. Returns [upper-arm turn about the shoulder,
## new elbow, forearm turn about the new elbow applied after the upper-arm turn].
static func two_bone(s: Vector3, e: Vector3, h: Vector3, want: Vector3) -> Array:
	var a: float = s.distance_to(e)
	var b: float = e.distance_to(h)
	var to: Vector3 = want - s
	if a < 1e-4 or b < 1e-4 or to.length_squared() < 1e-8:
		return [Quaternion.IDENTITY, e, Quaternion.IDENTITY]
	var dir: Vector3 = to.normalized()
	var d: float = clampf(to.length(), absf(a - b) + 0.002, a + b - 0.002)
	var hs: Vector3 = h - s
	var pole: Vector3 = (e - s) - hs.normalized() * (e - s).dot(hs.normalized()) if hs.length_squared() > 1e-8 else e - s
	var n: Vector3 = pole - dir * pole.dot(dir)
	if n.length_squared() < 1e-8:
		n = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
		if n.length_squared() < 1e-8:
			n = Vector3.FORWARD
	n = n.normalized()
	var x: float = (a * a - b * b + d * d) / (2.0 * d)
	var hh: float = sqrt(maxf(a * a - x * x, 0.0))
	var e2: Vector3 = s + dir * x + n * hh
	var q1: Quaternion = arc(e - s, e2 - s)
	var fore: Vector3 = Basis(q1) * (h - e)
	var q2: Quaternion = arc(fore, s + dir * d - e2)
	return [q1, e2, q2]
