class_name Crowd
extends Node3D
## The spectators: Houdini meshes (res://assets/crowd/*.glb), one MultiMesh per variant and angular sector (sectors
## let the renderer cull the half of the stands behind the camera). Visual only: no colliders, nothing reads this.
## A standing seat owns a calm and a cheering twin; crowd.gdshader shows one or the other from `excitement`.
## Feed it: set_excitement(SfxDirector.crowd_excitement()) every frame, react(kind) on a crowd reaction.

const DIR: String = "res://assets/crowd/"
const SHADER: String = "res://game/arena/crowd.gdshader"
const CARD_SHADER: String = "res://game/arena/crowd_card.gdshader"
## Houdini LOD set per variant (assets/crowd/<variant>_lod<n>.glb): our level 0 (about half) is their lod1, level 1
## their lod2 (about 30%, heads kept), level 2 their lod3, a textured impostor card (2 triangles). A missing file
## falls back to `decimated`.
const ART_LOD: Array[int] = [1, 2, 3]
const CARD_LOD: int = 3
const DEFAULT_SECTORS: int = 4
const RING_INNER: float = 11.6
const LEVEL_EPS: float = 0.002  ## excitement change that re-counts the shown spectators of every group

var mood: CrowdMood = CrowdMood.new()
var triangle_count: int = 0
var draw_calls: int = 0
var seat_count: int = 0
var shown_triangles: int = 0  ## triangles actually drawn at the current excitement (before view culling)
## Angular sectors per variant (more sectors cull better, fewer cost fewer draw calls). Set before add_spectator.
var sectors: int = DEFAULT_SECTORS
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _tris: Dictionary = {}
var _lod_meshes: Dictionary = {}
## key "variant|sector|lod" -> {"xf": Array[Transform3D], "data": Array[Color], "thr": PackedFloat32Array}
var _groups: Dictionary = {}
## Built groups: {"mm": MultiMesh, "thr": PackedFloat32Array (sorted), "asc": bool, "tris": int}
var _built: Array[Dictionary] = []
var _applied_level: float = -1.0


func _ready() -> void:
	set_process(true)


func set_excitement(x: float) -> void:
	mood.set_target(x)


func react(kind: String) -> void:
	mood.react(kind)


func _process(delta: float) -> void:
	mood.tick(delta)
	if absf(mood.level - _applied_level) < LEVEL_EPS:
		return
	_apply_level(mood.level)


## Sets the shader's excitement and counts, per group, the spectators drawn (see CrowdCull).
func _apply_level(level: float) -> void:
	_applied_level = level
	for mat: Variant in _materials.values():
		(mat as ShaderMaterial).set_shader_parameter("excitement", level)
	shown_triangles = 0
	for g: Dictionary in _built:
		var n: int = CrowdCull.shown_count(g["thr"], bool(g["asc"]), level)
		(g["mm"] as MultiMesh).visible_instance_count = n
		shown_triangles += n * int(g["tris"])


## Queue one spectator. `xf` places the feet centre on the tier floor facing the arena (-Z). `seed_value` (0 to
## CrowdMood.SEED_COUNT-1) picks skin, hair, phase and the excitement at which the cheering twin appears. A "" cheer
## variant means the spectator never stands up to cheer. `lod` (-1 full, 0..) picks a decimated mesh for far seats.
func add_spectator(xf: Transform3D, variants: PackedStringArray, cloth: Color, seed_value: int, lod: int = -1) -> void:
	var sector: int = posmod(int(floor(atan2(xf.origin.z, xf.origin.x) / TAU * float(sectors))), sectors)
	var data := Color(cloth.r, cloth.g, cloth.b, float(seed_value))
	var has_twin: bool = variants[1] != ""
	var thr: float = CrowdCull.threshold(seed_value, Vector2(xf.origin.x, xf.origin.z).length(), RING_INNER)
	_queue(variants[0], sector, lod, xf, data, thr if has_twin else CrowdCull.NEVER)
	seat_count += 1
	if has_twin:
		_queue(variants[1], sector, lod, xf, data, thr)


