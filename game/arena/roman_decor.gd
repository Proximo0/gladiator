class_name RomanDecor
extends RefCounted
## Procedural Roman decoration helpers for the arena: quads, boxes, stroke-drawn Latin capitals, laurel wreaths,
## Greek key (meander) strips, arches and a simple aquila. All draw into a SurfaceTool with vertex colours.

const PALETTE_RED: Color = Color(0.557, 0.165, 0.118)
const PALETTE_OCHRE: Color = Color(0.72, 0.5, 0.16)
const PALETTE_BLACK: Color = Color(0.11, 0.102, 0.09)
const MARBLE: Color = Color(0.88, 0.85, 0.78)
const GOLD: Color = Color(0.86, 0.66, 0.22)
const LAUREL: Color = Color(0.32, 0.4, 0.15)
const PURPLE: Color = Color(0.36, 0.1, 0.34)

## Letters as polylines in a unit box (x 0..1 is letter width, y 0..1 is height).
const LETTERS: Dictionary = {
	"A": [[[0, 0], [0.5, 1], [1, 0]], [[0.2, 0.4], [0.8, 0.4]]],
	"C": [[[1, 0.85], [0.7, 1], [0.3, 1], [0, 0.75], [0, 0.25], [0.3, 0], [0.7, 0], [1, 0.15]]],
	"D": [[[0, 0], [0, 1], [0.6, 1], [1, 0.7], [1, 0.3], [0.6, 0], [0, 0]]],
	"E": [[[1, 1], [0, 1], [0, 0], [1, 0]], [[0, 0.5], [0.7, 0.5]]],
	"G": [[[1, 0.85], [0.7, 1], [0.3, 1], [0, 0.75], [0, 0.25], [0.3, 0], [0.7, 0], [1, 0.15], [1, 0.45], [0.55, 0.45]]],
	"I": [[[0.5, 0], [0.5, 1]], [[0.2, 1], [0.8, 1]], [[0.2, 0], [0.8, 0]]],
	"L": [[[0, 1], [0, 0], [1, 0]]],
	"M": [[[0, 0], [0, 1], [0.5, 0.35], [1, 1], [1, 0]]],
	"N": [[[0, 0], [0, 1], [1, 0], [1, 1]]],
	"O": [[[0.3, 1], [0.7, 1], [1, 0.75], [1, 0.25], [0.7, 0], [0.3, 0], [0, 0.25], [0, 0.75], [0.3, 1]]],
	"P": [[[0, 0], [0, 1], [0.7, 1], [1, 0.8], [1, 0.62], [0.7, 0.45], [0, 0.45]]],
	"Q": [[[0.3, 1], [0.7, 1], [1, 0.75], [1, 0.25], [0.7, 0], [0.3, 0], [0, 0.25], [0, 0.75], [0.3, 1]], [[0.55, 0.3], [1.05, -0.15]]],
	"R": [[[0, 0], [0, 1], [0.7, 1], [1, 0.8], [1, 0.62], [0.7, 0.45], [0, 0.45]], [[0.5, 0.45], [1, 0]]],
	"S": [[[1, 0.85], [0.7, 1], [0.3, 1], [0, 0.8], [0.1, 0.6], [0.9, 0.4], [1, 0.2], [0.7, 0], [0.3, 0], [0, 0.15]]],
	"T": [[[0, 1], [1, 1]], [[0.5, 1], [0.5, 0]]],
	"V": [[[0, 1], [0.5, 0], [1, 1]]],
}


## Adds a quad whose front looks along `front_hint`; winding is fixed for Godot's clockwise fronts.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, front_hint: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var order: Array[Vector3]
	if n.dot(front_hint) > 0.0:
		order = [a, c, b, a, d, c]
	else:
		n = -n
		order = [a, b, c, a, c, d]
	for p: Vector3 in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, front_hint: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var order: Array[Vector3]
	if n.dot(front_hint) > 0.0:
		order = [a, c, b]
	else:
		n = -n
		order = [a, b, c]
	for p: Vector3 in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h: Vector3 = size * 0.5
	var c: Array[Vector3] = []
	for i: int in 8:
		c.append(xf * Vector3(h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z))
	var faces: Array = [
		[0, 1, 3, 2, -xf.basis.z], [4, 5, 7, 6, xf.basis.z],
		[0, 4, 6, 2, -xf.basis.x], [1, 5, 7, 3, xf.basis.x],
		[0, 1, 5, 4, -xf.basis.y], [2, 3, 7, 6, xf.basis.y],
	]
	for f: Array in faces:
		quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]], col, f[4])


