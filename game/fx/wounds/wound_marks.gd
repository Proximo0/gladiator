class_name WoundMarks
extends RefCounted
## Accumulated damage on one fighter's body, as marks in each part's own frame: gashes (edged hits), punctures
## (points), bruises (blunt, they swell), smears (blood splashed on skin or armor, bloody knuckles) and rings (the wet
## band round a stump or a severed part's cut end). Marks stay for the whole match, darken as they dry, and gashes and
## punctures grow a trickle of blood running down. A part keeps at most `cap` marks (the body shader loops over them);
## a new mark near an old one of the same kind deepens it instead. A full part drops its oldest lesser mark (smears,
## then bruises) for a new one; when nothing lesser is left the new mark deepens the nearest of its kind instead, so a
## part's marks stop churning once it fills up with wounds.
## Pure data and math: no nodes, no RNG (seeds come from the hit itself, so a host and a client draw the same marks).
## Presentation only: never read back by the fight.

enum Kind { GASH, PUNCTURE, BRUISE, SMEAR, RING }

const MAX_CAP: int = 8  ## the shader's loop bound; a part never holds more
const CAPS: Array[int] = [6, 8, 8]  ## marks per part per graphics level (low, medium, high)
const MIN_WOUND: float = 1.2  ## damage points (cut + pierce, or 0.35 x blunt) below which a hit leaves no mark
const DRY_TAU: float = 45.0  ## seconds for a mark to get most of the way from fresh to dried
const TRICKLE_SPEED: float = 0.035  ## m/s a fresh trickle runs down
const TRICKLE_MAX: float = 0.16  ## longest trickle of a full-strength wound
const MERGE_DIST: float = 0.035  ## a new mark this close to one of its kind deepens that one
## Sizes (m), cartoonishly big so they read at fight distance.
const GASH_LEN_MIN: float = 0.06
const GASH_LEN_MAX: float = 0.22
const GASH_W_MIN: float = 0.018
const GASH_W_MAX: float = 0.04
const HOLE_MIN: float = 0.014
const HOLE_MAX: float = 0.034
const BRUISE_MIN: float = 0.04
const BRUISE_MAX: float = 0.1
const SMEAR_MIN: float = 0.025
const SMEAR_MAX: float = 0.08
const STRETCH_MAX: float = 3.0  ## longest streak of a smear, as length over width
## Rank of each kind when a full part must drop a mark (lower goes first): smear, bruise, open wounds, ring.
const RANK: Array[int] = [2, 2, 1, 0, 3]
const FULL_DEEPEN: float = 0.4  ## share of a new mark's strength that deepens the nearest one when the part is full
## Damage at which a mark reaches full size and strength.
const FULL_CUT: float = 20.0
const FULL_PIERCE: float = 18.0
const FULL_BLUNT: float = 30.0
## Surface snap: the hit point is pulled onto the part's collision surface within this band (m) so marks sit on
## the skin even when the contact point is a little inside the body or off it.
const SNAP_IN: float = 0.02
const SNAP_OUT: float = 0.012


class Mark extends RefCounted:
	var kind: int = 0
	var pos: Vector3 = Vector3.ZERO  ## part frame
	var nrm: Vector3 = Vector3.UP  ## outward surface normal, part frame
	var dir: Vector3 = Vector3.RIGHT  ## along the cut (tangent), part frame
	var down: Vector3 = Vector3.DOWN  ## world down at the time of the hit, in the part frame (tangent)
	var size: float = 0.05  ## half length of a gash, radius of the others
	var width: float = 0.01  ## half width of a gash (a smear: its radius across `dir`)
	var stretch: float = 1.0  ## a smear's length over its width (a drop that landed fast streaks along `dir`)
	var sev: float = 0.5  ## 0..1 strength
	var age: float = 0.0
	var seed: float = 0.0  ## 0..1 shape variety
	var slot: int = 0  ## blood palette slot (the side whose blood it is)
	var bleeds: bool = false

var cap: int = MAX_CAP
var marks: Dictionary = {}  ## part name -> Array of Mark, oldest first
var dirty: Dictionary = {}  ## part name -> true when its packed uniforms changed shape (added or merged)
var evicted: int = 0  ## marks dropped from a full part so far (churn)


func _init(level: int = 2) -> void:
	cap = cap_for(level)


