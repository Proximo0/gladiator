class_name CapMesh
extends RefCounted
## The gore face of one cut, built once per sever as a single vertex-coloured ArrayMesh in the cap's frame (+Y out of the
## wound, origin on the cut plane): an irregular torn edge, a slight dome with a dented marrow pit, muscle fibres as
## radial colour streaks, a bone ring, a flared collar that tapers the limb's skin into the face, and a few short
## dangling tendrils. Presentation only; a seeded RNG keeps one key looking the same every time.

const RINGS: int = 9
const SEGS: int = 22
const EDGE_NOISE: float = 0.13  ## torn edge: radius varies by this share
const DOME: float = 0.011  ## height of the face's dome at the centre (m)
const PIT: float = 0.007  ## depth of the marrow dent (m)
const BONE_R0: float = 0.12  ## marrow / bone ring edges as shares of the radius
const BONE_R1: float = 0.28
const BONE_LIFT: float = 0.008  ## the bone ring stands this far proud of the flesh
const COLLAR_DROP: float = 0.05  ## how far the collar reaches back down the limb (m)
const COLLAR_RINGS: int = 3
const TENDRILS: int = 3  ## two or three thin ones
const TENDRIL_SEGS: int = 6
const TENDRIL_SIDES: int = 6
const TENDRIL_LEN: float = 0.065
const TENDRIL_SAG: float = 1.0  ## droop: the tip hangs this many lengths below the rise
const TENDRIL_R0: float = 0.011  ## strand radius at the root and at the tip (m)
const TENDRIL_R1: float = 0.0035


## Mesh for a face of `radius` (m) on a limb whose skin is `skin_radius` wide. `pal` holds Colors: flesh, fat, bone,
## marrow, skin. `seed_value` fixes the noise. `gravity` is world down in the cap's frame (the strands sag along it).
static func build(radius: float, skin_radius: float, pal: Dictionary, seed_value: int, gravity: Vector3 = Vector3.DOWN) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ph: Array[float] = []
	for i: int in 6:
		ph.append(rng.randf() * TAU)
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var flesh: Color = pal["flesh"]
	var fat: Color = pal["fat"]
	var bone: Color = pal["bone"]
	var marrow: Color = pal["marrow"]
	var skin: Color = pal["skin"]
	# Face: centre vertex plus RINGS rings.
	pos.append(Vector3(0.0, DOME - PIT, 0.0))
	col.append(marrow)
	for r: int in range(1, RINGS + 1):
		var t: float = float(r) / float(RINGS)
		for s: int in SEGS:
			var a: float = TAU * float(s) / float(SEGS)
			var edge: float = edge_scale(a, ph)
			var rr: float = radius * t * lerpf(1.0, edge, t * t)
			var y: float = face_height(t, a, ph)
			pos.append(Vector3(cos(a) * rr, y, sin(a) * rr))
			col.append(face_color(t, a, ph, flesh, fat, bone, marrow))
	for s: int in SEGS:
		var s2: int = (s + 1) % SEGS
		idx.append_array([0, 1 + s2, 1 + s])
	for r: int in range(1, RINGS):
		for s: int in SEGS:
			var s2: int = (s + 1) % SEGS
			var a0: int = 1 + (r - 1) * SEGS
			var b0: int = 1 + r * SEGS
			idx.append_array([a0 + s, a0 + s2, b0 + s])
			idx.append_array([a0 + s2, b0 + s2, b0 + s])
	# Collar: from the face's torn rim flaring down into the skin, flesh at the top fading to skin colour.
	var rim0: int = 1 + (RINGS - 1) * SEGS
	var base: int = pos.size()
	for c: int in range(1, COLLAR_RINGS + 1):
		var u: float = float(c) / float(COLLAR_RINGS)
		for s: int in SEGS:
			var a: float = TAU * float(s) / float(SEGS)
			var rim: Vector3 = pos[rim0 + s]
			var rim_r: float = Vector2(rim.x, rim.z).length()
			var rr2: float = lerpf(rim_r, skin_radius * 1.03, smoothstep(0.0, 1.0, u))
			var drop: float = COLLAR_DROP * u * (0.75 + 0.25 * sin(a * 3.0 + ph[3]))
			pos.append(Vector3(cos(a) * rr2, rim.y - drop, sin(a) * rr2))
			var cc: Color = fat.lerp(flesh, 0.35).lerp(skin, smoothstep(0.1, 0.9, u))
			col.append(cc)
	for s: int in SEGS:
		var s2: int = (s + 1) % SEGS
		idx.append_array([rim0 + s, rim0 + s2, base + s])
		idx.append_array([rim0 + s2, base + s2, base + s])
	for c: int in range(1, COLLAR_RINGS):
		for s: int in SEGS:
			var s2: int = (s + 1) % SEGS
			var a0: int = base + (c - 1) * SEGS
			var b0: int = base + c * SEGS
			idx.append_array([a0 + s, a0 + s2, b0 + s])
			idx.append_array([a0 + s2, b0 + s2, b0 + s])
	# Tendrils: thin, soft strands. Each leaves the face, bows out a little and then sags over the collar under its own
	# weight (quadratic droop), tapering to a hair-thin wet tip. Flesh coloured, darker toward the tip; no pale one.
	var gdir: Vector3 = gravity.normalized() if gravity.length_squared() > 0.01 else Vector3.DOWN
	for k: int in TENDRILS:
		var a: float = ph[k] + float(k) * TAU / float(TENDRILS)
		var t0: float = rng.randf_range(0.35, 0.65)
		var root: Vector3 = Vector3(cos(a), 0.0, sin(a)) * radius * t0
		root.y = face_height(t0, a, ph)
		var out: Vector3 = Vector3(cos(a), 0.0, sin(a))
		var side: Vector3 = out.cross(Vector3.UP).normalized()
		var len: float = TENDRIL_LEN * rng.randf_range(0.8, 1.25)
		var wob: float = rng.randf_range(-0.012, 0.012)
		var tb: int = pos.size()
		for sg: int in TENDRIL_SEGS + 1:
			var f: float = float(sg) / float(TENDRIL_SEGS)
			var c: Vector3 = root + out * (len * 0.5 * f) + side * (wob * sin(f * PI))
			c.y += len * 0.3 * sin(minf(f * 2.2, 1.0) * PI * 0.5)
			c += gdir * (len * TENDRIL_SAG * f * f)
			var tr: float = lerpf(TENDRIL_R0, TENDRIL_R1, pow(f, 0.8))
			var tcol: Color = flesh.darkened(0.12).lerp(marrow.darkened(0.25), f * 0.7)
			var nb: Vector3 = out.cross(side).normalized()
			for si: int in TENDRIL_SIDES:
				var sa: float = TAU * float(si) / float(TENDRIL_SIDES)
				pos.append(c + (side * cos(sa) + nb * sin(sa)) * tr)
				col.append(tcol)
		for sg: int in TENDRIL_SEGS:
			for si: int in TENDRIL_SIDES:
				var si2: int = (si + 1) % TENDRIL_SIDES
				var p0: int = tb + sg * TENDRIL_SIDES
				var p1: int = tb + (sg + 1) * TENDRIL_SIDES
				idx.append_array([p0 + si, p0 + si2, p1 + si])
				idx.append_array([p0 + si2, p1 + si2, p1 + si])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for i: int in range(0, idx.size(), 3):
		var fn: Vector3 = (pos[idx[i + 1]] - pos[idx[i]]).cross(pos[idx[i + 2]] - pos[idx[i]])
		for j: int in 3:
			nrm[idx[i + j]] += fn
	for i: int in nrm.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 1e-12 else Vector3.UP
	arr[Mesh.ARRAY_NORMAL] = nrm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Radius multiplier of the torn edge at angle `a`: low-frequency lumps plus a ragged high-frequency term.
