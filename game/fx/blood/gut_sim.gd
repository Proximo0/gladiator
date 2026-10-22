class_name GutSim
extends RefCounted
## The spilled guts of a gutting or run-through: a pool of GutRope strings plus a few loose organ chunks that
## fly out, bounce and lie on the sand. Pure presentation logic, no nodes and no RNG (BloodFx passes seeds and
## directions). It writes its instances straight into a MultiMesh buffer: stride 16 floats, a transform (12) then a
## colour (4, rgb + a), one ellipsoid per rope link and per chunk.

const STRIDE: int = 16
const MAX_TOUCHES: int = 6

var rope_cap: int = 12
var blob_cap: int = 24
var ropes: Array[GutRope] = []
var blob_pos: PackedVector3Array = PackedVector3Array()
var blob_vel: PackedVector3Array = PackedVector3Array()
var blob_rad: PackedFloat32Array = PackedFloat32Array()
var blob_yaw: PackedFloat32Array = PackedFloat32Array()
var blob_slot: PackedByteArray = PackedByteArray()
var blob_asleep: PackedByteArray = PackedByteArray()
var blob_hit: PackedByteArray = PackedByteArray()
var blob_seed: PackedFloat32Array = PackedFloat32Array()
var touches: PackedVector3Array = PackedVector3Array()  ## sand contacts of the last step
var touch_slots: PackedByteArray = PackedByteArray()
var dirty: bool = true
var buf: PackedFloat32Array = PackedFloat32Array()
var _spawned: int = 0


func set_caps(max_ropes: int, max_blobs: int) -> void:
	rope_cap = maxi(max_ropes, 0)
	blob_cap = maxi(max_blobs, 0)
	while ropes.size() > rope_cap:
		ropes.pop_front()
	while blob_pos.size() > blob_cap:
		_remove_blob(0)
	dirty = true


func clear() -> void:
	ropes.clear()
	blob_pos.clear()
	blob_vel.clear()
	blob_rad.clear()
	blob_yaw.clear()
	blob_slot.clear()
	blob_asleep.clear()
	blob_hit.clear()
	blob_seed.clear()
	dirty = true


## Sizes the buffer for `n` instances (the MultiMesh instance count).
func reserve(n: int) -> void:
	buf.resize(maxi(n, 1) * STRIDE)
	buf.fill(0.0)
	dirty = true


func max_instances(segs: int) -> int:
	return rope_cap * maxi(segs - 1, 1) + blob_cap


func rope_count() -> int:
	return ropes.size()


func blob_count() -> int:
	return blob_pos.size()


## Adds a rope; the oldest is dropped when the pool is full. Returns it (null when the pool has no room at all).
func add_rope(r: GutRope) -> GutRope:
	if rope_cap <= 0:
		return null
	r.order = _spawned
	_spawned += 1
	ropes.append(r)
	if ropes.size() > rope_cap:
		ropes.pop_front()
	dirty = true
	return r


func add_blob(at: Vector3, v: Vector3, rad: float, yaw: float, slot: int, seed_v: float) -> void:
	if blob_cap <= 0:
		return
	if blob_pos.size() >= blob_cap:
		_remove_blob(0)
	blob_pos.append(at)
	blob_vel.append(v)
	blob_rad.append(rad)
	blob_yaw.append(yaw)
	blob_slot.append(slot)
	blob_asleep.append(0)
	blob_hit.append(0)
	blob_seed.append(seed_v)
	dirty = true


func _remove_blob(i: int) -> void:
	blob_pos.remove_at(i)
	blob_vel.remove_at(i)
	blob_rad.remove_at(i)
	blob_yaw.remove_at(i)
	blob_slot.remove_at(i)
	blob_asleep.remove_at(i)
	blob_hit.remove_at(i)
	blob_seed.remove_at(i)


