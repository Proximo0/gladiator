class_name BloodDecals
extends RefCounted
## Blood lying on the sand: small spots from landed droplets and pools that spread under bleeding or fallen
## fighters. Pooled, with state kept directly in a MultiMesh buffer (stride 16: transform with the quad scaled
## to the radius, custom = dryness, alpha, shape seed, pool flag + 2 x palette slot). Visual only; litres here are a presentation
## number and never feed back into any fighter's blood. Pure logic: no nodes, no RNG (callers pass a seed).

const STRIDE: int = 16
const CELL: float = 0.14
const SPOT_MAX_LITRES: float = 0.02  ## below this a decal is a spot, above it a pool
const SPREAD_TAU: float = 2.2  ## seconds for a pool radius to close most of the gap to its target
const SPOT_FADE_START: float = 35.0  ## spots soak into the sand and fade after this age
const SPOT_FADE_LEN: float = 40.0
const POOL_ALPHA_FLOOR: float = 0.55  ## a dried pool stays as a dark crust

var capacity: int = 0
var count: int = 0
var buf: PackedFloat32Array = PackedFloat32Array()
var pos: PackedVector3Array = PackedVector3Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var target: PackedFloat32Array = PackedFloat32Array()
var litres: PackedFloat32Array = PackedFloat32Array()
var age: PackedFloat32Array = PackedFloat32Array()
var seeds: PackedFloat32Array = PackedFloat32Array()
var slots: PackedByteArray = PackedByteArray()  ## palette slot (0 or 1): whose blood lies here
var _cells: Dictionary = {}  ## Vector2i -> slot
var _tick: int = 0
var _next: int = 0  ## ring pointer for recycling when full


func _init(cap: int = 160) -> void:
	resize(cap)


func resize(cap: int) -> void:
	capacity = maxi(cap, 1)
	count = 0
	_next = 0
	_cells.clear()
	buf.resize(capacity * STRIDE)
	buf.fill(0.0)
	pos.resize(capacity)
	radius.resize(capacity)
	target.resize(capacity)
	litres.resize(capacity)
	age.resize(capacity)
	seeds.resize(capacity)
	slots.resize(capacity)
	slots.fill(0)
	for i: int in capacity:
		var o: int = i * STRIDE
		buf[o] = 0.001
		buf[o + 5] = 1.0
		buf[o + 10] = 0.001


func is_pool(i: int) -> bool:
	return litres[i] > SPOT_MAX_LITRES


## Adds blood at a world position (y is the surface height). Merges into a decal in the same cell or a
## neighbouring pool whose radius covers the point; otherwise starts a new one (recycling the oldest when full).
## Returns the slot used.
## `pal` is the palette slot of the bleeding fighter: only a decal of the same slot is merged into, so red and
## ichor lying next to each other stay two colours.
func add(p: Vector3, l: float, seed_value: float, pal: int = 0) -> int:
	if l <= 0.0:
		return -1
	var slot: int = _find_near(p, pal)
	if slot < 0:
		slot = _alloc(p, seed_value, pal)
	litres[slot] += l
	target[slot] = BloodMath.pool_radius(litres[slot])
	age[slot] = minf(age[slot], 8.0 * (1.0 - clampf(l * 20.0, 0.0, 0.9)))  ## fresh blood refreshes the colour
	return slot


## Feeds a long-lived pool: `slot` (from an earlier call, or -1) keeps growing while its centre is within 0.6 m
## of `p`; otherwise a new decal starts at `p`. Returns the slot to pass next time.
func feed(slot: int, p: Vector3, l: float, seed_value: float, pal: int = 0) -> int:
	if slot >= 0 and slot < count and slots[slot] == pal and Vector2(pos[slot].x - p.x, pos[slot].z - p.z).length() < 0.6:
		litres[slot] += l
		target[slot] = BloodMath.pool_radius(litres[slot])
		age[slot] = minf(age[slot], 8.0)
		return slot
	return add(p, l, seed_value, pal)


func _find_near(p: Vector3, pal: int) -> int:
	var c: Vector2i = BloodMath.splat_cell(p.x, p.z, CELL)
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var k: Vector2i = Vector2i(c.x + dx, c.y + dz)
			if not _cells.has(k):
				continue
			var s: int = int(_cells[k])
			if s >= count or BloodMath.splat_cell(pos[s].x, pos[s].z, CELL) != k:
				_cells.erase(k)
				continue
			var d: float = Vector2(pos[s].x - p.x, pos[s].z - p.z).length()
			if slots[s] == pal and d < maxf(radius[s] * 0.8, CELL * 0.5):
				return s
	return -1


func _alloc(p: Vector3, seed_value: float, pal: int) -> int:
	var slot: int
	if count < capacity:
		slot = count
		count += 1
	else:
		slot = _next
		_next = (_next + 1) % capacity
		_cells.erase(BloodMath.splat_cell(pos[slot].x, pos[slot].z, CELL))
	pos[slot] = p
	radius[slot] = 0.004
	target[slot] = 0.004
	litres[slot] = 0.0
	age[slot] = 0.0
	seeds[slot] = seed_value - floorf(seed_value)
	slots[slot] = pal
	_cells[BloodMath.splat_cell(p.x, p.z, CELL)] = slot
	buf[slot * STRIDE] = radius[slot]
	buf[slot * STRIDE + 10] = radius[slot]
	_write(slot)
	return slot


func _write(i: int) -> void:
	var o: int = i * STRIDE
	buf[o + 3] = pos[i].x
	buf[o + 7] = pos[i].y + 0.0004 * float(i % 7)
	buf[o + 11] = pos[i].z
	buf[o + 12] = BloodMath.dryness(age[i])
	buf[o + 13] = alpha_of(i)
	buf[o + 14] = seeds[i]
	buf[o + 15] = (1.0 if is_pool(i) else 0.0) + 2.0 * float(slots[i])


## Alpha of decal i: pools keep a crust, spots fade as the sand soaks them up.
func alpha_of(i: int) -> float:
	var a: float = clampf(age[i] * 6.0, 0.0, 1.0) * 0.96
	if is_pool(i):
		var dry: float = BloodMath.dryness(age[i])
		return a * lerpf(1.0, POOL_ALPHA_FLOOR, dry)
	var f: float = clampf((age[i] - SPOT_FADE_START) / SPOT_FADE_LEN, 0.0, 1.0)
	return a * (1.0 - f)


func step(dt: float) -> void:
	var grow: float = 1.0 - exp(-dt / SPREAD_TAU)
	_tick += 1
	for i: int in count:
		age[i] += dt
		var o: int = i * STRIDE
		var gap: float = target[i] - radius[i]
		if gap > 0.0005:
			radius[i] += gap * grow
			buf[o] = radius[i]
			buf[o + 10] = radius[i]
		if (i + _tick) % 4 == 0:  ## colour and fade change slowly: a quarter of the decals per frame
			_write(i)


func clear() -> void:
	count = 0
	_next = 0
	_cells.clear()
	for i: int in capacity:
		buf[i * STRIDE + 13] = 0.0
