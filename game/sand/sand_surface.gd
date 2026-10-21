class_name SandSurface
extends Node3D
## The arena floor's visual sand: a deformable heightmap plus a blood/wetness map, both CPU side and uploaded in
## dirty tiles, drawn by a subdivided disc with a vertex-displacing shader. Presentation only: never part of the
## simulation state, the collider stays flat at y = 0.
## Maps: height R16F (metres), blood RGBA8 (R blood, G damp, B dryness).

const TILE: int = 16
const UPLOAD_INTERVAL: float = 1.0 / 30.0
const SWEEP_TILES_PER_FRAME: int = 4
const WET_DECAY: float = 1.0 / 240.0  ## damp fraction lost per second
const DRY_RATE: float = 1.0 / 120.0  ## dryness gained per second
const MAX_DRAG_STAMPS: int = 80
const PUFF_POOL: int = 6
const GRAIN_POOL: int = 6
const FLOOR_SHADER: Shader = preload("res://game/sand/sand_floor.gdshader")

var radius: float = 11.0
var extent: float = 11.6
var n: int = 0
var texels_per_m: float = 40.0
var rim_gain: float = 1.0

var _h: PackedFloat32Array = PackedFloat32Array()
var _blood: PackedFloat32Array = PackedFloat32Array()
var _wet: PackedFloat32Array = PackedFloat32Array()
var _dry: PackedFloat32Array = PackedFloat32Array()
var _h_img: Image
var _b_img: Image
var _h_tex: ImageTexture
var _b_tex: ImageTexture
var _material: ShaderMaterial
var _mesh_node: MeshInstance3D
var _tiles_x: int = 0
var _h_dirty: PackedByteArray = PackedByteArray()
var _h_list: PackedInt32Array = PackedInt32Array()
var _b_dirty: PackedByteArray = PackedByteArray()
var _b_list: PackedInt32Array = PackedInt32Array()
var _b_active: PackedByteArray = PackedByteArray()
var _b_active_list: PackedInt32Array = PackedInt32Array()
var _b_tile_time: PackedFloat32Array = PackedFloat32Array()
var _sweep_cursor: int = 0
var _h_upload_pending: bool = false
var _b_upload_pending: bool = false
var _since_upload: float = 0.0
var _time: float = 0.0
var _pools: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _puffs: Array[CPUParticles3D] = []
var _grains: Array[CPUParticles3D] = []
var _next_puff: int = 0
var _next_grain: int = 0


## Builds maps, mesh and material. radius = arena radius in metres. texels_per_m 40 gives 2.5 cm texels
## (use about 28 on weak phones); mesh_cell is the vertex spacing of the floor mesh in metres.
func setup(arena_radius: float = 11.0, tpm: float = 40.0, mesh_cell: float = 0.1) -> void:
	radius = arena_radius
	texels_per_m = tpm
	extent = SandMap.map_extent(radius)
	n = SandMap.map_size(radius, tpm)
	_rng.seed = 90210
	var count: int = n * n
	_h.resize(count)
	_blood.resize(count)
	_wet.resize(count)
	_dry.resize(count)
	_h.fill(0.0)
	_blood.fill(0.0)
	_wet.fill(0.0)
	_dry.fill(0.0)
	_tiles_x = int(ceil(float(n) / float(TILE)))
	var tiles: int = _tiles_x * _tiles_x
	for arr: PackedByteArray in [_h_dirty, _b_dirty, _b_active]:
		arr.resize(tiles)
		arr.fill(0)
	_b_tile_time.resize(tiles)
	_b_tile_time.fill(0.0)
	_h_img = Image.create(n, n, false, Image.FORMAT_RH)
	_b_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
	_b_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_h_tex = ImageTexture.create_from_image(_h_img)
	_b_tex = ImageTexture.create_from_image(_b_img)
	_material = ShaderMaterial.new()
	_material.shader = FLOOR_SHADER
	_material.set_shader_parameter("height_tex", _h_tex)
	_material.set_shader_parameter("blood_tex", _b_tex)
	_material.set_shader_parameter("noise_tex", make_noise_texture())
	_material.set_shader_parameter("extent", extent)
	_material.set_shader_parameter("map_n", float(n))
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "SandMesh"
	_mesh_node.mesh = build_disc_mesh(radius + 0.35, mesh_cell)
	_mesh_node.material_override = _material
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_node.custom_aabb = AABB(Vector3(-extent, -0.5, -extent), Vector3(extent * 2.0, 1.0, extent * 2.0))
	add_child(_mesh_node)
	_build_particles()


## Presses a round footprint, knee, weapon tip or body part into the sand. push biases the rim along it (length
## 1 or more = strong bias).
func stamp(pos: Vector3, radius_m: float, depth: float, push: Vector3 = Vector3.ZERO) -> void:
	stamp_ellipse(pos, radius_m, radius_m, 0.0, depth, push)


