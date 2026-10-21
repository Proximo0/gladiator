class_name SandMap
extends RefCounted
## Pure map math for the sand: world <-> texel mapping, stamp kernels with mass-conserving rims, blood spread.
## Heights are metres, stored row-major in a PackedFloat32Array of n * n (index = y * n + x). The map covers the
## square [-extent, extent] on X and Z. Texel i covers [i, i + 1) in texel space, its centre is i + 0.5.

const H_MIN: float = -0.14
const H_MAX: float = 0.10
const RIM_START: float = 0.85  ## q (normalised distance) where the rim ring begins
const RIM_WIDTH: float = 0.8  ## ring width in q units
const MAP_MARGIN: float = 0.6  ## map extends this far beyond the arena radius


static func map_extent(radius: float) -> float:
	return radius + MAP_MARGIN


static func map_size(radius: float, texels_per_m: float) -> int:
	return int(ceil(map_extent(radius) * 2.0 * texels_per_m))


static func texel_metres(extent: float, n: int) -> float:
	return 2.0 * extent / float(n)


## Continuous texel coordinates (texel centres at +0.5) of a world X/Z point.
static func world_to_texel(x: float, z: float, extent: float, n: int) -> Vector2:
	var s: float = float(n) / (2.0 * extent)
	return Vector2((x + extent) * s, (z + extent) * s)


static func texel_to_world(t: Vector2, extent: float, n: int) -> Vector2:
	var s: float = 2.0 * extent / float(n)
	return Vector2(t.x * s - extent, t.y * s - extent)


## Bilinear height at a world point. Outside the map: 0.
static func sample_height(h: PackedFloat32Array, n: int, extent: float, x: float, z: float) -> float:
	var t: Vector2 = world_to_texel(x, z, extent, n) - Vector2(0.5, 0.5)
	var x0: int = int(floor(t.x))
	var y0: int = int(floor(t.y))
	if x0 < 0 or y0 < 0 or x0 >= n - 1 or y0 >= n - 1:
		return 0.0
	var fx: float = t.x - float(x0)
	var fy: float = t.y - float(y0)
	var i: int = y0 * n + x0
	var a: float = lerpf(h[i], h[i + 1], fx)
	var b: float = lerpf(h[i + n], h[i + n + 1], fx)
	return lerpf(a, b, fy)


## Depression depth fraction (0..1) at normalised distance q from the stamp centre: flat bottom, sloped wall.
static func bowl_profile(q: float) -> float:
	if q >= 1.0:
		return 0.0
	return 1.0 - smoothstep(0.5, 1.0, q)


## Raised rim weight (not yet normalised) at normalised distance q.
static func rim_profile(q: float) -> float:
	var t: float = (q - RIM_START) / RIM_WIDTH
	if t <= 0.0 or t >= 1.0:
		return 0.0
	var s: float = sin(PI * t)
	return s * s


## Weight multiplier along the push direction. dir_dot = cos of the angle between texel direction and push.
static func push_factor(dir_dot: float, push_len: float) -> float:
	return maxf(0.15, 1.0 + 1.3 * dir_dot * minf(push_len, 1.0))


## Presses an elliptical stamp into `h`. Centre c in texel coords, radii rx (local X) and rz (local Z) in texels,
## yaw rotates the ellipse about Y like a Godot node. The bowl is blended toward -depth (never digs deeper than
## depth), and the displaced volume is spread over a rim ring (scaled by rim_gain; 1.0 conserves volume), biased
## along push (world X/Z, length 0..1). Returns the touched rect in texels (empty rect if nothing changed).
static func apply_stamp(h: PackedFloat32Array, n: int, c: Vector2, rx: float, rz: float, yaw: float,
		depth: float, push: Vector2, rim_gain: float) -> Rect2i:
	rx = maxf(rx, 0.5)
	rz = maxf(rz, 0.5)
	var ext: float = maxf(rx, rz) * (RIM_START + RIM_WIDTH) + 1.5
	var x0: int = maxi(0, int(floor(c.x - ext)))
	var x1: int = mini(n - 1, int(ceil(c.x + ext)))
	var y0: int = maxi(0, int(floor(c.y - ext)))
	var y1: int = mini(n - 1, int(ceil(c.y + ext)))
	if x1 < x0 or y1 < y0:
		return Rect2i()
	var w: int = x1 - x0 + 1
	var cs: float = cos(yaw)
	var sn: float = sin(yaw)
	var push_len: float = push.length()
	var push_dir: Vector2 = push / push_len if push_len > 0.001 else Vector2.ZERO
	var rim_w: PackedFloat32Array = PackedFloat32Array()
	rim_w.resize(w * (y1 - y0 + 1))
	var removed: float = 0.0
	var wsum: float = 0.0
	for y in range(y0, y1 + 1):
		var dz: float = float(y) + 0.5 - c.y
		for x in range(x0, x1 + 1):
			var dx: float = float(x) + 0.5 - c.x
			var lx: float = (dx * cs - dz * sn) / rx
			var lz: float = (dx * sn + dz * cs) / rz
			var q: float = sqrt(lx * lx + lz * lz)
			var k: int = (y - y0) * w + (x - x0)
			var prof: float = bowl_profile(q)
			if prof > 0.0:
				var i: int = y * n + x
				var cur: float = h[i]
				var nh: float = minf(cur, lerpf(cur, -depth, prof))
				nh = maxf(nh, H_MIN)
				removed += cur - nh
				h[i] = nh
			var rw: float = rim_profile(q)
			if rw > 0.0:
				if push_len > 0.001:
					var dl: float = maxf(sqrt(dx * dx + dz * dz), 0.001)
					rw *= push_factor((dx * push_dir.x + dz * push_dir.y) / dl, push_len)
				rim_w[k] = rw
				wsum += rw
	if wsum > 0.0 and removed > 0.0:
		var scale: float = removed * rim_gain / wsum
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var rw2: float = rim_w[(y - y0) * w + (x - x0)]
				if rw2 > 0.0:
					var i2: int = y * n + x
					h[i2] = minf(h[i2] + rw2 * scale, H_MAX)
	return Rect2i(x0, y0, w, y1 - y0 + 1)


