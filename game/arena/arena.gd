class_name Arena
extends Node3D
## The sand arena, built entirely in code: floor collider, stone wall with a wooden rail, stepped stands with a
## blocky crowd, banners, torches, a velarium, one shadowed sun, sky and haze. Collision is layer 1 only.
## The floor's visual is a SandSurface (game/sand/) when that script exists, else a flat placeholder disc.

const SAND_SCRIPT: String = "res://game/sand/sand_surface.gd"
## SandSurface.BASE_SEED and the disc margin of SandSurface.setup, for the SandTables prewarm (keys must match).
const SAND_BASE_SEED: int = 7
const SAND_DISC_MARGIN: float = 0.35
const WALL_SIDES: int = 48
const WALL_HEIGHT: float = 3.0
const TIER_COUNT: int = 6
const TIER_DEPTH: float = 1.3
const TIER_RISE: float = 0.75
const STAND_GAP: float = 0.6
const SPAWN_DISTANCE: float = 4.0
const SUN_AZIMUTH: float = 3.75
const SUN_ELEVATION: float = 0.62
const CROWD_SEED: int = 20260721
## From this tier out the spectators are small and far: GfxQuality spaces them wider.
const CROWD_BACK_TIER: int = 3
const CROWD_SPACING: Array[float] = [0.62, 0.62, 0.66, 0.8, 0.9, 1.0]
const ATTIC_HEIGHT: float = 2.0
const BOX_ANGLE: float = 4.71238898
const TRAVERTINE: Color = Color(0.84, 0.74, 0.56)
const PLAQUES: PackedStringArray = ["SPQR", "MVNVS", "ROMA", "LEGIO"]
## Light and grade (art direction: warm low afternoon sun, deep shade). Presentation only.
const SUN_COLOR: Color = Color(1.0, 0.9, 0.78)
const SUN_ENERGY: float = 1.3
const AMBIENT_ENERGY: float = 0.4
const EXPOSURE: float = 1.05
## Houdini dressing placement (metres, radians). Portcullis 3.6 x 3.9 m as exported, scaled to the 3 m podium wall.
const BRAZIER_FLAME_Y: float = 1.12
const STATUE_ANGLE_OFFSET: float = 0.3
const STATUE_SCALE: float = 0.7
const LOW_CODE_PROPS: PackedStringArray = ["banner", "brazier"]
## Cloth banners hung on the wall panels (Houdini banner, scaled to clear the plinth moulding and the cornice).
const WALL_BANNER_ANGLES: Array[float] = [1.1126, 2.1598, 4.2542, 5.3014]
const WALL_BANNER_SCALE: float = 0.85
const WALL_BANNER_OUT: float = 0.16
## The big statue on its plinth stands on this tier behind the imperial box, its top under the velarium.
const BOX_STATUE_TIER: int = 3
const BOX_STATUE_SCALE: float = 1.65
const BOX_STATUE_GAP: float = 0.07  ## radians of that tier left empty of spectators round the statue

var radius: float = 11.0
var sand: Node3D
var sun: DirectionalLight3D
var crowd: Crowd
var _flames: Array[MeshInstance3D] = []
var _flame_time: float = 0.0
var _torch_positions: PackedVector3Array = PackedVector3Array()
var _dressing: ArenaDressing = ArenaDressing.new()
var build_ms: Dictionary = {}  ## step name -> ms of the last build (see build_profile)
var _sand_load_ms: float = 0.0
## Flame height above the wall cap: a Houdini brazier's bowl, or the code torch's bowl.
var _flame_y: float = 1.8


## Spawn transform for a side: 0 at +Z, 1 at -Z, both facing the centre (fighter forward is -Z).
static func spawn_transform(side: int, arena_radius: float) -> Transform3D:
	var d: float = minf(SPAWN_DISTANCE, arena_radius * 0.5)
	if side == 0:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, d))
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -d))


## Point on the polygon ring whose flat sides sit at `apothem`, at angle `a` (radians), height `y`.
static func ring_point(apothem: float, a: float, y: float, sides: int) -> Vector3:
	var r: float = apothem / cos(PI / float(sides))
	return Vector3(r * cos(a), y, r * sin(a))


## Basis whose local +Z points outward at angle `a` (so local -Z faces the centre).
static func ring_basis(a: float) -> Basis:
	return Basis(Vector3.UP, PI * 0.5 - a)


func _ready() -> void:
	radius = Tuning.shared().arena_radius
	if get_viewport() != null:
		get_viewport().msaa_3d = GfxQuality.pick_i(GfxQuality.MSAA) as Viewport.MSAA
	_dressing.stone_tint = TRAVERTINE
	if _art("brazier") != null:
		_flame_y = BRAZIER_FLAME_Y
	_torch_positions = PackedVector3Array()
	for k: int in 6:
		var ta: float = deg_to_rad(30.0 + float(k) * 60.0)
		_torch_positions.append(ring_point(radius + 0.3, ta, WALL_HEIGHT, WALL_SIDES) + Vector3(0, _flame_y - 0.2, 0))
	if ResourceLoader.exists(SAND_SCRIPT):
		var cell: float = GfxQuality.pick_f(GfxQuality.SAND_MESH_CELL)
		SandTables.prewarm(radius, SandMap.map_extent(radius), SAND_BASE_SEED, radius + SAND_DISC_MARGIN, cell)
	var steps: Array[Callable] = [_build_floor, _build_wall_colliders, _build_wall_visual, _build_stands, _build_crowd,
			_build_props, _build_velarium, _build_dressing, _build_sand, _build_environment]
	for step: Callable in steps:
		var t0: int = Time.get_ticks_usec()
		step.call()
		build_ms[step.get_method().trim_prefix("_build_")] = float(Time.get_ticks_usec() - t0) / 1000.0
	if Flags.args.has("arena_profile"):
		ProfileLog.emit("ARENA_BUILD", build_profile())


## Per-step build times (ms) of the last _ready, with the sand setup's own steps under "sand.<step>". Wall clock:
## presentation profiling only (`-- --arena_profile` prints it), never gameplay.
func build_profile() -> Dictionary:
	var out: Dictionary = build_ms.duplicate()
	var total: float = 0.0
	for k: String in build_ms:
		total += float(build_ms[k])
	out["total"] = total
	out["sand.load_script"] = _sand_load_ms
	if sand != null and "setup_ms" in sand:
		for k: String in (sand.get("setup_ms") as Dictionary):
			out["sand." + k] = sand.get("setup_ms")[k]
	return out


func spawn_point(side: int) -> Transform3D:
	return spawn_transform(side, radius)


func _process(delta: float) -> void:
	_flame_time += delta
	for i: int in _flames.size():
		var f: float = 1.0 + 0.18 * sin(_flame_time * 13.0 + float(i) * 2.1) + 0.1 * sin(_flame_time * 29.0 + float(i))
		_flames[i].scale = Vector3(1.0, f, 1.0)


