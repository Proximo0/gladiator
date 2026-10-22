class_name DecorLayout
extends RefCounted
## Where the Houdini dressing stands on the arena floor along the wall, and the box/cylinder colliders that keep a
## fighter out of it (pure, no nodes). Angles are radians round the arena (0 is the +X gate, PI/2 the wall behind
## spawn 0, 3PI/2 the imperial box). Every piece's front (+Z) faces the centre. The colliders depend on the arena radius
## only, never on the graphics level or on whether the art exists, so the presented Arena and the headless match
## (Match._build_collision) collide identically. Visuals and colliders come from the same transforms.

const WALL_SIDES: int = 48
## Gates: the portcullis (3.6 x 3.9 m as exported) scaled to the 3 m podium wall, a column either side.
const GATE_ANGLES: Array[float] = [0.0, PI]
const PORTCULLIS_SCALE: float = 0.8
const PORTCULLIS_OUT: float = 0.08
const GATE_COLUMN_SCALE: float = 0.75
const GATE_COLUMN_OFFSET: float = 1.95
const GATE_COLUMN_OUT: float = 0.3
## Weapon racks against the wall behind each spawn, a little round from the spawn axis.
const RACK_ANGLES: Array[float] = [PI * 0.5 + 0.36, PI * 1.5 + 0.36]
const RACK_OUT: float = 0.32
## Barriers either side of each gate, beyond its columns.
const BARRIER_ANGLES: Array[float] = [0.349, -0.349, PI + 0.349, PI - 0.349]
const BARRIER_SCALE: float = 0.9
const BARRIER_OUT: float = 0.08
## Broken column stumps on the open stretches of wall, turned for variety.
const STUMP_ANGLES: Array[float] = [0.6545, PI + 0.6545]
const STUMP_YAW: Array[float] = [0.6, -2.2]
const STUMP_SCALE: float = 0.8
const STUMP_OUT: float = 0.12

## Collision volumes in each asset's own frame (unscaled; front +Z): "box" size and centre, or "cyl" radius, height
## and centre. Only the solid parts: the portcullis is closed, so its whole frame is one slab.
const SHAPES: Dictionary = {
	"portcullis": {"box": Vector3(3.4, 3.9, 0.7), "centre": Vector3(0.0, 1.95, 0.0)},
	"column": {"cyl": Vector2(0.4, 4.2), "centre": Vector3(0.0, 2.1, 0.0)},
	"weapon_rack": {"box": Vector3(1.6, 1.5, 0.6), "centre": Vector3(0.0, 0.75, 0.0)},
	"barrier": {"box": Vector3(2.1, 1.2, 0.16), "centre": Vector3(0.0, 0.6, 0.02)},
	"column_stump": {"cyl": Vector2(0.36, 1.4), "centre": Vector3(0.0, 0.7, 0.0)},
}


## Basis whose +Z faces the arena centre from angle `a`, x the viewer's right (RomanDecor.face_basis), scaled.
static func facing(a: float, s: float = 1.0, yaw: float = 0.0) -> Basis:
	var b := Basis(Vector3.UP, PI * 0.5 - a)
	var f := Basis(-b.x, Vector3.UP, -b.z)
	if yaw != 0.0:
		f = f * Basis(Vector3.UP, yaw)
	return f.scaled(Vector3(s, s, s))


## The wall's corner-ring point at angle `a` (Arena.ring_point with the wall's apothem), on the floor.
static func wall_point(radius: float, a: float) -> Vector3:
	var r: float = radius / cos(PI / float(WALL_SIDES))
	return Vector3(r * cos(a), 0.0, r * sin(a))


## Floor pieces as {"id": String, "xf": Transform3D}.
static func pieces(radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ga: float in GATE_ANGLES:
		var fb: Basis = facing(ga)
		var face: Vector3 = wall_point(radius, ga)
		out.append({"id": "portcullis", "xf": Transform3D(facing(ga, PORTCULLIS_SCALE), face + fb.z * PORTCULLIS_OUT)})
		for sx: float in [-1.0, 1.0]:
			out.append({"id": "column", "xf": Transform3D(facing(ga, GATE_COLUMN_SCALE), face + fb.z * GATE_COLUMN_OUT + fb.x * (sx * GATE_COLUMN_OFFSET))})
	for a: float in RACK_ANGLES:
		out.append({"id": "weapon_rack", "xf": Transform3D(facing(a), wall_point(radius, a) + facing(a).z * RACK_OUT)})
	for a: float in BARRIER_ANGLES:
		out.append({"id": "barrier", "xf": Transform3D(facing(a, BARRIER_SCALE), wall_point(radius, a) + facing(a).z * BARRIER_OUT)})
	for i: int in STUMP_ANGLES.size():
		var a: float = STUMP_ANGLES[i]
		out.append({"id": "column_stump", "xf": Transform3D(facing(a, STUMP_SCALE, STUMP_YAW[i]), wall_point(radius, a) + facing(a).z * STUMP_OUT)})
	return out


## The floor pieces of one kind, as transforms.
static func transforms(radius: float, id: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p: Dictionary in pieces(radius):
		if p["id"] == id:
			out.append(p["xf"] as Transform3D)
	return out


## Colliders of every floor piece: {"xf": Transform3D (unscaled), "box": Vector3} or {"xf", "cyl": Vector2(radius,
## height)}, sizes already scaled (physics shapes must not be scaled through their transform).
static func colliders(radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in pieces(radius):
		var shape: Dictionary = SHAPES.get(p["id"], {})
		if shape.is_empty():
			continue
		var xf: Transform3D = p["xf"]
		var s: float = xf.basis.x.length()
		var basis: Basis = xf.basis.orthonormalized()
		var c: Dictionary = {"xf": Transform3D(basis, xf * (shape["centre"] as Vector3))}
		if shape.has("box"):
			c["box"] = (shape["box"] as Vector3) * s
		else:
			c["cyl"] = (shape["cyl"] as Vector2) * s
		out.append(c)
	return out
