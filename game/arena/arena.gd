class_name Arena
extends Node3D
## The sand arena, built entirely in code: floor collider, stone wall with a wooden rail, stepped stands with a
## blocky crowd, banners, torches, a velarium, one shadowed sun, sky and haze. Collision is layer 1 only.
## The floor's visual is a SandSurface (game/sand/) when that script exists, else a flat placeholder disc.

const SAND_SCRIPT: String = "res://game/sand/sand_surface.gd"
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

var radius: float = 11.0
var sand: Node3D
var sun: DirectionalLight3D
var _flames: Array[MeshInstance3D] = []
var _flame_time: float = 0.0


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
	_build_floor()
	_build_wall_colliders()
	_build_wall_visual()
	_build_stands()
	_build_crowd()
	_build_props()
	_build_velarium()
	_build_environment()


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

	if ResourceLoader.exists(SAND_SCRIPT):
		var script: GDScript = load(SAND_SCRIPT)
		sand = script.new() as Node3D
		sand.name = "Sand"
		add_child(sand)
		sand.call("setup", radius)
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
	add_child(body)


func _build_wall_visual() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED
	var plaster := Color(0.78, 0.7, 0.55)
	for i: int in WALL_SIDES:
		var a0: float = TAU * float(i) / float(WALL_SIDES)
		var a1: float = TAU * float(i + 1) / float(WALL_SIDES)
		var tint: float = rng.randf_range(0.9, 1.05)
		var c: Color = plaster * tint
		c.a = 1.0
		var in0: Vector3 = ring_point(radius, a0, 0.0, WALL_SIDES)
		var in1: Vector3 = ring_point(radius, a1, 0.0, WALL_SIDES)
		var mid: float = (a0 + a1) * 0.5
		var inward: Vector3 = Vector3(-cos(mid), 0.0, -sin(mid))
		_quad(st, in0, in1, in1 + Vector3(0, WALL_HEIGHT, 0), in0 + Vector3(0, WALL_HEIGHT, 0), c, inward)
		# Cap from the inner face to the stands.
		var out0: Vector3 = ring_point(radius + STAND_GAP, a0, WALL_HEIGHT, WALL_SIDES)
		var out1: Vector3 = ring_point(radius + STAND_GAP, a1, WALL_HEIGHT, WALL_SIDES)
		_quad(st, in0 + Vector3(0, WALL_HEIGHT, 0), in1 + Vector3(0, WALL_HEIGHT, 0), out1, out0, c * 0.9, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.mesh = st.commit()
	mi.material_override = _stone_material(Vector2(0.55, 1.25), 1.6)
	add_child(mi)

	# Wooden rail: a coping beam on the cap and posts down the face. Lifted off the plaster, not coplanar.
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in WALL_SIDES:
		var a0: float = TAU * float(i) / float(WALL_SIDES)
		var a1: float = TAU * float(i + 1) / float(WALL_SIDES)
		var mid: float = (a0 + a1) * 0.5
		var p: Vector3 = ring_point(radius - 0.08, mid, WALL_HEIGHT + 0.08, WALL_SIDES)
		var seg_len: float = 2.0 * (radius - 0.08) * tan(PI / float(WALL_SIDES)) + 0.04
		var beam := Transform3D(ring_basis(mid), p)
		_box(wood, beam, Vector3(seg_len, 0.16, 0.3), Color(0.38, 0.25, 0.14) * rng.randf_range(0.85, 1.1))
		if i % 3 == 0:
			var post_pos: Vector3 = ring_point(radius - 0.07, mid, WALL_HEIGHT * 0.5, WALL_SIDES)
			_box(wood, Transform3D(ring_basis(mid), post_pos), Vector3(0.2, WALL_HEIGHT, 0.14), Color(0.3, 0.2, 0.12))
		if i % 3 == 1:
			var brace: Vector3 = ring_point(radius - 0.07, mid, 1.1, WALL_SIDES)
			_box(wood, Transform3D(ring_basis(mid), brace), Vector3(seg_len + 0.1, 0.12, 0.1), Color(0.34, 0.22, 0.13))
	var wi := MeshInstance3D.new()
	wi.name = "Rail"
	wi.mesh = wood.commit()
	wi.material_override = _vertex_material(false, 0.85)
	add_child(wi)


# ---------------------------------------------------------------- stands and crowd

func _tier_inner(i: int) -> float:
	return radius + STAND_GAP + float(i) * TIER_DEPTH


func _tier_top(i: int) -> float:
	return WALL_HEIGHT + 0.4 + float(i) * TIER_RISE


func _stand_rim() -> float:
	return _tier_inner(TIER_COUNT)


func _build_stands() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED + 1
	var base := Color(0.66, 0.6, 0.5)
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
			var c: Color = base * rng.randf_range(0.85, 1.08) * (1.0 - 0.04 * float(i))
			c.a = 1.0
			var inward: Vector3 = Vector3(-cos(mid), 0.0, -sin(mid))
			_quad(st, ring_point(r0, a0, y0, n), ring_point(r0, a1, y0, n), ring_point(r0, a1, y1, n), ring_point(r0, a0, y1, n), c * 0.85, inward)
			_quad(st, ring_point(r0, a0, y1, n), ring_point(r0, a1, y1, n), ring_point(r1, a1, y1, n), ring_point(r1, a0, y1, n), c, Vector3.UP)
	# Back wall of the stands.
	var yt: float = _tier_top(TIER_COUNT - 1)
	for s: int in n:
		var a0: float = TAU * float(s) / float(n)
		var a1: float = TAU * float(s + 1) / float(n)
		var mid: float = (a0 + a1) * 0.5
		var c: Color = base * rng.randf_range(0.8, 0.95)
		c.a = 1.0
		var r: float = _stand_rim()
		_quad(st, ring_point(r, a0, 0.0, n), ring_point(r, a1, 0.0, n), ring_point(r, a1, yt, n), ring_point(r, a0, yt, n), c, Vector3(cos(mid), 0.0, sin(mid)))
	var mi := MeshInstance3D.new()
	mi.name = "Stands"
	mi.mesh = st.commit()
	mi.material_override = _stone_material(Vector2(0.9, 1.4), 1.0)
	add_child(mi)


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CROWD_SEED + 2
	var tunics: Array[Color] = [
		Color(0.72, 0.6, 0.42), Color(0.62, 0.28, 0.2), Color(0.8, 0.74, 0.6), Color(0.45, 0.45, 0.28),
		Color(0.34, 0.38, 0.46), Color(0.5, 0.36, 0.24), Color(0.7, 0.5, 0.2), Color(0.55, 0.2, 0.25),
	]
	var skins: Array[Color] = [
		Color(0.8, 0.6, 0.45), Color(0.66, 0.46, 0.33), Color(0.52, 0.36, 0.26), Color(0.86, 0.68, 0.54),
	]
	var bodies: Array[Transform3D] = []
	var body_cols: Array[Color] = []
	var heads: Array[Transform3D] = []
	var head_cols: Array[Color] = []
	var arms: Array[Transform3D] = []
	var arm_cols: Array[Color] = []
	for t: int in TIER_COUNT:
		var rr: float = _tier_inner(t) + TIER_DEPTH * 0.55
		var count: int = int(TAU * rr / 0.62)
		var fill: float = 0.95 - 0.05 * float(t)
		for k: int in count:
			if rng.randf() > fill:
				continue
			var a: float = TAU * (float(k) + rng.randf_range(-0.2, 0.2)) / float(count)
			var h: float = rng.randf_range(0.9, 1.12)
			var pos := Vector3(rr * cos(a), _tier_top(t), rr * sin(a))
			var facing: Basis = ring_basis(a).rotated(Vector3.UP, PI + rng.randf_range(-0.35, 0.35))
			var tc: Color = tunics[rng.randi() % tunics.size()] * rng.randf_range(0.85, 1.1)
			tc.a = 1.0
			bodies.append(Transform3D(facing.scaled_local(Vector3(1, h, 1)), pos + Vector3(0, 0.38 * h, 0)))
			body_cols.append(tc)
			heads.append(Transform3D(facing, pos + Vector3(0, 0.76 * h + 0.14, 0)))
			head_cols.append(skins[rng.randi() % skins.size()] * rng.randf_range(0.9, 1.05))
			if rng.randf() < 0.18:
				var side: float = 1.0 if rng.randf() < 0.5 else -1.0
				var lean: Basis = facing * Basis(Vector3(0, 0, 1), side * rng.randf_range(0.2, 0.7))
				arms.append(Transform3D(lean, pos + facing * Vector3(side * 0.3, 0.68 * h + 0.2, 0.0)))
				arm_cols.append(skins[rng.randi() % skins.size()])
	_add_multimesh("CrowdBodies", Vector3(0.5, 0.76, 0.34), bodies, body_cols)
	_add_multimesh("CrowdHeads", Vector3(0.24, 0.26, 0.24), heads, head_cols)
	_add_multimesh("CrowdArms", Vector3(0.11, 0.5, 0.11), arms, arm_cols)


func _add_multimesh(node_name: String, size: Vector3, xforms: Array[Transform3D], cols: Array[Color]) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = _vertex_material(false, 1.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------------------------------------------------------------- banners, torches, velarium

func _build_props() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var red := Color(0.55, 0.12, 0.1)
	var gold := Color(0.85, 0.65, 0.2)
	var ochre := Color(0.7, 0.5, 0.15)
	# Hanging wall banners, away from the spawn axis (angles 90 and 270 degrees).
	for k: int in 6:
		var a: float = deg_to_rad(float(k) * 60.0)
		var field: Color = red if k % 2 == 0 else Color(0.2, 0.22, 0.32)
		_banner(st, wood, ring_point(radius - 0.12, a, WALL_HEIGHT - 0.2, WALL_SIDES), a, 1.1, 1.9, field, gold)
	# Flags on poles along the stands' rim.
	var rim: float = _stand_rim() - 0.4
	for k: int in 10:
		var a: float = TAU * (float(k) + 0.5) / 10.0
		var base: Vector3 = Vector3(rim * cos(a), _tier_top(TIER_COUNT - 1), rim * sin(a))
		_box(wood, Transform3D(ring_basis(a), base + Vector3(0, 2.2, 0)), Vector3(0.12, 4.4, 0.12), Color(0.3, 0.2, 0.12))
		_banner(st, wood, base + Vector3(0, 4.3, 0), a, 1.0, 2.2, red if k % 2 == 0 else ochre, gold, false)
	# Torches on the wall cap.
	for k: int in 6:
		var a: float = deg_to_rad(30.0 + float(k) * 60.0)
		var p: Vector3 = ring_point(radius + 0.3, a, WALL_HEIGHT, WALL_SIDES)
		_box(wood, Transform3D(ring_basis(a), p + Vector3(0, 0.7, 0)), Vector3(0.12, 1.4, 0.12), Color(0.25, 0.17, 0.1))
		_box(wood, Transform3D(ring_basis(a), p + Vector3(0, 1.45, 0)), Vector3(0.3, 0.14, 0.3), Color(0.12, 0.1, 0.09))
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
		flame.position = p + Vector3(0, 1.75, 0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		_flames.append(flame)
	var bi := MeshInstance3D.new()
	bi.name = "Banners"
	bi.mesh = st.commit()
	bi.material_override = _vertex_material(true, 0.9)
	bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bi)
	var pi := MeshInstance3D.new()
	pi.name = "Poles"
	pi.mesh = wood.commit()
	pi.material_override = _vertex_material(false, 0.85)
	add_child(pi)


## A banner hanging from `top` (centre of its top edge), facing the arena centre, with a trim stripe and a diamond.
func _banner(st: SurfaceTool, wood: SurfaceTool, top: Vector3, a: float, w: float, h: float, field: Color, trim: Color, hang: bool = true) -> void:
	var b: Basis = ring_basis(a)
	var tangent: Vector3 = b.x
	var inward: Vector3 = -b.z
	var front: Vector3 = top + inward * 0.04
	var hw: float = w * 0.5
	_quad(st, front - tangent * hw, front + tangent * hw, front + tangent * hw - Vector3(0, h, 0), front - tangent * hw - Vector3(0, h, 0), field, inward)
	var f2: Vector3 = front + inward * 0.01
	_quad(st, f2 - tangent * hw, f2 + tangent * hw, f2 + tangent * hw - Vector3(0, 0.14, 0), f2 - tangent * hw - Vector3(0, 0.14, 0), trim, inward)
	var c: Vector3 = f2 - Vector3(0, h * 0.5, 0)
	var d: float = w * 0.25
	_quad(st, c - Vector3(0, d, 0), c + tangent * d, c + Vector3(0, d, 0), c - tangent * d, trim, inward)
	if hang:
		_box(wood, Transform3D(b, top + inward * 0.06 + Vector3(0, 0.04, 0)), Vector3(w + 0.2, 0.08, 0.08), Color(0.25, 0.17, 0.1))


func _build_velarium() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_out: float = _stand_rim()
	var r_in: float = r_out - 5.5
	var y_out: float = _tier_top(TIER_COUNT - 1) + 3.6
	var y_in: float = y_out - 2.4
	var steps: int = 20
	var a_start: float = deg_to_rad(-80.0)
	var a_span: float = deg_to_rad(170.0)
	var cream := Color(0.88, 0.8, 0.62)
	var madder := Color(0.62, 0.16, 0.12)
	for s: int in steps:
		var a0: float = a_start + a_span * float(s) / float(steps)
		var a1: float = a_start + a_span * float(s + 1) / float(steps)
		var c: Color = cream if s % 2 == 0 else madder
		var rows: int = 2
		for rw: int in rows:
			var t0: float = float(rw) / float(rows)
			var t1: float = float(rw + 1) / float(rows)
			var sag0: float = -0.35 * sin(PI * t0)
			var sag1: float = -0.35 * sin(PI * t1)
			var p00: Vector3 = ring_point(lerpf(r_in, r_out, t0), a0, lerpf(y_in, y_out, t0) + sag0, 24)
			var p01: Vector3 = ring_point(lerpf(r_in, r_out, t0), a1, lerpf(y_in, y_out, t0) + sag0, 24)
			var p10: Vector3 = ring_point(lerpf(r_in, r_out, t1), a0, lerpf(y_in, y_out, t1) + sag1, 24)
			var p11: Vector3 = ring_point(lerpf(r_in, r_out, t1), a1, lerpf(y_in, y_out, t1) + sag1, 24)
			_quad(st, p00, p01, p11, p10, c, Vector3.DOWN)
			_quad(st, p00, p10, p11, p01, c * 0.8, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "Velarium"
	mi.mesh = st.commit()
	mi.material_override = _vertex_material(true, 0.95)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- light, sky, haze

func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var dir_to_sun := Vector3(cos(SUN_ELEVATION) * cos(SUN_AZIMUTH), sin(SUN_ELEVATION), cos(SUN_ELEVATION) * sin(SUN_AZIMUTH))
	sun.transform = Transform3D(Basis.looking_at(-dir_to_sun, Vector3.UP), Vector3.ZERO)
	sun.light_color = Color(1.0, 0.82, 0.58)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 0.5
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.9, 0.78, 0.6)
	sky_mat.ground_horizon_color = Color(0.8, 0.68, 0.52)
	sky_mat.ground_bottom_color = Color(0.45, 0.36, 0.26)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.72, 0.54)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------- mesh helpers

func _stone_material(block: Vector2, grime_height: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = STONE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("block", block)
	m.set_shader_parameter("grime_height", grime_height)
	return m


func _vertex_material(double_sided: bool, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Adds a quad whose front face looks along `front_hint`; winding is fixed up for Godot's clockwise fronts.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, front_hint: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var order: Array[Vector3]
	if n.dot(front_hint) > 0.0:
		order = [a, c, b, a, d, c]
	else:
		n = -n
		order = [a, b, c, a, c, d]
	for p: Vector3 in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: Color) -> void:
	var h: Vector3 = size * 0.5
	var c: Array[Vector3] = []
	for i: int in 8:
		c.append(xf * Vector3(h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z))
	var faces: Array = [
		[0, 1, 3, 2, -xf.basis.z], [4, 5, 7, 6, xf.basis.z],
		[0, 4, 6, 2, -xf.basis.x], [1, 5, 7, 3, xf.basis.x],
		[0, 1, 5, 4, -xf.basis.y], [2, 3, 7, 6, xf.basis.y],
	]
	for f: Array in faces:
		_quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]], col, f[4])


const STONE_SHADER: String = """
shader_type spatial;
uniform vec2 block = vec2(0.6, 0.5);
uniform float grime_height = 1.5;
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
	float shade = 0.85 + 0.3 * hash21(vec2(cell, row));
	vec2 fr = vec2(fract(cu), fract(wpos.y / block.y));
	float edge = min(min(fr.x, 1.0 - fr.x) * block.x, min(fr.y, 1.0 - fr.y) * block.y);
	float mortar = 1.0 - smoothstep(0.015, 0.045, edge);
	col *= mix(1.0, shade, vertical);
	col = mix(col, col * 0.75, mortar * vertical);
	float stain = vnoise(vec2(u * 0.5, wpos.y * 1.5)) * 0.5 + vnoise(vec2(u * 3.0, wpos.y * 6.0)) * 0.25;
	col *= 0.82 + stain * 0.5;
	col *= mix(0.55, 1.0, smoothstep(0.0, grime_height, wpos.y));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""
