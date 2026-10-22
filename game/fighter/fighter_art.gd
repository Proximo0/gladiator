class_name FighterArt
extends RefCounted
## Body art for one fighter: instances res://assets/body/<part>.glb (authored in the part's own frame) under the part's
## "Look" slot, tinted per fighter with shared material overrides (cloth = side colour, skin = tone picked from the
## match seed), and the flat flesh/bone caps shown on both sides of a dismemberment. Visual only: collision shapes
## and physics never change. A missing asset leaves the primitive mesh in place.

const DIR: String = "res://assets/body/"
const OUTFIT_DIR: String = "res://assets/outfits/"
const ART_NAME: String = "Art"
## Distance the cap's origin sits inside the cut plane along its normal (the disc is 0.0165 thick, top at +0.0045).
const CAP_SINK: float = -0.004
## Procedural gore face on a cut (the glb cap's flat disc was sunk into the stump's skin and read as a thin ring): stacked
## flat discs, dark wet rim, fat band, red flesh, bone and a dark marrow eye, widened past the limb's skin. Radii are
## shares of the glb cap's half width; each disc is DISC_STEP taller than the one below so none z-fights.
const SKIN_ROUGH: float = 0.78  ## skin is matte: a low roughness mirrored the blue sky as a pale sheen
const SKIN_SPEC: float = 0.12  ## Godot's metallic_specular (default 0.5)
const SKIN_TAN_SAT: float = 1.1
const SKIN_TAN_VAL: float = 0.9
const CAP_WIDEN: float = 1.2
const CAP_DISCS: Array = [
	["rim", 1.08, "flesh", 0.32],
	["fat", 1.0, "fat", 0.6],
	["flesh", 0.92, "flesh", 0.82],
	["bone", 0.27, "bone", 0.9],
	["marrow", 0.12, "flesh", 0.3],
]
const DISC_H: float = 0.006
const DISC_STEP: float = 0.0035
## How far from the pivot to the art's end the cut face sits (0 = at the pivot, 1 = at the tip).
const CUT_REACH: float = 0.5

## Parts whose meshes (art, caps, armor on them) are too small to matter in the shadow map; they stop casting when
## `GfxQuality.small_part_shadows()` is false (low). The torso, pelvis, head, thighs and upper arms keep their shadow.
## Alien art overrides, set here and not in the glb: the Houdini preview reads dark and drab at fight distance.
const ALIEN_SKIN_COLOR: Color = Color(0.42, 0.58, 0.47)  ## brighter and more green-grey saturated than the glb's 0.51/0.58/0.51
const ALIEN_SKIN_ROUGH: float = 0.6
const ALIEN_SKIN_SPEC: float = 0.2
const ALIEN_EYE_ROUGH: float = 0.02
const ALIEN_EYE_SPEC: float = 1.0

const SMALL_SHADOW_PARTS: PackedStringArray = ["forearm_l", "forearm_r", "shin_l", "shin_r"]

var _skin: StandardMaterial3D = null
var _cloth: StandardMaterial3D = null
var _head_scene: String = "head"
var _caps: Dictionary = {}
var _outfit: String = OutfitRules.DEFAULT_ID
var _armor: StandardMaterial3D = null  ## the outfit palette's armor material (palette fallback and covered parts)
var _team: StandardMaterial3D = null  ## side colour for "cloth" surfaces of outfit art (palette cloth is for the fallback)
var _blood: BloodPalette = BloodPalette.red()  ## inner colours of cut caps (flesh, fat, bone or chitin)
var _cap_mats: Dictionary = {}  ## cap surface kind -> tinted material, shared by every cap of this fighter
var _face_mat: StandardMaterial3D = null  ## shared by every gore face of this fighter
var _ready_caps: Dictionary = {}  ## key -> cap built ahead by prebuild_step, outside the tree until a cut uses it
var _prebuild_i: int = 0
var _prebuild_specs: Array = []
var _alien_mats: Dictionary = {}  ## glb material name -> override (see ALIEN_SKIN_LIFT, ALIEN_EYE)