# ---------------------------------------------------------------- floor and wall

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	body.physics_material_override = pm
	var shape := BoxShape3D.new()
	var side: float = radius * 2.0 + 10.0
	shape.size = Vector3(side, 1.0, side)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(cs)
	add_child(body)
	# Dirt beyond the stands so the horizon is never empty. Lowered, never coplanar with the floor.
	var ground := MeshInstance3D.new()
	ground.mesh = _disc_mesh(140.0, 32)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.28, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(0.0, -0.06, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## The floor's visual: a SandSurface, or a flat placeholder disc without the sand script. Built late in _ready so the
## SandTables prewarm started at its top has run on a worker while the walls, stands and crowd were built.
func _build_sand() -> void:
	if ResourceLoader.exists(SAND_SCRIPT):
		var t0: int = Time.get_ticks_usec()
		var script: GDScript = load(SAND_SCRIPT)
		_sand_load_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		sand = script.new() as Node3D
		sand.name = "Sand"
		add_child(sand)
		sand.call("setup", radius, GfxQuality.pick_f(GfxQuality.SAND_TEXELS_PER_M), GfxQuality.pick_f(GfxQuality.SAND_MESH_CELL))
	else:
		var mi := MeshInstance3D.new()
		mi.name = "Sand"
		mi.mesh = _disc_mesh(radius + 1.0, 64)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.37, 0.22)
		m.roughness = 1.0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		sand = mi


func _disc_mesh(r: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in segs:
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(r * cos(a0), 0.0, r * sin(a0)))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(r * cos(a1), 0.0, r * sin(a1)))
	return st.commit()


func _build_wall_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "WallBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var depth: float = 1.0
	var apothem_out: float = radius + depth
	var width: float = 2.0 * apothem_out * tan(PI / float(WALL_SIDES)) + 0.3
	for i: int in WALL_SIDES:
		var a: float = TAU * (float(i) + 0.5) / float(WALL_SIDES)
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, WALL_HEIGHT + 2.5, depth)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(ring_basis(a), Vector3((radius + depth * 0.5) * cos(a), (WALL_HEIGHT - 2.5) * 0.5, (radius + depth * 0.5) * sin(a)))
		body.add_child(cs)
	ArenaDressing.add_colliders(body, DecorLayout.colliders(radius))
	add_child(body)


func _build_wall_visual() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bronze := SurfaceTool.new()
	bronze.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED
	var n: int = WALL_SIDES
	for i: int in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var mid: float = (a0 + a1) * 0.5
		var tint: float = rng.randf_range(0.92, 1.05)
		var c: Color = TRAVERTINE * tint
		c.a = 1.0
		var in0: Vector3 = ring_point(radius, a0, 0.0, n)
		var in1: Vector3 = ring_point(radius, a1, 0.0, n)
		var inward: Vector3 = Vector3(-cos(mid), 0.0, -sin(mid))
		var up := Vector3(0, WALL_HEIGHT, 0)
		RomanDecor.quad(st, in0, in1, in1 + up, in0 + up, c, inward)
		var out0: Vector3 = ring_point(radius + STAND_GAP, a0, WALL_HEIGHT, n)
		var out1: Vector3 = ring_point(radius + STAND_GAP, a1, WALL_HEIGHT, n)
		RomanDecor.quad(st, in0 + up, in1 + up, out1, out0, c * 0.92, Vector3.UP)
		var seg_len: float = 2.0 * radius * tan(PI / float(n))
		var bm: Basis = ring_basis(mid)
		var fb: Basis = RomanDecor.face_basis(mid)
		# Plinth and cornice mouldings (stone, proud of the wall).
		RomanDecor.box(st, Transform3D(bm, ring_point(radius - 0.04, mid, 0.25, n)), Vector3(seg_len + 0.02, 0.5, 0.1), c * 0.85)
		RomanDecor.box(st, Transform3D(bm, ring_point(radius - 0.07, mid, WALL_HEIGHT - 0.22, n)), Vector3(seg_len + 0.02, 0.2, 0.16), c * 1.04)
		RomanDecor.box(st, Transform3D(bm, ring_point(radius - 0.04, mid, WALL_HEIGHT - 0.4, n)), Vector3(seg_len + 0.02, 0.06, 0.1), c * 0.9)
		var gate: bool = _near_gate(mid)
		# Pilasters on every even vertex, except at the gates.
		if i % 2 == 0 and not _near_gate(a0, 0.12):
			var bp := Basis(Vector3.UP, PI * 0.5 - a0)
			var pil: Color = TRAVERTINE * 1.04
			pil.a = 1.0
			RomanDecor.box(st, Transform3D(bp, ring_point(radius - 0.1, a0, 1.45, n)), Vector3(0.36, 2.2, 0.2), pil)
			RomanDecor.box(st, Transform3D(bp, ring_point(radius - 0.12, a0, 0.6, n)), Vector3(0.46, 0.14, 0.24), pil * 0.9)
			RomanDecor.box(st, Transform3D(bp, ring_point(radius - 0.12, a0, 2.6, n)), Vector3(0.5, 0.22, 0.26), pil * 1.02)
			RomanDecor.box(bronze, Transform3D(bp, ring_point(radius - 0.14, a0, 2.43, n)), Vector3(0.4, 0.05, 0.22), Color(0.55, 0.38, 0.16))
		if gate:
			continue
		var centre: Vector3 = (in0 + in1) * 0.5 + inward * 0.03
		var plaque: bool = (i % 12) == 6
		var pw: float = seg_len - 0.32
		if plaque:
			RomanDecor.rect(paint, centre + Vector3(0, 1.45, 0), fb, pw, 1.0, Color(0.1, 0.09, 0.08))
			RomanDecor.rect(paint, centre + Vector3(0, 1.45, 0) + fb.z * 0.01, fb, pw - 0.1, 0.9, RomanDecor.MARBLE)
			var word: String = PLAQUES[(i / 12) % PLAQUES.size()]
			var th: float = minf(0.3, (pw - 0.25) / (RomanDecor.text_width(word, 1.0)))
			RomanDecor.text(paint, word, centre + Vector3(0, 1.45, 0) + fb.z * 0.02, fb, th, Color(0.2, 0.17, 0.14))
			for sx: float in [-1.0, 1.0]:
				RomanDecor.box(bronze, Transform3D(bm, centre + Vector3(0, 1.45, 0) + fb.x * (sx * (pw * 0.5)) - fb.z * 0.01), Vector3(0.07, 1.06, 0.07), Color(0.55, 0.38, 0.16))
			continue
		_panel_frame(st, (in0 + in1) * 0.5, bm, fb, pw, 1.75, c)
		var field: Color = RomanDecor.PALETTE_RED if i % 2 == 0 else RomanDecor.PALETTE_OCHRE
		RomanDecor.rect(paint, centre + Vector3(0, 1.45, 0), fb, pw, 1.75, RomanDecor.PALETTE_BLACK)
		RomanDecor.rect(paint, centre + Vector3(0, 1.45, 0) + fb.z * 0.01, fb, pw - 0.22, 1.53, field)
		# Greek key under the top border, in the other panel colour; a wreath on every fourth panel.
		var key_bg: Color = RomanDecor.PALETTE_OCHRE if i % 2 == 0 else RomanDecor.PALETTE_RED
		RomanDecor.meander(paint, centre + Vector3(0, 2.1, 0) - fb.x * (pw * 0.5 - 0.16) + fb.z * 0.02, fb.x, pw - 0.32, 0.16, fb, key_bg, RomanDecor.PALETTE_BLACK)
		if i % 4 == 0:
			RomanDecor.wreath(paint, centre + Vector3(0, 1.4, 0) + fb.z * 0.02, fb, 0.34, RomanDecor.LAUREL)
		else:
			RomanDecor.rect(paint, centre + Vector3(0, 1.4, 0) + fb.z * 0.02, fb, 0.5, 0.5, RomanDecor.PALETTE_BLACK)
			RomanDecor.rect(paint, centre + Vector3(0, 1.4, 0) + fb.z * 0.03, fb, 0.4, 0.4, key_bg)
	# Gates (carceres): dark arches in stone frames with bronze studs, on the x axis. With the Houdini portcullis
	# (placed in _build_dressing) only the dark opening behind its bars stays.
	var portcullis: bool = _art("portcullis") != null
	for ga: float in [0.0, PI]:
		var fb: Basis = RomanDecor.face_basis(ga)
		var base: Vector3 = ring_point(radius, ga, 0.0, n) + Vector3(-cos(ga), 0.0, -sin(ga)) * 0.05
		if portcullis:
			RomanDecor.arch(paint, base + fb.z * 0.01, fb, 2.5, 2.35, Color(0.04, 0.035, 0.03))
			continue
		RomanDecor.arch(paint, base, fb, 2.9, 2.6, Color(0.35, 0.3, 0.24))
		RomanDecor.arch(paint, base + fb.z * 0.01, fb, 2.5, 2.35, Color(0.04, 0.035, 0.03))
		for k: int in 5:
			var gx: float = (float(k) - 2.0) * 0.5
			RomanDecor.box(bronze, Transform3D(RomanDecor.face_basis(ga), base + fb.x * gx + fb.y * 1.0 + fb.z * 0.03), Vector3(0.06, 1.9, 0.04), Color(0.4, 0.28, 0.12))
		RomanDecor.text(paint, "AVE" if ga == 0.0 else "MORS", base + fb.y * 2.78 + fb.z * 0.03, fb, 0.22, Color(0.2, 0.17, 0.14))
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.mesh = st.commit()
	mi.material_override = _stone_material(Vector2(0.9, 0.5), 1.6)
	add_child(mi)
	_add_mesh("Panels", paint, _fresco_material(), false)
	_add_mesh("Bronze", bronze, _bronze_material(), false)

	# Wooden rail along the cap, with posts and a brace, in the arena side of the wall.
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var mid: float = (a0 + a1) * 0.5
		var p: Vector3 = ring_point(radius - 0.2, mid, WALL_HEIGHT + 0.08, n)
		var seg_len: float = 2.0 * (radius - 0.2) * tan(PI / float(n)) + 0.04
		RomanDecor.box(wood, Transform3D(ring_basis(mid), p), Vector3(seg_len, 0.14, 0.2), Color(0.38, 0.25, 0.14) * rng.randf_range(0.85, 1.1))
		if i % 4 == 0:
			var post_pos: Vector3 = ring_point(radius - 0.2, mid, WALL_HEIGHT - 0.4, n)
			RomanDecor.box(wood, Transform3D(ring_basis(mid), post_pos), Vector3(0.14, 0.8, 0.14), Color(0.3, 0.2, 0.12))
	_add_mesh("Rail", wood, _vertex_material(false, 0.85, true), false)