## Basis for something that faces the arena centre from angle `a`: x is the viewer's right, z points at the viewer.
static func face_basis(a: float) -> Basis:
	var b: Basis = Arena.ring_basis(a)
	return Basis(-b.x, Vector3.UP, -b.z)


## A flat rectangle on a face: centre `c`, face basis `fb`, size (w, h).
static func rect(st: SurfaceTool, c: Vector3, fb: Basis, w: float, h: float, col: Color) -> void:
	var rx: Vector3 = fb.x * (w * 0.5)
	var uy: Vector3 = fb.y * (h * 0.5)
	quad(st, c - rx - uy, c + rx - uy, c + rx + uy, c - rx + uy, col, fb.z)


## A stroke of thickness `t` between two points on a face, extended half a thickness at each end.
static func stroke(st: SurfaceTool, p0: Vector3, p1: Vector3, fb: Basis, t: float, col: Color) -> void:
	var d: Vector3 = p1 - p0
	if d.length() < 0.0001:
		return
	var dir: Vector3 = d.normalized()
	var side: Vector3 = fb.z.cross(dir).normalized() * (t * 0.5)
	var a: Vector3 = p0 - dir * (t * 0.5)
	var b: Vector3 = p1 + dir * (t * 0.5)
	quad(st, a - side, b - side, b + side, a + side, col, fb.z)


## Width of a text line at height `h` (letters 0.72 h wide, 0.3 h gaps, word gaps 0.6 h).
static func text_width(text: String, h: float) -> float:
	var w: float = 0.0
	for i: int in text.length():
		w += h * 0.6 if text[i] == " " else h * 1.02
	return maxf(w - h * 0.3, 0.0)


## Draws Latin capitals centred on `c` (centre of the line) on a face. Unknown letters are skipped.
static func text(st: SurfaceTool, s: String, c: Vector3, fb: Basis, h: float, col: Color) -> void:
	var x: float = -text_width(s, h) * 0.5
	var lw: float = h * 0.72
	for i: int in s.length():
		var ch: String = s[i]
		if ch == " ":
			x += h * 0.6
			continue
		if LETTERS.has(ch):
			for line: Array in LETTERS[ch]:
				for k: int in line.size() - 1:
					var a: Array = line[k]
					var b: Array = line[k + 1]
					var pa: Vector3 = c + fb.x * (x + float(a[0]) * lw) + fb.y * ((float(a[1]) - 0.5) * h)
					var pb: Vector3 = c + fb.x * (x + float(b[0]) * lw) + fb.y * ((float(b[1]) - 0.5) * h)
					stroke(st, pa, pb, fb, h * 0.13, col)
		x += h * 1.02


## Laurel wreath: leaf diamonds on a circle, open at the top.
static func wreath(st: SurfaceTool, c: Vector3, fb: Basis, r: float, col: Color) -> void:
	var leaves: int = 11
	for side: int in 2:
		var sgn: float = 1.0 if side == 0 else -1.0
		for k: int in leaves:
			# Point on the circle: angle measured from the bottom, up each side.
			var phi: float = deg_to_rad(10.0 + 15.0 * float(k))
			var pos: Vector3 = c + fb.x * (sgn * r * sin(phi)) - fb.y * (r * cos(phi))
			var tangent: Vector3 = (fb.x * (sgn * cos(phi)) + fb.y * sin(phi)).normalized()
			var normal: Vector3 = fb.z.cross(tangent).normalized()
			var l: float = r * 0.2
			var w: float = r * 0.09
			var leaf_col: Color = col * (0.85 + 0.3 * float((k * 7 + side * 3) % 5) / 4.0)
			leaf_col.a = 1.0
			quad(st, pos - tangent * l, pos + normal * w, pos + tangent * l, pos - normal * w, leaf_col, fb.z)
	# Ribbon tie at the bottom.
	quad(st, c - fb.y * (r * 1.02) - fb.x * (r * 0.1), c - fb.y * (r * 0.88) - fb.x * (r * 0.05), c - fb.y * (r * 1.0) + fb.x * (r * 0.1), c - fb.y * (r * 1.12), PALETTE_RED, fb.z)


