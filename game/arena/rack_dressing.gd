class_name RackDressing
extends Node3D
## The weapons standing in the arena's weapon racks: visual copies of the textured weapon models (TexturedArt), no
## physics, posed by RackLayout. `stock(loadouts)` names the fighters' loadouts (side order); without a call the racks
## get starter weapons a frame after the arena is built (menu backdrop). The weapon art loads on background threads
## (ResourceLoader threaded requests) and the copies appear once every file is in, so stocking never stalls the arena
## build or a match start. One MultiMesh per distinct mesh across both racks; no shadows (thin meshes, see lessons).

const DEFAULT_ART: String = "res://assets/weapons/%s.glb"

var rack_xforms: Array[Transform3D] = []
var _plan: Array = []  ## per rack: Array[Dictionary] from RackLayout.stock
var _paths: Dictionary = {}  ## weapon id -> art path still loading or loaded
var _requested: Dictionary = {}  ## art path -> true when a threaded load was requested (and not yet taken)
var _key: String = ""
var _stocked: bool = false
var _waiting: bool = false
var rebuild_ms: float = 0.0  ## main-thread cost of the last copy rebuild (profiling)
var _art_cache: Dictionary = {}  ## weapon id -> Array of [Mesh, Transform3D] (opaque copies, frame of the weapon)


func _ready() -> void:
	set_process(false)
	_stock_default.call_deferred()


## Fills the racks for these loadouts (Array of loadout Dictionaries, side order; missing sides get starters).
func stock(loadouts: Array) -> void:
	_stocked = true
	var fill: int = RackLayout.FILL_LOW if GfxQuality.level <= GfxQuality.LOW else RackLayout.FILL
	var plan: Array = []
	for side: int in rack_xforms.size():
		var lo: Dictionary = loadouts[side] if side < loadouts.size() and loadouts[side] is Dictionary else {}
		plan.append(RackLayout.stock(lo, side, fill))
	var key: String = var_to_str(plan)
	if key == _key:
		return
	_key = key
	_plan = plan
	_paths.clear()
	for items: Array in _plan:
		for it: Dictionary in items:
			var id: String = it["id"]
			if _paths.has(id) or _art_cache.has(id):
				continue
			var path: String = art_path(id)
			if not ResourceLoader.exists(path):
				continue
			_paths[id] = path
			if not ResourceLoader.has_cached(path) and not _requested.has(path):
				if ResourceLoader.load_threaded_request(path) == OK:
					_requested[path] = true
	_waiting = true
	set_process(true)
	_process(0.0)


## The art file of a weapon: its def's "art" or assets/weapons/<id>.glb, textured copy when there is one.
static func art_path(id: String) -> String:
	return TexturedArt.path(str(CombatData.weapon(id).get("art", DEFAULT_ART % id)))


## Number of racked weapon copies drawn (tests, captures).
func copies() -> int:
	var n: int = 0
	for c: Node in get_children():
		if c is MultiMeshInstance3D:
			n += (c as MultiMeshInstance3D).multimesh.instance_count
	return n


## True once the planned copies are drawn.
func is_ready() -> bool:
	return _stocked and not _waiting


func _exit_tree() -> void:
	# Take every threaded load this node started, so none is left behind unfetched.
	for path: String in _requested:
		ResourceLoader.load_threaded_get(path)
	_requested.clear()


func _stock_default() -> void:
	if not _stocked:
		stock([])


func _process(_delta: float) -> void:
	if not _waiting:
		set_process(false)
		return
	for id: String in _paths:
		var path: String = _paths[id]
		if not _requested.has(path):
			continue
		var st: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
	_waiting = false
	set_process(false)
	_rebuild()


func _rebuild() -> void:
	var t0: int = Time.get_ticks_usec()
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var groups: Dictionary = {}  ## Mesh -> Array[Transform3D]
	for r: int in mini(_plan.size(), rack_xforms.size()):
		for it: Dictionary in _plan[r]:
			var id: String = it["id"]
			var item_xf: Transform3D = rack_xforms[r] * (it["xf"] as Transform3D) * Weapon.art_transform(id, CombatData.weapon(id))
			for part: Array in _art(id):
				var m: Mesh = part[0]
				if not groups.has(m):
					groups[m] = [] as Array[Transform3D]
				(groups[m] as Array[Transform3D]).append(item_xf * (part[1] as Transform3D))
	var k: int = 0
	for m: Mesh in groups:
		ArenaDressing.add_instances(self, "Rack%d" % k, m, groups[m] as Array[Transform3D], false)
		k += 1
	rebuild_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## Opaque mesh copies of a weapon's art with their transforms in the weapon frame (cached per id).
func _art(id: String) -> Array:
	if _art_cache.has(id):
		return _art_cache[id]
	var parts: Array = []
	var path: String = _paths.get(id, "")
	var scene: PackedScene = null
	if path != "":
		if _requested.has(path):
			_requested.erase(path)
			scene = ResourceLoader.load_threaded_get(path) as PackedScene
		else:
			scene = load(path) as PackedScene
	if scene != null:
		var root: Node = scene.instantiate()
		var stack: Array = [[root, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var top: Array = stack.pop_back()
			var n: Node = top[0]
			var xf: Transform3D = top[1]
			if n is Node3D and n != root:
				xf = xf * (n as Node3D).transform
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
				parts.append([_opaque_copy((n as MeshInstance3D).mesh), xf])
			for c: Node in n.get_children():
				stack.append([c, xf])
		root.free()
	_art_cache[id] = parts
	return parts


## A copy of `m` with every surface material opaque (Weapon.opaque_art_material), baked into the mesh so a MultiMesh
## draws it. The scene's nodes are left untouched.
static func _opaque_copy(m: Mesh) -> Mesh:
	var o := m.duplicate() as Mesh
	for s: int in o.get_surface_count():
		var mat := o.surface_get_material(s) as BaseMaterial3D
		if mat != null:
			o.surface_set_material(s, Weapon.opaque_art_material(mat))
	return o