## A carved stone frame proud of the wall around a painted panel (w x h, centred 1.45 m up on the wall face at
## `face`): a lintel, a deeper sill and two jambs, so the sun draws a shadow line under the lintel and the panels
## stop reading as flat cards.
func _panel_frame(st: SurfaceTool, face: Vector3, bm: Basis, fb: Basis, w: float, h: float, c: Color) -> void:
	var y: float = 1.45
	var t: float = 0.07
	var p: Vector3 = face + fb.z * 0.045
	RomanDecor.box(st, Transform3D(bm, p + Vector3(0, y + h * 0.5 + t * 0.5, 0)), Vector3(w + t * 2.6, t * 1.2, 0.09), c * 1.06)
	RomanDecor.box(st, Transform3D(bm, p + fb.z * 0.015 + Vector3(0, y - h * 0.5 - t * 0.6, 0)), Vector3(w + t * 3.2, t * 1.3, 0.12), c * 1.02)
	for sx: float in [-1.0, 1.0]:
		RomanDecor.box(st, Transform3D(bm, p + fb.x * (sx * (w * 0.5 + t * 0.5)) + Vector3(0, y, 0)), Vector3(t, h + t * 0.4, 0.07), c * 0.97)


func _near_gate(a: float, tol: float = 0.2) -> bool:
	for ga: float in [0.0, PI, TAU]:
		if absf(a - ga) < tol:
			return true
	return false


