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


func start(attacker: Vector3, victim: Vector3, hit: Vector3, tun: Tuning) -> void:
	_hold_s = tun.feel_finale_hold_s
	_ease_s = tun.feel_finale_ease_s
	_release_s = tun.feel_finale_release_s
	_dist = tun.feel_finale_dist
	_height = tun.feel_finale_height
	_point = hold_point(victim, hit, tun.feel_finale_look_y)
	_side = side_dir(attacker, victim)
	_age = 0.0
	active = true
	weight = 0.0


func clear() -> void:
	active = false
	weight = 0.0
	_age = 0.0


## Advances by `delta`. While easing in or holding, the held point creeps toward the victim's flat position (slowly,
## so a ragdoll sliding to rest is followed but its flailing is not).
func update(delta: float, victim: Vector3) -> void:
	if not active:
		return
	_age += maxf(delta, 0.0)
	if is_finite(victim.x) and is_finite(victim.z):
		var k: float = 1.0 - exp(-0.8 * maxf(delta, 0.0))
		_point.x = lerpf(_point.x, victim.x, k)
		_point.z = lerpf(_point.z, victim.z, k)
	weight = weight_at(_age, _ease_s, _hold_s, _release_s)
	if _age >= _hold_s + _release_s:
		clear()


func look() -> Vector3:
	return _point


func pos() -> Vector3:
	return _point + _side * _dist + Vector3(0.0, _height, 0.0)
