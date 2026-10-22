class_name WoundFx
extends Node
## Visible accumulated damage: wound marks on the fighters' bodies (WoundMarks: gashes, punctures, bruises, blood
## smears, also on the attacker who gets splashed) and blood coating their weapons and fists (WeaponCoat). Driven only
## by the fighters' `hit` and `gore` signals, which an online client already replays from the host's events, so both
## screens draw the same marks. BloodFx also routes its body stains here (`add_stain`: the soak of a bleeding blow,
## `add_drop`: blood drops landing on a fighter), so every mark on skin or armor wraps the real surface. A severed limb
## or neck gets a blood collar on both cut ends. Presentation only: never part of the fight state.
## Drawing: each marked body part (or bloodied weapon) gets a "shell": a second MeshInstance3D per visible mesh, with
## the same mesh and a wound shader that is transparent except where the marks are. Shells live in their own node
## (not under Look / ArmorSlot, so HitFx flashes and armor code never see them) and follow their source's visibility.
## Cost: one extra draw per marked mesh (none before the first mark), at most WoundMarks.cap marks per part.
## Wire up: add as a child, `set_palette(side, palette)` and `track(fighter)` per fighter, `clear()` between matches.

const BODY_SHADER: String = "res://game/fx/wounds/wound_overlay.gdshader"
const COAT_SHADER: String = "res://game/fx/wounds/weapon_coat.gdshader"
const SHELL_NODE: String = "WoundShells"
const PUSH_EVERY: float = 0.2  ## seconds between uniform refreshes as marks age (new marks push at once)
const SPLASH_CHANCE: float = 0.75  ## share of bleeding hits that splash the attacker
const SPLASH_REACH: float = 1.2  ## m from the hit to the attacker's nearest part surface (the spray flies back)
const SPLASH_PARTS: PackedStringArray = ["forearm_r", "forearm_l", "upper_arm_r", "upper_arm_l", "torso", "head"]
const HEAD_SIZE: Vector3 = Vector3(0.095, 0.095, 0.095)  ## the drawn head is smaller than the rig's sphere
const BRUISE_RED: Color = Color(0.20, 0.03, 0.16)
const BRUISE_RED_OLD: Color = Color(0.42, 0.40, 0.10)
const ART_RAY_OUT: float = 0.15  ## the art ray starts this far outside the collider surface
const ART_RAY_IN: float = 0.08  ## and accepts drawn surfaces up to this far inside it
static var _TRI_CACHE: Dictionary = {}  ## Mesh -> TriangleMesh

var quality: int = 2
var palettes: Array = [BloodPalette.red(), BloodPalette.red()]
var _by_side: Dictionary = {}  ## side -> fighter
var _marks: Dictionary = {}  ## side -> WoundMarks
var _shells: Dictionary = {}  ## part or weapon Node3D -> Array of [shell MeshInstance3D, source MeshInstance3D]
var _coats: Dictionary = {}  ## Weapon node -> WeaponCoat
var _body_shader: Shader = null
var _coat_shader: Shader = null
var _push_acc: float = 0.0
var _drop_budget: Dictionary = {}  ## side -> drop smears it may still take (refills at Tuning wound_drop_rate per s)
var stat_shells: int = 0  ## live shell meshes (extra draws), for perf checks


func _init() -> void:
	quality = GfxQuality.blood_level()


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	for side: int in _marks:
		(_marks[side] as WoundMarks).cap = WoundMarks.cap_for(quality)


func set_palette(slot: int, pal: BloodPalette) -> void:
	palettes[clampi(slot, 0, 1)] = pal if pal != null else BloodPalette.red()
	for host: Variant in _shells:
		for pair: Array in _shells[host]:
			if is_instance_valid(pair[0]):
				_set_palette_params((pair[0] as MeshInstance3D).material_override as ShaderMaterial)


func track(f: Node) -> void:
	if f == null:
		return
	var sv: Variant = f.get("side")
	var side: int = int(sv) if sv != null else _by_side.size()
	_by_side[side] = f
	_marks[side] = WoundMarks.new(quality)
	_drop_budget[side] = _tn().wound_drop_rate
	if f.has_signal("hit") and not f.is_connected("hit", on_hit):
		f.connect("hit", on_hit)
	if f.has_signal("gore") and not f.is_connected("gore", on_gore):
		f.connect("gore", on_gore.bind(side))


