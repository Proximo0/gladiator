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
	return clampf(depth_m / 0.003, 0.2, 1.0)


## Soaks blood into the maps around c (texel coords, radius r_texel). R: blood, wet: damp halo, dry: 0 fresh .. 1
## dried. additive adds to existing blood, otherwise takes the max (used for slow spreading). Returns touched rect.
## `pal` (optional, one byte per texel) is the blood palette slot map: a texel the new blood owns (it adds to it, or is
## stronger than what was there) takes `slot`, so red and ichor can lie on the same sand; empty pal = no palette.
static func apply_blood(blood: PackedFloat32Array, wet: PackedFloat32Array, dry: PackedFloat32Array, n: int,
		c: Vector2, r_texel: float, strength: float, seed_v: float, additive: bool,
		pal: PackedByteArray = PackedByteArray(), slot: int = 0) -> Rect2i:
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
	var has_pal: bool = pal.size() == blood.size()
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
			if has_pal and ((val > 0.0 and (additive or val >= blood[i])) or (blood[i] < 0.002 and wv > 0.0)):
				pal[i] = slot
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


# --- Permanent piles (the base relief under the deformation map) ------------------------------------------------

const BASE_CELL: float = 0.1  ## base relief grid spacing in metres (smooth shapes, sampled bilinearly)
const WALL_OVERLAP: float = 0.3  ## the drift peaks this far outside the arena radius (under the wall)
const HEAP_COUNT: int = 9
const HEAP_MAX_H: float = 0.09  ## floor heaps stay low: the collider is flat, feet must not sink visibly
const DRIFT_MAX_H: float = 0.30


static func base_size(extent: float) -> int:
	return int(ceil(extent * 2.0 / BASE_CELL))


## Drift height (0..1 of its own amplitude, already shaped) as a function of the distance d in from the drift peak.
static func drift_profile(d: float, width: float) -> float:
	if d <= 0.0:
		return 1.0
	var t: float = clampf(1.0 - d / maxf(width, 0.05), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t) * (0.55 + 0.45 * t)


## Wall drift amplitude in metres around the arena at angle a (radians): lumps and gaps, never below a thin bank.
static func drift_amp(a: float, seed_v: float) -> float:
	var v: float = 0.5 + 0.5 * sin(2.0 * a + seed_v) * 0.55 + 0.5 * sin(3.0 * a + 2.1 * seed_v + 1.0) * 0.35 \
			+ 0.5 * sin(7.0 * a + 0.7 * seed_v) * 0.25 + 0.5 * sin(13.0 * a + 1.3 * seed_v) * 0.12
	var k: float = clampf(v, 0.0, 1.0)
	return DRIFT_MAX_H * (0.35 + 0.65 * k * k)


## How far (m) the drift reaches in from its peak at angle a.
static func drift_width(a: float, seed_v: float) -> float:
	return 1.3 + 1.0 * (0.5 + 0.5 * sin(5.0 * a + 1.7 * seed_v)) + 1.0 * (0.5 + 0.5 * sin(2.0 * a + 0.4 * seed_v + 2.0))


## Floor heaps: array of Vector3(x, z, h) plus the shape in a parallel Vector3(rx, rz, yaw). Deterministic per seed,
## kept off the spawn points (0, +-spawn) and the middle of the ring, inside the wall.
static func make_heaps(arena_radius: float, seed_v: int) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Array[Dictionary] = []
	var tries: int = 0
	while out.size() < HEAP_COUNT and tries < 200:
		tries += 1
		var a: float = rng.randf_range(0.0, TAU)
		var r: float = rng.randf_range(arena_radius * 0.34, arena_radius - 1.6)
		var big: bool = out.size() < 3
		if big:
			r = rng.randf_range(arena_radius * 0.55, arena_radius - 1.9)
		var p: Vector2 = Vector2(cos(a), sin(a)) * r
		var rx: float = rng.randf_range(0.45, 1.05)
		var rz: float = rx * rng.randf_range(0.5, 0.9)
		var h: float = rng.randf_range(0.2, 0.55) * HEAP_MAX_H
		if big:
			h = HEAP_MAX_H * rng.randf_range(0.75, 1.0)
			rx *= 1.1
		var ok: bool = true
		for d: float in [-4.0, 4.0]:
			if p.distance_to(Vector2(0.0, d)) < 1.8 + rx:
				ok = false
		for o: Dictionary in out:
			if p.distance_to(Vector2(float(o["x"]), float(o["z"]))) < 1.6 + rx + float(o["rx"]):
				ok = false
		if not ok:
			continue
		out.append({"x": p.x, "z": p.y, "rx": rx, "rz": rz, "yaw": rng.randf_range(0.0, PI), "h": h})
	return out


## Height of one heap at world (x, z): a flat-ish dome with a soft foot.
static func heap_height(hp: Dictionary, x: float, z: float) -> float:
	var dx: float = x - float(hp["x"])
	var dz: float = z - float(hp["z"])
	var yaw: float = float(hp["yaw"])
	var lx: float = (dx * cos(yaw) - dz * sin(yaw)) / float(hp["rx"])
	var lz: float = (dx * sin(yaw) + dz * cos(yaw)) / float(hp["rz"])
	var q2: float = lx * lx + lz * lz
	if q2 >= 1.0:
		return 0.0
	var t: float = 1.0 - q2
	return float(hp["h"]) * t * t * (1.0 + 0.6 * q2)