func _add_mesh(node_name: String, st: SurfaceTool, mat: Material, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ---------------------------------------------------------------- stands and crowd

func _tier_inner(i: int) -> float:
	return radius + STAND_GAP + float(i) * TIER_DEPTH


func _tier_top(i: int) -> float:
	return WALL_HEIGHT + 0.4 + float(i) * TIER_RISE


func _stand_rim() -> float:
	return _tier_inner(TIER_COUNT)


func _attic_top() -> float:
	return _tier_top(TIER_COUNT - 1) + ATTIC_HEIGHT


func _build_stands() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED + 1
	var n: int = WALL_SIDES
	for i: int in TIER_COUNT:
		var r0: float = _tier_inner(i)
		var r1: float = _tier_inner(i + 1)
		var y0: float = WALL_HEIGHT if i == 0 else _tier_top(i - 1)
		var y1: float = _tier_top(i)
		for s: int in n:
			var a0: float = TAU * float(s) / float(n)
			var a1: float = TAU * float(s + 1) / float(n)
			var mid: float = (a0 + a1) * 0.5
			var c: Color = TRAVERTINE * rng.randf_range(0.88, 1.06) * (1.0 - 0.03 * float(i))
			c.a = 1.0
			var inward: Vector3 = Vector3(-cos(mid), 0.0, -sin(mid))
			RomanDecor.quad(st, ring_point(r0, a0, y0, n), ring_point(r0, a1, y0, n), ring_point(r0, a1, y1, n), ring_point(r0, a0, y1, n), c * 0.85, inward)
			RomanDecor.quad(st, ring_point(r0, a0, y1, n), ring_point(r0, a1, y1, n), ring_point(r1, a1, y1, n), ring_point(r1, a0, y1, n), c, Vector3.UP)
	# Attic: the inner face of the back wall, with arcade niches and pilasters, plus a flat top.
	var yt: float = _tier_top(TIER_COUNT - 1)
	var ya: float = _attic_top()
	var r: float = _stand_rim()
	for s: int in n:
		var a0: float = TAU * float(s) / float(n)
		var a1: float = TAU * float(s + 1) / float(n)
		var mid: float = (a0 + a1) * 0.5
		var c: Color = TRAVERTINE * rng.randf_range(0.82, 0.95)
		c.a = 1.0
		var inward: Vector3 = Vector3(-cos(mid), 0.0, -sin(mid))
		RomanDecor.quad(st, ring_point(r, a0, 0.0, n), ring_point(r, a1, 0.0, n), ring_point(r, a1, ya, n), ring_point(r, a0, ya, n), c, -inward)
		RomanDecor.quad(st, ring_point(r, a0, yt, n), ring_point(r, a1, yt, n), ring_point(r, a1, ya, n), ring_point(r, a0, ya, n), c * 0.9, inward)
		RomanDecor.quad(st, ring_point(r, a0, ya, n), ring_point(r, a1, ya, n), ring_point(r + 0.7, a1, ya, n), ring_point(r + 0.7, a0, ya, n), c * 1.05, Vector3.UP)
		var seg_len: float = 2.0 * r * tan(PI / float(n))
		var bm: Basis = ring_basis(mid)
		RomanDecor.box(st, Transform3D(bm, ring_point(r - 0.05, mid, ya - 0.12, n)), Vector3(seg_len + 0.02, 0.24, 0.14), c * 1.06)
		if s % 2 == 0:
			var bp := Basis(Vector3.UP, PI * 0.5 - a0)
			RomanDecor.box(st, Transform3D(bp, ring_point(r - 0.1, a0, yt + ATTIC_HEIGHT * 0.5, n)), Vector3(0.4, ATTIC_HEIGHT, 0.2), c * 1.05)
		else:
			var fb: Basis = RomanDecor.face_basis(mid)
			var base: Vector3 = ring_point(r - 0.02, mid, yt, n) + inward * 0.02
			RomanDecor.arch(paint, base, fb, 1.3, 1.7, Color(0.1, 0.085, 0.07))
	_add_mesh("Stands", st, _stone_material(Vector2(1.1, 0.55), 1.0), true)
	_add_mesh("Arcade", paint, _vertex_material(false, 1.0, true), false)


func _in_box_sector(a: float, tier: int) -> bool:
	if tier == BOX_STATUE_TIER and _art("statue_plinth") != null and GfxQuality.level > GfxQuality.LOW:
		return absf(wrapf(a - BOX_ANGLE, -PI, PI)) < BOX_STATUE_GAP
	if tier > 1:
		return false
	return absf(wrapf(a - BOX_ANGLE, -PI, PI)) < 0.24


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED + 2
	# Undyed wool, madder red, saffron, the odd purple. Rich low, plain high.
	var low: Array[Color] = [Color(0.93, 0.9, 0.82), Color(0.9, 0.86, 0.76), Color(0.93, 0.9, 0.82), Color(0.62, 0.17, 0.14), Color(0.84, 0.64, 0.18), Color(0.3, 0.1, 0.27)]
	var high: Array[Color] = [Color(0.72, 0.62, 0.46), Color(0.58, 0.46, 0.32), Color(0.62, 0.2, 0.16), Color(0.8, 0.6, 0.2), Color(0.8, 0.74, 0.62), Color(0.45, 0.4, 0.3), Color(0.5, 0.36, 0.22)]
	crowd = Crowd.new()
	crowd.sectors = GfxQuality.pick_i(GfxQuality.CROWD_SECTORS)
	crowd.name = "Crowd"
	add_child(crowd)
	for t: int in TIER_COUNT:
		var rr: float = _tier_inner(t) + TIER_DEPTH * 0.5
		var spacing: float = CROWD_SPACING[t] * GfxQuality.pick_f(GfxQuality.CROWD_SPACING_MULT)
		if t >= CROWD_BACK_TIER:
			spacing *= GfxQuality.pick_f(GfxQuality.CROWD_BACK_SPACING)
		var count: int = int(TAU * rr / spacing)
		var lod: int = GfxQuality.tier_lod(t)
		var fill: float = 0.95 - 0.05 * float(t)
		var palette: Array[Color] = low if t < 2 else high
		var seated_share: float = 0.7 if t < 2 else 0.4
		for k: int in count:
			if rng.randf() > fill:
				continue
			var a: float = TAU * (float(k) + rng.randf_range(-0.2, 0.2)) / float(count)
			if _in_box_sector(a, t):
				continue
			var h: float = rng.randf_range(0.94, 1.08)
			var pos := Vector3(rr * cos(a), _tier_top(t), rr * sin(a))
			var facing: Basis = ring_basis(a).rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
			var tc: Color = palette[rng.randi() % palette.size()] * rng.randf_range(0.88, 1.08)
			tc.a = 1.0
			var seated: bool = rng.randf() < seated_share
			var variants: PackedStringArray = CrowdMood.pick_variants(seated, rng.randf() < 0.35, rng.randf())
			if t >= GfxQuality.pick_i(GfxQuality.CROWD_CHEER_TIER):
				variants[1] = ""
			crowd.add_spectator(Transform3D(facing.scaled_local(Vector3(1.0, h, 1.0)), pos), variants, tc, rng.randi() % CrowdMood.SEED_COUNT, lod)
	# The emperor and his consort in the box, in imperial purple, on the gilded seats.
	var bb: Basis = ring_basis(BOX_ANGLE)
	var floor_y: float = _tier_top(1) + 0.02
	for sx: float in [-0.5, 0.5]:
		var p: Vector3 = Vector3((radius + 1.7) * cos(BOX_ANGLE), floor_y, (radius + 1.7) * sin(BOX_ANGLE)) + bb.x * sx
		crowd.add_spectator(Transform3D(bb, p), PackedStringArray([CrowdMood.NOBLE, ""]), RomanDecor.PURPLE, 7 if sx > 0.0 else 12, -1)
	crowd.build()


## The stands' excitement, 0..1 (feed SfxDirector.crowd_excitement() every frame).
func set_crowd_excitement(x: float) -> void:
	if crowd != null:
		crowd.set_excitement(x)


## A crowd reaction ("gasp", "cheer", "roar", "finisher", "boo") makes the stands jump for a moment.
func crowd_react(kind: String) -> void:
	if crowd != null:
		crowd.react(kind)


# ---------------------------------------------------------------- banners, torches, imperial box

func _build_props() -> void:
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bronze := SurfaceTool.new()
	bronze.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Banners on the wall panels, away from the spawn axis and the gates (Houdini cloth in _build_dressing if it exists).
	for k: int in 0 if _art("banner") != null else 4:
		var a: float = [deg_to_rad(63.75), deg_to_rad(123.75), deg_to_rad(243.75), deg_to_rad(303.75)][k]
		_banner(cloth, bronze, ring_point(radius - 0.12, a, WALL_HEIGHT - 0.55, WALL_SIDES), a, 1.0, 1.7, k % 2 == 1)
	# Standards on masts along the attic top.
	var rim: float = _stand_rim() - 0.5
	for k: int in 12:
		var a: float = TAU * (float(k) + 0.5) / 12.0
		if absf(wrapf(a - BOX_ANGLE, -PI, PI)) < 0.3:
			continue
		var base := Vector3(rim * cos(a), _attic_top(), rim * sin(a))
		RomanDecor.box(wood, Transform3D(ring_basis(a), base + Vector3(0, 2.0, 0)), Vector3(0.12, 4.0, 0.12), Color(0.3, 0.2, 0.12))
		if _art("banner") == null:
			_banner(cloth, bronze, base + Vector3(0, 3.9, 0), a, 1.0, 2.0, k % 2 == 0, false)
	# Torches on the wall cap, bronze bowls.
	for k: int in 6:
		var a: float = deg_to_rad(30.0 + float(k) * 60.0)
		var p: Vector3 = ring_point(radius + 0.3, a, WALL_HEIGHT, WALL_SIDES)
		if _art("brazier") == null:
			RomanDecor.box(wood, Transform3D(ring_basis(a), p + Vector3(0, 0.7, 0)), Vector3(0.12, 1.4, 0.12), Color(0.25, 0.17, 0.1))
			RomanDecor.box(bronze, Transform3D(ring_basis(a), p + Vector3(0, 1.45, 0)), Vector3(0.3, 0.16, 0.3), Color(0.55, 0.38, 0.16))
			RomanDecor.box(bronze, Transform3D(ring_basis(a), p + Vector3(0, 1.2, 0)), Vector3(0.16, 0.06, 0.16), Color(0.5, 0.35, 0.15))
		var flame := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.15
		cone.height = 0.55
		cone.radial_segments = 6
		cone.rings = 1
		flame.mesh = cone
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.62, 0.18)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.5, 0.1)
		fm.emission_energy_multiplier = 2.0
		flame.material_override = fm
		flame.position = p + Vector3(0, _flame_y, 0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		_flames.append(flame)
	_build_imperial_box(cloth, wood, bronze)
	_add_mesh("Banners", cloth, _vertex_material(true, 0.9, true), false)
	_add_mesh("Poles", wood, _vertex_material(false, 0.85, true), false)
	_add_mesh("BronzeProps", bronze, _bronze_material(), false)


## A hanging vexillum facing the centre: SPQR on red, or an aquila on dark red, gold fringe, bronze rod.
func _banner(cloth: SurfaceTool, bronze: SurfaceTool, top: Vector3, a: float, w: float, h: float, eagle: bool, hang: bool = true) -> void:
	var fb: Basis = RomanDecor.face_basis(a)
	var inward: Vector3 = fb.z
	var front: Vector3 = top + inward * 0.05
	var field: Color = Color(0.5, 0.1, 0.09) if not eagle else Color(0.3, 0.07, 0.08)
	var centre: Vector3 = front - fb.y * (h * 0.5)
	RomanDecor.rect(cloth, centre, fb, w, h, field)
	RomanDecor.rect(cloth, centre + inward * 0.01, fb, w - 0.1, h - 0.1, field * 1.12)
	RomanDecor.rect(cloth, centre + inward * 0.02, fb, w - 0.16, 0.05, RomanDecor.GOLD)
	RomanDecor.rect(cloth, front - fb.y * (h - 0.08) + inward * 0.02, fb, w - 0.16, 0.05, RomanDecor.GOLD)
	if eagle:
		RomanDecor.aquila(cloth, centre + fb.y * (h * 0.12) + inward * 0.025, fb, w * 0.7, RomanDecor.GOLD)
		RomanDecor.text(cloth, "SPQR", centre - fb.y * (h * 0.36) + inward * 0.025, fb, w * 0.16, RomanDecor.GOLD)
	else:
		RomanDecor.text(cloth, "SPQR", centre + fb.y * (h * 0.22) + inward * 0.025, fb, w * 0.2, RomanDecor.GOLD)
		RomanDecor.wreath(cloth, centre - fb.y * (h * 0.14) + inward * 0.025, fb, w * 0.28, RomanDecor.LAUREL * 1.3)
	var fringe: int = int(w / 0.1)
	for k: int in fringe:
		var fx: float = (float(k) + 0.5) / float(fringe) * (w - 0.1) - (w - 0.1) * 0.5
		RomanDecor.rect(cloth, front - fb.y * (h + 0.05) + fb.x * fx + inward * 0.01, fb, 0.05, 0.1, RomanDecor.GOLD)
	if hang:
		RomanDecor.box(bronze, Transform3D(fb, top + inward * 0.06), Vector3(w + 0.2, 0.06, 0.06), Color(0.55, 0.38, 0.16))
	else:
		RomanDecor.box(bronze, Transform3D(fb, top + inward * 0.02 + Vector3(0, 0.1, 0)), Vector3(0.2, 0.2, 0.2), Color(0.7, 0.5, 0.18))


## Imperial box: a raised marble gallery at the -Z side with columns, a purple canopy, gilded seats and a wreath.
func _build_imperial_box(cloth: SurfaceTool, wood: SurfaceTool, bronze: SurfaceTool) -> void:
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: float = BOX_ANGLE
	var bb: Basis = ring_basis(a)
	var fb: Basis = RomanDecor.face_basis(a)
	var radial := Vector3(cos(a), 0.0, sin(a))
	var r0: float = radius + STAND_GAP - 0.05
	var floor_y: float = _tier_top(1) + 0.02
	var depth: float = 2.7
	var half_w: float = 2.9
	var roof_y: float = floor_y + 2.9
	var mar: Color = RomanDecor.MARBLE
	var front: Vector3 = radial * r0
	var centre_floor: Vector3 = radial * (r0 + depth * 0.5)
	# Platform slab and its front face.
	RomanDecor.box(paint, Transform3D(bb, centre_floor + Vector3(0, floor_y - 0.2, 0)), Vector3(half_w * 2.0, 0.4, depth), mar * 0.95)
	RomanDecor.box(paint, Transform3D(bb, front + radial * 0.05 + Vector3(0, (floor_y + WALL_HEIGHT) * 0.5 - 0.0, 0)), Vector3(half_w * 2.0, floor_y - WALL_HEIGHT, 0.12), mar * 0.9)
	RomanDecor.rect(paint, front - radial * 0.02 + Vector3(0, (floor_y + _tier_top(0)) * 0.5, 0), fb, half_w * 1.8, floor_y - _tier_top(0) - 0.1, RomanDecor.PALETTE_RED)
	RomanDecor.meander(paint, front - radial * 0.03 + Vector3(0, floor_y - 0.3, 0) - fb.x * (half_w * 0.9), fb.x, half_w * 1.8, 0.16, fb, RomanDecor.PALETTE_OCHRE, RomanDecor.PALETTE_BLACK)
	# Columns, entablature, canopy.
	for cx: float in [-2.6, -0.9, 0.9, 2.6]:
		var cp: Vector3 = front + radial * 0.4 + bb.x * cx
		RomanDecor.box(paint, Transform3D(bb, cp + Vector3(0, floor_y + 1.35, 0)), Vector3(0.26, 2.7, 0.26), mar)
		RomanDecor.box(paint, Transform3D(bb, cp + Vector3(0, floor_y + 0.08, 0)), Vector3(0.4, 0.16, 0.4), mar * 0.9)
		RomanDecor.box(bronze, Transform3D(bb, cp + Vector3(0, floor_y + 2.75, 0)), Vector3(0.42, 0.18, 0.42), Color(0.7, 0.5, 0.18))
	RomanDecor.box(paint, Transform3D(bb, front + radial * (depth * 0.5 + 0.1) + Vector3(0, roof_y, 0)), Vector3(half_w * 2.0 + 0.5, 0.35, depth + 0.4), mar)
	RomanDecor.box(cloth, Transform3D(bb, front + radial * (depth * 0.5 + 0.1) + Vector3(0, roof_y + 0.22, 0)), Vector3(half_w * 2.0 + 0.3, 0.12, depth + 0.2), RomanDecor.PURPLE)
	RomanDecor.meander(paint, front - radial * 0.03 + Vector3(0, roof_y - 0.17, 0) - fb.x * (half_w + 0.2), fb.x, half_w * 2.0 + 0.4, 0.2, fb, RomanDecor.PALETTE_OCHRE, RomanDecor.PALETTE_BLACK)
	# Purple swags between the columns, gold-fringed.
	for sx: float in [-1.75, 0.0, 1.75]:
		var sp: Vector3 = front + radial * 0.3 + bb.x * sx + Vector3(0, roof_y - 0.7, 0)
		RomanDecor.rect(cloth, sp - radial * 0.02, fb, 1.55, 0.6, RomanDecor.PURPLE)
		RomanDecor.rect(cloth, sp - radial * 0.025 - Vector3(0, 0.28, 0), fb, 1.55, 0.06, RomanDecor.GOLD)
	RomanDecor.wreath(cloth, front - radial * 0.06 + Vector3(0, roof_y - 0.75, 0), fb, 0.3, RomanDecor.LAUREL * 1.3)
	# Back drape and gilded seats.
	RomanDecor.rect(cloth, front + radial * (depth - 0.1) + Vector3(0, floor_y + 1.4, 0), fb, half_w * 2.0 - 0.4, 2.8, RomanDecor.PURPLE * 0.9)
	RomanDecor.text(cloth, "AVE CAESAR", front + radial * (depth - 0.12) + Vector3(0, floor_y + 1.3, 0), fb, 0.3, RomanDecor.GOLD)
	for sx: float in [-0.5, 0.5]:
		var sp: Vector3 = front + radial * 1.5 + bb.x * sx
		RomanDecor.box(bronze, Transform3D(bb, sp + Vector3(0, floor_y + 0.25, 0)), Vector3(0.6, 0.5, 0.55), Color(0.72, 0.52, 0.2))
		RomanDecor.box(bronze, Transform3D(bb, sp + radial * 0.25 + Vector3(0, floor_y + 0.8, 0)), Vector3(0.6, 0.6, 0.08), Color(0.72, 0.52, 0.2))
	RomanDecor.box(wood, Transform3D(bb, front + radial * 0.4 + Vector3(0, floor_y + 0.05, 0)), Vector3(half_w * 2.0 - 0.2, 0.05, 0.1), Color(0.3, 0.2, 0.12))
	_add_mesh("ImperialBox", paint, _vertex_material(false, 0.8, true), false)


func _build_velarium() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_out: float = _stand_rim() - 0.5
	var r_in: float = r_out - 6.2
	var y_a: float = _attic_top()
	var y_out: float = y_a + 3.4
	var y_in: float = y_a + 0.3
	var steps: int = 64
	# Over the stands whose shadows fall outside the arena (sun comes from the opposite side).
	var a_start: float = deg_to_rad(-105.0)
	var a_span: float = deg_to_rad(250.0)
	var linen := Color(0.9, 0.84, 0.7)
	var madder := Color(0.66, 0.2, 0.14)
	var rows: int = 3
	for s: int in steps:
		var a0: float = a_start + a_span * float(s) / float(steps)
		var a1: float = a_start + a_span * float(s + 1) / float(steps)
		var c: Color = linen if s % 2 == 0 else madder
		var edge_fall: float = 0.0
		for rw: int in rows:
			var t0: float = float(rw) / float(rows)
			var t1: float = float(rw + 1) / float(rows)
			var sag0: float = -0.5 * sin(PI * t0)
			var sag1: float = -0.5 * sin(PI * t1)
			var p00: Vector3 = ring_point(lerpf(r_in, r_out, t0), a0, lerpf(y_in, y_out, t0) + sag0, 64)
			var p01: Vector3 = ring_point(lerpf(r_in, r_out, t0), a1, lerpf(y_in, y_out, t0) + sag0, 64)
			var p10: Vector3 = ring_point(lerpf(r_in, r_out, t1), a0, lerpf(y_in, y_out, t1) + sag1, 64)
			var p11: Vector3 = ring_point(lerpf(r_in, r_out, t1), a1, lerpf(y_in, y_out, t1) + sag1, 64)
			RomanDecor.quad(st, p00, p01, p11, p10, c, Vector3.DOWN)
			RomanDecor.quad(st, p00, p10, p11, p01, c * 0.85, Vector3.UP)
		# Scalloped valance on the inner edge.
		var q0: Vector3 = ring_point(r_in, a0, y_in, 64)
		var q1: Vector3 = ring_point(r_in, a1, y_in, 64)
		var drop: float = 0.42
		var inward: Vector3 = Vector3(-cos((a0 + a1) * 0.5), 0.0, -sin((a0 + a1) * 0.5))
		RomanDecor.quad(st, q0, q1, q1 - Vector3(0, drop * 0.55, 0), q0 - Vector3(0, drop * 0.55, 0), c, inward)
		RomanDecor.tri(st, q0 - Vector3(0, drop * 0.55, 0), q1 - Vector3(0, drop * 0.55, 0), (q0 + q1) * 0.5 - Vector3(0, drop, 0), c, inward)
		edge_fall += drop
	# Masts at the attic top with guy ropes to the sail rim.
	var mast_count: int = 21
	for k: int in mast_count:
		var a: float = a_start + a_span * float(k) / float(mast_count - 1)
		var base: Vector3 = ring_point(r_out + 0.2, a, y_a, 64)
		RomanDecor.box(wood, Transform3D(ring_basis(a), base + Vector3(0, 1.8, 0)), Vector3(0.2, 3.6, 0.2), Color(0.34, 0.23, 0.13))
		var tip: Vector3 = ring_point(r_out, a, y_out - 0.2, 64)
		var low: Vector3 = ring_point(r_in, a, y_in, 64)
		var dir: Vector3 = (low - tip)
		var rope_basis := Basis.looking_at(dir.normalized(), Vector3.UP)
		RomanDecor.box(wood, Transform3D(rope_basis, (tip + low) * 0.5), Vector3(0.05, 0.05, dir.length()), Color(0.4, 0.33, 0.22))
	_add_mesh("Velarium", st, _vertex_material(true, 0.95, true), GfxQuality.level >= GfxQuality.HIGH)  # its shadow only falls on the stands
	_add_mesh("Masts", wood, _vertex_material(false, 0.9, true), false)


# ---------------------------------------------------------------- Houdini dressing

## The Houdini mesh `id`, or null when it is missing or skipped at this quality (the code stand-in is built instead).
## On low the cloth standards and braziers (876 and 1116 triangles each) fall back to the merged code meshes, which
## cost no extra draw call and keep the low MultiMesh triangle budget.
func _art(id: String) -> Mesh:
	if GfxQuality.level <= GfxQuality.LOW and id in LOW_CODE_PROPS:
		return null
	return _dressing.mesh(id)


## Portcullis gates with flanking columns and barriers, braziers on the torch posts, cloth standards on the attic masts
## and banners on the wall, a weapon rack against the wall behind each spawn, column stumps, statues beside the gates
## and behind the imperial box, and the laurel trophy under the box. One MultiMesh per asset; only the big stone
## pieces cast shadows. Missing assets keep the code stand-ins; the floor pieces' colliders exist either way.
func _build_dressing() -> void:
	var low: bool = GfxQuality.level <= GfxQuality.LOW
	# Floor pieces (gates, gate columns, racks, barriers, stumps) come from DecorLayout, which also gives their colliders.
	var statues: Array[Transform3D] = []
	for ga: float in DecorLayout.GATE_ANGLES:
		for sx: float in [-1.0, 1.0]:
			var sa: float = ga + sx * STATUE_ANGLE_OFFSET
			statues.append(Transform3D(RomanDecor.face_basis(sa).scaled(Vector3.ONE * STATUE_SCALE), ring_point(radius + 0.3, sa, WALL_HEIGHT, WALL_SIDES)))
	ArenaDressing.add_instances(self, "Portcullis", _art("portcullis"), DecorLayout.transforms(radius, "portcullis"), true)
	ArenaDressing.add_instances(self, "GateColumns", _art("column"), DecorLayout.transforms(radius, "column"), not low)
	ArenaDressing.add_instances(self, "Barriers", _art("barrier"), DecorLayout.transforms(radius, "barrier"), false)
	ArenaDressing.add_instances(self, "ColumnStumps", _art("column_stump"), DecorLayout.transforms(radius, "column_stump"), not low)
	var braziers: Array[Transform3D] = []
	for k: int in 6:
		var a: float = deg_to_rad(30.0 + float(k) * 60.0)
		braziers.append(Transform3D(RomanDecor.face_basis(a), ring_point(radius + 0.3, a, WALL_HEIGHT, WALL_SIDES)))
	ArenaDressing.add_instances(self, "Braziers", _art("brazier"), braziers, false)
	var standards: Array[Transform3D] = []
	var rim: float = _stand_rim() - 0.5
	for k: int in 12:
		var a: float = TAU * (float(k) + 0.5) / 12.0
		if absf(wrapf(a - BOX_ANGLE, -PI, PI)) < 0.3:
			continue
		var fb: Basis = RomanDecor.face_basis(a)
		standards.append(Transform3D(fb, Vector3(rim * cos(a), _attic_top() + 1.0, rim * sin(a)) + fb.z * 0.1))
	ArenaDressing.add_instances(self, "Standards", _art("banner"), standards, false)
	var wall_banners: Array[Transform3D] = []
	for a: float in WALL_BANNER_ANGLES:
		var fb: Basis = RomanDecor.face_basis(a)
		wall_banners.append(Transform3D(fb.scaled(Vector3.ONE * WALL_BANNER_SCALE), ring_point(radius, a, 0.0, WALL_SIDES) + fb.z * WALL_BANNER_OUT))
	ArenaDressing.add_instances(self, "WallBanners", _art("banner"), wall_banners, false)
	ArenaDressing.add_instances(self, "WeaponRacks", _art("weapon_rack"), DecorLayout.transforms(radius, "weapon_rack"), false)
	if low:
		return  # phones: the statues and the trophy are a few pixels up on the wall cap; save their draw calls
	# The big statue stands on the stands behind the imperial box (its tier's seats there stay empty).
	var radial := Vector3(cos(BOX_ANGLE), 0.0, sin(BOX_ANGLE))
	var box_r: float = _tier_inner(BOX_STATUE_TIER) + TIER_DEPTH * 0.5
	statues.append(Transform3D(RomanDecor.face_basis(BOX_ANGLE).scaled(Vector3.ONE * BOX_STATUE_SCALE), radial * box_r + Vector3(0, _tier_top(BOX_STATUE_TIER), 0)))
	ArenaDressing.add_instances(self, "Statues", _art("statue_plinth"), statues, false)
	var tb: Basis = RomanDecor.face_basis(BOX_ANGLE)
	var trophy: Array[Transform3D] = [Transform3D(tb, ring_point(radius + 0.3, BOX_ANGLE, WALL_HEIGHT, WALL_SIDES))]
	ArenaDressing.add_instances(self, "LaurelTrophy", _art("laurel_trophy"), trophy, false)


# ---------------------------------------------------------------- light, sky, haze

func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var dir_to_sun := Vector3(cos(SUN_ELEVATION) * cos(SUN_AZIMUTH), sin(SUN_ELEVATION), cos(SUN_ELEVATION) * sin(SUN_AZIMUTH))
	sun.transform = Transform3D(Basis.looking_at(-dir_to_sun, Vector3.UP), Vector3.ZERO)
	# Warm but not orange: an orange sun times orange sand clipped the lit sand to (254, 192, 115) under Filmic.
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_blur = GfxQuality.pick_f(GfxQuality.SHADOW_BLUR)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if GfxQuality.pick_i(GfxQuality.SHADOW_SPLITS) >= 2 \
			else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = GfxQuality.pick_f(GfxQuality.SHADOW_DISTANCE)
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.5
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.33, 0.64)
	sky_mat.sky_horizon_color = Color(0.8, 0.72, 0.6)
	sky_mat.ground_horizon_color = Color(0.8, 0.68, 0.52)
	sky_mat.ground_bottom_color = Color(0.45, 0.36, 0.26)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Warm bounce light from the sand: a blue sky ambient turned every shadow olive-green. Kept low so the shade under
	# the wall reads deep (lit sand / shaded sand about 2:1 instead of 1.3:1).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.72, 0.64)
	env.ambient_light_energy = AMBIENT_ENERGY
	# ACES with a high white point: contrast and a soft shoulder, so sunlit sand, linen and marble roll off instead of
	# clipping. Tonemapping runs in the scene shader on Compatibility: no extra pass (no glow or adjustments, which
	# add a full-screen copy on phones).
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = EXPOSURE
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.72, 0.6)
	env.fog_density = 0.005
	env.fog_sun_scatter = 0.2
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------- materials