func clear() -> void:
	for f: Variant in _by_side.values():
		if is_instance_valid(f) and (f as Node).is_connected("hit", on_hit):
			(f as Node).disconnect("hit", on_hit)
		if is_instance_valid(f) and (f as Node).has_signal("gore"):
			for c: Dictionary in (f as Node).get_signal_connection_list("gore"):
				if (c["callable"] as Callable).get_object() == self:
					(f as Node).disconnect("gore", c["callable"] as Callable)
	for host: Variant in _shells:
		if is_instance_valid(host):
			var n: Node = (host as Node).get_node_or_null(SHELL_NODE)
			if n != null:
				n.queue_free()
	_by_side.clear()
	_marks.clear()
	_shells.clear()
	_coats.clear()
	_drop_budget.clear()
	stat_shells = 0


func marks_of(side: int) -> WoundMarks:
	return _marks.get(side) as WoundMarks


func coat_of(w: Node) -> WeaponCoat:
	return _coats.get(w) as WeaponCoat


# --- events ------------------------------------------------------------------------------------------------------

func on_hit(ev: Dictionary) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		return
	var tside: int = int(ev.get("target", -1))
	var target: Node = _by_side.get(tside)
	if target == null or not is_instance_valid(target):
		return
	var part: String = str(ev.get("part", ""))
	var body: Node3D = _part(target, part)
	if body == null:
		return
	var cut: float = float(ev.get("cut", 0.0))
	var pierce: float = float(ev.get("pierce", 0.0))
	var blunt: float = float(ev.get("blunt", 0.0))
	var kind: int = WoundMarks.kind_for(str(ev.get("contact", "")), cut, pierce, blunt, bool(ev.get("glanced", false)))
	if kind < 0:
		return
	var point: Vector3 = ev.get("point", body.global_position)
	var sev: float = WoundMarks.severity(kind, cut, pierce, blunt)
	var slot: int = clampi(tside, 0, 1)
	var rel: Vector3 = ev.get("rel_vel", Vector3.ZERO)
	_mark(tside, body, part, kind, point, rel, sev, slot)
	var bleeds: bool = kind != WoundMarks.Kind.BRUISE
	if bleeds and sev > 0.3:  ## a big wound throws a splash of its own blood beside it, along the blow
		var along: Vector3 = rel.normalized() if rel.length() > 0.5 else Vector3.DOWN
		_mark(tside, body, part, WoundMarks.Kind.SMEAR, point + along * 0.08, rel, sev * 0.7, slot)
	var aside: int = int(ev.get("attacker", -1))
	var attacker: Node = _by_side.get(aside)
	if attacker == null or not is_instance_valid(attacker):
		return
	_coat_weapon(attacker, str(ev.get("weapon_id", "")), point, cut, pierce, blunt, slot)
	if bleeds and aside != tside and WoundMarks.seed_of(point * 1.7) < SPLASH_CHANCE:
		_splash_attacker(aside, attacker, point, rel, sev, slot)


func _mark(side: int, body: Node3D, part: String, kind: int, point: Vector3, rel: Vector3, sev: float,
		slot: int, stretch: float = 1.0, push: bool = true) -> bool:
	var wm: WoundMarks = _marks.get(side) as WoundMarks
	if wm == null:
		return false
	var shape: Array = _shape_of(part)
	var inv: Basis = body.global_transform.basis.inverse()
	var local: Vector3 = WoundMarks.snap_to_surface(str(shape[0]), shape[1] as Vector3, body.to_local(point))
	var nrm: Vector3 = WoundMarks.surface_normal(str(shape[0]), shape[1] as Vector3, local)
	_ensure_shells(body, true)
	var hit: Array = _on_art(body, local, nrm)  # the drawn surface, which can sit well inside the collider (alien)
	if not hit.is_empty():
		local = hit[0]
		nrm = hit[1]
	if wm.add(part, kind, local, nrm, inv * rel, inv * Vector3.DOWN, sev, slot, stretch) == null:
		return false
	if push:
		_push_part(wm, part, body)
	return true


