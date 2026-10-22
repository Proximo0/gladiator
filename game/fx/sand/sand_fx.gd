class_name SandFx
extends RefCounted
## Thrown sand: a pooled ballistic grain sim (pure logic, no nodes). Grains arc under gravity with a little air drag,
## land on the visual ground (a height callback), lie there for a moment and shrink away. SandSurface owns one,
## feeds it events (kick-ups, bursts, falls) and draws it through a MultiMesh via fill_buffer().
## Presentation only: it never touches physics and is not part of any state hash.

const FLOATS_PER_GRAIN: int = 16  ## 3x4 transform (row major) + RGBA colour, the MultiMesh buffer layout
const GRAVITY: float = 9.8
const AIR_DRAG: float = 0.9  ## 1/s velocity loss, grains are light
const MIN_SIZE: float = 0.006  ## grain cube edge, metres
const MAX_SIZE: float = 0.017
const LAND_BOUNCE: float = 0.22
const REST_MIN: float = 0.5  ## seconds a landed grain lies there before shrinking, min and max
const REST_MAX: float = 1.4
const SHRINK_S: float = 0.35
const FLIGHT_MAX: float = 2.5  ## safety lifetime in the air

var capacity: int = 0
var count: int = 0

var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _rest: PackedFloat32Array = PackedFloat32Array()  ## < 0 flying (time left in the air), >= 0 seconds lain
var _hold: PackedFloat32Array = PackedFloat32Array()  ## how long this grain lies after landing
var _size: PackedFloat32Array = PackedFloat32Array()
var _spin: PackedFloat32Array = PackedFloat32Array()  ## yaw of the cube
var _shade: PackedFloat32Array = PackedFloat32Array()  ## 0..1 colour variation
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ground: Callable = Callable()
var landed_total: int = 0


func _init(p_capacity: int = 480, seed_v: int = 4242) -> void:
	capacity = maxi(p_capacity, 1)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_rest.resize(capacity)
	_hold.resize(capacity)
	_size.resize(capacity)
	_spin.resize(capacity)
	_shade.resize(capacity)
	_rng.seed = seed_v


## Callable(Vector3) -> float giving the visual ground height under a point. Without one the ground is y = 0.
func set_ground(c: Callable) -> void:
	_ground = c


func clear() -> void:
	count = 0


func _ground_y(p: Vector3) -> float:
	if _ground.is_valid():
		return float(_ground.call(p))
	return 0.0


## Adds one grain, replacing the oldest when the pool is full. Returns its index.
func _add(p: Vector3, v: Vector3, size: float) -> int:
	var i: int = count
	if count >= capacity:
		i = _rng.randi_range(0, capacity - 1)
	else:
		count += 1
	_pos[i] = p
	_vel[i] = v
	_rest[i] = -FLIGHT_MAX
	_hold[i] = _rng.randf_range(REST_MIN, REST_MAX)
	_size[i] = size
	_spin[i] = _rng.randf_range(0.0, TAU)
	_shade[i] = _rng.randf()
	return i


func _rand_size(scale: float) -> float:
	var s: float = lerpf(MIN_SIZE, MAX_SIZE, _rng.randf() * _rng.randf())
	return s * scale


## A direction inside a cone of half-angle `spread` (radians) around unit vector `axis`.
func cone_dir(axis: Vector3, spread: float) -> Vector3:
	var a: Vector3 = axis.normalized() if axis.length() > 0.001 else Vector3.UP
	var helper: Vector3 = Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP
	var u: Vector3 = a.cross(helper).normalized()
	var w: Vector3 = a.cross(u)
	var phi: float = _rng.randf_range(0.0, TAU)
	var theta: float = spread * sqrt(_rng.randf())
	return (a * cos(theta) + (u * cos(phi) + w * sin(phi)) * sin(theta)).normalized()


## Burst of n grains from pos, mostly along dir (a hit, a stab, a falling body). speed in m/s.
func burst(pos: Vector3, dir: Vector3, speed: float, n: int, spread: float = 0.9, size_scale: float = 1.0) -> void:
	for k in range(n):
		var d: Vector3 = cone_dir(dir, spread)
		var sp: float = speed * _rng.randf_range(0.35, 1.1)
		var o: Vector3 = Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(0.0, 0.03), _rng.randf_range(-0.04, 0.04))
		_add(pos + o, d * sp, _rand_size(size_scale))


