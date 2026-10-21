class_name BloodMist
extends RefCounted
## Short-lived mist sprites for impact spray. Buffer stride 16: transform (origin at 3, 7, 11), custom
## (size, alpha, rotation, tint) at 12..15. Rendered as billboards by blood_mist.gdshader.

const STRIDE: int = 16

var capacity: int = 0
var count: int = 0
var buf: PackedFloat32Array = PackedFloat32Array()
var vel: PackedVector3Array = PackedVector3Array()
var age: PackedFloat32Array = PackedFloat32Array()
var life: PackedFloat32Array = PackedFloat32Array()
var size0: PackedFloat32Array = PackedFloat32Array()
var size1: PackedFloat32Array = PackedFloat32Array()
var alpha0: PackedFloat32Array = PackedFloat32Array()


func _init(cap: int = 60) -> void:
	resize(cap)


func resize(cap: int) -> void:
	capacity = maxi(cap, 1)
	count = 0
	buf.resize(capacity * STRIDE)
	buf.fill(0.0)
	vel.resize(capacity)
	age.resize(capacity)
	life.resize(capacity)
	size0.resize(capacity)
	size1.resize(capacity)
	alpha0.resize(capacity)
	for i: int in capacity:
		var o: int = i * STRIDE
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0


func emit(p: Vector3, v: Vector3, s0: float, s1: float, lifetime: float, alpha: float, rot: float) -> bool:
	if count >= capacity:
		return false
	var o: int = count * STRIDE
	buf[o + 3] = p.x
	buf[o + 7] = p.y
	buf[o + 11] = p.z
	buf[o + 12] = s0
	buf[o + 13] = 0.0
	buf[o + 14] = rot
	buf[o + 15] = 0.0
	vel[count] = v
	age[count] = 0.0
	life[count] = lifetime
	size0[count] = s0
	size1[count] = s1
	alpha0[count] = alpha
	count += 1
	return true


## Fade curve: quick rise, slow fade. t = age / life.
static func alpha_at(t: float, a0: float) -> float:
	return a0 * minf(t * 10.0, 1.0) * pow(maxf(1.0 - t, 0.0), 1.6)


static func size_at(t: float, s0: float, s1: float) -> float:
	return lerpf(s0, s1, sqrt(clampf(t, 0.0, 1.0)))


func step(dt: float) -> void:
	var damp: float = exp(-2.5 * dt)
	var i: int = 0
	while i < count:
		var a: float = age[i] + dt
		var l: float = life[i]
		if a >= l:
			var last: int = count - 1
			if i != last:
				var o: int = i * STRIDE
				var lo: int = last * STRIDE
				for j: int in STRIDE:
					buf[o + j] = buf[lo + j]
				vel[i] = vel[last]
				age[i] = age[last]
				life[i] = life[last]
				size0[i] = size0[last]
				size1[i] = size1[last]
				alpha0[i] = alpha0[last]
			count -= 1
			continue
		age[i] = a
		var v: Vector3 = vel[i] * damp
		v.y -= 1.2 * dt
		vel[i] = v
		var o2: int = i * STRIDE
		buf[o2 + 3] += v.x * dt
		buf[o2 + 7] += v.y * dt
		buf[o2 + 11] += v.z * dt
		var t: float = a / l
		buf[o2 + 12] = size_at(t, size0[i], size1[i])
		buf[o2 + 13] = alpha_at(t, alpha0[i])
		i += 1
