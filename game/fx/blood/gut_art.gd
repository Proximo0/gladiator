class_name GutArt
extends RefCounted
## The gut spill's meshes: the Houdini gore pieces in res://assets/gore/ (tools/houdini/build_props.py), each merged
## into one opaque surface and normalised to the unit frame GutSim writes its instance transforms in. The glb's
## materials are dropped (Houdini's glTF exporter makes every material alpha BLEND); their base colours are baked
## into vertex colours relative to the piece's main colour, so the instance colour (the fighter's blood palette)
## sets the main tone and fat, torn ends and vessels keep their shade against it. Built once per process and
## shared, read-only, by every BloodFx. A missing file falls back to a sphere, so the spill never disappears.

const DIR: String = "res://assets/gore/"
const FILES: PackedStringArray = ["gut_rope", "gut_torn", "gut_cluster", "gut_coil", "liver", "stomach", "heart"]
const ROT_Y_TO_Z: Basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))  ## columns: y -> z, z -> -y

static var _meshes: Array = []  ## by GutSim kind: Mesh
static var _floors: PackedFloat32Array = PackedFloat32Array()
static var _sizes: PackedFloat32Array = PackedFloat32Array()  ## authored half width, m (organs keep their size)


## The mesh for GutSim kind `kind`.
static func mesh(kind: int) -> Mesh:
	_ensure()
	return _meshes[clampi(kind, 0, GutSim.KINDS - 1)] as Mesh


## How high the piece's centre sits above the sand when it rests, as a share of its size.
static func floor_share(kind: int) -> float:
	_ensure()
	return _floors[clampi(kind, 0, GutSim.KINDS - 1)]


## The authored half width of the piece in metres (a liver is a liver's size).
static func authored_size(kind: int) -> float:
	_ensure()
	return _sizes[clampi(kind, 0, GutSim.KINDS - 1)]


static func _ensure() -> void:
	if not _meshes.is_empty():
		return
	_floors.resize(GutSim.KINDS)
	_sizes.resize(GutSim.KINDS)
	for k: int in GutSim.KINDS:
		var d: Dictionary = _build(k)
		_meshes.append(d["mesh"])
		_floors[k] = float(d["floor"])
		_sizes[k] = float(d["size"])


## Loads and normalises one kind: {"mesh", "floor", "size"}.
static func _build(kind: int) -> Dictionary:
	var src: Dictionary = _load_merged(DIR + FILES[kind] + ".glb")
	if src.is_empty():
		src = _sphere()
	var verts: PackedVector3Array = src["v"]
	var norms: PackedVector3Array = src["n"]
	var rot: Basis = ROT_Y_TO_Z if kind == GutSim.K_LINK or kind == GutSim.K_TORN else Basis.IDENTITY
	for i: int in verts.size():
		verts[i] = rot * verts[i]
		norms[i] = rot * norms[i]
	var lo: Vector3 = verts[0]
	var hi: Vector3 = verts[0]
	for p: Vector3 in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var half: Vector3 = (hi - lo) * 0.5
	var mid: Vector3 = (hi + lo) * 0.5
	var off: Vector3 = -mid
	var sc: Vector3
	var wide: float = maxf(maxf(half.x, half.z), 0.0001)
	var floor_s: float = half.y / wide
	match kind:
		GutSim.K_LINK:  # unit tube: radius 1, z -1..1
			wide = maxf(maxf(half.x, half.y), 0.0001)
			sc = Vector3(1.0 / wide, 1.0 / wide, 1.0 / maxf(half.z, 0.0001))
			floor_s = 1.0
		GutSim.K_TORN:  # radius 1, from the joined end at z 0 to the torn end at z 1
			wide = maxf(maxf(half.x, half.y), 0.0001)
			off = Vector3(-mid.x, -mid.y, -lo.z)
			sc = Vector3(1.0 / wide, 1.0 / wide, 1.0 / maxf(hi.z - lo.z, 0.0001))
			floor_s = 1.0
		GutSim.K_CLUSTER:  # unit wide, sitting on y 0 (the wound)
			off = Vector3(-mid.x, -lo.y, -mid.z)
			sc = Vector3.ONE / wide
		_:
			sc = Vector3.ONE / wide
	var inv: Vector3 = Vector3(1.0 / sc.x, 1.0 / sc.y, 1.0 / sc.z)
	for i: int in verts.size():
		verts[i] = (verts[i] + off) * sc
		norms[i] = (norms[i] * inv).normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = src["c"]
	arrays[Mesh.ARRAY_INDEX] = src["i"]
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": am, "floor": floor_s, "size": wide}


## Every surface of the first mesh in a glb merged into one: {"v", "n", "c", "i"}, colours relative to the largest
## surface's base colour. {} when the file is missing or holds no mesh.
static func _load_merged(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return {}
	var root: Node = ps.instantiate()
	var mi: MeshInstance3D = _find_mesh(root)
	var out: Dictionary = {}
	if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		var xf: Transform3D = _xf_to_root(mi, root)
		var m: Mesh = mi.mesh
		var main_i: int = 0
		var main_n: int = -1
		for s: int in m.get_surface_count():
			var n: int = (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if n > main_n:
				main_n = n
				main_i = s
		var main_c: Color = _albedo(m.surface_get_material(main_i))
		var v: PackedVector3Array = PackedVector3Array()
		var nn: PackedVector3Array = PackedVector3Array()
		var c: PackedColorArray = PackedColorArray()
		var ix: PackedInt32Array = PackedInt32Array()
		for s: int in m.get_surface_count():
			var arr: Array = m.surface_get_arrays(s)
			var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var sn: Variant = arr[Mesh.ARRAY_NORMAL]
			var si: Variant = arr[Mesh.ARRAY_INDEX]
			var tint: Color = _ratio(_albedo(m.surface_get_material(s)), main_c)
			var base: int = v.size()
			for k: int in sv.size():
				v.append(xf * sv[k])
				nn.append((xf.basis * ((sn as PackedVector3Array)[k] if sn is PackedVector3Array else Vector3.UP)).normalized())
				c.append(tint)
			if si is PackedInt32Array and (si as PackedInt32Array).size() > 0:
				for k: int in (si as PackedInt32Array):
					ix.append(base + k)
			else:
				for k: int in sv.size():
					ix.append(base + k)
		out = {"v": v, "n": nn, "c": c, "i": ix}
	root.free()
	return out


static func _sphere() -> Dictionary:
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr: Array = sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = PackedColorArray()
	c.resize(v.size())
	c.fill(Color.WHITE)
	return {"v": v, "n": arr[Mesh.ARRAY_NORMAL], "c": c, "i": arr[Mesh.ARRAY_INDEX]}


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for ch: Node in n.get_children():
		var m: MeshInstance3D = _find_mesh(ch)
		if m != null:
			return m
	return null


static func _xf_to_root(n: Node3D, root: Node) -> Transform3D:
	var xf: Transform3D = Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _albedo(m: Material) -> Color:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color.WHITE


## `c` relative to `main` per channel (main itself is white), capped so a pale fat streak stays a highlight.
static func _ratio(c: Color, main: Color) -> Color:
	return Color(clampf(c.r / maxf(main.r, 0.05), 0.0, 2.5), clampf(c.g / maxf(main.g, 0.05), 0.0, 2.5),
			clampf(c.b / maxf(main.b, 0.05), 0.0, 2.5), 1.0)