## Radial fountain: sand thrown out and up around pos (a body hitting the ground). radius = footprint of the thing.
func fountain(pos: Vector3, radius: float, speed: float, n: int, size_scale: float = 1.0) -> void:
	for k in range(n):
		var a: float = _rng.randf_range(0.0, TAU)
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var up: float = _rng.randf_range(0.5, 1.4)
		var sp: float = speed * _rng.randf_range(0.3, 1.0)
		var o: Vector3 = out * radius * _rng.randf_range(0.5, 1.1)
		_add(pos + o + Vector3(0.0, 0.01, 0.0), (out * 0.8 + Vector3(0.0, up, 0.0)).normalized() * sp, _rand_size(size_scale))


## Kick-up from something sliding or pushing along `travel` (unit, flat) at `speed`: grains fly back, up and aside.
func kick(pos: Vector3, travel: Vector3, speed: float, n: int, size_scale: float = 1.0) -> void:
	var side: Vector3 = Vector3(-travel.z, 0.0, travel.x)
	for k in range(n):
		var r: float = _rng.randf()
		var v: Vector3 = -travel * speed * (0.15 + 0.35 * r) + side * speed * _rng.randf_range(-0.25, 0.25) \
				+ Vector3(0.0, 0.8 + speed * 0.3 * _rng.randf() + 1.2 * r, 0.0)
		var o: Vector3 = Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(0.0, 0.02), _rng.randf_range(-0.03, 0.03))
		_add(pos + o, v, _rand_size(size_scale))


func step(delta: float) -> void:
	var i: int = 0
	while i < count:
		var rest: float = _rest[i]
		var keep: bool = true
		if rest < 0.0:
			var v: Vector3 = _vel[i]
			v.y -= GRAVITY * delta
			v *= maxf(0.0, 1.0 - AIR_DRAG * delta)
			var p: Vector3 = _pos[i] + v * delta
			var half: float = _size[i] * 0.5
			var g: float = _ground_y(p) + half
			rest += delta
			if p.y <= g and v.y <= 0.0:
				p.y = g
				if v.y < -1.2 and rest < -0.3:
					v = Vector3(v.x * 0.5, -v.y * LAND_BOUNCE, v.z * 0.5)
				else:
					v = Vector3.ZERO
					rest = 0.0
					landed_total += 1
			elif rest >= 0.0:
				rest = 0.0  ## flew too long: lie down where it is
				v = Vector3.ZERO
			_pos[i] = p
			_vel[i] = v
			_rest[i] = rest
		else:
			rest += delta
			_rest[i] = rest
			if rest > _hold[i] + SHRINK_S:
				keep = false
		if keep:
			i += 1
		else:
			count -= 1
			if i != count:
				_pos[i] = _pos[count]
				_vel[i] = _vel[count]
				_rest[i] = _rest[count]
				_hold[i] = _hold[count]
				_size[i] = _size[count]
				_spin[i] = _spin[count]
				_shade[i] = _shade[count]


## Scale factor 0..1 of grain i (shrinks away at the end of its rest).
func scale_of(i: int) -> float:
	if _rest[i] < 0.0:
		return 1.0
	return clampf(1.0 - (_rest[i] - _hold[i]) / SHRINK_S, 0.0, 1.0)


func flying_count() -> int:
	var c: int = 0
	for i in range(count):
		if _rest[i] < 0.0:
			c += 1
	return c


func position_of(i: int) -> Vector3:
	return _pos[i]


## Writes count grains into a MultiMesh buffer (transform + colour per grain, FLOATS_PER_GRAIN floats each) and
## returns count. `out` must hold capacity * FLOATS_PER_GRAIN floats. Colours are linear; base is the sand colour.
func fill_buffer(out: PackedFloat32Array, base: Color) -> int:
	for i in range(count):
		var s: float = _size[i] * scale_of(i)
		var yaw: float = _spin[i]
		var c: float = cos(yaw) * s
		var sn: float = sin(yaw) * s
		var o: int = i * FLOATS_PER_GRAIN
		var p: Vector3 = _pos[i]
		out[o] = c
		out[o + 1] = 0.0
		out[o + 2] = sn
		out[o + 3] = p.x
		out[o + 4] = 0.0
		out[o + 5] = s
		out[o + 6] = 0.0
		out[o + 7] = p.y
		out[o + 8] = -sn
		out[o + 9] = 0.0
		out[o + 10] = c
		out[o + 11] = p.z
		var k: float = 0.72 + 0.4 * _shade[i]
		out[o + 12] = base.r * k
		out[o + 13] = base.g * k
		out[o + 14] = base.b * k
		out[o + 15] = 1.0
	return count