## Blood soaked into part `part` of fighter `f` at world `point`: a smear streaked along `along` (world), strength
## `sev` 0..1, of palette `slot`. Returns false when `f` or the part is not tracked.
func add_stain(f: Node, part: String, point: Vector3, along: Vector3, sev: float, slot: int,
		stretch: float = 1.0) -> bool:
	var side: int = _side_of(f)
	var body: Node3D = _part(f, part)
	if side < 0 or body == null:
		return false
	return _mark(side, body, part, WoundMarks.Kind.SMEAR, point, along, sev, clampi(slot, 0, 1), stretch)


## A blood drop of radius `radius` (m) landing on part `part` of fighter `f` at `point` with velocity `vel`: a small
## smear streaked along the landing speed, or a deeper one where drops already landed. At most Tuning
## wound_drop_rate per fighter per second; the shells pick it up at the next refresh. False when it left no mark.
func add_drop(f: Node, part: String, point: Vector3, vel: Vector3, radius: float, slot: int) -> bool:
	var side: int = _side_of(f)
	if side < 0 or float(_drop_budget.get(side, 0.0)) < 1.0:
		return false
	var body: Node3D = _part(f, part)
	if body == null:
		return false
	_drop_budget[side] = float(_drop_budget[side]) - 1.0
	var sev: float = WoundMarks.smear_sev_for(radius * _tn().wound_drop_size)
	return _mark(side, body, part, WoundMarks.Kind.SMEAR, point, vel, sev, clampi(slot, 0, 1), drop_stretch(vel),
			false)


## Streak of a landed drop: longer the faster it hit (1 at rest, WoundMarks.STRETCH_MAX at 18 m/s and up).
static func drop_stretch(vel: Vector3) -> float:
	return clampf(1.0 + vel.length() * 0.12, 1.0, WoundMarks.STRETCH_MAX)


## A severed limb or head: a blood collar on the stump (the parent part, at the joint) and on the cut end of the part
## that came off, so the skin round both cap faces reads as cut, not clean.
func on_gore(ev: Dictionary, side: int) -> void:
	var kind: String = str(ev.get("kind", ""))
	if kind != "sever" and kind != "behead":
		return
	var sev: float = _tn().wound_stump_sev
	var f: Node = _by_side.get(side)
	if sev <= 0.0 or f == null or not is_instance_valid(f):
		return
	var part: String = str(ev.get("part", "head" if kind == "behead" else ""))
	var ends: Array = stump_ends(part)
	if ends.is_empty():
		return
	var slot: int = clampi(side, 0, 1)
	for e: Array in ends:
		var body: Node3D = _part(f, str(e[0]))
		if body != null:
			var at: Vector3 = body.to_global(e[1] as Vector3)
			_mark(side, body, str(e[0]), WoundMarks.Kind.SMEAR, at, body.global_transform.basis * Vector3.UP, sev, slot)


## [[part, joint point in that part's frame], ...] for the two cut ends of severing `part` from its parent (the
## stump first); empty for a part with no parent. Rig parts sit unrotated in the rest pose, so frame offsets are
## differences of rest positions.
static func stump_ends(part: String) -> Array:
	var pd: Dictionary = {}
	for d: Dictionary in FighterRig.PARTS:
		if str(d["name"]) == part:
			pd = d
	if pd.is_empty() or str(pd["parent"]) == "":
		return []
	var parent: String = str(pd["parent"])
	var pivot: Vector3 = pd["pivot"]
	var pcenter: Vector3 = Vector3.ZERO
	for d: Dictionary in FighterRig.PARTS:
		if str(d["name"]) == parent:
			pcenter = d["center"]
	return [[parent, pivot - pcenter], [part, pivot - (pd["center"] as Vector3)]]


## The point where a ray from outside along -`nrm` through `local` (part frame) meets the part's drawn meshes (skin,
## outfit or armor, whichever is outermost), with that surface's normal; empty when it misses them all.
func _on_art(body: Node3D, local: Vector3, nrm: Vector3) -> Array:
	var best: Array = []
	var best_t: float = INF
	var from: Vector3 = local + nrm * ART_RAY_OUT
	for pair: Array in _shells.get(body, []):
		var sh: Variant = pair[0]
		if not is_instance_valid(sh) or not (sh as MeshInstance3D).visible:
			continue
		var tm: TriangleMesh = _tri_mesh((sh as MeshInstance3D).mesh)
		if tm == null:
			continue
		var rel: Transform3D = (sh as MeshInstance3D).transform
		var ri: Transform3D = rel.affine_inverse()
		var r: Dictionary = tm.intersect_ray(ri * from, (ri.basis * -nrm).normalized())
		if r.is_empty():
			continue
		var p: Vector3 = rel * (r["position"] as Vector3)
		var t: float = (p - from).dot(-nrm)
		if t >= 0.0 and t < best_t and t < ART_RAY_OUT + ART_RAY_IN:
			best_t = t
			var n: Vector3 = (rel.basis * (r["normal"] as Vector3)).normalized()
			best = [p, n if n.dot(nrm) > 0.0 else nrm]
	return best