static func cap_for(level: int) -> int:
	return mini(CAPS[clampi(level, 0, CAPS.size() - 1)], MAX_CAP)


## Mark kind for a hit: GASH, PUNCTURE, BRUISE, or -1 for none (too weak, or a glancing tap).
static func kind_for(contact: String, cut: float, pierce: float, blunt: float, glanced: bool) -> int:
	var scale: float = 0.5 if glanced else 1.0
	var sharp: float = (cut + pierce) * scale
	if sharp >= MIN_WOUND and sharp >= 0.35 * blunt * scale:
		if pierce > cut * 1.2 or (contact == "point" and pierce >= cut):
			return Kind.PUNCTURE
		return Kind.GASH
	if 0.35 * blunt * scale >= MIN_WOUND:
		return Kind.BRUISE
	return -1


## Strength 0..1 of a mark of `kind` from the hit's damage numbers.
static func severity(kind: int, cut: float, pierce: float, blunt: float) -> float:
	match kind:
		Kind.GASH:
			return clampf((cut + 0.5 * pierce) / FULL_CUT, 0.15, 1.0)
		Kind.PUNCTURE:
			return clampf((pierce + 0.5 * cut) / FULL_PIERCE, 0.15, 1.0)
		Kind.BRUISE:
			return clampf(blunt / FULL_BLUNT, 0.15, 1.0)
	return clampf((cut + pierce + 0.3 * blunt) / FULL_CUT, 0.15, 1.0)


## Outward surface normal of a part at local point `p`: radial from the bone axis for capsules (Y is the bone),
## an ellipsoid normal for boxes (the art is rounded), radial for spheres and the head.
static func surface_normal(shape: String, size: Vector3, p: Vector3) -> Vector3:
	var n: Vector3
	match shape:
		"capsule":
			var hs: float = maxf(size.y * 0.5 - size.x, 0.0)
			n = p - Vector3(0, clampf(p.y, -hs, hs), 0)
		"box":
			var h: Vector3 = size * 0.5
			n = Vector3(p.x / (h.x * h.x), p.y / (h.y * h.y), p.z / (h.z * h.z))
		_:
			n = p
	if n.length_squared() < 1e-8:
		return Vector3.FORWARD
	return n.normalized()


## `p` pulled onto the part's collision surface (within SNAP_IN / SNAP_OUT of it).
static func snap_to_surface(shape: String, size: Vector3, p: Vector3) -> Vector3:
	match shape:
		"capsule":
			var hs: float = maxf(size.y * 0.5 - size.x, 0.0)
			var c: Vector3 = Vector3(0, clampf(p.y, -hs, hs), 0)
			var r: Vector3 = p - c
			var d: float = r.length()
			if d < 1e-5:
				return p
			return c + r / d * clampf(d, size.x - SNAP_IN, size.x + SNAP_OUT)
		"box":
			var h: Vector3 = size * 0.5
			var e: float = Vector3(p.x / h.x, p.y / h.y, p.z / h.z).length()
			if e < 1e-5:
				return p
			return p * clampf(e, 1.0 - SNAP_IN / h.z, 1.0 + SNAP_OUT / h.z) / e
		_:
			var d2: float = p.length()
			if d2 < 1e-5:
				return p
			return p / d2 * clampf(d2, size.x - SNAP_IN, size.x + SNAP_OUT)


## `v` projected onto the plane of normal `n` and normalised; `fallback` (also projected) when that is degenerate.
static func tangent(v: Vector3, n: Vector3, fallback: Vector3) -> Vector3:
	var t: Vector3 = v - n * v.dot(n)
	if t.length_squared() < 1e-6:
		t = fallback - n * fallback.dot(n)
	if t.length_squared() < 1e-6:
		t = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP)
	return t.normalized()


## A 0..1 shape seed from the hit point (the same on host and client).
static func seed_of(p: Vector3) -> float:
	var s: float = sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return s - floorf(s)


## Seconds-of-age to dryness 0 (fresh) .. 1 (dried).
static func dryness(age: float) -> float:
	return 1.0 - exp(-maxf(age, 0.0) / DRY_TAU)