func _queue(variant: String, sector: int, lod: int, xf: Transform3D, data: Color, thr: float) -> void:
	var key: String = "%s|%d|%d" % [variant, sector, lod]
	if not _groups.has(key):
		_groups[key] = {"xf": [] as Array[Transform3D], "data": [] as Array[Color], "thr": PackedFloat32Array()}
	var g: Dictionary = _groups[key]
	(g["xf"] as Array[Transform3D]).append(xf)
	(g["data"] as Array[Color]).append(data)
	var thrs: PackedFloat32Array = g["thr"]  # packed arrays are values: write the appended copy back
	thrs.append(thr)
	g["thr"] = thrs


## Create the MultiMesh nodes from everything queued.
func build() -> void:
	var keys: Array = _groups.keys()
	keys.sort()
	triangle_count = 0
	draw_calls = 0
	_built.clear()
	for key: String in keys:
		var variant: String = key.get_slice("|", 0)
		var lod: int = int(key.get_slice("|", 2))
		var g: Dictionary = _groups[key]
		var mesh: Mesh = _mesh_for(variant, lod)
		if mesh == null:
			continue
		var ascending: bool = variant in CrowdMood.STAND_CHEER or variant in CrowdMood.STAND_CHEER_F
		var thr_raw: PackedFloat32Array = g["thr"]
		var ord: PackedInt32Array = CrowdCull.order(thr_raw, ascending)
		var xfs: Array[Transform3D] = g["xf"]
		var data: Array[Color] = g["data"]
		var sorted_thr := PackedFloat32Array()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i: int in ord.size():
			var src: int = ord[i]
			mm.set_instance_transform(i, xfs[src])
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, data[src])
			sorted_thr.append(thr_raw[src])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Crowd_" + key.replace("|", "_")
		mmi.multimesh = mm
		mmi.material_override = _material_for(variant, mesh)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 0.6
		add_child(mmi)
		var tris: int = int(_tris.get(_mesh_key(variant, lod), 0))
		triangle_count += tris * xfs.size()
		draw_calls += 1
		_built.append({"mm": mm, "thr": sorted_thr, "asc": ascending, "tris": tris})
	_groups.clear()
	_apply_level(mood.level)


func _mesh_key(variant: String, lod: int) -> String:
	return "%s|%d" % [variant, lod]


func _mesh_for(variant: String, lod: int = -1) -> Mesh:
	var full: Mesh = _full_mesh(variant)
	if full == null or lod < 0:
		return full
	var key: String = _mesh_key(variant, lod)
	if not _lod_meshes.has(key):
		var art: Mesh = _art_lod(variant, lod)
		_lod_meshes[key] = art if art != null else decimated(full, lod)
		var m: Mesh = _lod_meshes[key]
		var idx: Variant = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		_tris[key] = (idx as PackedInt32Array).size() / 3 if idx != null else m.surface_get_array_len(0) / 3
	return _lod_meshes[key] as Mesh


## The Houdini mesh for decimation level `lod`, or null. Card meshes keep their texture in meta "card_tex".
func _art_lod(variant: String, lod: int) -> Mesh:
	var n: int = ART_LOD[clampi(lod, 0, ART_LOD.size() - 1)]
	var path: String = "%s%s_lod%d.glb" % [DIR, variant, n]
	if not ResourceLoader.exists(path):
		return null
	var found: Mesh = _first_mesh(load(path) as PackedScene)
	if found == null:
		return null
	if n == CARD_LOD:
		var tex: Texture2D = null
		var mat := found.surface_get_material(0) as BaseMaterial3D
		if mat != null:
			tex = mat.albedo_texture
		var png: String = "%s%s_impostor.png" % [DIR, variant]
		if tex == null and ResourceLoader.exists(png):
			tex = load(png) as Texture2D
		if tex == null:
			return null
		found = found.duplicate() as Mesh
		found.set_meta("card_tex", tex)
	return found