## Ray-test mesh of a drawn mesh, built once per mesh resource (body art is shared by every fighter).
static func _tri_mesh(m: Mesh) -> TriangleMesh:
	if m == null:
		return null
	if not _TRI_CACHE.has(m):
		_TRI_CACHE[m] = m.generate_triangle_mesh()
	return _TRI_CACHE[m] as TriangleMesh


## Blood from the wound lands on the attacker's nearest part (a forearm, the chest, the face).
func _splash_attacker(aside: int, attacker: Node, point: Vector3, rel: Vector3, sev: float, slot: int) -> void:
	var best: String = ""
	var best_d: float = SPLASH_REACH
	for pn: String in SPLASH_PARTS:
		var b: Node3D = _part(attacker, pn)
		if b == null:
			continue
		var shape: Array = _shape_of(pn)
		var lp: Vector3 = b.to_local(point)
		var d: float = lp.distance_to(WoundMarks.snap_to_surface(str(shape[0]), shape[1] as Vector3, lp))
		if d < best_d:
			best_d = d
			best = pn
	if best != "":
		_mark(aside, _part(attacker, best), best, WoundMarks.Kind.SMEAR, point, rel, clampf(sev * 0.7, 0.2, 0.8), slot)


func _coat_weapon(attacker: Node, wid: String, point: Vector3, cut: float, pierce: float, blunt: float,
		slot: int) -> void:
	var w: Node3D = null
	var best: float = INF
	for key: String in ["weapon", "offhand", "fist_r", "fist_l"]:
		var c: Variant = attacker.get(key)
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var cw: Node3D = c as Node3D
		if str(cw.get("weapon_id")) != wid:
			continue
		var d: float = cw.global_position.distance_to(point)  ## two fists: the one that landed is the nearer
		if d < best:
			best = d
			w = cw
	if w == null or str((w.get("def") as Dictionary).get("look", "")) == "laser":
		return
	var coat: WeaponCoat = _coats.get(w) as WeaponCoat
	if coat == null:
		coat = WeaponCoat.new()
		_coats[w] = coat
	coat.add_hit(w.to_local(point), cut, pierce, blunt, slot,
			WeaponCoat.FIST_BLOT_MAX if w.get("is_fist") == true else WeaponCoat.BLOT_MAX)
	if coat.is_bloody():
		_ensure_shells(w, false)
		_push_coat(w, coat)


# --- per frame ---------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	var rate: float = _tn().wound_drop_rate
	for side: int in _marks:
		(_marks[side] as WoundMarks).step(dt)
		_drop_budget[side] = minf(float(_drop_budget.get(side, 0.0)) + rate * dt, maxf(rate, 1.0))
	for w: Variant in _coats:
		(_coats[w] as WeaponCoat).step(dt)
	_push_acc += dt
	if _push_acc < PUSH_EVERY:
		return
	_push_acc = 0.0
	_sync_visibility()
	for side: int in _marks:
		var f: Node = _by_side.get(side)
		if f == null or not is_instance_valid(f):
			continue
		var wm: WoundMarks = _marks[side]
		for part: String in wm.marks:
			var body: Node3D = _part(f, part)
			if body != null:
				_push_part(wm, part, body)
	for w: Variant in _coats.keys():
		if not is_instance_valid(w):
			_coats.erase(w)
			continue
		_push_coat(w as Node3D, _coats[w] as WeaponCoat)


