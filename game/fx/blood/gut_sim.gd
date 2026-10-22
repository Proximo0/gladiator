class_name GutSim
extends RefCounted
## The spilled guts of a gutting or run-through: a pool of GutRope strings plus loose pieces that fly out, bounce and
## lie on the sand (coiled intestine chunks and, on big wounds, whole organs that slide on the sand). Pure
## presentation logic, no nodes and no RNG (BloodFx passes seeds and directions). It writes its instances straight
## into one buffer, a block per piece kind and one MultiMesh each (the Houdini meshes in assets/gore/, see GutArt): stride 16 floats, a
## transform (12) then a colour (4, rgb + a). Each mesh is normalised by GutArt so the transforms here only carry
## the size: rope links are unit tubes along Z, the torn end runs from z 0 to 1, the rest are unit-wide pieces.

const STRIDE: int = 16
const MAX_TOUCHES: int = 6
## Piece kinds, one MultiMesh each: a rope link, the torn end of a rope, the tangle at the wound, a loose coil, organs.
const K_LINK: int = 0
const K_TORN: int = 1
const K_CLUSTER: int = 2
const K_COIL: int = 3
const K_LIVER: int = 4
const K_STOMACH: int = 5
const K_HEART: int = 6
const KINDS: int = 7
const ORGAN_KINDS: Array[int] = [K_LIVER, K_STOMACH, K_HEART]
const TORN_LEN: float = 3.5  ## torn end length in rope radii

var rope_cap: int = 12
var blob_cap: int = 24
var organ_cap: int = 6
var ropes: Array[GutRope] = []
var blob_pos: PackedVector3Array = PackedVector3Array()
var blob_vel: PackedVector3Array = PackedVector3Array()
var blob_rad: PackedFloat32Array = PackedFloat32Array()
var blob_yaw: PackedFloat32Array = PackedFloat32Array()
var blob_slot: PackedByteArray = PackedByteArray()
var blob_asleep: PackedByteArray = PackedByteArray()
var blob_hit: PackedByteArray = PackedByteArray()
var blob_seed: PackedFloat32Array = PackedFloat32Array()
var blob_kind: PackedByteArray = PackedByteArray()
var blob_slid: PackedFloat32Array = PackedFloat32Array()  ## metres slid on the sand since the last smear
## Height of each kind's centre above the sand when it rests, as a share of the piece's size (GutArt sets them).
var kind_floor: PackedFloat32Array = PackedFloat32Array([0.55, 0.55, 0.55, 0.45, 0.35, 0.4, 0.5])
var organ_friction: float = -1.0  ## sand grip for organs per 60th of a second (< 0: the rope friction)
var smear_step: float = 0.12  ## an organ sliding on the sand leaves a smear every this many metres
var cluster_size: float = 0.13  ## half width of the tangle at the wound when fully out, m
var touches: PackedVector3Array = PackedVector3Array()  ## sand contacts of the last step
var touch_slots: PackedByteArray = PackedByteArray()
var dirty: bool = true
var all: PackedFloat32Array = PackedFloat32Array()  ## every instance of the last write, kind by kind
var counts: PackedInt32Array = PackedInt32Array()  ## instances per kind in the last write
var bases: PackedInt32Array = PackedInt32Array()  ## first instance of each kind in `all`
var _spawned: int = 0


func _init() -> void:
	counts.resize(KINDS)
	bases.resize(KINDS)


static func is_organ(kind: int) -> bool:
	return kind >= K_LIVER


func set_caps(max_ropes: int, max_blobs: int, max_organs: int = -1) -> void:
	rope_cap = maxi(max_ropes, 0)
	blob_cap = maxi(max_blobs, 0)
	if max_organs >= 0:
		organ_cap = max_organs
	while ropes.size() > rope_cap:
		ropes.pop_front()
	while blob_count() > blob_cap:
		_remove_blob(_oldest(false))
	while organ_count() > organ_cap:
		_remove_blob(_oldest(true))
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
	blob_kind.clear()
	blob_slid.clear()
	dirty = true


## Sizes the buffer for ropes of `segs` points (the MultiMesh instance counts are `max_instances_of`).
func reserve(segs: int) -> void:
	all.resize(maxi(max_instances(segs), 1) * STRIDE)
	dirty = true


## Kind `kind`'s instances of the last write, padded with zeros to `cap` instances (a MultiMesh buffer of that size).
func kind_buffer(kind: int, cap: int) -> PackedFloat32Array:
	var n: int = mini(counts[kind], cap)
	var out: PackedFloat32Array = all.slice(bases[kind] * STRIDE, (bases[kind] + n) * STRIDE)
	out.resize(maxi(cap, 1) * STRIDE)
	return out


func max_instances_of(kind: int, segs: int) -> int:
	match kind:
		K_LINK:
			return rope_cap * maxi(segs - 1, 1)
		K_TORN, K_CLUSTER:
			return rope_cap
		K_COIL:
			return blob_cap
	return organ_cap


