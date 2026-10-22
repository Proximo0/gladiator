class_name ArenaDressing
extends RefCounted
## Houdini-built arena dressing (assets/decor, assets/dressing): loads a glb's mesh once, makes its materials opaque
## (Houdini exports every material alpha-blended, which sorts and flickers), tints the stone to the arena's
## travertine and lights the brazier embers, then draws every placement of one asset as a single MultiMesh (one draw
## call per surface). `add_colliders` builds the floor pieces' collision from DecorLayout. Every asset is optional: `mesh()` returns null when the file is
## missing and the arena keeps its code-built stand-in.

const PATHS: Dictionary = {
	"column": "res://assets/decor/column.glb",
	"brazier": "res://assets/decor/brazier.glb",
	"banner": "res://assets/decor/banner.glb",
	"statue_plinth": "res://assets/decor/statue_plinth.glb",
	"portcullis": "res://assets/dressing/portcullis.glb",
	"weapon_rack": "res://assets/dressing/weapon_rack.glb",
	"laurel_trophy": "res://assets/dressing/laurel_trophy.glb",
	"column_stump": "res://assets/decor/column_stump.glb",
	"barrier": "res://assets/dressing/barrier.glb",
}
## Assets that load their textured copy (TexturedArt). The other dressing keeps the flat files: its stone takes the
## arena's travertine tint, which would multiply the stone maps.
const TEXTURED: PackedStringArray = ["weapon_rack"]
## Material names (as Houdini exports them) and what they become here.
const STONE_MATERIAL: String = "stone"
const EMBER_MATERIAL: String = "ember"
const EMBER_EMISSION: Color = Color(1.0, 0.45, 0.12)
const EMBER_ENERGY: float = 2.2
## Wrought iron (rack cups, brazier bowls, portcullis bars): at Houdini's metallic 1 and roughness 0.55 every face
## pointing up mirrored the sky's deep-blue top, so the rack's cups read blue. Half metal and matte reflects a grey
## blur of the sky and keeps the warm ambient; the shade darkens the now-diffuse albedo back to iron. Roughness is the effective value; over an ORM map (mean green ~0.885,
## the textured copies) the factor is divided by that mean so both copies land on it.
const IRON_MATERIAL: String = "iron"
const IRON_METALLIC: float = 0.5
const IRON_ROUGHNESS: float = 0.8
const IRON_SHADE: float = 0.6
const ORM_METAL_G_MEAN: float = 0.885

var _cache: Dictionary = {}
var stone_tint: Color = Color(0.84, 0.74, 0.56)


## The opaque, re-tinted mesh of asset `id`, or null if its file is missing.
func mesh(id: String) -> Mesh:
	if _cache.has(id):
		return _cache[id] as Mesh
	var found: Mesh = null
	var path: String = String(PATHS.get(id, ""))
	if id in TEXTURED:
		path = TexturedArt.path(path)
	if path != "" and ResourceLoader.exists(path):
		found = _named_mesh(load(path) as PackedScene, id)
		if found != null:
			found = found.duplicate() as Mesh  # never edit the imported resource others may share
			for s: int in found.get_surface_count():
				found.surface_set_material(s, opaque_material(found.surface_get_material(s), stone_tint))
	_cache[id] = found
	return found


## A copy of `m` that is opaque; stone takes `stone` as its colour, embers glow. Null in, a plain material out.
static func opaque_material(m: Material, stone: Color) -> Material:
	var src := m as BaseMaterial3D
	if src == null:
		var plain := StandardMaterial3D.new()
		plain.roughness = 0.9
		return plain if m == null else m
	var o := src.duplicate() as BaseMaterial3D
	o.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	o.albedo_color.a = 1.0
	o.cull_mode = BaseMaterial3D.CULL_BACK
	if o.resource_name == STONE_MATERIAL:
		o.albedo_color = stone
		o.roughness = 0.95
	elif o.resource_name == IRON_MATERIAL:
		o.metallic = IRON_METALLIC
		o.albedo_color = Color(o.albedo_color * IRON_SHADE, 1.0)
		o.roughness = minf(1.0, IRON_ROUGHNESS / (ORM_METAL_G_MEAN if o.roughness_texture != null else 1.0))
	elif o.resource_name == EMBER_MATERIAL:
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = EMBER_EMISSION
		o.emission_enabled = true
		o.emission = EMBER_EMISSION
		o.emission_energy_multiplier = EMBER_ENERGY
	return o


## Adds one MultiMeshInstance3D drawing `m` at every transform. Returns it (null when `m` is null or nothing to draw).
static func add_instances(parent: Node, node_name: String, m: Mesh, xforms: Array[Transform3D], shadows: bool) -> MultiMeshInstance3D:
	if m == null or xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Adds DecorLayout's colliders ({"xf", "box"} or {"xf", "cyl"}) as shapes of the wall's static `body`. The Arena and
## the headless match both call this, so a watched fight and a bot fight collide the same.
static func add_colliders(body: StaticBody3D, colliders: Array[Dictionary]) -> void:
	for c: Dictionary in colliders:
		var cs := CollisionShape3D.new()
		if c.has("box"):
			var box := BoxShape3D.new()
			box.size = c["box"]
			cs.shape = box
		else:
			var cyl := CylinderShape3D.new()
			var rh: Vector2 = c["cyl"]
			cyl.radius = rh.x
			cyl.height = rh.y
			cs.shape = cyl
		cs.transform = c["xf"]
		body.add_child(cs)


## The mesh named like the asset if there is one (weapon_rack.glb also carries other props' empties), else the first.
static func _named_mesh(scene: PackedScene, id: String) -> Mesh:
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var first: Mesh = null
	var named: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			if first == null:
				first = (n as MeshInstance3D).mesh
			if String(n.name) == id:
				named = (n as MeshInstance3D).mesh
		for c: Node in n.get_children():
			stack.append(c)
	root.free()
	return named if named != null else first
