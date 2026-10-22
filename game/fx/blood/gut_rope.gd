class_name GutRope
extends RefCounted
## One string of intestine: a chain of points pinned at the wound (point 0) and pulled along by position based
## constraints, so it pays out of the belly, swings, flops onto the sand and then sleeps there. Presentation only:
## pure logic with no nodes and no RNG (the caller passes the directions and seeds). The chain grows from a stub to
## its full length over `pay_time`, which reads as the guts sliding out.

const REF_HZ: float = 60.0
const ITERATIONS: int = 5
const MIN_GROW: float = 0.12

var n: int = 0
var pos: PackedVector3Array = PackedVector3Array()
var vel: PackedVector3Array = PackedVector3Array()
var grounded: PackedByteArray = PackedByteArray()  ## 1 once the point has touched the sand
var anchor: Vector3 = Vector3.ZERO
var seg_full: float = 0.1
var radius: float = 0.04
var pay_time: float = 0.9
var sway: Vector3 = Vector3.ZERO  ## constant sideways acceleration on hanging points: keeps neighbouring strings fanned out, m/s^2
var push: Vector3 = Vector3.ZERO  ## acceleration that shoves the chain out of the wound while it pays out, m/s^2
var age: float = 0.0
var asleep: bool = false
var calm_time: float = 0.0
var slot: int = 0
var seed_value: float = 0.0
var order: int = 0  ## spawn number, for colour variation
var cluster: bool = false  ## draws the tangle of guts bulging out of the wound at point 0
var _sleep_anchor: Vector3 = Vector3.ZERO
## Points that first touched the sand during the last step (world positions); the caller turns them into smears.
var touches: PackedVector3Array = PackedVector3Array()


## Starts the chain at `at`, every point stacked on the wound; `dir` is the outward direction, `speed` the initial
## shove (m/s) and `push_accel` the pay-out acceleration.
func setup(count: int, seg_len: float, rad: float, pay: float, at: Vector3, dir: Vector3, speed: float,
		push_accel: float, slot_id: int, seed_v: float, sway_accel: Vector3 = Vector3.ZERO) -> void:
	sway = sway_accel
	n = maxi(count, 2)
	seg_full = seg_len
	radius = rad
	pay_time = maxf(pay, 0.05)
	anchor = at
	_sleep_anchor = at
	slot = slot_id
	seed_value = seed_v
	var d: Vector3 = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.DOWN
	push = d * push_accel
	pos.resize(n)
	vel.resize(n)
	grounded.resize(n)
	for i: int in n:
		pos[i] = at + d * (0.005 * float(i))
		vel[i] = d * speed * (float(i) / float(n - 1))
		grounded[i] = 0
	age = 0.0
	asleep = false
	calm_time = 0.0
	touches.clear()


## 0.._ share of the full segment length out of the wound `t` seconds after the spill began.
static func grow(t: float, pay: float) -> float:
	var x: float = clampf(t / maxf(pay, 0.001), 0.0, 1.0)
	return MIN_GROW + (1.0 - MIN_GROW) * (1.0 - pow(1.0 - x, 2.2))


func seg_len() -> float:
	return seg_full * grow(age, pay_time)


func total_length() -> float:
	return seg_len() * float(n - 1)


## Advances the chain. `anchor_pos` is where the wound is now. `ground` gives the sand height at (x, 0, z) or null.
func step(dt: float, gravity: float, anchor_pos: Vector3, ground: Callable, damp: float, friction: float,
		sleep_speed: float, sleep_after: float) -> void:
	touches.clear()
	if dt <= 0.0:
		return
	anchor = anchor_pos
	if asleep:
		if anchor.distance_to(_sleep_anchor) < 0.04:
			return
		asleep = false  # the body it hangs from moved: wake up
		calm_time = 0.0
	age += dt
	var seg: float = seg_len()
	var k: float = pow(damp, dt * REF_HZ)
	var pred: PackedVector3Array = pos.duplicate()
	var pay_left: float = clampf(1.0 - age / pay_time, 0.0, 1.0)
	pred[0] = anchor
	for i: int in range(1, n):
		var v: Vector3 = vel[i] * k
		v.y -= gravity * dt
		if pos[i].y > _ground_at(ground, pos[i]) + radius * 2.5:
			v += sway * (dt * float(i) / float(n - 1))
		v += push * (pay_left * dt * (0.35 + 0.65 * float(i) / float(n - 1)))
		pred[i] = pos[i] + v * dt
	for _it: int in ITERATIONS:
		pred[0] = anchor
		for i: int in range(n - 1):
			var d: Vector3 = pred[i + 1] - pred[i]
			var len_d: float = d.length()
			if len_d < 0.00001:
				continue
			var corr: Vector3 = d * ((len_d - seg) / len_d)
			if i == 0:
				pred[i + 1] -= corr
			else:
				pred[i] += corr * 0.5
				pred[i + 1] -= corr * 0.5
		for i: int in range(1, n):
			var gy: float = _ground_at(ground, pred[i]) + radius * 0.9
			if pred[i].y < gy:
				pred[i].y = gy
	var moving: float = 0.0
	for i: int in range(1, n):
		var nv: Vector3 = (pred[i] - pos[i]) / dt
		var gy: float = _ground_at(ground, pred[i]) + radius * 0.9
		if pred[i].y <= gy + 0.004:
			nv.x *= pow(friction, dt * REF_HZ)
			nv.z *= pow(friction, dt * REF_HZ)
			if grounded[i] == 0:
				grounded[i] = 1
				if touches.size() < 3:
					touches.append(Vector3(pred[i].x, gy - radius * 0.9, pred[i].z))
		vel[i] = nv
		moving = maxf(moving, nv.length())
	pos = pred
	pos[0] = anchor
	vel[0] = Vector3.ZERO
	if age > pay_time and moving < sleep_speed:
		calm_time += dt
		if calm_time >= sleep_after:
			asleep = true
			_sleep_anchor = anchor
			for i: int in range(1, n):
				vel[i] = Vector3.ZERO
	else:
		calm_time = 0.0


static func _ground_at(ground: Callable, p: Vector3) -> float:
	if ground.is_valid():
		return float(ground.call(Vector3(p.x, 0.0, p.z)))
	return 0.0


## Number of points that have touched the sand.
func grounded_count() -> int:
	var c: int = 0
	for i: int in n:
		c += grounded[i]
	return c