## `outfit_id` is a premium or default outfit (see OutfitRules). Parts load from OUTFIT_DIR/<id>/<part>.glb when the
## art exists, else the base body is tinted with the outfit palette, so an outfit works before its art lands.
## Cosmetic only: nothing here touches physics or the match state.
func _init(side: int, match_seed: int, outfit_id: String = OutfitRules.DEFAULT_ID) -> void:
	_outfit = OutfitRules.clean_id(outfit_id)
	var pal: Dictionary = OutfitRules.palette(_outfit)
	var skin_col: Color = tanned(BodyLook.skin_color(match_seed, side))  # an outfit's own skin colour is used as authored
	var cloth_col: Color = BodyLook.cloth_color(side)
	if _outfit != OutfitRules.DEFAULT_ID:
		skin_col = OutfitRules.color(pal, "skin", skin_col)
		cloth_col = OutfitRules.color(pal, "cloth", cloth_col)
		_armor = _tinted("armor", OutfitRules.color(pal, "armor", Color(0.4, 0.4, 0.4)))
		_armor.metallic = float(pal.get("metal", 0.0))
		_armor.roughness = float(pal.get("rough", 0.6))
	_skin = _tinted("skin", skin_col)
	_cloth = _tinted("cloth", cloth_col)
	_team = _tinted("cloth", BodyLook.cloth_color(side))
	_blood = OutfitRules.blood_palette(_outfit)
	if BodyLook.bearded(match_seed, side) and not OutfitRules.covers(_outfit, "head"):
		_head_scene = "head_b"


func _tinted(kind: String, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = kind
	m.albedo_color = col
	m.roughness = SKIN_ROUGH if kind == "skin" else 0.9
	if kind == "skin":
		m.metallic_specular = SKIN_SPEC
	return m


## Skin tone as it should read in strong warm sun: the sun tint (1, 0.8, 0.55) bleaches a pale albedo to cream, so skin
## is a little more saturated and darker than the table value.
static func tanned(c: Color) -> Color:
	return Color.from_hsv(c.h, minf(c.s * SKIN_TAN_SAT, 1.0), c.v * SKIN_TAN_VAL)


## `asset` is a base body asset ("torso", "cap_neck") or "outfits/<id>/<name>" (an outfit's own cap, see BodyLook.cap_for).
static func _scene(asset: String) -> PackedScene:
	var path: String = DIR + asset + ".glb"
	if asset.begins_with("outfits/"):
		path = "res://assets/" + asset + ".glb"
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


## Outfit art for body part `asset` (the head asset may be head_b): "res://assets/outfits/<id>/<part>.glb", or null.
## The bearded head has no outfit twin; an outfit ships one "head".
func _outfit_scene(asset: String) -> PackedScene:
	if _outfit == OutfitRules.DEFAULT_ID:
		return null
	var name: String = "head" if asset == "head_b" else asset
	var path: String = OUTFIT_DIR + _outfit + "/" + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


## `part` is the body part the asset dresses ("" for caps, which keep flesh tint). Outfit art keeps its own materials,
## except "skin" surfaces on parts the outfit does not cover. The base body under an outfit palette tints "skin" with
## the armor colour on covered parts (skin tone never shows through armor) and "cloth" with the outfit cloth.
func _instance(asset: String, part: String = "", cap: bool = false) -> Node3D:
	var sc: PackedScene = null
	var own_art: bool = false
	if part != "":
		sc = _outfit_scene(asset)
		own_art = sc != null
	if sc == null:
		sc = _scene(asset)
	if sc == null:
		return null
	var root: Node3D = sc.instantiate() as Node3D
	if root == null:
		return null
	var covered: bool = part != "" and _armor != null and OutfitRules.covers(_outfit, part)
	_tint(root, covered, own_art or (cap and asset.begins_with("outfits/")), cap)
	return root


## Material rules. Base body art: "skin" takes the skin tone (the armor colour on covered palette-fallback parts) and
## "cloth" the outfit cloth. Outfit art (`own_art`): "skin" surfaces take the skin tone, "cloth" the side's team colour,
## the alien_* surfaces never take the skin tone (the alien keeps its own skin, lifted by ALIEN_* overrides), and every
## other surface keeps the imported material. `cap` colours the flesh, fat and bone surfaces from the blood palette.
func _tint(n: Node, covered: bool = false, own_art: bool = false, cap: bool = false) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(i)
				if m == null:
					continue
				var o: Material = override_for(m, covered, own_art, cap)
				if o != null:
					mi.set_surface_override_material(i, o)
	for c: Node in n.get_children():
		_tint(c, covered, own_art, cap)


## The override material for glb material `m`, or null to keep it. See `_tint` for the rules.
func override_for(m: Material, covered: bool, own_art: bool, cap: bool) -> Material:
	var mn: String = m.resource_name
	if cap:
		var kind: String = mn.trim_prefix("alien_")
		if kind == "flesh" or kind == "fat" or kind == "bone":
			return _cap_material(kind, m)
	if mn == "skin":
		if own_art or not covered:
			return _skin
		return _armor
	if mn == "cloth":
		return _team if own_art else _cloth
	if mn == "alien_skin" or mn == "alien_eye":
		return _alien_material(mn, m)
	return null


## Cut-surface material: the glb's own material with the albedo from the blood palette (and a faint glow for ichor).
func _cap_material(kind: String, src: Material) -> Material:
	if _cap_mats.has(kind):
		return _cap_mats[kind]
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = _blood.inner(kind)
	m.vertex_color_use_as_albedo = false
	if _blood.emission > 0.0 and kind != "bone":
		m.emission_enabled = true
		m.emission = _blood.inner(kind)
		m.emission_energy_multiplier = _blood.emission * 0.5
	_cap_mats[kind] = m
	return m


## Alien skin brighter and greener than the glb, eyes glossy black. Only materials the alien glbs name.
func _alien_material(mn: String, src: Material) -> Material:
	if _alien_mats.has(mn):
		return _alien_mats[mn]
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	if mn == "alien_skin":
		m.albedo_color = ALIEN_SKIN_COLOR
		m.roughness = ALIEN_SKIN_ROUGH
		m.metallic_specular = ALIEN_SKIN_SPEC
	else:
		m.albedo_color = Color(0.0, 0.0, 0.0)
		m.roughness = ALIEN_EYE_ROUGH
		m.metallic_specular = ALIEN_EYE_SPEC
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.03
	_alien_mats[mn] = m
	return m


## Whether the outfit's own art for part `pn` already shows armor, so the drawn ARMOR_FIT shell is not drawn over it
## (a shell on the samurai's lacquer plates would clip). The part's armor still protects; only the shell is hidden.
func shows_armor(pn: String) -> bool:
	return OutfitRules.art_shows_armor(_outfit, pn) and _outfit_scene(pn) != null


## Puts the art for part `pn` under body `b`'s Look slot and hides the primitive meshes there. False when the asset is
## missing (the primitives stay).
func dress(b: Node3D, pn: String) -> bool:
	var asset: String = _head_scene if pn == "head" else pn
	var art: Node3D = _instance(asset, pn)
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
	var look: Node3D = b.get_node_or_null("Look") as Node3D
	if look == null:
		return
	var cap: Node3D = _ready_caps.get(key) as Node3D
	_ready_caps.erase(key)
	if cap == null or not is_instance_valid(cap):
		cap = _build_cap(b, key, asset, at, normal)
	if cap == null:
		return
	look.add_child(cap)
	apply_shadow(cap, str(b.name))
	_caps[key] = cap


## One cut cap for body `b` (glb cap, hidden, plus the gore face), positioned in the Look frame, not yet in the tree.
func _build_cap(b: Node3D, key: String, asset: String, at: Vector3, normal: Vector3) -> Node3D:
	var cap: Node3D = _instance(asset, "", true)
	if cap == null:
		return null
	cap.name = "Cap_" + key
	var basis := Basis(Quaternion(Vector3.UP, normal.normalized()))
	var half_w: float = 0.0
	for mi: Node in cap.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).get_aabb()
		half_w = maxf(half_w, maxf(bb.size.x, bb.size.z) * 0.5)
		(mi as MeshInstance3D).visible = false
	half_w = half_w if half_w > 0.0 else 0.058
	_cap_face(cap, half_w * CAP_WIDEN, key, _local_down(b, basis))
	cap.transform = Transform3D(basis, at - normal.normalized() * CAP_SINK)
	return cap


