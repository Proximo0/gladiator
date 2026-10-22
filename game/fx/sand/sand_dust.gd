class_name SandDust
extends RefCounted
## Fine lingering dust: a pooled set of soft sprites that drift, rise a little and fade (pure logic, no nodes).
## SandSurface owns one and draws it through a billboard MultiMesh via fill_buffer(). Presentation only.

const FLOATS_PER_SPRITE: int = 16  ## 3x4 transform (row major) + RGBA colour, the MultiMesh buffer layout
const DRAG: float = 1.8  ## 1/s velocity loss
const FLOAT_UP: float = 0.18  ## m/s^2 buoyancy: dust hangs and drifts up before it settles
const WIND: Vector3 = Vector3(0.12, 0.0, 0.05)  ## m/s drift
const FADE_IN: float = 0.08  ## share of the life spent fading in

var capacity: int = 0
var count: int = 0

var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _s0: PackedFloat32Array = PackedFloat32Array()
var _s1: PackedFloat32Array = PackedFloat32Array()
var _alpha: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_capacity: int = 200, seed_v: int = 777) -> void:
	capacity = maxi(p_capacity, 1)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_age.resize(capacity)
	_life.resize(capacity)
	_s0.resize(capacity)
	_s1.resize(capacity)
	_alpha.resize(capacity)
	_rng.seed = seed_v


func clear() -> void:
	count = 0


## Adds one sprite (replacing a random one when the pool is full). Size grows from s0 to s1 metres over `life` s.
func add(p: Vector3, v: Vector3, s0: float, s1: float, life: float, alpha: float) -> void:
	var i: int = count
	if count >= capacity:
		i = _rng.randi_range(0, capacity - 1)
	else:
		count += 1
	_pos[i] = p
	_vel[i] = v
	_age[i] = 0.0
	_life[i] = maxf(life, 0.05)
	_s0[i] = s0
	_s1[i] = s1
	_alpha[i] = alpha


## A cloud of n sprites around pos: thrown along dir at up to speed (m/s), spread over `radius`, sized by `size`
## (final width, m), living `life` s (each a little different), peak opacity `alpha`.
func cloud(pos: Vector3, dir: Vector3, speed: float, n: int, radius: float, size: float, life: float, alpha: float) -> void:
	for k in range(n):
		var o: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.0, 0.6), _rng.randf_range(-1.0, 1.0)) * radius
		var jitter: Vector3 = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.0, 0.5), _rng.randf_range(-0.5, 0.5))
		var v: Vector3 = (dir + jitter) * speed * _rng.randf_range(0.2, 1.0)
		var sz: float = size * _rng.randf_range(0.55, 1.2)
		add(pos + o, v, sz * 0.3, sz, life * _rng.randf_range(0.6, 1.2), alpha * _rng.randf_range(0.6, 1.0))


func step(delta: float) -> void:
	var i: int = 0
	while i < count:
		var a: float = _age[i] + delta
		if a >= _life[i]:
			count -= 1
			if i != count:
				_pos[i] = _pos[count]
				_vel[i] = _vel[count]
				_age[i] = _age[count]
				_life[i] = _life[count]
				_s0[i] = _s0[count]
				_s1[i] = _s1[count]
				_alpha[i] = _alpha[count]
			continue
		var v: Vector3 = _vel[i]
		v *= maxf(0.0, 1.0 - DRAG * delta)
		v.y += FLOAT_UP * delta
		v += WIND * delta
		_vel[i] = v
		_pos[i] += v * delta
		_age[i] = a
		i += 1


## Opacity multiplier 0..1 of sprite i over its life: quick fade in, slow fade out.
func fade_of(i: int) -> float:
	var t: float = clampf(_age[i] / _life[i], 0.0, 1.0)
	var up: float = smoothstep(0.0, FADE_IN, t)
	var down: float = (1.0 - t) * (1.0 - t)
	return up * down


func size_of(i: int) -> float:
	var t: float = clampf(_age[i] / _life[i], 0.0, 1.0)
	return lerpf(_s0[i], _s1[i], 1.0 - (1.0 - t) * (1.0 - t))


func position_of(i: int) -> Vector3:
	return _pos[i]


## Writes count sprites into a MultiMesh buffer (capacity * FLOATS_PER_SPRITE floats) and returns count.
func fill_buffer(out: PackedFloat32Array, base: Color) -> int:
	for i in range(count):
		var s: float = size_of(i)
		var o: int = i * FLOATS_PER_SPRITE
		var p: Vector3 = _pos[i]
		out[o] = s
		out[o + 1] = 0.0
		out[o + 2] = 0.0
		out[o + 3] = p.x
		out[o + 4] = 0.0
		out[o + 5] = s
		out[o + 6] = 0.0
		out[o + 7] = p.y
		out[o + 8] = 0.0
		out[o + 9] = 0.0
		out[o + 10] = s
		out[o + 11] = p.z
		out[o + 12] = base.r
		out[o + 13] = base.g
		out[o + 14] = base.b
		out[o + 15] = _alpha[i] * fade_of(i)
	return count
