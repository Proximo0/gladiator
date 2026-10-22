class_name ArenaDecor
extends RefCounted
## Builds the Houdini decor (assets/decor) and dressing (assets/dressing) into the arena: one MultiMeshInstance3D
## per piece type (a draw call per material, however many are placed) and one static body with the dressing's box
## colliders. Each glb is baked once into a single ArrayMesh, one surface per material, with its own opaque copies of
## the materials (the Houdini glTF exporter sets alphaMode BLEND on every material), and cached per decimation level.

const PATHS: Dictionary = {
	"banner": "res://assets/decor/banner.glb",
	"brazier": "res://assets/decor/brazier.glb",
	"column": "res://assets/decor/column.glb",
	"column_stump": "res://assets/decor/column_stump.glb",
	"statue_plinth": "res://assets/decor/statue_plinth.glb",
	"barrier": "res://assets/dressing/barrier.glb",
	"laurel_trophy": "res://assets/dressing/laurel_trophy.glb",
	"portcullis": "res://assets/dressing/portcullis.glb",
	"weapon_rack": "res://assets/dressing/weapon_rack.glb",
}
## Big pieces that cast the sun's shadow (when GfxQuality.decor_shadows); thin dressing never does.
const SHADOW_IDS: PackedStringArray = ["column", "column_stump", "portcullis", "statue_plinth"]
## Stone the colour of the arena's travertine wall instead of the exporter's grey.
const TINTS: Dictionary = {"stone": Color(0.8, 0.7, 0.53)}
## Material named "ember" (the brazier coals) glows.
const EMBER_MATERIAL: String = "ember"
const EMBER_EMISSION: float = 1.6

## "id|lod" -> baked ArrayMesh (or null when the glb is missing).
static var _cache: Dictionary = {}


## True when the art for `id` is in the project.
static func has_art(id: String) -> bool:
	return PATHS.has(id) and ResourceLoader.exists(String(PATHS[id]))


## Places `items` ({"id", "xf"}) under `parent` and adds `boxes` ({"xf", "size"}) as layer-1 colliders. Returns
## {"nodes": int, "triangles": int, "draw_calls": int}.
static func build(parent: Node3D, items: Array[Dictionary], boxes: Array[Dictionary], lod: int, shadows: bool) -> Dictionary:
	var stats: Dictionary = {"nodes": 0, "triangles": 0, "draw_calls": 0}
	var groups: Dictionary = {}
	for it: Dictionary in items:
		var id: String = it["id"]
		if not groups.has(id):
			groups[id] = [] as Array[Transform3D]
		(groups[id] as Array[Transform3D]).append(it["xf"] as Transform3D)
	var ids: Array = groups.keys()
	ids.sort()
	for id: String in ids:
		var mesh: ArrayMesh = mesh_for(id, lod)
		if mesh == null:
			continue
		var xfs: Array[Transform3D] = groups[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Decor_" + id
		mmi.multimesh = mm
		if not (shadows and id in SHADOW_IDS):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		stats["nodes"] = int(stats["nodes"]) + 1
		stats["triangles"] = int(stats["triangles"]) + triangles(mesh) * xfs.size()
		stats["draw_calls"] = int(stats["draw_calls"]) + mesh.get_surface_count()
	if not boxes.is_empty():
		var body := StaticBody3D.new()
		body.name = "DecorBody"
		body.collision_layer = 1
		body.collision_mask = 0
		for b: Dictionary in boxes:
			var shape := BoxShape3D.new()
			shape.size = b["size"]
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = b["xf"]
			body.add_child(cs)
		parent.add_child(body)
		stats["nodes"] = int(stats["nodes"]) + 1 + boxes.size()
	return stats


static func triangles(mesh: Mesh) -> int:
	var t: int = 0
	for s: int in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		t += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


## The baked mesh of `id` at decimation level `lod` (-1 full), cached.
static func mesh_for(id: String, lod: int = -1) -> ArrayMesh:
	var key: String = "%s|%d" % [id, lod]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var mesh: ArrayMesh = null
	if lod >= 0:
		var full: ArrayMesh = mesh_for(id, -1)
		mesh = _decimated(full, lod) if full != null else null
	elif has_art(id):
		mesh = _bake(load(String(PATHS[id])) as PackedScene)
	_cache[key] = mesh
	return mesh


## Every MeshInstance3D of the scene, transforms applied, merged into one surface per material name.
static func _bake(scene: PackedScene) -> ArrayMesh:
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var tools: Dictionary = {}  # material name -> SurfaceTool
	var mats: Dictionary = {}  # material name -> Material
	var order: Array[String] = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var n: Node = top[0]
		var xf: Transform3D = top[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			for s: int in m.get_surface_count():
				var mat: Material = m.surface_get_material(s)
				var mname: String = mat.resource_name if mat != null else ""
				if not tools.has(mname):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[mname] = st
					mats[mname] = mat
					order.append(mname)
				(tools[mname] as SurfaceTool).append_from(m, s, xf)
		for c: Node in n.get_children():
			stack.append([c, xf])
	root.free()
	if order.is_empty():
		return null
	var out := ArrayMesh.new()
	for mname: String in order:
		(tools[mname] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _opaque(mats[mname] as Material))
	return out


## An opaque copy of an imported material (the original stays untouched in the import cache).
static func _opaque(mat: Material) -> Material:
	var src := mat as BaseMaterial3D
	if src == null:
		return mat
	var o := src.duplicate() as BaseMaterial3D
	o.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	o.albedo_color.a = 1.0
	if TINTS.has(o.resource_name):
		o.albedo_color = TINTS[o.resource_name]
	if o.resource_name == EMBER_MATERIAL:
		o.emission_enabled = true
		o.emission = o.albedo_color
		o.emission_energy_multiplier = EMBER_EMISSION
	return o


## The same mesh with fewer triangles per surface (ImporterMesh LODs, as Crowd.decimated), materials kept.
static func _decimated(mesh: ArrayMesh, lod: int) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s: int in mesh.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s), [], {}, mesh.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	var out := ArrayMesh.new()
	for s: int in mesh.get_surface_count():
		var arrays: Array = im.get_surface_arrays(s)
		var levels: int = im.get_surface_lod_count(s)
		if levels > 0:
			arrays[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(s, mini(lod, levels - 1))
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out