## World down in the frame of a cap that sits on body `b` with orientation `cap_basis` (so loose strands can hang).
static func _local_down(b: Node3D, cap_basis: Basis) -> Vector3:
	if not b.is_inside_tree():
		return Vector3.DOWN
	return (b.global_transform.basis * cap_basis).inverse() * Vector3.DOWN


## The gore face of one cut (`CapMesh`: torn edge, dome, fibres, flared collar, tendrils), built once per sever and
## coloured from the fighter's blood palette (ichor for the alien).
func _cap_face(cap: Node3D, radius: float, key: String, down: Vector3 = Vector3.DOWN) -> void:
	var pal: Dictionary = {}
	for d: Array in CAP_DISCS:
		var base: Color = _blood.inner(str(d[2]))
		var k: float = float(d[3])
		pal[str(d[0])] = Color(base.r * k, base.g * k, base.b * k, 1.0)
	pal["skin"] = _skin.albedo_color if _skin != null else Color(0.8, 0.6, 0.5)
	if _face_mat == null:
		# One material for every gore face of this fighter (its palette never changes).
		_face_mat = StandardMaterial3D.new()
		_face_mat.vertex_color_use_as_albedo = true
		_face_mat.roughness = 0.62
		_face_mat.metallic_specular = 0.06
		_face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if _blood.emission > 0.0:
			_face_mat.emission_enabled = true
			_face_mat.emission = (pal["flesh"] as Color) * _blood.emission * 0.4
	var mat: StandardMaterial3D = _face_mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Face"
	mi.mesh = CapMesh.build(radius, radius / CAP_WIDEN, pal, key.hash(), down)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.add_child(mi)