## Advances every awake rope and chunk. `anchors` gives each rope's wound position this step (parallel to `ropes`,
## missing entries keep the rope's last anchor).
func step(dt: float, gravity: float, anchors: PackedVector3Array, ground: Callable, damp: float, friction: float,
		sleep_speed: float, sleep_after: float, bounce: float) -> void:
	touches.clear()
	touch_slots.clear()
	for k: int in ropes.size():
		var r: GutRope = ropes[k]
		var was_asleep: bool = r.asleep
		var a: Vector3 = anchors[k] if k < anchors.size() else r.anchor
		r.step(dt, gravity, a, ground, damp, friction, sleep_speed, sleep_after)
		if not was_asleep or not r.asleep:
			dirty = true
		for t: Vector3 in r.touches:
			if touches.size() < MAX_TOUCHES:
				touches.append(t)
				touch_slots.append(r.slot)
	for i: int in blob_pos.size():
		if blob_asleep[i] == 1:
			continue
		dirty = true
		var v: Vector3 = blob_vel[i]
		v.y -= gravity * dt
		v *= pow(damp, dt * GutRope.REF_HZ)
		var p: Vector3 = blob_pos[i] + v * dt
		var floor_y: float = GutRope._ground_at(ground, p) + blob_rad[i] * 0.55
		if p.y < floor_y:
			p.y = floor_y
			if v.y < 0.0:
				if blob_hit[i] == 0 or v.y < -1.5:
					if touches.size() < MAX_TOUCHES:
						touches.append(Vector3(p.x, floor_y - blob_rad[i] * 0.55, p.z))
						touch_slots.append(blob_slot[i])
					blob_hit[i] = 1
				v.y = -v.y * bounce
			var f: float = pow(friction, dt * GutRope.REF_HZ)
			v.x *= f
			v.z *= f
			if v.length() < sleep_speed * 2.0 and absf(v.y) < 0.4:
				blob_asleep[i] = 1
				v = Vector3.ZERO
		blob_yaw[i] += (v.x - v.z) * dt * 2.0
		blob_pos[i] = p
		blob_vel[i] = v


func all_asleep() -> bool:
	for r: GutRope in ropes:
		if not r.asleep:
			return false
	for a: int in blob_asleep:
		if a == 0:
			return false
	return true


## Fills `buf` with one instance per rope link and per chunk; returns the instance count.
## `rope_cols` / `blob_cols` hold the colours by palette slot: [slot][variant] -> Color.
func write(rope_cols: Array, blob_cols: Array) -> int:
	var count: int = 0
	for r: GutRope in ropes:
		count += r.n - 1
	count += blob_pos.size()
	if buf.size() < count * STRIDE:
		buf.resize(count * STRIDE)
	var o: int = 0
	for r: GutRope in ropes:
		var cols: Array = rope_cols[clampi(r.slot, 0, rope_cols.size() - 1)] as Array
		for i: int in range(r.n - 1):
			var a: Vector3 = r.pos[i]
			var b: Vector3 = r.pos[i + 1]
			var d: Vector3 = b - a
			var len_d: float = d.length()
			var z: Vector3 = d / len_d if len_d > 0.0001 else Vector3.DOWN
			var ref: Vector3 = Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
			var x: Vector3 = ref.cross(z).normalized()
			var y: Vector3 = z.cross(x)
			var bulge: float = 1.0 + 0.22 * sin(float(i) * 2.3 + r.seed_value * 6.0)
			var rr: float = r.radius * bulge
			var half: float = len_d * 0.5 + rr * 0.55
			var c: Vector3 = (a + b) * 0.5
			_put(o, x * rr, y * rr, z * half, c)
			var col: Color = (cols[(r.order + i) % cols.size()] as Color)
			var coat: float = clampf(1.0 - float(i) / 3.0, 0.0, 1.0) * 0.55
			buf[o + 12] = lerpf(col.r, 0.55, coat)
			buf[o + 13] = lerpf(col.g, 0.02, coat)
			buf[o + 14] = lerpf(col.b, 0.03, coat)
			buf[o + 15] = 1.0
			o += STRIDE
	for j: int in blob_pos.size():
		var cols2: Array = blob_cols[clampi(blob_slot[j], 0, blob_cols.size() - 1)] as Array
		var rr2: float = blob_rad[j]
		var yaw: float = blob_yaw[j]
		var ux: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
		var uz: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
		_put(o, ux * rr2 * 1.25, Vector3.UP * rr2 * 0.65, uz * rr2 * 0.95, blob_pos[j])
		var col2: Color = cols2[j % cols2.size()] as Color
		buf[o + 12] = col2.r
		buf[o + 13] = col2.g
		buf[o + 14] = col2.b
		buf[o + 15] = 1.0
		o += STRIDE
	dirty = false
	return count


func _put(o: int, bx: Vector3, by: Vector3, bz: Vector3, origin: Vector3) -> void:
	# MultiMesh transform rows: (bx.x by.x bz.x ox), (bx.y by.y bz.y oy), (bx.z by.z bz.z oz)
	buf[o] = bx.x
	buf[o + 1] = by.x
	buf[o + 2] = bz.x
	buf[o + 3] = origin.x
	buf[o + 4] = bx.y
	buf[o + 5] = by.y
	buf[o + 6] = bz.y
	buf[o + 7] = origin.y
	buf[o + 8] = bx.z
	buf[o + 9] = by.z
	buf[o + 10] = bz.z
	buf[o + 11] = origin.z