## Base relief height at world (x, z) for an arena of this radius. Wall drifts plus heaps.
static func base_height(x: float, z: float, arena_radius: float, seed_v: int, heaps: Array[Dictionary]) -> float:
	var r: float = sqrt(x * x + z * z)
	var h: float = 0.0
	var inner: float = arena_radius - 4.0
	if r > inner:
		var a: float = atan2(z, x)
		var d: float = (arena_radius + WALL_OVERLAP) - r
		h = drift_amp(a, float(seed_v) * 0.37) * drift_profile(d, drift_width(a, float(seed_v) * 0.37))
	for hp: Dictionary in heaps:
		h += heap_height(hp, x, z)
	return h


## Base relief grid for the map square [-extent, extent]: n = base_size(extent) texels per side, row-major, texel
## (i, j) is centred at (-extent + (i + 0.5) * step), the same convention as the deformation map. Heights in metres.
static func build_base(arena_radius: float, extent: float, seed_v: int) -> PackedFloat32Array:
	var n: int = base_size(extent)
	var step: float = extent * 2.0 / float(n)
	var heaps: Array[Dictionary] = make_heaps(arena_radius, seed_v)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n * n)
	out.fill(0.0)
	var sv: float = float(seed_v) * 0.37
	var steps: int = 720
	var tab: PackedFloat32Array = PackedFloat32Array()
	tab.resize(steps * 2)
	for k in range(steps):
		var a: float = -PI + (float(k) + 0.5) * TAU / float(steps)
		tab[k * 2] = drift_amp(a, sv)
		tab[k * 2 + 1] = drift_width(a, sv)
	var inner2: float = (arena_radius - 4.0) * (arena_radius - 4.0)
	var peak: float = arena_radius + WALL_OVERLAP
	for j in range(n):
		var z: float = -extent + (float(j) + 0.5) * step
		for i in range(n):
			var x: float = -extent + (float(i) + 0.5) * step
			var r2: float = x * x + z * z
			if r2 > inner2:
				var k2: int = clampi(int((atan2(z, x) + PI) / TAU * float(steps)), 0, steps - 1)
				out[j * n + i] = tab[k2 * 2] * drift_profile(peak - sqrt(r2), tab[k2 * 2 + 1])
	for hp: Dictionary in heaps:
		var rr: float = maxf(float(hp["rx"]), float(hp["rz"]))
		var i0: int = maxi(0, int(floor((float(hp["x"]) - rr + extent) / step)))
		var i1: int = mini(n - 1, int(ceil((float(hp["x"]) + rr + extent) / step)))
		var j0: int = maxi(0, int(floor((float(hp["z"]) - rr + extent) / step)))
		var j1: int = mini(n - 1, int(ceil((float(hp["z"]) + rr + extent) / step)))
		for j in range(j0, j1 + 1):
			var zz: float = -extent + (float(j) + 0.5) * step
			for i in range(i0, i1 + 1):
				out[j * n + i] += heap_height(hp, -extent + (float(i) + 0.5) * step, zz)
	return out


## Bilinear base height at world (x, z) from a build_base() grid, clamped at the edges.
static func sample_base(b: PackedFloat32Array, extent: float, x: float, z: float) -> float:
	var n: int = int(round(sqrt(float(b.size()))))
	if n < 2:
		return 0.0
	var step: float = extent * 2.0 / float(n)
	var fx: float = clampf((x + extent) / step - 0.5, 0.0, float(n - 1) - 0.0001)
	var fz: float = clampf((z + extent) / step - 0.5, 0.0, float(n - 1) - 0.0001)
	var i: int = int(floor(fx))
	var j: int = int(floor(fz))
	var tx: float = fx - float(i)
	var tz: float = fz - float(j)
	var a: float = lerpf(b[j * n + i], b[j * n + i + 1], tx)
	var c: float = lerpf(b[(j + 1) * n + i], b[(j + 1) * n + i + 1], tx)
	return lerpf(a, c, tz)


## Packs a base grid into RGBA float bytes (R height, G dh/dx, B dh/dz by central differences, A 1) for the shader.
static func base_to_rgba_bytes(b: PackedFloat32Array, extent: float) -> PackedByteArray:
	var n: int = int(round(sqrt(float(b.size()))))
	var step: float = extent * 2.0 / float(n)
	var f: PackedFloat32Array = PackedFloat32Array()
	f.resize(n * n * 4)
	for j in range(n):
		var j0: int = maxi(j - 1, 0)
		var j1: int = mini(j + 1, n - 1)
		for i in range(n):
			var i0: int = maxi(i - 1, 0)
			var i1: int = mini(i + 1, n - 1)
			var o: int = (j * n + i) * 4
			f[o] = b[j * n + i]
			f[o + 1] = (b[j * n + i1] - b[j * n + i0]) / (step * float(i1 - i0))
			f[o + 2] = (b[j1 * n + i] - b[j0 * n + i]) / (step * float(j1 - j0))
			f[o + 3] = 1.0
	return f.to_byte_array()