## Shells follow their source mesh: hidden with it (a knocked-off armor piece), dropped when it is gone.
func _sync_visibility() -> void:
	var live: int = 0
	for host: Variant in _shells.keys():
		if not is_instance_valid(host):
			_shells.erase(host)
			continue
		var kept: Array = []
		for pair: Array in _shells[host]:
			var sh: Variant = pair[0]
			var src: Variant = pair[1]
			if not is_instance_valid(sh):
				continue
			if not is_instance_valid(src):
				(sh as Node).queue_free()
				continue
			(sh as MeshInstance3D).visible = (src as MeshInstance3D).is_visible_in_tree()
			kept.append(pair)
		_shells[host] = kept
		live += kept.size()
	stat_shells = live


# --- shells and uniforms -----------------------------------------------------------------------------------------

## Builds the shells of `host` (a body part, or a weapon) once: one per visible source mesh.
func _ensure_shells(host: Node3D, body: bool) -> void:
	if _shells.has(host):
		return
	if _body_shader == null:
		_body_shader = load(BODY_SHADER) as Shader
		_coat_shader = load(COAT_SHADER) as Shader
	var holder := Node3D.new()
	holder.name = SHELL_NODE
	host.add_child(holder)
	var pairs: Array = []
	var sources: Array = []
	if body:
		for slot_name: String in ["Look", "ArmorSlot"]:
			var s: Node = host.get_node_or_null(slot_name)
			if s != null:
				_collect(s, sources, slot_name == "ArmorSlot")
	else:
		_collect(host, sources, false)
	var inv: Transform3D = host.global_transform.affine_inverse()
	for e: Array in sources:
		var src: MeshInstance3D = e[0]
		var rel: Transform3D = inv * src.global_transform
		var mat := ShaderMaterial.new()
		mat.shader = _body_shader if body else _coat_shader
		mat.set_shader_parameter("to_part" if body else "to_weapon", Projection(rel))
		if body:
			mat.set_shader_parameter("armor", bool(e[1]))
		else:
			_setup_coat_params(mat, host)
		_set_palette_params(mat)
		var sh := MeshInstance3D.new()
		sh.mesh = src.mesh
		sh.material_override = mat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh.transform = rel
		holder.add_child(sh)
		pairs.append([sh, src])
	_shells[host] = pairs
	stat_shells += pairs.size()


func _collect(n: Node, out: Array, armor: bool) -> void:
	if n.name == SHELL_NODE or n.has_meta("glow"):
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
		out.append([n, armor])
	for c: Node in n.get_children():
		_collect(c, out, armor)


