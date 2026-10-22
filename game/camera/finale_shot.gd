class_name FinaleShot
extends RefCounted
## Cinematic hold for a finisher or a death: the look point eases to a held point near the victim (not the flung
## pelvis), the camera takes a low side-on three-quarter framing from the arena side, holds, then hands back to the
## normal framing. Pure maths; the FightCamera blends its normal pose toward `pos()`/`look()` by `weight`.
## Presentation only: it never reads or writes fight state.

var active: bool = false
var weight: float = 0.0  ## 0 = normal camera, 1 = full finale shot
var _age: float = 0.0
var _hold_s: float = 3.0
var _ease_s: float = 0.6
var _release_s: float = 1.5
var _point: Vector3 = Vector3.ZERO  ## held look point
var _side: Vector3 = Vector3.RIGHT  ## unit ground direction from the point to the camera
var _dist: float = 3.6
var _height: float = 1.1
const NO_HEAD: Vector3 = Vector3(INF, INF, INF)  ## "no severed head to track"
var _arena_r: float = 0.0  ## arena radius for the wall checks (0 = unknown, no checks)
var _wall_margin: float = 0.7
var _high: bool = false  ## the high 3/4 fallback is in use (no side-on angle fits inside the wall)
var _head: Vector3 = NO_HEAD  ## clamped severed-head position, or NO_HEAD
var _head_t: float = 0.0  ## seconds since the head came free
var _bias0: float = 0.2
var _bias1: float = 0.65
var _bias_s: float = 2.0
var _reach: float = 5.0
var _dist_max: float = 7.5
var _high_h: float = 3.2
var _look_y: float = 0.8  ## held look height for a standing victim
var _look_low: float = 0.35  ## lowest the look point sinks to as the victim goes down
var _head_hold_s: float = 2.5
var _reaim_rate: float = 2.5


## Unit ground vector perpendicular to the blow line (attacker -> victim), pointing to the side nearer the arena centre
## so the camera does not end up against the wall.
static func side_dir(attacker: Vector3, victim: Vector3) -> Vector3:
	var f := Vector3(victim.x - attacker.x, 0.0, victim.z - attacker.z)
	if f.length() < 0.001:
		f = Vector3(0.0, 0.0, -1.0)
	f = f.normalized()
	var s: Vector3 = f.cross(Vector3.UP).normalized()
	var a: float = Vector2(victim.x + s.x, victim.z + s.z).length()
	var b: float = Vector2(victim.x - s.x, victim.z - s.z).length()
	return s if a <= b else -s


## Pulls a point on the ground plane inside `arena_r - margin` of the arena centre (height is kept).
static func inside_wall(p: Vector3, arena_r: float, margin: float) -> Vector3:
	if arena_r <= 0.0:
		return p
	var lim: float = maxf(arena_r - margin, 0.5)
	var flat := Vector2(p.x, p.z)
	if flat.length() <= lim:
		return p
	flat = flat.normalized() * lim
	return Vector3(flat.x, p.y, flat.y)


## The camera's view of `point`: {"dir": unit ground direction from the point to the camera, "high": bool}. Side-on
## (perpendicular to the blow line) from whichever side keeps a camera at `dist` inside the wall with the most room;
## when neither side fits, a high 3/4 view from the arena-interior side (`high` true).
static func choose_view(attacker: Vector3, point: Vector3, dist: float, arena_r: float, margin: float) -> Dictionary:
	var s: Vector3 = side_dir(attacker, point)
	if arena_r <= 0.0:
		return {"dir": s, "high": false}
	var lim: float = maxf(arena_r - margin, 0.5)
	var best: Vector3 = s
	var best_room: float = -INF
	for cand: Vector3 in [s, -s]:
		var room: float = lim - Vector2(point.x + cand.x * dist, point.z + cand.z * dist).length()
		if room > best_room:
			best_room = room
			best = cand
	if best_room >= 0.0:
		return {"dir": best, "high": false}
	var inward := Vector3(-point.x, 0.0, -point.z)
	if inward.length() < 0.5:
		return {"dir": best, "high": true}
	return {"dir": (inward.normalized() * 0.65 + best * 0.35).normalized(), "high": true}