func _stone_material(block: Vector2, grime_height: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = STONE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("block", block)
	m.set_shader_parameter("grime_height", grime_height)
	var torches := PackedVector3Array()
	for i: int in 6:
		torches.append(_torch_positions[i] if i < _torch_positions.size() else Vector3(0, -100, 0))
	m.set_shader_parameter("torches", torches)
	return m


## Painted plaster on the podium wall: the vertex colours weathered in world space (art slot: swap for a fresco
## texture set). Same torch soot as the stone.
func _fresco_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = FRESCO_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var torches := PackedVector3Array()
	for i: int in 6:
		torches.append(_torch_positions[i] if i < _torch_positions.size() else Vector3(0, -100, 0))
	m.set_shader_parameter("torches", torches)
	m.set_shader_parameter("plaster", Vector3(TRAVERTINE.r, TRAVERTINE.g, TRAVERTINE.b) * 0.92)
	return m


func _vertex_material(double_sided: bool, rough: float, srgb: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = srgb
	m.roughness = rough
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _bronze_material() -> StandardMaterial3D:
	var m := _vertex_material(false, 0.5, true)
	m.metallic = 0.45
	return m


const STONE_SHADER: String = """
shader_type spatial;
uniform vec2 block = vec2(0.9, 0.5);
uniform float grime_height = 1.5;
uniform vec3 torches[6];
varying vec3 wpos;
varying vec3 wnrm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float u = atan(wpos.z, wpos.x) * length(wpos.xz);
	float vertical = 1.0 - smoothstep(0.4, 0.7, abs(wnrm.y));
	float row = floor(wpos.y / block.y);
	float cu = u / block.x + hash21(vec2(row, 3.0)) * 5.0;
	float cell = floor(cu);
	float shade = 0.9 + 0.2 * hash21(vec2(cell, row));
	vec2 fr = vec2(fract(cu), fract(wpos.y / block.y));
	float edge = min(min(fr.x, 1.0 - fr.x) * block.x, min(fr.y, 1.0 - fr.y) * block.y);
	float mortar = 1.0 - smoothstep(0.012, 0.035, edge);
	col *= mix(1.0, shade, vertical);
	col = mix(col, col * 0.72, mortar * vertical);
	float stain = vnoise(vec2(u * 0.5, wpos.y * 1.5)) * 0.5 + vnoise(vec2(u * 3.0, wpos.y * 6.0)) * 0.25;
	col *= 0.84 + stain * 0.4;
	float pits = step(0.82, vnoise(vec2(u * 11.0, wpos.y * 11.0 + wpos.x)));
	col *= 1.0 - 0.18 * pits;
	col *= mix(0.6, 1.0, smoothstep(0.0, grime_height, wpos.y));
	float soot = 0.0;
	for (int i = 0; i < 6; i++) {
		vec3 d = wpos - torches[i];
		float dh = length(d.xz);
		float above = smoothstep(-0.3, 0.6, d.y) * (1.0 - smoothstep(0.8, 2.8, d.y));
		soot = max(soot, (1.0 - smoothstep(0.2, 1.3, dh)) * above);
	}
	col *= 1.0 - 0.55 * soot;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""


## Fresco weathering: sun-faded pigment (lighter and chalkier in blotches), flaked paint showing the plaster below
## (more toward the bottom, where feet and sand hit), hairline cracks, a grime band at the foot, torch soot. Every
## term is a multiplier or a mix toward plaster or soot, never a hue shift. Vertex-colour input, no textures.
const FRESCO_SHADER: String = """
shader_type spatial;
render_mode cull_back;
uniform vec3 torches[6];
uniform vec3 plaster : source_color = vec3(0.77, 0.68, 0.52);
varying vec3 wpos;

float fhash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fhash(i), fhash(i + vec2(1.0, 0.0)), f.x), mix(fhash(i + vec2(0.0, 1.0)), fhash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec2 p = vec2(atan(wpos.z, wpos.x) * length(wpos.xz), wpos.y);
	float big = fnoise(p * vec2(1.3, 1.8));
	float mid = fnoise(p * 5.0 + 17.0);
	float fine = fnoise(p * 23.0 + 3.0);
	// Faded pigment: blotches drift toward a chalky, lighter version of the same colour.
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	vec3 chalk = mix(vec3(lum), col, 0.55) * 1.18 + vec3(0.05, 0.045, 0.035);
	col = mix(col, chalk, smoothstep(0.45, 0.9, big * 0.7 + mid * 0.3) * 0.55);
	col *= 0.9 + 0.16 * mid + 0.08 * fine;
	// Flaking: paint gone where the noise crosses a threshold that rises toward the foot of the wall.
	float flake_n = mid * 0.6 + fine * 0.4;
	float flake_t = 0.8 - 0.1 * (1.0 - smoothstep(0.3, 1.6, wpos.y));
	float flake = smoothstep(flake_t, flake_t + 0.04, flake_n) * smoothstep(0.06, 0.14, lum);
	col = mix(col, plaster * (0.85 + 0.2 * fine), flake);
	// Hairline cracks.
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(fnoise(p * vec2(3.0, 2.2) + 41.0) - 0.5));
	col *= 1.0 - 0.3 * crack * smoothstep(0.4, 0.7, big);
	// Grime at the foot, soot above torches.
	col *= mix(0.62, 1.0, smoothstep(0.2, 1.5, wpos.y));
	float soot = 0.0;
	for (int i = 0; i < 6; i++) {
		vec3 d = wpos - torches[i];
		soot = max(soot, (1.0 - smoothstep(0.2, 1.3, length(d.xz))) * smoothstep(-0.3, 0.6, d.y) * (1.0 - smoothstep(0.8, 2.8, d.y)));
	}
	col *= 1.0 - 0.55 * soot;
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
"""
