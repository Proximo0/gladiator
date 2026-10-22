class_name BloodMesh
extends RefCounted
## Builds the unit droplet mesh: a teardrop along Z (round head at +Z, tapering tail at -Z, radius 1).
## The droplet shader scales head and tail separately and orients the mesh along the velocity.


const TAIL_RINGS: int = 6
const HEAD_RINGS: int = 8  ## rings from the head's equator to its tip: round silhouette, no visible facets


static func teardrop(radial: int = 12) -> ArrayMesh:
	var prof: Array[Vector2] = []  # (radius, z) from tail tip to head tip
	for i: int in TAIL_RINGS:  # rounded elliptical tail (no needle tip): reads as a liquid streak when stretched
		var th0: float = float(i) / float(TAIL_RINGS) * PI * 0.5
		prof.append(Vector2(sin(th0), -cos(th0)))
	for j: int in HEAD_RINGS + 1:
		var th: float = float(j) / float(HEAD_RINGS) * PI * 0.5
		prof.append(Vector2(cos(th), sin(th)))
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var idx: PackedInt32Array = PackedInt32Array()
	var rings: int = prof.size()
	for ri: int in rings:
		var a: Vector2 = prof[maxi(ri - 1, 0)]
		var b: Vector2 = prof[mini(ri + 1, rings - 1)]
		var tan2: Vector2 = (b - a).normalized()
		var n2: Vector2 = Vector2(tan2.y, -tan2.x)  # (radial, z) outward normal
		for k: int in radial:
			var az: float = TAU * float(k) / float(radial)
			var cx: float = cos(az)
			var cy: float = sin(az)
			verts.append(Vector3(cx * prof[ri].x, cy * prof[ri].x, prof[ri].y))
			norms.append(Vector3(cx * n2.x, cy * n2.x, n2.y).normalized())
			cols.append(Color.WHITE)  # explicit: some GL drivers default a missing COLOR attribute to black
	for ri: int in rings - 1:
		for k: int in radial:
			var k2: int = (k + 1) % radial
			var i0: int = ri * radial + k
			var i1: int = ri * radial + k2
			var i2: int = (ri + 1) * radial + k
			var i3: int = (ri + 1) * radial + k2
			idx.append_array(PackedInt32Array([i0, i1, i2, i1, i3, i2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
