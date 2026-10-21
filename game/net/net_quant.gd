class_name NetQuant
extends RefCounted
## Quantisation for the wire. Positions 1 mm in int16 (+-32.7 m), velocities 1 cm/s in int16 (+-327 m/s),
## rotations "smallest three" in 32 bits (about 0.1 degree), yaw in uint16, 0..1 fractions in uint8, directions
## in 3 x int8. Pure; every encoder has a matching decoder and the tests check the round trip error.

const POS_SCALE: float = 1000.0
const VEL_SCALE: float = 100.0
const QUAT_BITS: int = 10
const QUAT_RANGE: float = 0.70710678  ## the three smallest components of a unit quaternion lie in +-1/sqrt(2)
const I16_MAX: int = 32767
const U16_MAX: int = 65535


static func to_i16(v: float, scale: float) -> int:
	return clampi(roundi(v * scale), -I16_MAX, I16_MAX)


static func put_vec_i16(buf: StreamPeerBuffer, v: Vector3, scale: float) -> void:
	buf.put_16(to_i16(v.x, scale))
	buf.put_16(to_i16(v.y, scale))
	buf.put_16(to_i16(v.z, scale))


static func get_vec_i16(buf: StreamPeerBuffer, scale: float) -> Vector3:
	var x: int = buf.get_16()
	var y: int = buf.get_16()
	var z: int = buf.get_16()
	return Vector3(float(x), float(y), float(z)) / scale


## Unit vector in 3 x int8 (direction only; zero stays zero).
static func put_dir(buf: StreamPeerBuffer, v: Vector3) -> void:
	var n: Vector3 = v.normalized() if v.length_squared() > 0.000001 else Vector3.ZERO
	buf.put_8(clampi(roundi(n.x * 127.0), -127, 127))
	buf.put_8(clampi(roundi(n.y * 127.0), -127, 127))
	buf.put_8(clampi(roundi(n.z * 127.0), -127, 127))


static func get_dir(buf: StreamPeerBuffer) -> Vector3:
	var x: int = buf.get_8()
	var y: int = buf.get_8()
	var z: int = buf.get_8()
	var v := Vector3(float(x), float(y), float(z)) / 127.0
	return v.normalized() if v.length_squared() > 0.000001 else Vector3.ZERO


## 0..1 to uint8.
static func frac_u8(f: float) -> int:
	return clampi(roundi(clampf(f, 0.0, 1.0) * 255.0), 0, 255)


static func u8_frac(b: int) -> float:
	return float(b) / 255.0


## Non-negative value in uint16 at `scale` units per 1.
static func to_u16(v: float, scale: float) -> int:
	return clampi(roundi(v * scale), 0, U16_MAX)


## Angle (any range) to uint16 over -PI..PI.
static func yaw_u16(yaw: float) -> int:
	var w: float = wrapf(yaw, -PI, PI)
	return clampi(roundi((w + PI) / TAU * float(U16_MAX)), 0, U16_MAX)


static func u16_yaw(v: int) -> float:
	return float(v) / float(U16_MAX) * TAU - PI


## Smallest three: 2 bits for the index of the largest component, 3 x 10 bits for the others (the largest is
## made positive and rebuilt from the unit length).
static func quat_u32(q_in: Quaternion) -> int:
	var q: Quaternion = q_in.normalized()
	var c: Array[float] = [q.x, q.y, q.z, q.w]
	var big: int = 0
	for i: int in range(1, 4):
		if absf(c[i]) > absf(c[big]):
			big = i
	var sgn: float = -1.0 if c[big] < 0.0 else 1.0
	var out: int = big
	var levels: int = (1 << QUAT_BITS) - 2  # even step count, so 0 is exact
	var shift: int = 2
	for i: int in range(4):
		if i == big:
			continue
		var v: float = clampf(c[i] * sgn, -QUAT_RANGE, QUAT_RANGE)
		var k: int = clampi(roundi((v + QUAT_RANGE) / (2.0 * QUAT_RANGE) * float(levels)), 0, levels)
		out |= k << shift
		shift += QUAT_BITS
	return out


static func u32_quat(v: int) -> Quaternion:
	var big: int = v & 3
	var levels: int = (1 << QUAT_BITS) - 2  # even step count, so 0 is exact
	var c: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var shift: int = 2
	var sum: float = 0.0
	for i: int in range(4):
		if i == big:
			continue
		var k: int = (v >> shift) & ((1 << QUAT_BITS) - 1)
		c[i] = float(k) / float(levels) * 2.0 * QUAT_RANGE - QUAT_RANGE
		sum += c[i] * c[i]
		shift += QUAT_BITS
	c[big] = sqrt(maxf(1.0 - sum, 0.0))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()


## Writes a short string (up to 255 UTF-8 bytes).
static func put_str(buf: StreamPeerBuffer, s: String) -> void:
	var b: PackedByteArray = s.to_utf8_buffer()
	if b.size() > 255:
		b = b.slice(0, 255)
	buf.put_u8(b.size())
	buf.put_data(b)


static func get_str(buf: StreamPeerBuffer) -> String:
	var n: int = buf.get_u8()
	if n == 0 or buf.get_available_bytes() < n:
		return ""
	var r: Array = buf.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()
