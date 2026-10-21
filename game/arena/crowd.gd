class_name Crowd
extends Node3D
## The spectators: Houdini meshes (res://assets/crowd/*.glb), one MultiMesh per variant and angular sector (sectors
## let the renderer cull the half of the stands behind the camera). Visual only: no colliders, nothing reads this.
## A standing seat owns a calm and a cheering twin; crowd.gdshader shows one or the other from `excitement`.
## Feed it: set_excitement(SfxDirector.crowd_excitement()) every frame, react(kind) on a crowd reaction.

const DIR: String = "res://assets/crowd/"
const SHADER: String = "res://game/arena/crowd.gdshader"
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
		mmi.material_override = _material_for(variant)
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
		_lod_meshes[key] = decimated(full, lod)
		var m: Mesh = _lod_meshes[key]
		var idx: PackedInt32Array = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		_tris[key] = idx.size() / 3
	return _lod_meshes[key] as Mesh


## The same mesh with fewer triangles: ImporterMesh builds its LOD index sets (about 50%, 20% and 6% of the
## triangles for levels 0, 1, 2) and level `lod` becomes the base index buffer. Falls back to `mesh` itself.
static func decimated(mesh: Mesh, lod: int) -> Mesh:
	if mesh.get_surface_count() == 0:
		return mesh
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


func _full_mesh(variant: String) -> Mesh:
	if _meshes.has(variant):
		return _meshes[variant] as Mesh
	var found: Mesh = null
	var path: String = DIR + variant + ".glb"
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var root: Node = scene.instantiate()
		var stack: Array[Node] = [root]
		while found == null and not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				found = (n as MeshInstance3D).mesh
			for c: Node in n.get_children():
				stack.append(c)
		root.free()
	_meshes[variant] = found
	if found != null:
		var arrays: Array = found.surface_get_arrays(0)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_tris[_mesh_key(variant, -1)] = idx.size() / 3
	return found


func _material_for(variant: String) -> ShaderMaterial:
	if _materials.has(variant):
		return _materials[variant] as ShaderMaterial
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	var mode: int = 0
	if variant == CrowdMood.NOBLE:
		mode = 3
	elif variant.begins_with("sit_"):
		mode = 2
	elif variant in CrowdMood.STAND_CHEER or variant in CrowdMood.STAND_CHEER_F:
		mode = 1
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("excitement", mood.level)
	_materials[variant] = mat
	return mat
