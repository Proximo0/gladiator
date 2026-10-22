class_name DecorLayout
extends RefCounted
## Where the Houdini decor and dressing pieces stand along the arena wall (pure, no nodes). Angles are degrees round
## the arena (0 is the +X gate, 90 the wall behind spawn 0, 270 the imperial box). Every piece's front (+Z) faces the
## centre. `inset` is how far the piece's origin sits inside the wall's face (negative: sunk into the wall).
## Graphics levels only change the purely visual pieces (columns, stumps, banners); the pieces with colliders
## (gates, barriers, weapon racks) are the same on every level so physics never depends on the graphics setting.

## id, angle (deg), inset (m), scale. The first entries of each list are kept when a level shows fewer.
const COLUMNS: Array = [[15.0], [345.0], [165.0], [195.0], [60.0], [120.0], [240.0], [300.0]]
const STUMPS: Array = [[97.5, 0.0], [277.5, 180.0], [37.5, 180.0], [217.5, 0.0]]  ## angle, extra yaw
const BANNERS: Array = [[71.25], [251.25], [108.75], [288.75]]
const GATES: Array = [[0.0], [180.0]]
const RACKS: Array = [[27.0], [207.0]]
const BARRIERS: Array = [[333.0], [153.0]]

## Engaged columns: half sunk into the wall, the shaft stands 0.24 m proud and the base 0.32 m (no collider).
const COLUMN_SCALE: float = 0.72
const COLUMN_INSET: float = 0.0
const STUMP_SCALE: float = 0.8
const STUMP_INSET: float = 0.0
## Hangs clear of the plinth moulding and under the cornice.
const BANNER_SCALE: float = 0.85
const BANNER_INSET: float = 0.16
## Portcullis: the iron grate hangs just in front of the painted gate arch; the frame stands 0.37 m proud.
const GATE_SCALE: float = 0.78
const GATE_INSET: float = 0.1
const GATE_COLLIDER: Vector3 = Vector3(2.85, 3.0, 0.45)
const GATE_COLLIDER_INSET: float = 0.15
const RACK_SCALE: float = 0.85
const RACK_INSET: float = 0.27
const RACK_COLLIDER: Vector3 = Vector3(1.36, 1.28, 0.5)
const BARRIER_SCALE: float = 0.85
const BARRIER_INSET: float = 0.07
const BARRIER_COLLIDER: Vector3 = Vector3(1.75, 1.0, 0.16)
const BARRIER_COLLIDER_INSET: float = 0.09

## Half widths (m, after scaling) along the wall, for the overlap check.
const HALF_WIDTH: Dictionary = {
	"column": 0.36, "column_stump": 0.55, "banner": 0.73, "portcullis": 1.41, "weapon_rack": 0.68, "barrier": 0.9,
}


## Basis whose +Z faces the arena centre from angle `a` (radians), x the viewer's right, scaled uniformly.
static func facing(a: float, s: float = 1.0, yaw: float = 0.0) -> Basis:
	var b := Basis(Vector3.UP, PI * 0.5 - a)
	var f := Basis(-b.x, Vector3.UP, -b.z)
	if yaw != 0.0:
		f = f * Basis(Vector3.UP, yaw)
	return f.scaled_local(Vector3(s, s, s))


## A point `inset` metres inside the wall face at angle `a` (radians), height `y`.
static func wall_point(radius: float, a: float, inset: float, y: float = 0.0) -> Vector3:
	return Vector3((radius - inset) * cos(a), y, (radius - inset) * sin(a))


## The pieces for an arena of `radius` showing `columns`, `stumps` and `banners` of their lists. Each entry is
## {"id": String, "xf": Transform3D, "angle": float (deg)}.
static func pieces(radius: float, columns: int, stumps: int, banners: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Array in GATES:
		_add(out, "portcullis", radius, float(row[0]), GATE_INSET, GATE_SCALE)
	for row: Array in RACKS:
		_add(out, "weapon_rack", radius, float(row[0]), RACK_INSET, RACK_SCALE)
	for row: Array in BARRIERS:
		_add(out, "barrier", radius, float(row[0]), BARRIER_INSET, BARRIER_SCALE)
	for i: int in mini(columns, COLUMNS.size()):
		_add(out, "column", radius, float(COLUMNS[i][0]), COLUMN_INSET, COLUMN_SCALE)
	for i: int in mini(stumps, STUMPS.size()):
		_add(out, "column_stump", radius, float(STUMPS[i][0]), STUMP_INSET, STUMP_SCALE, deg_to_rad(float(STUMPS[i][1])))
	for i: int in mini(banners, BANNERS.size()):
		_add(out, "banner", radius, float(BANNERS[i][0]), BANNER_INSET, BANNER_SCALE)
	return out


## Box colliders of the dressing that stands proud of the wall: {"xf": Transform3D, "size": Vector3}. The same on
## every graphics level.
static func colliders(radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Array in GATES:
		_add_box(out, radius, float(row[0]), GATE_COLLIDER_INSET, GATE_COLLIDER)
	for row: Array in RACKS:
		_add_box(out, radius, float(row[0]), RACK_INSET, RACK_COLLIDER)
	for row: Array in BARRIERS:
		_add_box(out, radius, float(row[0]), BARRIER_COLLIDER_INSET, BARRIER_COLLIDER)
	return out


static func _add(out: Array[Dictionary], id: String, radius: float, deg: float, inset: float, s: float, yaw: float = 0.0) -> void:
	var a: float = deg_to_rad(deg)
	out.append({"id": id, "xf": Transform3D(facing(a, s, yaw), wall_point(radius, a, inset)), "angle": deg})


static func _add_box(out: Array[Dictionary], radius: float, deg: float, inset: float, size: Vector3) -> void:
	var a: float = deg_to_rad(deg)
	out.append({"xf": Transform3D(facing(a), wall_point(radius, a, inset, size.y * 0.5)), "size": size})