## Elliptical stamp: half-width rx (local X) and half-length rz (local Z) in metres, yaw about Y like a node.
func stamp_ellipse(pos: Vector3, rx: float, rz: float, yaw: float, depth: float, push: Vector3 = Vector3.ZERO) -> void:
	if n == 0:
		return
	var c: Vector2 = SandMap.world_to_texel(pos.x, pos.z, extent, n)
	var pv: Vector2 = Vector2(push.x, push.z)
	if pv.length() > 1.0:
		pv = pv.normalized()
	var t: float = texels_per_m
	var rect: Rect2i = SandMap.apply_stamp(_h, n, c, rx * t, rz * t, yaw, depth, pv, rim_gain)
	_mark_h(rect)


## A furrow: a stamp swept from `from` to `to`, sand spills to both sides and piles up ahead.
func drag(from: Vector3, to: Vector3, radius_m: float, depth: float) -> void:
	if n == 0:
		return
	var a: Vector2 = Vector2(from.x, from.z)
	var b: Vector2 = Vector2(to.x, to.z)
	var dir: Vector2 = (b - a).normalized() if a.distance_to(b) > 0.0001 else Vector2.ZERO
	radius_m = maxf(radius_m, 1.6 / texels_per_m)
	var spacing: float = maxf(radius_m * 0.35, 0.5 / texels_per_m)
	var pts: PackedVector2Array = SandMap.drag_points(a, b, spacing, MAX_DRAG_STAMPS)
	var t: float = texels_per_m
	var gain: float = rim_gain * 0.85
	for p: Vector2 in pts:
		var c: Vector2 = SandMap.world_to_texel(p.x, p.y, extent, n)
		_mark_h(SandMap.apply_stamp(_h, n, c, radius_m * t, radius_m * t, 0.0, depth, dir * 0.5, gain))


## Soaks blood in: pools spread a little, small amounts leave dark clumps.
func add_blood(pos: Vector3, radius_m: float, litres: float) -> void:
	if n == 0:
		return
	var r: float = SandMap.blood_spread_radius(litres, radius_m)
	var strength: float = SandMap.blood_strength(litres, r)
	var c: Vector2 = SandMap.world_to_texel(pos.x, pos.z, extent, n)
	var seed_v: float = _rng.randf_range(0.0, TAU)
	var rect: Rect2i = SandMap.apply_blood(_blood, _wet, _dry, n, c, r * texels_per_m, strength, seed_v, true)
	_mark_b(rect)
	if r > 0.05 and _pools.size() < 8:
		_pools.append({"c": c, "r0": r * texels_per_m, "r1": r * texels_per_m * 1.3, "t": 0.0, "dur": 2.5,
				"s": strength * 0.8, "seed": seed_v})


## Kicks up a sand puff and a few grains. vel = initial direction and speed (m/s), amount 0..1.
func spray(pos: Vector3, vel: Vector3, amount: float) -> void:
	if _puffs.is_empty():
		return
	amount = clampf(amount, 0.0, 1.5)
	var dir: Vector3 = vel.normalized() if vel.length() > 0.01 else Vector3.UP
	dir = (dir + Vector3.UP * 0.6).normalized()
	var speed: float = clampf(vel.length() * 0.35, 0.5, 4.0)
	var puff: CPUParticles3D = _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	puff.global_position = pos + Vector3(0.0, 0.03, 0.0)
	puff.direction = dir
	puff.initial_velocity_min = speed * 0.4
	puff.initial_velocity_max = speed
	puff.scale_amount_min = 0.12 + 0.1 * amount
	puff.scale_amount_max = 0.22 + 0.2 * amount
	puff.restart()
	puff.emitting = true
	var gr: CPUParticles3D = _grains[_next_grain]
	_next_grain = (_next_grain + 1) % _grains.size()
	gr.global_position = pos + Vector3(0.0, 0.02, 0.0)
	gr.direction = dir
	gr.initial_velocity_min = speed * 0.8
	gr.initial_velocity_max = speed * 2.2
	gr.restart()
	gr.emitting = true


## Visual height offset in metres at a point (bilinear). Zero outside the map.
func height_at(pos: Vector3) -> float:
	if n == 0:
		return 0.0
	return SandMap.sample_height(_h, n, extent, pos.x, pos.z)


## Blood amount 0..1 at a point (for feet and decals).
func blood_at(pos: Vector3) -> float:
	if n == 0:
		return 0.0
	var t: Vector2 = SandMap.world_to_texel(pos.x, pos.z, extent, n)
	var x: int = int(t.x)
	var y: int = int(t.y)
	if x < 0 or y < 0 or x >= n or y >= n:
		return 0.0
	return _blood[y * n + x]