## Adds a mark on `part`. `pos`, `nrm`, `motion` (the weapon's motion, for a gash's direction) and `down` are in
## the part frame. Returns the mark (a merged one when it deepened an old mark), or null for a bad kind or a full part
## with nothing to make room or deepen.
## `stretch` (smears only, 1..3) streaks the smear along `motion`.
func add(part: String, kind: int, pos: Vector3, nrm: Vector3, motion: Vector3, down: Vector3, sev: float,
		slot: int, stretch: float = 1.0) -> Mark:
	if kind < Kind.GASH or kind > Kind.RING:
		return null
	var list: Array = marks.get(part, [])
	var n: Vector3 = nrm.normalized() if nrm.length_squared() > 1e-8 else Vector3.FORWARD
	sev = clampf(sev, 0.0, 1.0)
	for m: Mark in list:
		if m.kind == kind and m.slot == slot and m.pos.distance_to(pos) < maxf(MERGE_DIST, m.size * 0.6):
			_deepen(m, sev)
			dirty[part] = true
			return m
	var mk: Mark = Mark.new()
	mk.kind = kind
	mk.pos = pos
	mk.nrm = n
	mk.seed = seed_of(pos)
	mk.dir = tangent(motion, n, Vector3.UP.rotated(n, mk.seed * TAU))
	mk.down = tangent(down, n, Vector3.DOWN)
	mk.slot = slot
	mk.sev = sev
	mk.bleeds = kind == Kind.GASH or kind == Kind.PUNCTURE
	mk.stretch = clampf(stretch, 1.0, STRETCH_MAX) if kind == Kind.SMEAR else 1.0
	_size(mk)
	return _insert(part, list, mk)


## A blood ring round the cut end of `part`: centred on the joint `pos`, running back into the part from the cut along
## `-axis` (`axis` points out of the part, through the cut) for `band` m, on the surface within `radius` m of the bone.
func add_ring(part: String, pos: Vector3, axis: Vector3, radius: float, band: float, sev: float, slot: int) -> Mark:
	var list: Array = marks.get(part, [])
	var n: Vector3 = axis.normalized() if axis.length_squared() > 1e-8 else Vector3.UP
	for m: Mark in list:
		if m.kind == Kind.RING and m.pos.distance_to(pos) < MERGE_DIST:
			_deepen(m, sev)
			dirty[part] = true
			return m
	var mk: Mark = Mark.new()
	mk.kind = Kind.RING
	mk.pos = pos
	mk.nrm = n
	mk.seed = seed_of(pos)
	mk.dir = tangent(Vector3.RIGHT, n, Vector3.FORWARD)
	mk.down = tangent(Vector3.DOWN, n, Vector3.DOWN)
	mk.slot = slot
	mk.sev = clampf(sev, 0.0, 1.0)
	mk.size = maxf(radius, 0.01)
	mk.width = maxf(band, 0.005)
	return _insert(part, list, mk)


## Puts `mk` on `part`, making room on a full part (see the class notes). Returns the mark that holds it: `mk`, or the
## old mark it deepened, or null when the part had no room and nothing of its kind to deepen.
func _insert(part: String, list: Array, mk: Mark) -> Mark:
	if list.size() >= cap:
		var i: int = _evict_index(list, mk.kind)
		if i < 0:
			var near: Mark = _nearest(list, mk.kind, mk.slot, mk.pos)
			if near == null:
				return null
			_deepen(near, mk.sev * FULL_DEEPEN)
			dirty[part] = true
			return near
		list.remove_at(i)
		evicted += 1
	list.append(mk)
	marks[part] = list
	dirty[part] = true
	return mk


func _deepen(m: Mark, sev: float) -> void:
	m.sev = minf(1.0, maxf(m.sev, sev) + 0.25 * sev)
	m.age = minf(m.age, 2.0)  ## fresh blood over the old wound
	_size(m)


func _size(m: Mark) -> void:
	var s: float = m.sev
	match m.kind:
		Kind.GASH:
			m.size = lerpf(GASH_LEN_MIN, GASH_LEN_MAX, s) * 0.5
			m.width = lerpf(GASH_W_MIN, GASH_W_MAX, s) * 0.5
		Kind.PUNCTURE:
			m.size = lerpf(HOLE_MIN, HOLE_MAX, s)
			m.width = m.size
		Kind.BRUISE:
			m.size = lerpf(BRUISE_MIN, BRUISE_MAX, s)
			m.width = m.size
		Kind.SMEAR:
			m.size = lerpf(SMEAR_MIN, SMEAR_MAX, s) * sqrt(m.stretch)
			m.width = m.size / m.stretch


