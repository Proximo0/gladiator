class_name FighterArt
extends RefCounted
## Body art for one fighter: instances res://assets/body/<part>.glb (authored in the part's own frame) under the part's
## "Look" slot, tinted per fighter with shared material overrides (cloth = side colour, skin = tone picked from the
## match seed), and the flat flesh/bone caps shown on both sides of a dismemberment. Visual only: collision shapes
## and physics never change. A missing asset leaves the primitive mesh in place.

const DIR: String = "res://assets/body/"
const ART_NAME: String = "Art"
## Distance the cap's origin sits inside the cut plane along its normal (the disc is 0.0165 thick, top at +0.0045).
const CAP_SINK: float = 0.004
## How far from the pivot to the art's end the cut face sits (0 = at the pivot, 1 = at the tip).
const CUT_REACH: float = 0.5

## Parts whose meshes (art, caps, armor on them) are too small to matter in the shadow map; they stop casting when
## `GfxQuality.small_part_shadows()` is false (low). The torso, pelvis, head, thighs and upper arms keep their shadow.
const SMALL_SHADOW_PARTS: PackedStringArray = ["forearm_l", "forearm_r", "shin_l", "shin_r"]

var _skin: StandardMaterial3D = null
var _cloth: StandardMaterial3D = null
var _head_scene: String = "head"
var _caps: Dictionary = {}


func _init(side: int, match_seed: int) -> void:
	_skin = _tinted("skin", BodyLook.skin_color(match_seed, side))
	_cloth = _tinted("cloth", BodyLook.cloth_color(side))
	if BodyLook.bearded(match_seed, side):
		_head_scene = "head_b"