## Smooths the sand back to flat and removes blood (new round).
func clear() -> void:
	if n == 0:
		return
	_h.fill(0.0)
	_blood.fill(0.0)
	_wet.fill(0.0)
	_dry.fill(0.0)
	_h_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_b_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_h_dirty.fill(0)
	_b_dirty.fill(0)
	_b_active.fill(0)
	_h_list.clear()
	_b_list.clear()
	_b_active_list.clear()
	_pools.clear()
	_h_upload_pending = true
	_b_upload_pending = true


func _process(delta: float) -> void:
	if n == 0:
		return
	_time += delta
	_since_upload += delta
	_spread_pools(delta)
	_sweep_blood()
	if _since_upload >= UPLOAD_INTERVAL:
		flush()


## Writes dirty tiles to the images and uploads textures. Called from _process, public for tests and renders.
func flush() -> void:
	_since_upload = 0.0
	if not _h_list.is_empty():
		for t: int in _h_list:
			_write_h_tile(t)
			_h_dirty[t] = 0
		_h_list.clear()
		_h_upload_pending = true
	if not _b_list.is_empty():
		for t2: int in _b_list:
			_write_b_tile(t2)
			_b_dirty[t2] = 0
		_b_list.clear()
		_b_upload_pending = true
	if _h_upload_pending:
		_h_tex.update(_h_img)
		_h_upload_pending = false
	if _b_upload_pending:
		_b_tex.update(_b_img)
		_b_upload_pending = false


func _tile_bounds(t: int) -> Rect2i:
	var tx: int = t % _tiles_x
	var ty: int = t / _tiles_x
	var x0: int = tx * TILE
	var y0: int = ty * TILE
	return Rect2i(x0, y0, mini(TILE, n - x0), mini(TILE, n - y0))


func _write_h_tile(t: int) -> void:
	var r: Rect2i = _tile_bounds(t)
	for y in range(r.position.y, r.end.y):
		var row: int = y * n
		for x in range(r.position.x, r.end.x):
			_h_img.set_pixel(x, y, Color(_h[row + x], 0.0, 0.0, 1.0))


func _write_b_tile(t: int) -> void:
	var r: Rect2i = _tile_bounds(t)
	for y in range(r.position.y, r.end.y):
		var row: int = y * n
		for x in range(r.position.x, r.end.x):
			var i: int = row + x
			_b_img.set_pixel(x, y, Color(_blood[i], _wet[i], _dry[i], 1.0))


func _mark_h(rect: Rect2i) -> void:
	if rect.size.x <= 0:
		return
	for ty in range(rect.position.y / TILE, (rect.end.y - 1) / TILE + 1):
		for tx in range(rect.position.x / TILE, (rect.end.x - 1) / TILE + 1):
			var t: int = ty * _tiles_x + tx
			if _h_dirty[t] == 0:
				_h_dirty[t] = 1
				_h_list.append(t)


func _mark_b(rect: Rect2i) -> void:
	if rect.size.x <= 0:
		return
	for ty in range(rect.position.y / TILE, (rect.end.y - 1) / TILE + 1):
		for tx in range(rect.position.x / TILE, (rect.end.x - 1) / TILE + 1):
			var t: int = ty * _tiles_x + tx
			if _b_dirty[t] == 0:
				_b_dirty[t] = 1
				_b_list.append(t)
			if _b_active[t] == 0:
				_b_active[t] = 1
				_b_active_list.append(t)
				_b_tile_time[t] = _time


func _spread_pools(delta: float) -> void:
	var i: int = _pools.size() - 1
	while i >= 0:
		var p: Dictionary = _pools[i]
		var t: float = float(p["t"]) + delta
		p["t"] = t
		var k: float = clampf(t / float(p["dur"]), 0.0, 1.0)
		var r: float = lerpf(float(p["r0"]), float(p["r1"]), 1.0 - (1.0 - k) * (1.0 - k))
		var rect: Rect2i = SandMap.apply_blood(_blood, _wet, _dry, n, p["c"], r, float(p["s"]), float(p["seed"]), false)
		_mark_b(rect)
		if k >= 1.0:
			_pools.remove_at(i)
		i -= 1


## Dries and slowly un-dampens blood, a few tiles per frame.
func _sweep_blood() -> void:
	var count: int = _b_active_list.size()
	if count == 0:
		return
	var steps: int = mini(SWEEP_TILES_PER_FRAME, count)
	for s in range(steps):
		if _sweep_cursor >= _b_active_list.size():
			_sweep_cursor = 0
		var t: int = _b_active_list[_sweep_cursor]
		if _sweep_tile(t):
			_b_active[t] = 0
			_b_active_list.remove_at(_sweep_cursor)
			if _b_active_list.is_empty():
				return
		else:
			_sweep_cursor += 1