## Part `n` was cut from its parent: a cap on the stump (parent side, facing the piece) and one on the piece.
## `parts` maps names to bodies. Cap positions follow the joint pivot and the art's end faces.
func cut(parts: Dictionary, n: String) -> void:
	if _caps.has(n + "_piece"):
		return
	for sp: Array in _cut_specs(parts, n):
		_add_cap(sp[0], sp[1], sp[2], sp[3], sp[4])


## Builds one not-yet-built cap of a possible cut ahead of time (call once per frame from the start of a match), so a
## sever only attaches ready caps instead of instancing art and building gore meshes in the frame of the blow (the
## stall at a beheading). Returns false when every cap is built. Visual only.
func prebuild_step(parts: Dictionary) -> bool:
	while _prebuild_i < FighterRig.PARTS.size():
		var n: String = str(FighterRig.PARTS[_prebuild_i]["name"])
		if _prebuild_specs.is_empty():
			if n != "torso" and not _caps.has(n + "_piece"):  # the torso is never cut off
				_prebuild_specs = _cut_specs(parts, n)
		if _prebuild_specs.is_empty():
			_prebuild_i += 1
			continue
		var sp: Array = _prebuild_specs.pop_front()
		if _prebuild_specs.is_empty():
			_prebuild_i += 1
		var key: String = sp[1]
		if _ready_caps.has(key) or _caps.has(key):
			continue
		var cap: Node3D = _build_cap(sp[0], key, sp[2], sp[3], sp[4])
		if cap != null:
			_ready_caps[key] = cap
		return true
	return false


## Frees the prebuilt caps that were never used (they are outside the tree). Call when the fighter leaves.
func free_ready_caps() -> void:
	for k: String in _ready_caps:
		var c: Node = _ready_caps[k]
		if is_instance_valid(c):
			c.free()
	_ready_caps.clear()


## The two caps of a cut of part `n` as [body, key, asset, at, normal] (piece first), or [] when it has none.
func _cut_specs(parts: Dictionary, n: String) -> Array:
	var asset: String = BodyLook.cap_for(n, _outfit)
	var pd: Dictionary = FighterRig.part(n)
	if asset == "" or pd.is_empty() or str(pd["parent"]) == "":
		return []
	var pn: String = str(pd["parent"])
	if not parts.has(n) or not parts.has(pn):
		return []
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
	return [[piece_b, n + "_piece", asset, at_piece, -toward_piece], [parent_b, n + "_stump", asset, at_stump, toward_piece]]


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


const ARMOR_ART_DIR: String = "res://assets/armor/"
const ARMOR_ART_METALLIC: float = 0.6
static var _armor_art: Dictionary = {}  ## id -> opaque Mesh (or null when the asset is missing)


## Houdini armor piece `id` (res://assets/armor/<id>.glb or its textured copy, built in its body part's frame by
## tools/houdini/build_props.py, so it sits at the part's origin) as one opaque mesh with its own materials, or null.
## Loaded once per id; every caller gets its own duplicate of the mesh (the materials are shared and never changed).
static func armor_art(id: String) -> Mesh:
	if id == "":
		return null
	if not _armor_art.has(id):
		_armor_art[id] = _load_armor_art(TexturedArt.path(ARMOR_ART_DIR + id + ".glb"))
	var m: Mesh = _armor_art[id]
	return m.duplicate() as Mesh if m != null else null


static func _load_armor_art(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var sc: PackedScene = load(path) as PackedScene
	if sc == null:
		return null
	var root: Node = sc.instantiate()
	var src: MeshInstance3D = root as MeshInstance3D
	if src == null:
		var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
		src = found[0] as MeshInstance3D if not found.is_empty() else null
	var out: ArrayMesh = null
	if src != null and src.mesh is ArrayMesh:
		out = src.mesh.duplicate() as ArrayMesh
		# Houdini's glTF exporter marks every material alpha-blend: force opaque so it neither sorts nor flickers.
		for s: int in out.get_surface_count():
			var bm: BaseMaterial3D = out.surface_get_material(s) as BaseMaterial3D
			if bm != null:
				var o: BaseMaterial3D = bm.duplicate() as BaseMaterial3D
				o.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				o.albedo_color.a = 1.0
				# Fully metallic bronze mirrored the pale sky and read as silver: keep some of its own colour.
				o.metallic = minf(o.metallic, ARMOR_ART_METALLIC)
				out.surface_set_material(s, o)
	root.free()
	return out


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