static func edge_scale(a: float, ph: Array[float]) -> float:
	return 1.0 + EDGE_NOISE * (0.55 * sin(a * 3.0 + ph[0]) + 0.3 * sin(a * 5.0 + ph[1]) + 0.35 * sin(a * 9.0 + ph[2]))


## Height of the face at radius share `t` and angle `a`: dome, marrow pit, raised bone ring, lumpy flesh.
static func face_height(t: float, a: float, ph: Array[float]) -> float:
	var y: float = DOME * (1.0 - t * t)
	y -= PIT * exp(-pow(t / (BONE_R0 * 1.2), 2.0))
	y += BONE_LIFT * smoothstep(BONE_R0 * 0.8, BONE_R0 * 1.2, t) * (1.0 - smoothstep(BONE_R1, BONE_R1 * 1.25, t))
	y += 0.003 * sin(a * 4.0 + ph[3] + t * 6.0) * t
	return y


## Colour at radius share `t`: marrow, bone, then flesh streaked with fibres fading to fat and a dark wet rim.
static func face_color(t: float, a: float, ph: Array[float], flesh: Color, fat: Color, bone: Color, marrow: Color) -> Color:
	if t <= BONE_R0:
		return marrow
	if t <= BONE_R1:
		return bone.lerp(marrow, (1.0 - smoothstep(BONE_R0, BONE_R1, t)) * 0.3)
	var fibre: float = 0.5 + 0.5 * sin(a * 17.0 + ph[4] + 3.0 * sin(a * 5.0 + ph[5]))
	var c: Color = flesh.lerp(flesh.darkened(0.35), fibre * 0.7).lerp(flesh.lightened(0.15), (1.0 - fibre) * 0.25)
	c = c.lerp(fat, smoothstep(0.62, 0.88, t) * (0.4 + 0.5 * fibre))
	return c.lerp(flesh.darkened(0.5), smoothstep(0.9, 1.0, t))