func _set_palette_params(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	for k: int in 2:
		var pal: BloodPalette = palettes[k]
		mat.set_shader_parameter("fresh%d" % k, pal.stain_color(0.0))
		mat.set_shader_parameter("dried%d" % k, pal.stain_color(1.0))
		mat.set_shader_parameter("flesh%d" % k, pal.flesh)
		mat.set_shader_parameter("glow%d" % k, pal.emission)
		var bz: Array = bruise_colors(pal)
		mat.set_shader_parameter("bruise%d" % k, bz[0])
		mat.set_shader_parameter("bruise_old%d" % k, bz[1])


## [core, faded rim] colours of a bruise for blood palette `pal`: purple going yellow-green for red blood; a darkened
## shade of the blood itself for any other colour (the alien bruises teal, never purple).
static func bruise_colors(pal: BloodPalette) -> Array:
	var c: Color = pal.fresh
	if c.r > c.g and c.r > c.b:
		return [BRUISE_RED, BRUISE_RED_OLD]
	return [BloodPalette.scaled(pal.dried, 1.1), BloodPalette.scaled(pal.fresh, 0.55)]


func _push_part(wm: WoundMarks, part: String, body: Node3D) -> void:
	var pairs: Array = _shells.get(body, [])
	if pairs.is_empty():
		return
	var pk: Dictionary = wm.pack(part)
	wm.dirty.erase(part)
	var tn: Tuning = _tn()
	var glow_dry: float = WoundMarks.dryness(tn.wound_rim_glow_s)
	for pair: Array in pairs:
		if not is_instance_valid(pair[0]):
			continue
		var mat: ShaderMaterial = (pair[0] as MeshInstance3D).material_override as ShaderMaterial
		mat.set_shader_parameter("core_scale", tn.wound_core_scale)
		mat.set_shader_parameter("rim_glow", tn.wound_rim_glow)
		mat.set_shader_parameter("rim_glow_dry", glow_dry)
		mat.set_shader_parameter("count", int(pk["count"]))
		mat.set_shader_parameter("wa", pk["a"])
		mat.set_shader_parameter("wb", pk["b"])
		mat.set_shader_parameter("wc", pk["c"])
		mat.set_shader_parameter("wd", pk["d"])
		mat.set_shader_parameter("we", pk["e"])


## Weapon-frame numbers the coat shader needs: how the coat spreads (mode) and over which span.
func _setup_coat_params(mat: ShaderMaterial, w: Node3D) -> void:
	var p: Dictionary = coat_shape(w.get("def") as Dictionary, w.get("tip_local") as Vector3)
	mat.set_shader_parameter("mode", int(p["mode"]))
	mat.set_shader_parameter("tip_y", float(p["tip_y"]))
	mat.set_shader_parameter("base_y", float(p["base_y"]))
	mat.set_shader_parameter("edge_x", float(p["edge_x"]))
	mat.set_shader_parameter("seed", WoundMarks.seed_of(Vector3(float(w.get_instance_id() % 997), 1.0, 2.0)))


## Coat layout for a weapon def: mode 0 blade (tip then edges), 1 blunt head, 2 shield face, 3 fist; the blood
## creeps from tip_y down to base_y; edge_x is the blade's half width where the edges are (0: no edge creep).
static func coat_shape(def: Dictionary, tip_local: Vector3) -> Dictionary:
	var shape: String = str(def.get("shape", "club"))
	var length: float = maxf(float(def.get("length", 0.3)), 0.05)
	var edge_len: float = float(def.get("edge_len", 0.0))
	var tip: float = tip_local.y
	match shape:
		"fist":
			return {"mode": 3, "tip_y": tip, "base_y": tip - 0.1, "edge_x": 0.0}
		"shield":
			return {"mode": 2, "tip_y": tip, "base_y": -tip, "edge_x": 0.0}
		"sword", "axe", "spear", "rake":
			var span: float = maxf(edge_len, 0.12) if shape != "spear" else 0.3
			var ex: float = 0.026 if shape == "sword" else 0.0
			return {"mode": 0, "tip_y": tip, "base_y": tip - span, "edge_x": ex}
	return {"mode": 1, "tip_y": tip, "base_y": tip - length * 0.5, "edge_x": 0.0}


func _push_coat(w: Node3D, coat: WeaponCoat) -> void:
	var pairs: Array = _shells.get(w, [])
	if pairs.is_empty():
		return
	var pk: Dictionary = coat.pack()
	var pal: BloodPalette = palettes[clampi(int(pk["slot"]), 0, 1)]
	coat.dirty = false
	for pair: Array in pairs:
		if not is_instance_valid(pair[0]):
			continue
		var mat: ShaderMaterial = (pair[0] as MeshInstance3D).material_override as ShaderMaterial
		mat.set_shader_parameter("coat", float(pk["coat"]))
		mat.set_shader_parameter("dry", float(pk["dry"]))
		mat.set_shader_parameter("blot_count", int(pk["count"]))
		mat.set_shader_parameter("blots", pk["blots"])
		mat.set_shader_parameter("fresh", pal.stain_color(0.0))
		mat.set_shader_parameter("dried", pal.stain_color(1.0))
		mat.set_shader_parameter("glow", pal.emission)


# --- helpers -----------------------------------------------------------------------------------------------------

static func _tn() -> Tuning:
	return Tuning.shared()


## Side of tracked fighter `f`, or -1.
func _side_of(f: Node) -> int:
	if f == null:
		return -1
	for side: int in _by_side:
		if _by_side[side] == f:
			return side
	return -1


func _part(f: Node, part: String) -> Node3D:
	if f == null or part == "":
		return null
	var pv: Variant = f.get("parts")
	if pv is Dictionary and (pv as Dictionary).has(part):
		var b: Variant = (pv as Dictionary)[part]
		if b is Node3D and is_instance_valid(b):
			return b as Node3D
	return null


## [shape, size] of a rig part ("capsule", "box", "sphere"); the head uses its drawn size.
static func _shape_of(part: String) -> Array:
	if part == "head":
		return ["sphere", HEAD_SIZE]
	for pd: Dictionary in FighterRig.PARTS:
		if str(pd["name"]) == part:
			return [str(pd["shape"]), pd["size"] as Vector3]
	return ["sphere", Vector3(0.08, 0.08, 0.08)]