static func _first_mesh(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while found == null and not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found = (n as MeshInstance3D).mesh
		for c: Node in n.get_children():
			stack.append(c)
	root.free()
	return found


## Decimation level from which every body part becomes a proxy solid (a box, or an octahedron for small parts and
## at the far level); parts smaller than PROXY_DROP metres are left out at the far level (hands at 20 m are pixels).
const PROXY_FROM_LOD: int = 1
const PROXY_SMALL_TRIS: int = 44
const PROXY_DROP: float = 0.13


## The same mesh with fewer triangles. Level 0: ImporterMesh's whole-mesh LOD (about half the triangles). Levels 1
## and 2 rebuild the figure part by part (head, hair, sleeves, hands): each connected part becomes a smooth-shaded
## box or octahedron along its own principal axes, in its own mask colour. A whole-mesh decimation at those levels
## removed heads and hair first and left headless pegs in the stands on phones. Falls back to `mesh`.
static func decimated(mesh: Mesh, lod: int) -> Mesh:
	if mesh.get_surface_count() == 0:
		return mesh
	if lod < PROXY_FROM_LOD:
		return _decimated_whole(mesh, lod)
	var src: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		return mesh
	var cols: PackedColorArray = src[Mesh.ARRAY_COLOR] if src[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var far: bool = lod > PROXY_FROM_LOD
	for part: PackedInt32Array in mesh_parts(verts, idx):
		var octa: bool = far or (part.size() / 3 <= PROXY_SMALL_TRIS and part.size() / 3 > 20)
		proxy_part(st, part, verts, cols, octa, PROXY_DROP if far else 0.0)
	st.index()
	var out: ArrayMesh = st.commit()
	if out.get_surface_count() == 0:
		return mesh
	var out_idx: Variant = out.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	if out_idx == null or (out_idx as PackedInt32Array).size() >= idx.size():
		return mesh
	return out


static func _decimated_whole(mesh: Mesh, lod: int) -> Mesh:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0), [], {}, mesh.surface_get_material(0))
	im.generate_lods(25.0, 60.0, [])
	var levels: int = im.get_surface_lod_count(0)
	if levels == 0:
		return mesh
	var arrays: Array = im.get_surface_arrays(0)
	arrays[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(0, mini(lod, levels - 1))
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Adds one part's proxy solid to `st`: a box (12 triangles) or an octahedron (8) on the part's principal axes, sized
## to its extent, normals pointing out from the centre so it shades round, coloured with the part's mean mask colour.
## Parts whose longest extent is under `drop` metres are skipped.
static func proxy_part(st: SurfaceTool, part: PackedInt32Array, verts: PackedVector3Array, cols: PackedColorArray,
		octa: bool, drop: float) -> void:
	var centre := Vector3.ZERO
	var col := Color(0, 0, 0, 0)
	var used: Dictionary = {}
	for v: int in part:
		if used.has(v):
			continue
		used[v] = true
		centre += verts[v]
		col += cols[v] if v < cols.size() else Color.WHITE
	var n: float = float(used.size())
	centre /= n
	col /= n
	var axes: Basis = principal_axes(used.keys(), verts, centre)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v: Variant in used.keys():
		var d: Vector3 = axes.transposed() * (verts[int(v)] - centre)
		lo = lo.min(d)
		hi = hi.max(d)
	var half: Vector3 = (hi - lo) * 0.5
	if maxf(half.x, maxf(half.y, half.z)) * 2.0 < drop:
		return
	var mid: Vector3 = centre + axes * ((hi + lo) * 0.5)
	var e: Array[Vector3] = [axes.x * maxf(half.x, 0.005), axes.y * maxf(half.y, 0.005), axes.z * maxf(half.z, 0.005)]
	if octa:
		var p: Array[Vector3] = []
		for k: int in 3:
			p.append(e[k] * 1.15)
			p.append(-e[k] * 1.15)
		for sx: int in [0, 1]:
			for sy: int in [2, 3]:
				for sz: int in [4, 5]:
					_proxy_tri(st, mid, p[sx], p[sy], p[sz], col)
		return
	var c: Array[Vector3] = []
	for k: int in 8:
		c.append((e[0] * (1.0 if (k & 1) != 0 else -1.0) + e[1] * (1.0 if (k & 2) != 0 else -1.0) + e[2] * (1.0 if (k & 4) != 0 else -1.0)) * 0.82)
	for f: Array in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		_proxy_tri(st, mid, c[f[0]], c[f[1]], c[f[2]], col)
		_proxy_tri(st, mid, c[f[0]], c[f[2]], c[f[3]], col)


## One outward-facing triangle of a proxy solid (offsets from `mid`), with normals from the centre.
static func _proxy_tri(st: SurfaceTool, mid: Vector3, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var order: Array[Vector3] = [a, b, c]
	if (b - a).cross(c - a).dot(a + b + c) > 0.0:  # Godot's front faces wind clockwise seen from outside
		order = [a, c, b]
	for p: Vector3 in order:
		st.set_color(col)
		st.set_normal(p.normalized())
		st.add_vertex(mid + p)


## Orthonormal axes of a point set, longest spread first (power iteration on the covariance).
static func principal_axes(ids: Array, verts: PackedVector3Array, centre: Vector3) -> Basis:
	var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for v: Variant in ids:
		var d: Vector3 = verts[int(v)] - centre
		cov.x += d * d.x
		cov.y += d * d.y
		cov.z += d * d.z
	var a: Vector3 = _power_axis(cov, Vector3(0.31, 0.93, 0.17))
	var deflated := Basis(cov.x - a * a.dot(cov * a) * a.x, cov.y - a * a.dot(cov * a) * a.y, cov.z - a * a.dot(cov * a) * a.z)
	var seed_b: Vector3 = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var b: Vector3 = _power_axis(deflated, seed_b)
	b = (b - a * a.dot(b))
	b = b.normalized() if b.length() > 0.0001 else seed_b
	return Basis(a, b, a.cross(b).normalized())


static func _power_axis(m: Basis, start: Vector3) -> Vector3:
	var v: Vector3 = start.normalized()
	for _i: int in 24:
		var w: Vector3 = m * v
		if w.length() < 1e-9:
			return v
		v = w.normalized()
	return v


## The index lists of the connected parts of an indexed mesh (vertices at the same position count as joined, so
## colour and normal seams do not split a part).
static func mesh_parts(verts: PackedVector3Array, idx: PackedInt32Array) -> Array[PackedInt32Array]:
	var weld := PackedInt32Array()
	weld.resize(verts.size())
	var seen: Dictionary = {}
	for i: int in verts.size():
		var k: Vector3i = Vector3i((verts[i] * 4096.0).round())
		if not seen.has(k):
			seen[k] = i
		weld[i] = int(seen[k])
	var root := PackedInt32Array()
	root.resize(verts.size())
	for i: int in verts.size():
		root[i] = i
	for t: int in range(0, idx.size(), 3):
		var a: int = _part_root(root, weld[idx[t]])
		for j: int in [1, 2]:
			var b: int = _part_root(root, weld[idx[t + j]])
			if a != b:
				root[b] = a
	var by_root: Dictionary = {}
	var order: Array[int] = []
	for t: int in range(0, idx.size(), 3):
		var r: int = _part_root(root, weld[idx[t]])
		if not by_root.has(r):
			by_root[r] = PackedInt32Array()
			order.append(r)
		var tri: PackedInt32Array = by_root[r]
		tri.append_array([idx[t], idx[t + 1], idx[t + 2]])
		by_root[r] = tri
	var parts: Array[PackedInt32Array] = []
	for r: int in order:
		parts.append(by_root[r])
	return parts


static func _part_root(root: PackedInt32Array, x: int) -> int:
	var r: int = x
	while root[r] != r:
		r = root[r]
	while root[x] != r:
		var nx: int = root[x]
		root[x] = r
		x = nx
	return r


func _full_mesh(variant: String) -> Mesh:
	if _meshes.has(variant):
		return _meshes[variant] as Mesh
	var found: Mesh = null
	var path: String = DIR + variant + ".glb"
	if ResourceLoader.exists(path):
		found = _first_mesh(load(path) as PackedScene)
	_meshes[variant] = found
	if found != null:
		var arrays: Array = found.surface_get_arrays(0)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_tris[_mesh_key(variant, -1)] = idx.size() / 3
	return found


## One material per variant (and per impostor card, which needs its own texture and the card shader).
func _material_for(variant: String, mesh: Mesh = null) -> ShaderMaterial:
	var card: bool = mesh != null and mesh.has_meta("card_tex")
	var key: String = variant + ("|card" if card else "")
	if _materials.has(key):
		return _materials[key] as ShaderMaterial
	var mat := ShaderMaterial.new()
	mat.shader = load(CARD_SHADER if card else SHADER)
	if card:
		mat.set_shader_parameter("card_tex", mesh.get_meta("card_tex"))
	var mode: int = 0
	if variant == CrowdMood.NOBLE:
		mode = 3
	elif variant.begins_with("sit_"):
		mode = 2
	elif variant in CrowdMood.STAND_CHEER or variant in CrowdMood.STAND_CHEER_F:
		mode = 1
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("excitement", mood.level)
	_materials[key] = mat
	return mat