func max_instances(segs: int) -> int:
	var t: int = 0
	for k: int in KINDS:
		t += max_instances_of(k, segs)
	return t


func rope_count() -> int:
	return ropes.size()


## Loose intestine chunks (not organs).
func blob_count() -> int:
	var c: int = 0
	for k: int in blob_kind:
		if not is_organ(k):
			c += 1
	return c


func organ_count() -> int:
	return blob_pos.size() - blob_count()


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


## Adds a loose piece: a coil chunk (K_COIL) or an organ. `rad` is its half width, m. The oldest piece of the same
## group (chunks or organs) is dropped when that group is full.
func add_blob(at: Vector3, v: Vector3, rad: float, yaw: float, slot: int, seed_v: float, kind: int = K_COIL) -> void:
	var organ: bool = is_organ(kind)
	var cap: int = organ_cap if organ else blob_cap
	if cap <= 0:
		return
	if (organ_count() if organ else blob_count()) >= cap:
		_remove_blob(_oldest(organ))
	blob_pos.append(at)
	blob_vel.append(v)
	blob_rad.append(rad)
	blob_yaw.append(yaw)
	blob_slot.append(slot)
	blob_asleep.append(0)
	blob_hit.append(0)
	blob_seed.append(seed_v)
	blob_kind.append(clampi(kind, K_COIL, KINDS - 1))
	blob_slid.append(0.0)
	dirty = true


func _oldest(organ: bool) -> int:
	for i: int in blob_kind.size():
		if is_organ(blob_kind[i]) == organ:
			return i
	return 0


func _remove_blob(i: int) -> void:
	if i < 0 or i >= blob_pos.size():
		return
	blob_pos.remove_at(i)
	blob_vel.remove_at(i)
	blob_rad.remove_at(i)
	blob_yaw.remove_at(i)
	blob_slot.remove_at(i)
	blob_asleep.remove_at(i)
	blob_hit.remove_at(i)
	blob_seed.remove_at(i)
	blob_kind.remove_at(i)
	blob_slid.remove_at(i)


## Advances every awake rope and piece. `anchors` gives each rope's wound position this step (parallel to `ropes`,
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
	var organ_f: float = organ_friction if organ_friction >= 0.0 else friction
	for i: int in blob_pos.size():
		if blob_asleep[i] == 1:
			continue
		dirty = true
		var organ: bool = is_organ(blob_kind[i])
		var v: Vector3 = blob_vel[i]
		v.y -= gravity * dt
		v *= pow(damp, dt * GutRope.REF_HZ)
		var p: Vector3 = blob_pos[i] + v * dt
		var lift: float = blob_rad[i] * kind_floor[blob_kind[i]]
		var floor_y: float = GutRope._ground_at(ground, p) + lift
		if p.y < floor_y:
			p.y = floor_y
			if v.y < 0.0:
				if blob_hit[i] == 0 or v.y < -1.5:
					_touch(Vector3(p.x, floor_y - lift, p.z), blob_slot[i])
					blob_hit[i] = 1
				v.y = -v.y * bounce
			var f: float = pow(organ_f if organ else friction, dt * GutRope.REF_HZ)
			v.x *= f
			v.z *= f
			if organ:  # a sliding organ leaves a wet streak behind it
				blob_slid[i] += Vector2(v.x, v.z).length() * dt
				if blob_slid[i] >= smear_step:
					blob_slid[i] = 0.0
					_touch(Vector3(p.x, floor_y - lift, p.z), blob_slot[i])
			if v.length() < sleep_speed * 2.0 and absf(v.y) < 0.4:
				blob_asleep[i] = 1
				v = Vector3.ZERO
		blob_yaw[i] += (v.x - v.z) * dt * (1.0 if organ else 2.0)
		blob_pos[i] = p
		blob_vel[i] = v


func _touch(at: Vector3, slot: int) -> void:
	if touches.size() < MAX_TOUCHES:
		touches.append(at)
		touch_slots.append(slot)


func all_asleep() -> bool:
	for r: GutRope in ropes:
		if not r.asleep:
			return false
	for a: int in blob_asleep:
		if a == 0:
			return false
	return true