## Greek key strip from `from` along `dir` for `length`, `h` tall: background plus hooks.
static func meander(st: SurfaceTool, from: Vector3, dir: Vector3, length: float, h: float, fb: Basis, bg: Color, ink: Color) -> void:
	var up: Vector3 = fb.y
	var mid: Vector3 = from + dir * (length * 0.5) + up * (h * 0.5)
	var half_len: Vector3 = dir * (length * 0.5)
	var half_h: Vector3 = up * (h * 0.5)
	quad(st, mid - half_len - half_h, mid + half_len - half_h, mid + half_len + half_h, mid - half_len + half_h, bg, fb.z)
	var lift: Vector3 = fb.z * 0.004
	var unit: float = h * 1.0
	var n: int = int(length / unit)
	var t: float = h * 0.14
	for k: int in n:
		var x0: Vector3 = from + dir * (unit * float(k) + unit * 0.5) + lift
		# Hook: upright, top bar, down stub, in-turn.
		var base: Vector3 = x0 - dir * (unit * 0.38)
		var p0: Vector3 = base + up * (h * 0.12)
		var p1: Vector3 = base + up * (h * 0.88)
		var p2: Vector3 = base + dir * (unit * 0.76) + up * (h * 0.88)
		var p3: Vector3 = base + dir * (unit * 0.76) + up * (h * 0.38)
		var p4: Vector3 = base + dir * (unit * 0.4) + up * (h * 0.38)
		stroke(st, p0, p1, fb, t, ink)
		stroke(st, p1, p2, fb, t, ink)
		stroke(st, p2, p3, fb, t, ink)
		stroke(st, p3, p4, fb, t, ink)


## Arched opening: a rectangle with a semicircular top. `base` is the centre of the bottom edge.
static func arch(st: SurfaceTool, base: Vector3, fb: Basis, w: float, h: float, col: Color) -> void:
	var r: float = w * 0.5
	var rect_h: float = maxf(h - r, 0.01)
	rect(st, base + fb.y * (rect_h * 0.5), fb, w, rect_h, col)
	var top: Vector3 = base + fb.y * rect_h
	var steps: int = 8
	for i: int in steps:
		var a0: float = PI * float(i) / float(steps)
		var a1: float = PI * float(i + 1) / float(steps)
		var p0: Vector3 = top + fb.x * (r * cos(a0)) + fb.y * (r * sin(a0))
		var p1: Vector3 = top + fb.x * (r * cos(a1)) + fb.y * (r * sin(a1))
		tri(st, top, p0, p1, col, fb.z)


## A stylised eagle with spread wings, `s` wide, centred on `c`.
static func aquila(st: SurfaceTool, c: Vector3, fb: Basis, s: float, col: Color) -> void:
	var u: float = s * 0.5
	# Body and head.
	rect(st, c + fb.y * (u * 0.05), fb, u * 0.22, u * 0.7, col)
	tri(st, c + fb.y * (u * 0.42) - fb.x * (u * 0.1), c + fb.y * (u * 0.42) + fb.x * (u * 0.1), c + fb.y * (u * 0.62) - fb.x * (u * 0.18), col, fb.z)
	# Tail.
	tri(st, c - fb.y * (u * 0.28) - fb.x * (u * 0.14), c - fb.y * (u * 0.28) + fb.x * (u * 0.14), c - fb.y * (u * 0.6), col, fb.z)
	# Wings: stacked feather wedges, both sides.
	for side: int in 2:
		var sg: float = 1.0 if side == 0 else -1.0
		for k: int in 4:
			var y0: float = u * (0.35 - 0.15 * float(k))
			var reach: float = u * (1.0 - 0.12 * float(k))
			var tipy: float = y0 + u * (0.28 - 0.1 * float(k))
			tri(st, c + fb.y * y0 + fb.x * (sg * u * 0.1), c + fb.y * (y0 - u * 0.17) + fb.x * (sg * u * 0.1), c + fb.y * tipy + fb.x * (sg * reach), col * (0.9 + 0.05 * float(k)), fb.z)
