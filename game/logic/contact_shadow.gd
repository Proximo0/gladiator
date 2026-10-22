class_name ContactShadow
extends RefCounted
## Contact-darkening blobs on the sand under each fighter's feet and pelvis, so fighters read as standing in the sand
## even where the sun shadow is coarse (one split on low). Presentation only: MatchPresenter packs the blobs once
## per frame and the sand shader darkens the sand under each one. A blob is Vector4(x, z, radius, strength): it
## widens and fades as its part rises off the sand, and is dropped once it has faded out.

const MAX_BLOBS: int = 8  ## the sand shader's `contact` array size: two fighters, two feet and a pelvis each, spare
const MIN_STRENGTH: float = 0.005  ## fainter blobs are dropped


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


## Packs `blobs` for the shader: faded blobs dropped, at most MAX_BLOBS kept (strongest first), the rest zero.
## Returns the array (always MAX_BLOBS long); the live count is the number of non-zero entries at its start.
static func pack(blobs: Array[Vector4]) -> PackedVector4Array:
	var live: Array[Vector4] = []
	for b: Vector4 in blobs:
		if b.w >= MIN_STRENGTH and b.z > 0.0:
			live.append(b)
	if live.size() > MAX_BLOBS:
		live.sort_custom(func(a: Vector4, c: Vector4) -> bool: return a.w > c.w)
		live.resize(MAX_BLOBS)
	var out: PackedVector4Array = PackedVector4Array()
	out.resize(MAX_BLOBS)
	for i: int in live.size():
		out[i] = live[i]
	return out


## Number of live blobs at the start of a packed array.
static func live_count(packed: PackedVector4Array) -> int:
	var n: int = 0
	for b: Vector4 in packed:
		if b.w <= 0.0:
			break
		n += 1
	return n


## One circle (x, z, radius, 0) holding every live blob, so the shader can skip the blob loop outside it; zero when
## none is live. Two fighters far apart give a wide circle, which only costs the loop on more of the sand.
static func bound(packed: PackedVector4Array) -> Vector4:
	var n: int = live_count(packed)
	if n == 0:
		return Vector4.ZERO
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for i: int in n:
		var b: Vector4 = packed[i]
		lo = lo.min(Vector2(b.x - b.z, b.y - b.z))
		hi = hi.max(Vector2(b.x + b.z, b.y + b.z))
	var c: Vector2 = (lo + hi) * 0.5
	var r: float = 0.0
	for i: int in n:
		var b: Vector4 = packed[i]
		r = maxf(r, Vector2(b.x, b.y).distance_to(c) + b.z)
	return Vector4(c.x, c.y, r, 0.0)


## Darkening factor the shader applies at sand point (x, z): the product of 1 - strength * falloff over the blobs
## (falloff (1 - d²/r²)², 1 at the centre, 0 at the radius). Mirrors sand_floor.gdshader for tests.
static func shade_at(packed: PackedVector4Array, x: float, z: float) -> float:
	var s: float = 1.0
	for b: Vector4 in packed:
		if b.w <= 0.0:
			break
		var q: float = clampf(1.0 - (Vector2(x - b.x, z - b.y).length_squared()) / (b.z * b.z), 0.0, 1.0)
		s *= 1.0 - b.w * q * q
	return s