## Fills `all` and `counts`: one instance per rope link, a torn end per rope, a tangle at the wound of each rope that
## has one, and one per loose piece. Returns the total instance count. `rope_cols` holds the intestine colours by
## palette slot ([slot][variant] -> Color); `organ_cols` the organ colours ([slot][organ index] -> Color, index
## kind - K_LIVER), or variants when shorter.
func write(rope_cols: Array, organ_cols: Array) -> int:
	var need: PackedInt32Array = PackedInt32Array()
	need.resize(KINDS)
	for r: GutRope in ropes:
		need[K_LINK] += r.n - 1
		need[K_TORN] += 1
		if r.cluster:
			need[K_CLUSTER] += 1
	for k: int in blob_kind:
		need[k] += 1
	var total: int = 0
	for k: int in KINDS:
		bases[k] = total
		counts[k] = 0
		total += need[k]
	if all.size() < total * STRIDE:
		all.resize(total * STRIDE)
	for r: GutRope in ropes:
		var cols: Array = rope_cols[clampi(r.slot, 0, rope_cols.size() - 1)] as Array
		var roll0: float = r.seed_value * TAU
		for i: int in range(r.n - 1):
			var a: Vector3 = r.pos[i]
			var b: Vector3 = r.pos[i + 1]
			var d: Vector3 = b - a
			var len_d: float = d.length()
			var z: Vector3 = d / len_d if len_d > 0.0001 else Vector3.DOWN
			var fr: Array = _frame(z, roll0 + float(i) * 1.3)
			var bulge: float = 1.0 + 0.22 * sin(float(i) * 2.3 + r.seed_value * 6.0)
			var rr: float = r.radius * bulge
			var half: float = len_d * 0.5 + rr * 0.55
			var col: Color = (cols[(r.order + i) % cols.size()] as Color)
			var coat: float = clampf(1.0 - float(i) / 3.0, 0.0, 1.0) * 0.55
			col = Color(lerpf(col.r, 0.55, coat), lerpf(col.g, 0.02, coat), lerpf(col.b, 0.03, coat))
			_add(K_LINK, (fr[0] as Vector3) * rr, (fr[1] as Vector3) * rr, z * half, (a + b) * 0.5, col)
		# The torn end: from the last point on outward along the last link, overlapping it a little.
		var e: Vector3 = r.pos[r.n - 1]
		var de: Vector3 = e - r.pos[r.n - 2]
		var ze: Vector3 = de.normalized() if de.length_squared() > 0.000001 else Vector3.DOWN
		var fe: Array = _frame(ze, roll0)
		var tcol: Color = cols[(r.order + r.n) % cols.size()] as Color
		_add(K_TORN, (fe[0] as Vector3) * r.radius, (fe[1] as Vector3) * r.radius, ze * (r.radius * TORN_LEN),
				e - ze * (r.radius * 0.8), tcol)
		if r.cluster:  # the tangle bulging out of the wound, grown with the string
			var d0: Vector3 = r.pos[1] - r.pos[0]
			var up: Vector3 = d0.normalized() if d0.length_squared() > 0.000001 else r.push.normalized()
			if up.length_squared() < 0.5:
				up = Vector3.FORWARD
			var fc: Array = _frame(up, roll0)
			var s: float = cluster_size * GutRope.grow(r.age, r.pay_time)
			# Mesh Y (the pile's height) points out of the wound: columns x, y = up, z.
			_add(K_CLUSTER, (fc[0] as Vector3) * s, up * s, (fc[1] as Vector3) * s, r.pos[0], cols[r.order % cols.size()] as Color)
	for j: int in blob_pos.size():
		var kind: int = blob_kind[j]
		var slot_cols: Array
		var col2: Color
		if is_organ(kind):
			slot_cols = organ_cols[clampi(blob_slot[j], 0, organ_cols.size() - 1)] as Array
			col2 = slot_cols[(kind - K_LIVER) % slot_cols.size()] as Color
		else:
			slot_cols = rope_cols[clampi(blob_slot[j], 0, rope_cols.size() - 1)] as Array
			col2 = slot_cols[j % slot_cols.size()] as Color
		var rr2: float = blob_rad[j]
		var yaw: float = blob_yaw[j]
		var ux: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
		var uz: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
		_add(kind, ux * rr2, Vector3.UP * rr2, uz * rr2, blob_pos[j], col2)
	dirty = false
	return total


## Two unit vectors across `z`, turned `roll` radians about it.
static func _frame(z: Vector3, roll: float) -> Array:
	var ref: Vector3 = Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = ref.cross(z).normalized()
	var y: Vector3 = z.cross(x)
	var c: float = cos(roll)
	var s: float = sin(roll)
	return [x * c + y * s, y * c - x * s]


func _add(kind: int, bx: Vector3, by: Vector3, bz: Vector3, origin: Vector3, col: Color) -> void:
	var o: int = (bases[kind] + counts[kind]) * STRIDE
	# MultiMesh transform rows: (bx.x by.x bz.x ox), (bx.y by.y bz.y oy), (bx.z by.z bz.z oz)
	all[o] = bx.x
	all[o + 1] = by.x
	all[o + 2] = bz.x
	all[o + 3] = origin.x
	all[o + 4] = bx.y
	all[o + 5] = by.y
	all[o + 6] = bz.y
	all[o + 7] = origin.y
	all[o + 8] = bx.z
	all[o + 9] = by.z
	all[o + 10] = bz.z
	all[o + 11] = origin.z
	all[o + 12] = col.r
	all[o + 13] = col.g
	all[o + 14] = col.b
	all[o + 15] = 1.0
	counts[kind] += 1