## Returns true when the tile is fully settled (dry, damp at its floor).
func _sweep_tile(t: int) -> bool:
	var dt: float = _time - _b_tile_time[t]
	_b_tile_time[t] = _time
	var r: Rect2i = _tile_bounds(t)
	var settled: bool = true
	for y in range(r.position.y, r.end.y):
		var row: int = y * n
		for x in range(r.position.x, r.end.x):
			var i: int = row + x
			var b: float = _blood[i]
			var w: float = _wet[i]
			if b < 0.002 and w < 0.002:
				continue
			var d: float = _dry[i]
			var floor_w: float = 0.35 * minf(1.0, b * 2.0)
			var nw: float = maxf(floor_w, w - dt * WET_DECAY)
			var nd: float = minf(1.0, d + dt * DRY_RATE) if b > 0.002 else d
			if nw != w or nd != d:
				_wet[i] = nw
				_dry[i] = nd
				_b_img.set_pixel(x, y, Color(b, nw, nd, 1.0))
				_b_upload_pending = true
			if nd < 1.0 or nw > floor_w + 0.002:
				settled = false
	return settled


func _build_particles() -> void:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt: GradientTexture2D = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var pm: StandardMaterial3D = StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = gt
	pm.albedo_color = Color(0.80, 0.66, 0.46)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = pm
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.55))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.6))
	for i in range(PUFF_POOL):
		var p: CPUParticles3D = CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 14
		p.lifetime = 1.1
		p.explosiveness = 0.95
		p.local_coords = false
		p.mesh = quad
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.06
		p.spread = 40.0
		p.gravity = Vector3(0.0, -0.8, 0.0)
		p.damping_min = 2.0
		p.damping_max = 3.5
		p.color_ramp = fade
		p.scale_amount_curve = grow
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_puffs.append(p)
	var gm: StandardMaterial3D = StandardMaterial3D.new()
	gm.albedo_color = Color(0.78, 0.62, 0.40)
	gm.roughness = 0.9
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.012, 0.009, 0.012)
	box.material = gm
	for i in range(GRAIN_POOL):
		var g: CPUParticles3D = CPUParticles3D.new()
		g.emitting = false
		g.one_shot = true
		g.amount = 18
		g.lifetime = 0.75
		g.explosiveness = 1.0
		g.local_coords = false
		g.mesh = box
		g.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		g.emission_sphere_radius = 0.05
		g.spread = 55.0
		g.gravity = Vector3(0.0, -9.8, 0.0)
		g.angular_velocity_min = -360.0
		g.angular_velocity_max = 360.0
		g.scale_amount_min = 0.6
		g.scale_amount_max = 1.8
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_grains.append(g)


## Grid disc mesh of cell size `cell` metres, cells kept when any corner lies within r. Flat at y = 0, up normals.
static func build_disc_mesh(r: float, cell: float) -> ArrayMesh:
	var gn: int = int(ceil(2.0 * r / cell)) + 1
	var idx: PackedInt32Array = PackedInt32Array()
	idx.resize(gn * gn)
	idx.fill(-1)
	var verts: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var r2: float = r * r
	for cz in range(gn - 1):
		for cx in range(gn - 1):
			var keep: bool = false
			for k in range(4):
				var px: float = -r + float(cx + (k & 1)) * cell
				var pz: float = -r + float(cz + (k >> 1)) * cell
				if px * px + pz * pz <= r2:
					keep = true
			if not keep:
				continue
			var q: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
			for k in range(4):
				var gx: int = cx + (k & 1)
				var gz: int = cz + (k >> 1)
				var gi: int = gz * gn + gx
				if idx[gi] < 0:
					idx[gi] = verts.size()
					verts.append(Vector3(-r + float(gx) * cell, 0.0, -r + float(gz) * cell))
				q[k] = idx[gi]
			# Clockwise seen from above (+Y), Godot front faces.
			indices.append_array(PackedInt32Array([q[0], q[1], q[2], q[1], q[3], q[2]]))
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 256 px tileable noise: R fine grain, G medium clumps, B large ripples. With mipmaps.
static func make_noise_texture() -> ImageTexture:
	var chans: Array[PackedByteArray] = []
	var freqs: Array[float] = [0.09, 0.035, 0.012]
	for k in range(3):
		var fn: FastNoiseLite = FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = 11 + k * 7
		fn.frequency = freqs[k]
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM if k > 0 else FastNoiseLite.FRACTAL_NONE
		var im: Image = fn.get_seamless_image(256, 256, false, false, 0.1, true)
		im.convert(Image.FORMAT_L8)
		chans.append(im.get_data())
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(256 * 256 * 3)
	for i in range(256 * 256):
		bytes[i * 3] = chans[0][i]
		bytes[i * 3 + 1] = chans[1][i]
		bytes[i * 3 + 2] = chans[2][i]
	var img: Image = Image.create_from_data(256, 256, false, Image.FORMAT_RGB8, bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
