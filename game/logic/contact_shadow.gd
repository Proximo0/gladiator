class_name ContactShadow
extends RefCounted
## Contact-darkening blobs on the sand under each fighter's feet and pelvis, so fighters read as standing in the sand
## even where the sun shadow is coarse (one split on low). Presentation only: MatchPresenter packs the blobs once
## per frame and the sand shader darkens the sand under each one. A blob is Vector4(x, z, radius, strength): it
## widens and fades as its part rises off the sand, and is dropped once it has faded out. Each blob has an axis
## Vector4(dir x, dir z, aspect, 0): a foot's blob is an oval laid along the foot (aspect = length over width, the
## same area as the round blob of that radius); aspect 0 or 1 is round. Where the sun shadow is good (high quality) the
## shader takes the blobs off the sun light only, so a foot standing in a shadow is not darkened twice.

const MAX_BLOBS: int = 8  ## the sand shader's `contact` array size: two fighters, two feet and a pelvis each, spare
const MIN_STRENGTH: float = 0.005  ## fainter blobs are dropped
const ROUND: Vector4 = Vector4(1.0, 0.0, 1.0, 0.0)  ## the axis of a round blob


## One blob for a part at `pos`. `height` is how far it is above its resting height on the sand (m); the blob is gone
## at `fade_h`, and its radius grows by `spread` per metre of height.
static func blob(pos: Vector3, height: float, base_r: float, fade_h: float, strength: float, spread: float) -> Vector4:
	var h: float = maxf(height, 0.0)
	var k: float = 1.0 - smoothstep(0.0, maxf(fade_h, 0.001), h)
	return Vector4(pos.x, pos.z, base_r * (1.0 + h * spread), strength * k)


## The blobs of one fighter: a foot blob per standing foot (`feet` are foot-box centres), a body blob under the pelvis.
static func fighter_blobs(feet: Array[Vector3], pelvis: Vector3, t: Tuning) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for f: Vector3 in feet:
		out.append(blob(f, f.y - t.sand_contact_foot_rest, t.sand_contact_foot_r, t.sand_contact_foot_h,
				t.sand_contact_dark, t.sand_contact_spread))
	out.append(blob(pelvis, pelvis.y, t.sand_contact_body_r, t.sand_contact_body_h, t.sand_contact_body_dark,
			t.sand_contact_spread))
	return out


## The axes of one fighter's blobs, in fighter_blobs' order: an oval along each foot's flat `foot_fwd` (one per foot),
## round under the pelvis.
static func fighter_axes(foot_fwd: Array[Vector3], t: Tuning) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for f: Vector3 in foot_fwd:
		out.append(axis(f, t.sand_contact_foot_aspect))
	out.append(ROUND)
	return out


## A blob axis along the flat part of `fwd` with length over width `aspect` (at least 1); round when `fwd` is
## (nearly) vertical.
static func axis(fwd: Vector3, aspect: float) -> Vector4:
	var d: Vector2 = Vector2(fwd.x, fwd.z)
	if d.length() < 0.15:
		return ROUND
	d = d.normalized()
	return Vector4(d.x, d.y, maxf(aspect, 1.0), 0.0)


## Packs `blobs` for the shader: faded blobs dropped, at most MAX_BLOBS kept (strongest first), the rest zero.
## Returns the array (always MAX_BLOBS long); the live count is the number of non-zero entries at its start.
static func pack(blobs: Array[Vector4]) -> PackedVector4Array:
	var out: PackedVector4Array = PackedVector4Array()
	out.resize(MAX_BLOBS)
	var keep: Array[int] = _kept(blobs)
	for i: int in keep.size():
		out[i] = blobs[keep[i]]
	return out


## The axes of the blobs `pack(blobs)` keeps, in the same order (`axes` runs parallel to `blobs`; a missing axis is
## round). Always MAX_BLOBS long.
static func pack_axes(blobs: Array[Vector4], axes: Array[Vector4]) -> PackedVector4Array:
	var out: PackedVector4Array = PackedVector4Array()
	out.resize(MAX_BLOBS)
	var keep: Array[int] = _kept(blobs)
	for i: int in keep.size():
		out[i] = axes[keep[i]] if keep[i] < axes.size() else ROUND
	return out


## Indices of the blobs that pack keeps: the live ones in order, or the MAX_BLOBS strongest (ties by index).
static func _kept(blobs: Array[Vector4]) -> Array[int]:
	var live: Array[int] = []
	for i: int in blobs.size():
		var b: Vector4 = blobs[i]
		if b.w >= MIN_STRENGTH and b.z > 0.0:
			live.append(i)
	if live.size() > MAX_BLOBS:
		live.sort_custom(func(a: int, c: int) -> bool:
			return blobs[a].w > blobs[c].w or (blobs[a].w == blobs[c].w and a < c))
		live.resize(MAX_BLOBS)
	return live


## A blob's half length (along its axis) and half width: radius r spread over aspect k keeps the area of the circle.
static func half_extents(b: Vector4, ax: Vector4) -> Vector2:
	var k: float = ax.z if ax.z > 0.0 else 1.0
	var s: float = sqrt(k)
	return Vector2(b.z * s, b.z / s)


## Number of live blobs at the start of a packed array.
static func live_count(packed: PackedVector4Array) -> int:
	var n: int = 0
	for b: Vector4 in packed:
		if b.w <= 0.0:
			break
		n += 1
	return n


## One circle (x, z, radius, 0) holding every live blob (an oval by its half length), so the shader can skip the blob
## loop outside it; zero when none is live. Two fighters far apart give a wide circle, which only costs the loop on
## more of the sand.
static func bound(packed: PackedVector4Array, axes: PackedVector4Array = PackedVector4Array()) -> Vector4:
	var n: int = live_count(packed)
	if n == 0:
		return Vector4.ZERO
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	var reach: Array[float] = []
	for i: int in n:
		var b: Vector4 = packed[i]
		var e: float = half_extents(b, axes[i] if i < axes.size() else ROUND).x
		reach.append(e)
		lo = lo.min(Vector2(b.x - e, b.y - e))
		hi = hi.max(Vector2(b.x + e, b.y + e))
	var c: Vector2 = (lo + hi) * 0.5
	var r: float = 0.0
	for i: int in n:
		var b: Vector4 = packed[i]
		r = maxf(r, Vector2(b.x, b.y).distance_to(c) + reach[i])
	return Vector4(c.x, c.y, r, 0.0)


## Darkening factor the shader applies at sand point (x, z): the product of 1 - strength * falloff over the blobs
## (falloff (1 - e²)², with e² = (along / half length)² + (across / half width)²: 1 at the centre, 0 at the edge).
## Mirrors sand_floor.gdshader for tests.
static func shade_at(packed: PackedVector4Array, x: float, z: float,
		axes: PackedVector4Array = PackedVector4Array()) -> float:
	var s: float = 1.0
	for i: int in packed.size():
		var b: Vector4 = packed[i]
		if b.w <= 0.0:
			break
		var ax: Vector4 = axes[i] if i < axes.size() and axes[i].z > 0.0 else ROUND
		var d: Vector2 = Vector2(x - b.x, z - b.y)
		var along: float = d.dot(Vector2(ax.x, ax.y))
		var across: float = d.dot(Vector2(-ax.y, ax.x))
		var e2: float = (along * along / ax.z + across * across * ax.z) / (b.z * b.z)
		var q: float = clampf(1.0 - e2, 0.0, 1.0)
		s *= 1.0 - b.w * q * q
	return s