func _tinted(kind: String, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = kind
	m.albedo_color = col
	m.roughness = 0.55 if kind == "skin" else 0.9
	return m


static func _scene(asset: String) -> PackedScene:
	var path: String = DIR + asset + ".glb"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


## Whether part `pn`'s meshes cast into the shadow map at quality `l` (-1 = the current level).
static func casts_shadow(pn: String, l: int = -1) -> bool:
	return GfxQuality.small_part_shadows(l) or not SMALL_SHADOW_PARTS.has(pn)


## Sets the shadow casting of every mesh under `n` (a part's body, or its Look or ArmorSlot) for part `pn`. Call it
## again after adding armor or other pieces to the part.
static func apply_shadow(n: Node, pn: String) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow(pn) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c: Node in n.get_children():
		apply_shadow(c, pn)


func _instance(asset: String) -> Node3D:
	var sc: PackedScene = _scene(asset)
	if sc == null:
		return null
	var root: Node3D = sc.instantiate() as Node3D
	if root == null:
		return null
	_tint(root)
	return root


func _tint(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if m == null:
					continue
				if m.resource_name == "skin":
					mi.set_surface_override_material(i, _skin)
				elif m.resource_name == "cloth":
					mi.set_surface_override_material(i, _cloth)
	for c: Node in n.get_children():
		_tint(c)


## Puts the art for part `pn` under body `b`'s Look slot and hides the primitive meshes there. False when the asset is
## missing (the primitives stay).
func dress(b: Node3D, pn: String) -> bool:
	var asset: String = _head_scene if pn == "head" else pn
	var art: Node3D = _instance(asset)
	if art == null:
		return false
	var look: Node3D = b.get_node_or_null("Look") as Node3D
	if look == null:
		return false
	for c: Node in look.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
	art.name = ART_NAME
	look.add_child(art)
	apply_shadow(b, pn)
	return true


## Mesh bounds of the art on `b` in the part's frame (empty AABB when none).
static func _bounds(b: Node3D) -> AABB:
	var art: Node = b.get_node_or_null("Look/" + ART_NAME)
	if art == null:
		return AABB()
	var out := AABB()
	var first: bool = true
	for c: Node in art.get_children():
		if c is MeshInstance3D:
			var bb: AABB = (c as MeshInstance3D).get_aabb()
			out = bb if first else out.merge(bb)
			first = false
	return out


## Where the cut face of `b` lies along the unit direction `dir` (part frame): the art's extreme in that direction.
static func _plane(b: Node3D, dir: Vector3) -> Vector3:
	var bb: AABB = _bounds(b)
	if bb.size == Vector3.ZERO:
		return Vector3.ZERO
	var y: float = bb.end.y if dir.y > 0.0 else bb.position.y
	return Vector3(0.0, y, 0.0)


func _add_cap(b: Node3D, key: String, asset: String, at: Vector3, normal: Vector3) -> void:
	var cap: Node3D = _instance(asset)
	if cap == null:
		return
	cap.name = "Cap_" + key
	var look: Node3D = b.get_node_or_null("Look") as Node3D
	if look == null:
		cap.free()
		return
	var basis := Basis(Quaternion(Vector3.UP, normal.normalized()))
	cap.transform = Transform3D(basis, at - normal.normalized() * CAP_SINK)
	look.add_child(cap)
	apply_shadow(cap, str(b.name))
	_caps[key] = cap


## Part `n` was cut from its parent: a cap on the stump (parent side, facing the piece) and one on the piece.
## `parts` maps names to bodies. Cap positions follow the joint pivot and the art's end faces.
func cut(parts: Dictionary, n: String) -> void:
	var asset: String = BodyLook.cap_for(n)
	var pd: Dictionary = FighterRig.part(n)
	if asset == "" or pd.is_empty() or _caps.has(n + "_piece"):
		return
	var pn: String = str(pd["parent"])
	if not parts.has(n) or not parts.has(pn):
		return
	var pivot: Vector3 = pd["pivot"]
	var piece_c: Vector3 = pd["center"]
	var parent_c: Vector3 = FighterRig.part(pn)["center"]
	# Direction from the pivot toward the piece, along the bone (+-Y).
	var toward_piece: Vector3 = Vector3.DOWN if piece_c.y < pivot.y else Vector3.UP
	var piece_b: Node3D = parts[n]
	var parent_b: Node3D = parts[pn]
	var at_piece: Vector3 = _plane(piece_b, -toward_piece)
	var at_stump: Vector3 = _plane(parent_b, toward_piece)
	var has_art: bool = at_stump.y != 0.0 and at_piece.y != 0.0
	# The art tapers past the pivot (it overlaps its neighbour so a bent joint shows no gap): put the cut face part way
	# from the pivot to the art's end, where the mesh is about as wide as the cap.
	at_piece.y = (pivot.y - piece_c.y) + (at_piece.y - (pivot.y - piece_c.y)) * CUT_REACH
	at_stump.y = (pivot.y - parent_c.y) + (at_stump.y - (pivot.y - parent_c.y)) * CUT_REACH
	# Keep the cut face's lateral position on the joint axis.
	at_piece.x = pivot.x - piece_c.x
	at_piece.z = pivot.z - piece_c.z
	at_stump.x = pivot.x - parent_c.x
	at_stump.z = pivot.z - parent_c.z
	if not has_art:
		at_piece = pivot - piece_c
		at_stump = pivot - parent_c
	_add_cap(piece_b, n + "_piece", asset, at_piece, -toward_piece)
	_add_cap(parent_b, n + "_stump", asset, at_stump, toward_piece)


## Undo `cut` (a restored snapshot reattached the part).
func uncut(n: String) -> void:
	for k: String in [n + "_piece", n + "_stump"]:
		if _caps.has(k):
			var c: Node = _caps[k]
			if is_instance_valid(c):
				c.get_parent().remove_child(c)
				c.free()
			_caps.erase(k)


## Armor fit over the body art: per part, the shape that sits just outside the skin (placeholder armor meshes are
## still primitives). "cyl" is an elliptical (rx, rz) tapered cylinder, "sphere" an ellipsoid, "capsule" a limb sleeve.
const HELM_CLEAR: float = 0.006  ## helmet shell clearance over the head collider hull (m)
const HELM_BOTTOM: float = -0.03  ## lowest hull ring the helmet covers (part frame y)
const ARMOR_FIT: Dictionary = {
	"pelvis": {"shape": "cyl", "rx": 0.185, "rz": 0.135, "h": 0.19, "pos": Vector3(0, -0.01, 0), "taper": 1.0},
	"torso": {"shape": "cyl", "rx": 0.205, "rz": 0.125, "h": 0.40, "pos": Vector3(0, -0.03, 0), "taper": 0.83},
	"head": {"shape": "helm", "clear": HELM_CLEAR, "bottom": HELM_BOTTOM, "pos": Vector3.ZERO},
	"upper_arm_l": {"shape": "capsule", "r": 0.072, "h": 0.27, "pos": Vector3(0, 0.0, 0)},
	"upper_arm_r": {"shape": "capsule", "r": 0.072, "h": 0.27, "pos": Vector3(0, 0.0, 0)},
	"forearm_l": {"shape": "capsule", "r": 0.058, "h": 0.26, "pos": Vector3(0, 0.035, 0)},
	"forearm_r": {"shape": "capsule", "r": 0.058, "h": 0.26, "pos": Vector3(0, 0.035, 0)},
	"thigh_l": {"shape": "capsule", "r": 0.100, "h": 0.38, "pos": Vector3(0, 0.0, 0)},
	"thigh_r": {"shape": "capsule", "r": 0.100, "h": 0.38, "pos": Vector3(0, 0.0, 0)},
	"shin_l": {"shape": "capsule", "r": 0.066, "h": 0.34, "pos": Vector3(0, 0.03, 0)},
	"shin_r": {"shape": "capsule", "r": 0.066, "h": 0.34, "pos": Vector3(0, 0.03, 0)},
}


## {"mesh": Mesh, "pos": Vector3} fitted to the art on part `pn`, or {} when the part has no fit (use the primitive).
static func armor_fit(pn: String) -> Dictionary:
	if not ARMOR_FIT.has(pn):
		return {}
	var f: Dictionary = ARMOR_FIT[pn]
	var mesh: Mesh = null
	match str(f["shape"]):
		"cyl":
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = float(f["taper"])
			cm.height = float(f["h"])
			cm.radial_segments = 20
			cm.rings = 1
			var st := SurfaceTool.new()
			st.append_from(cm, 0, Transform3D(Basis.from_scale(Vector3(float(f["rx"]), 1.0, float(f["rz"]))), Vector3.ZERO))
			mesh = st.commit()
		"helm":
			mesh = helm_mesh(float(f["clear"]), float(f["bottom"]))
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = float(f["r"])
			sm.height = float(f["h"])
			mesh = sm
		_:
			var pm := CapsuleMesh.new()
			pm.radius = float(f["r"])
			pm.height = float(f["h"])
			mesh = pm
	return {"mesh": mesh, "pos": f["pos"]}


## Helmet shell: the head collider's rings (`Fighter.HEAD_PROFILE`) pushed out by `clear`, from the ring at `bottom` up
## over the crown, closed underneath. Part frame, so it hugs the collider and a blow that clips it also hits the head.
static func helm_mesh(clear: float, bottom: float) -> Mesh:
	var rings: Array = []
	for row: Array in Fighter.HEAD_PROFILE:
		if float(row[0]) >= bottom - 0.0001:
			rings.append(row)
	var seg: int = 24
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for row: Array in rings:
		var ring := PackedVector3Array()
		for k: int in seg:
			var a: float = TAU * float(k) / float(seg)
			var cz: float = cos(a)
			var depth: float = (float(row[3]) if cz > 0.0 else -float(row[2])) + clear
			ring.append(Vector3(sin(a) * (float(row[1]) + clear), float(row[0]), cz * depth))
		pts.append(ring)
	var top: Vector3 = Vector3(0.0, float((rings[rings.size() - 1] as Array)[0]) + clear, 0.0)
	var low_c := Vector3(0.0, float((rings[0] as Array)[0]) - clear * 0.5, 0.0)
	for r: int in range(pts.size() - 1):
		for k: int in seg:
			var k2: int = (k + 1) % seg
			var a0: Vector3 = (pts[r] as PackedVector3Array)[k]
			var a1: Vector3 = (pts[r] as PackedVector3Array)[k2]
			var b0: Vector3 = (pts[r + 1] as PackedVector3Array)[k]
			var b1: Vector3 = (pts[r + 1] as PackedVector3Array)[k2]
			for v: Vector3 in [a0, b0, a1, a1, b0, b1]:
				st.add_vertex(v)
	var last: PackedVector3Array = pts[pts.size() - 1]
	var first: PackedVector3Array = pts[0]
	for k: int in seg:
		var k2: int = (k + 1) % seg
		for v: Vector3 in [last[k], top, last[k2], first[k], first[k2], low_c]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
