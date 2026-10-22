class_name AimLogic
extends RefCounted
## Pure maths for the player's aim aid: a short world-space trail of the weapon tip, the screen-edge marker for an
## off-screen point, the nearest loose weapon, the weapon-lost timer and the pickup wording per device.
## Presentation only, local only: nothing here touches fight state or goes online.

## (position, age) samples of a point, newest last. Dropped once older than `max_age`.
var _pts: Array[Vector3] = []
var _ages: Array[float] = []
var max_age: float = 0.3
var max_samples: int = 24


func count() -> int:
	return _pts.size()


func point(i: int) -> Vector3:
	return _pts[i]


## Age as a fraction of max_age: 0 for the newest sample, 1 at the end of life.
func age_frac(i: int) -> float:
	return clampf(_ages[i] / maxf(max_age, 0.001), 0.0, 1.0)


func clear() -> void:
	_pts.clear()
	_ages.clear()


## Ages the samples by `delta`, drops the old ones and records `p` (a jump of more than `jump` m restarts the trail).
func push(p: Vector3, delta: float, jump: float = 2.0) -> void:
	for i: int in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[0] > max_age:
		_ages.remove_at(0)
		_pts.remove_at(0)
	if not _pts.is_empty() and _pts[_pts.size() - 1].distance_to(p) > jump:
		clear()
	_pts.append(p)
	_ages.append(0.0)
	while _pts.size() > max_samples:
		_pts.remove_at(0)
		_ages.remove_at(0)


## Where to draw a marker for a point that projects to `p` (screen units). `behind` is true when the point is behind
## the camera (the projection is then mirrored, so it is flipped). Returns {on_screen, pos, angle}: on screen the
## marker sits at the point; off screen it sits on the rectangle inset by `margin`, and `angle` points from the
## centre toward the target (radians, 0 = right, y down).
static func edge_marker(p: Vector2, behind: bool, vp: Vector2, margin: float) -> Dictionary:
	var c: Vector2 = vp * 0.5
	var q: Vector2 = p
	if behind:
		q = c - (p - c)
		if q.is_equal_approx(c):
			q = c + Vector2(0.0, vp.y)  # straight behind: point down, toward the player's feet
	var inside: bool = not behind and q.x >= margin and q.x <= vp.x - margin and q.y >= margin and q.y <= vp.y - margin
	var dir: Vector2 = q - c
	if inside:
		return {"on_screen": true, "pos": q, "angle": dir.angle()}
	if dir.length() < 0.001:
		dir = Vector2.DOWN
	var half: Vector2 = c - Vector2(margin, margin)
	var s: float = minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	return {"on_screen": false, "pos": c + dir * s, "angle": dir.angle()}


## Index of the point nearest `from`, or -1 for none.
static func nearest(from: Vector3, points: Array) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in points.size():
		var d: float = from.distance_squared_to(points[i] as Vector3)
		if d < best_d:
			best_d = d
			best = i
	return best


## Seconds the fighter has been without its weapon: counts up while disarmed after having held one, else 0.
static func lost_time(prev: float, was_armed: bool, armed: bool, delta: float) -> float:
	if armed or not was_armed and prev <= 0.0:
		return 0.0
	return prev + delta


static func prompt_due(lost_s: float, delay_s: float, alive: bool) -> bool:
	return alive and lost_s > 0.0 and lost_s >= delay_s


## The pickup key or button name for a device: "touch", "pad" or anything else (keyboard).
static func grab_key(device: String) -> String:
	match device:
		"touch":
			return "GRAB"
		"pad":
			return "A"
	return "E"


## Second prompt line: how to pick the weapon up on a device.
static func pickup_hint(device: String) -> String:
	match device:
		"touch":
			return "Walk to it and tap GRAB"
		"pad":
			return "Walk to it and press A (hold B to bend down)"
	return "Walk to it and press E (hold Ctrl + E to bend down)"