## Points along a->b (inclusive) no further apart than spacing, at most max_n of them.
static func drag_points(a: Vector2, b: Vector2, spacing: float, max_n: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var len: float = a.distance_to(b)
	var steps: int = clampi(int(ceil(len / maxf(spacing, 0.0001))), 1, maxi(max_n - 1, 1))
	for i in range(steps + 1):
		out.append(a.lerp(b, float(i) / float(steps)))
	return out


## Pool outline wobble: radius multiplier around 1.0 for a pool at angle `a` (radians) with a per-pool seed.
static func blood_edge(a: float, seed_v: float) -> float:
	return 1.0 + 0.16 * sin(3.0 * a + seed_v) + 0.09 * sin(5.0 * a + 2.3 * seed_v) + 0.05 * sin(9.0 * a + 4.1 * seed_v)


## Radius (m) a pool of `litres` ends up covering: at least the requested radius, growing with volume.
static func blood_spread_radius(litres: float, radius: float) -> float:
	var r_vol: float = sqrt(maxf(litres, 0.0) * 0.001 / (PI * 0.004))
	return maxf(radius, r_vol)


## Blood strength 0..1 for litres over a circle of radius r (m): about 3 mm of liquid saturates the sand.
static func blood_strength(litres: float, r: float) -> float:
	var depth_m: float = maxf(litres, 0.0) * 0.001 / (PI * maxf(r * r, 0.000001))
	return clampf(depth_m / 0.003, 0.12, 1.0)


## Soaks blood into the maps around c (texel coords, radius r_texel). R: blood, wet: damp halo, dry: 0 fresh .. 1
## dried. additive adds to existing blood, otherwise takes the max (used for slow spreading). Returns touched rect.
static func apply_blood(blood: PackedFloat32Array, wet: PackedFloat32Array, dry: PackedFloat32Array, n: int,
		c: Vector2, r_texel: float, strength: float, seed_v: float, additive: bool) -> Rect2i:
	if r_texel < 0.8:
		strength *= (r_texel / 0.8) * (r_texel / 0.8)
		r_texel = 0.8
	var ext: float = r_texel * 1.6 * 1.25 + 1.0
	var x0: int = maxi(0, int(floor(c.x - ext)))
	var x1: int = mini(n - 1, int(ceil(c.x + ext)))
	var y0: int = maxi(0, int(floor(c.y - ext)))
	var y1: int = mini(n - 1, int(ceil(c.y + ext)))
	if x1 < x0 or y1 < y0:
		return Rect2i()
	for y in range(y0, y1 + 1):
		var dz: float = float(y) + 0.5 - c.y
		for x in range(x0, x1 + 1):
			var dx: float = float(x) + 0.5 - c.x
			var d: float = sqrt(dx * dx + dz * dz)
			var edge: float = blood_edge(atan2(dz, dx), seed_v)
			var q: float = d / (r_texel * edge)
			var val: float = 0.0
			if q < 1.0:
				val = strength * (1.0 - smoothstep(0.4, 1.0, q))
			var wv: float = strength * (1.0 - smoothstep(0.5, 1.6, q)) * 1.2
			if val <= 0.0 and wv <= 0.0:
				continue
			var i: int = y * n + x
			if val > 0.0:
				blood[i] = minf(1.0, blood[i] + val) if additive else maxf(blood[i], val)
				dry[i] = dry[i] * (1.0 - minf(1.0, val * 3.0))
			wet[i] = maxf(wet[i], minf(1.0, wv))
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## Total of a height array (tests: mass conservation).
static func total_height(h: PackedFloat32Array) -> float:
	var s: float = 0.0
	for v: float in h:
		s += v
	return s