## Share (0..1) of the look point that sits on the head: starts at `b0` (the fountain at the neck), eases to `b1` over `over_s`.
static func head_bias(t: float, b0: float, b1: float, over_s: float) -> float:
	return lerpf(b0, b1, ease01(t / maxf(over_s, 0.001)))


## The head position limited to `reach` metres from `body` (a head flung far must not drag the framing out).
static func clamp_head(body: Vector3, head: Vector3, reach: float) -> Vector3:
	var d: Vector3 = head - body
	if d.length() <= reach or d.length() < 0.0001:
		return head
	return body + d.normalized() * reach


## Camera distance for a body and head `sep` metres apart (ground): grows with the gap, never under `base` or over `dmax`.
static func framing_dist(base: float, sep: float, dmax: float) -> float:
	return clampf(base + 0.6 * maxf(sep, 0.0), base, maxf(dmax, base))


## Smoothstep ease of a 0..1 progress.
static func ease01(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Weight at `age` seconds: eases in over `ease_s`, holds until `hold_s`, eases out over `release_s`.
static func weight_at(age: float, ease_s: float, hold_s: float, release_s: float) -> float:
	if age < 0.0:
		return 0.0
	if age < ease_s:
		return ease01(age / maxf(ease_s, 0.001))
	if age < hold_s:
		return 1.0
	return 1.0 - ease01((age - hold_s) / maxf(release_s, 0.001))


## The point to hold: the victim's ground position raised to chest height (a falling pelvis would drag it about).
static func hold_point(victim: Vector3, hit: Vector3, chest_y: float) -> Vector3:
	var p: Vector3 = victim.lerp(hit, 0.35) if is_finite(hit.x) and is_finite(hit.y) and is_finite(hit.z) else victim
	return Vector3(p.x, chest_y, p.z)


func start(attacker: Vector3, victim: Vector3, hit: Vector3, tun: Tuning, arena_r: float = 0.0, wall_margin: float = 0.7) -> void:
	_hold_s = tun.feel_finale_hold_s
	_ease_s = tun.feel_finale_ease_s
	_release_s = tun.feel_finale_release_s
	_dist = tun.feel_finale_dist
	_height = tun.feel_finale_height
	_arena_r = arena_r
	_wall_margin = wall_margin
	_bias0 = tun.feel_finale_head_bias0
	_bias1 = tun.feel_finale_head_bias1
	_bias_s = tun.feel_finale_head_s
	_reach = tun.feel_finale_head_reach
	_dist_max = tun.feel_finale_dist_max
	_high_h = tun.feel_finale_high
	_look_y = tun.feel_finale_look_y
	_look_low = minf(FightCamera.tuned(tun, "feel_finale_look_low", 0.35), _look_y)
	_head_hold_s = FightCamera.tuned(tun, "feel_finale_head_hold_s", 2.5)
	_reaim_rate = FightCamera.tuned(tun, "feel_finale_reaim_rate", 2.5)
	_head = NO_HEAD
	_head_t = 0.0
	_point = inside_wall(hold_point(victim, hit, tun.feel_finale_look_y), arena_r, wall_margin)
	var view: Dictionary = choose_view(attacker, _point, _dist, arena_r, wall_margin)
	_side = view["dir"]
	_high = bool(view["high"])
	_age = 0.0
	active = true
	weight = 0.0


## Age on the ease-in curve whose weight is `w` (inverse of the smoothstep, bisected).
static func ease_age_for(w: float, ease_s: float) -> float:
	var lo: float = 0.0
	var hi: float = 1.0
	var target: float = clampf(w, 0.0, 1.0)
	for _i: int in 16:
		var m: float = (lo + hi) * 0.5
		if ease01(m) < target:
			lo = m
		else:
			hi = m
	return hi * maxf(ease_s, 0.0)


## Ground side direction for filming a body at `body` and its head at `head` side-on to the line between them: the
## perpendicular nearest `current`. Returns `current` while they are under 0.4 m apart (no line yet).
static func head_side(body: Vector3, head: Vector3, current: Vector3) -> Vector3:
	var line := Vector3(head.x - body.x, 0.0, head.z - body.z)
	if line.length() < 0.4:
		return current
	var s: Vector3 = line.normalized().cross(Vector3.UP)
	return s if s.dot(current) >= 0.0 else -s


## Turns the unit ground vector `from` toward `to` by at most `max_rad` radians.
static func turn_toward(from: Vector3, to: Vector3, max_rad: float) -> Vector3:
	var a0: float = atan2(from.x, from.z)
	var da: float = wrapf(atan2(to.x, to.z) - a0, -PI, PI)
	var a: float = a0 + clampf(da, -max_rad, max_rad)
	return Vector3(sin(a), 0.0, cos(a))


## The victim's head came free after the shot began, or after it ended: re-aim on the body and head. The weight
## rises again from where it is (no cut), and the hold runs at least `head_hold_s` from now. `victim` is the body's
## current position (used when the shot had already ended).
func head_free(victim: Vector3) -> void:
	var t0: float = 0.0
	if active:
		t0 = _age if _age < _ease_s else ease_age_for(weight, _ease_s)
		_hold_s = maxf(_hold_s - _age + t0, maxf(t0, _ease_s) + _head_hold_s)
	else:
		if is_finite(victim.x) and is_finite(victim.z):
			_point = inside_wall(Vector3(victim.x, _point.y, victim.z), _arena_r, _wall_margin)
		_hold_s = _ease_s + _head_hold_s
		active = true
	_age = t0
	_head_t = 0.0
	weight = weight_at(_age, _ease_s, _hold_s, _release_s)


func clear() -> void:
	active = false
	weight = 0.0
	_age = 0.0


## Advances by `delta`. While easing in or holding, the held point creeps toward the victim's flat position (slowly,
## so a ragdoll sliding to rest is followed but its flailing is not).
## `head` is the severed head's position once it is free (else NO_HEAD).
func update(delta: float, victim: Vector3, head: Vector3 = NO_HEAD) -> void:
	if not active:
		return
	_age += maxf(delta, 0.0)
	if is_finite(victim.x) and is_finite(victim.z):
		var k: float = 1.0 - exp(-0.8 * maxf(delta, 0.0))
		var np: Vector3 = inside_wall(Vector3(victim.x, _point.y, victim.z), _arena_r, _wall_margin)
		_point.x = lerpf(_point.x, np.x, k)
		_point.z = lerpf(_point.z, np.z, k)
		# A body on the sand pulls the look down from chest height (so it is not framed in the top half).
		if is_finite(victim.y):
			_point.y = lerpf(_point.y, clampf(victim.y + 0.15, _look_low, _look_y), 1.0 - exp(-1.5 * maxf(delta, 0.0)))
	if is_finite(head.x) and is_finite(head.y) and is_finite(head.z):
		_head = clamp_head(_point, inside_wall(head, _arena_r, 0.2), _reach)
		_head_t += maxf(delta, 0.0)
		# Swing round to film the body and the flying head side-on, as far as the wall allows.
		if not _high:
			var want: Vector3 = head_side(_point, _head, _side)
			var cam_r: float = Vector2(_point.x + want.x * distance(), _point.z + want.z * distance()).length()
			if _arena_r <= 0.0 or cam_r <= _arena_r - _wall_margin:
				_side = turn_toward(_side, want, _reaim_rate * maxf(delta, 0.0))
	else:
		_head = NO_HEAD
	weight = weight_at(_age, _ease_s, _hold_s, _release_s)
	if _age >= _hold_s + _release_s:
		clear()


## The severed head being tracked (clamped), or NO_HEAD.
func head_point() -> Vector3:
	return _head


func has_head() -> bool:
	return is_finite(_head.x)


## The held body point (without the head lean).
func look_body() -> Vector3:
	return _point


func look() -> Vector3:
	if not has_head():
		return _point
	return _point.lerp(_head, head_bias(_head_t, _bias0, _bias1, _bias_s))


func distance() -> float:
	if not has_head():
		return _dist * (0.85 if _high else 1.0)
	var sep: float = Vector2(_head.x - _point.x, _head.z - _point.z).length()
	return framing_dist(_dist, sep, _dist_max) * (0.85 if _high else 1.0)


func pos() -> Vector3:
	var l: Vector3 = look()
	var h: float = _high_h if _high else _height
	return Vector3(l.x, _point.y, l.z) + _side * distance() + Vector3(0.0, h, 0.0)
