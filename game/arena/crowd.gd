class_name Crowd
extends Node3D
## The spectators: Houdini meshes (res://assets/crowd/*.glb), one MultiMesh per variant and angular sector (sectors
## let the renderer cull the half of the stands behind the camera). Visual only: no colliders, nothing reads this.
## A standing seat owns a calm and a cheering twin; crowd.gdshader shows one or the other from `excitement`.
## Feed it: set_excitement(SfxDirector.crowd_excitement()) every frame, react(kind) on a crowd reaction.

const DIR: String = "res://assets/crowd/"
const SHADER: String = "res://game/arena/crowd.gdshader"
const SECTORS: int = 4

var mood: CrowdMood = CrowdMood.new()
var triangle_count: int = 0
var draw_calls: int = 0
var seat_count: int = 0
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _tris: Dictionary = {}
## key "variant|sector" -> {"xf": Array[Transform3D], "data": Array[Color]}
var _groups: Dictionary = {}


func _ready() -> void:
	set_process(true)


func set_excitement(x: float) -> void:
	mood.set_target(x)


func react(kind: String) -> void:
	mood.react(kind)


func _process(delta: float) -> void:
	mood.tick(delta)
	for mat: Variant in _materials.values():
		(mat as ShaderMaterial).set_shader_parameter("excitement", mood.level)


## Queue one spectator. `xf` places the feet centre on the tier floor facing the arena (-Z). `seed_value` (0 to
## CrowdMood.SEED_COUNT-1) picks skin, hair, phase and the excitement at which the cheering twin appears. A "" cheer
## variant means the spectator never stands up to cheer.
func add_spectator(xf: Transform3D, variants: PackedStringArray, cloth: Color, seed_value: int) -> void:
	var sector: int = posmod(int(floor(atan2(xf.origin.z, xf.origin.x) / TAU * float(SECTORS))), SECTORS)
	var data := Color(cloth.r, cloth.g, cloth.b, float(seed_value))
	_queue(variants[0], sector, xf, data)
	seat_count += 1
	if variants[1] != "":
		_queue(variants[1], sector, xf, data)


func _queue(variant: String, sector: int, xf: Transform3D, data: Color) -> void:
	var key: String = "%s|%d" % [variant, sector]
	if not _groups.has(key):
		_groups[key] = {"xf": [] as Array[Transform3D], "data": [] as Array[Color]}
	var g: Dictionary = _groups[key]
	(g["xf"] as Array[Transform3D]).append(xf)
	(g["data"] as Array[Color]).append(data)


## Create the MultiMesh nodes from everything queued.
func build() -> void:
	var keys: Array = _groups.keys()
	keys.sort()
	triangle_count = 0
	draw_calls = 0
	for key: String in keys:
		var variant: String = key.get_slice("|", 0)
		var g: Dictionary = _groups[key]
		var xfs: Array[Transform3D] = g["xf"]
		var data: Array[Color] = g["data"]
		var mesh: Mesh = _mesh_for(variant)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, Color.WHITE)
			mm.set_instance_custom_data(i, data[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Crowd_" + key.replace("|", "_")
		mmi.multimesh = mm
		mmi.material_override = _material_for(variant)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 0.6
		add_child(mmi)
		triangle_count += int(_tris.get(variant, 0)) * xfs.size()
		draw_calls += 1
	_groups.clear()


func _mesh_for(variant: String) -> Mesh:
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
		_tris[variant] = idx.size() / 3
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