## Severity of a smear whose radius is `radius` m (the inverse of its sizing; 0 at SMEAR_MIN and below).
static func smear_sev_for(radius: float) -> float:
	return clampf(inverse_lerp(SMEAR_MIN, SMEAR_MAX, radius), 0.0, 1.0)


## Which mark a new mark of `kind` replaces on a full part: the oldest of the lowest rank below the new one's (smears
## first, then bruises, then open wounds for a ring), or -1 when every mark ranks as high or higher.
static func _evict_index(list: Array, kind: int) -> int:
	var best: int = -1
	var best_rank: int = RANK[kind]
	for i: int in list.size():
		var r: int = RANK[(list[i] as Mark).kind]
		if r < best_rank:
			best_rank = r
			best = i
	return best


## The mark of `kind` and palette `slot` nearest `pos`, or null.
static func _nearest(list: Array, kind: int, slot: int, pos: Vector3) -> Mark:
	var best: Mark = null
	var best_d: float = INF
	for m: Mark in list:
		if m.kind == kind and m.slot == slot and m.pos.distance_squared_to(pos) < best_d:
			best_d = m.pos.distance_squared_to(pos)
			best = m
	return best


## A smear's outline radius (share of its size) at angle `ang` round its centre: a few soft lobes from low, whole
## harmonics (so the outline closes on itself with no seam), at most `amp` in or out. Mirrors wound_overlay.gdshader.
static func smear_lobe(ang: float, seed: float, amp: float) -> float:
	var p: float = seed * TAU
	return 1.0 + amp * (0.55 * sin(2.0 * ang + p) + 0.3 * sin(3.0 * ang + 2.3 * p) + 0.15 * sin(5.0 * ang + 4.1 * p))


func step(dt: float) -> void:
	for part: String in marks:
		for m: Mark in marks[part]:
			m.age += dt


func count(part: String = "") -> int:
	if part != "":
		return (marks.get(part, []) as Array).size()
	var n: int = 0
	for p: String in marks:
		n += (marks[p] as Array).size()
	return n


## Current trickle length (m) of a mark: runs down while fresh, as long as the wound is strong.
static func trickle_len(m: Mark) -> float:
	if not m.bleeds:
		return 0.0
	return minf(m.age * TRICKLE_SPEED, TRICKLE_MAX * (0.35 + 0.65 * m.sev))


## The shader uniforms for `part`, five arrays of MAX_CAP vec4 each plus the count:
## a = (pos, size), b = (dir, width), c = (normal, kind), d = (down, trickle length), e = (dryness, seed, slot, sev).
func pack(part: String) -> Dictionary:
	var a: PackedVector4Array = PackedVector4Array()
	var b: PackedVector4Array = PackedVector4Array()
	var c: PackedVector4Array = PackedVector4Array()
	var d: PackedVector4Array = PackedVector4Array()
	var e: PackedVector4Array = PackedVector4Array()
	for arr: PackedVector4Array in [a, b, c, d, e]:
		arr.resize(MAX_CAP)
	var list: Array = draw_order(marks.get(part, []))
	var n: int = mini(list.size(), MAX_CAP)
	for i: int in n:
		var m: Mark = list[i]
		a[i] = Vector4(m.pos.x, m.pos.y, m.pos.z, m.size)
		b[i] = Vector4(m.dir.x, m.dir.y, m.dir.z, m.width)
		c[i] = Vector4(m.nrm.x, m.nrm.y, m.nrm.z, float(m.kind))
		d[i] = Vector4(m.down.x, m.down.y, m.down.z, trickle_len(m))
		e[i] = Vector4(dryness(m.age), m.seed, float(m.slot), m.sev)
	return {"count": n, "a": a, "b": b, "c": c, "d": d, "e": e}


## Marks in the order the shader layers them: smears, then bruises, then the open wounds on top (a later splash must
## not paint over a cut or a hole). Oldest first within each group.
static func draw_order(list: Array) -> Array:
	var out: Array = []
	for group: Array in [[Kind.SMEAR], [Kind.BRUISE], [Kind.GASH, Kind.PUNCTURE, Kind.RING]]:
		for m: Mark in list:
			if group.has(m.kind):
				out.append(m)
	return out


func clear() -> void:
	marks.clear()
	dirty.clear()
	evicted = 0
