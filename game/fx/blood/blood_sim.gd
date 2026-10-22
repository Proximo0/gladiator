class_name BloodSim
extends RefCounted
## Pooled CPU droplet sim. State lives directly in a MultiMesh buffer (stride 20 floats per instance):
## 0..11 transform (identity basis + origin at 3, 7, 11), 12..15 colour (r stretch factor, g shade, b palette slot),
## 16..19 custom (velocity xyz, radius). The buffer is uploaded as is; no per-frame copy loop.

const STRIDE: int = 20
const O_X: int = 3
const O_Y: int = 7
const O_Z: int = 11
const C_STRETCH: int = 12
const C_SHADE: int = 13
const C_SLOT: int = 14  ## palette slot (0 or 1): whose blood this droplet is
const C_VX: int = 16
const C_VY: int = 17
const C_VZ: int = 18
const C_R: int = 19

var capacity: int = 0
var count: int = 0
var buf: PackedFloat32Array = PackedFloat32Array()
var age: PackedFloat32Array = PackedFloat32Array()
var life: PackedFloat32Array = PackedFloat32Array()
var dead: PackedByteArray = PackedByteArray()

## Ground hits of the last step (parallel arrays; the droplets are flagged dead).
var imp_pos: PackedVector3Array = PackedVector3Array()
var imp_vel: PackedVector3Array = PackedVector3Array()
var imp_rad: PackedFloat32Array = PackedFloat32Array()
var imp_slot: PackedByteArray = PackedByteArray()
## Droplets near a registered body in the last step, with where they were at the step start.
var near_idx: PackedInt32Array = PackedInt32Array()
var near_from: PackedVector3Array = PackedVector3Array()


func _init(cap: int = 400) -> void:
	resize(cap)


func resize(cap: int) -> void:
	capacity = maxi(cap, 1)
	count = 0
	buf.resize(capacity * STRIDE)
	buf.fill(0.0)
	age.resize(capacity)
	life.resize(capacity)
	dead.resize(capacity)
	for i: int in capacity:
		var o: int = i * STRIDE
		buf[o] = 1.0
		buf[o + 5] = 1.0
		buf[o + 10] = 1.0
		buf[o + 15] = 1.0
	_clear_events()


func free_slots() -> int:
	return capacity - count


func emit(p: Vector3, v: Vector3, r: float, stretch: float, lifetime: float, shade: float, slot: int = 0) -> bool:
	if count >= capacity:
		return false
	var o: int = count * STRIDE
	buf[o + O_X] = p.x
	buf[o + O_Y] = p.y
	buf[o + O_Z] = p.z
	buf[o + C_STRETCH] = stretch
	buf[o + C_SHADE] = shade
	buf[o + C_SLOT] = float(slot)
	buf[o + C_VX] = v.x
	buf[o + C_VY] = v.y
	buf[o + C_VZ] = v.z
	buf[o + C_R] = r
	age[count] = 0.0
	life[count] = lifetime
	dead[count] = 0
	count += 1
	return true


func pos_of(i: int) -> Vector3:
	var o: int = i * STRIDE
	return Vector3(buf[o + O_X], buf[o + O_Y], buf[o + O_Z])


func vel_of(i: int) -> Vector3:
	var o: int = i * STRIDE
	return Vector3(buf[o + C_VX], buf[o + C_VY], buf[o + C_VZ])


func radius_of(i: int) -> float:
	return buf[i * STRIDE + C_R]


func slot_of(i: int) -> int:
	return int(buf[i * STRIDE + C_SLOT])


func kill(i: int) -> void:
	dead[i] = 1


func _clear_events() -> void:
	imp_pos.clear()
	imp_vel.clear()
	imp_rad.clear()
	imp_slot.clear()
	near_idx.clear()
	near_from.clear()


## Advance every droplet by dt. height_fn(Vector3) -> float gives the ground height (only asked below 12 cm);
## reach holds centres of registered bodies, reach_r2 their squared radius; grace is the age before body tests.
func step(dt: float, gravity: float, height_fn: Callable, reach: PackedVector3Array, reach_r2: float,
		grace: float) -> void:
	_clear_events()
	var b: PackedFloat32Array = buf
	var has_h: bool = height_fn.is_valid()
	var n_reach: int = reach.size()
	var drag: float = BloodMath.AIR_DRAG
	var gdt: float = gravity * dt
	for i: int in count:
		var o: int = i * STRIDE
		var a: float = age[i] + dt
		age[i] = a
		var vx: float = b[o + C_VX]
		var vy: float = b[o + C_VY] - gdt
		var vz: float = b[o + C_VZ]
		var r: float = b[o + C_R]
		var k: float = 1.0 / (1.0 + drag / maxf(r, 0.0005) * sqrt(vx * vx + vy * vy + vz * vz) * dt)
		vx *= k
		vy *= k
		vz *= k
		var px0: float = b[o + O_X]
		var py0: float = b[o + O_Y]
		var pz0: float = b[o + O_Z]
		var px: float = px0 + vx * dt
		var py: float = py0 + vy * dt
		var pz: float = pz0 + vz * dt
		var gh: float = 0.0
		if py < 0.12 and has_h:
			gh = float(height_fn.call(Vector3(px, 0.0, pz)))
		if py <= gh:
			imp_pos.append(Vector3(px, gh, pz))
			imp_vel.append(Vector3(vx, vy, vz))
			imp_rad.append(r)
			imp_slot.append(int(b[o + C_SLOT]))
			dead[i] = 1
		elif a > life[i]:
			dead[i] = 1
		else:
			b[o + O_X] = px
			b[o + O_Y] = py
			b[o + O_Z] = pz
			b[o + C_VX] = vx
			b[o + C_VY] = vy
			b[o + C_VZ] = vz
			if a > grace:
				for c: int in n_reach:
					var d: Vector3 = reach[c]
					var ex: float = px - d.x
					var ey: float = py - d.y
					var ez: float = pz - d.z
					if ex * ex + ey * ey + ez * ez < reach_r2:
						near_idx.append(i)
						near_from.append(Vector3(px0, py0, pz0))
						break


## Remove flagged droplets (swap with the last live one). Call after handling impacts and body hits.
func compact() -> void:
	var i: int = count - 1
	while i >= 0:
		if dead[i] != 0:
			var last: int = count - 1
			if i != last:
				var o: int = i * STRIDE
				var lo: int = last * STRIDE
				for j: int in STRIDE:
					buf[o + j] = buf[lo + j]
				age[i] = age[last]
				life[i] = life[last]
			dead[last] = 0
			count -= 1
		i -= 1
