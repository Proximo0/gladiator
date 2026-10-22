class_name SandSurface
extends Node3D
## The arena floor's visual sand: a deformable heightmap plus a blood/wetness map, both CPU side and uploaded in
## dirty tiles, drawn by a subdivided disc with a vertex-displacing shader. Presentation only: never part of the
## simulation state, the collider stays flat at y = 0.
## Maps: height R16F (metres), blood RGBA8 (R blood, G damp, B dryness, A blood palette slot 0 or 1: whose blood).

const TILE: int = 16
const SWEEP_TILES_PER_FRAME: int = 4
const WET_DECAY: float = 1.0 / 240.0  ## damp fraction lost per second
const DRY_RATE: float = 1.0 / 120.0  ## dryness gained per second
const MAX_DRAG_STAMPS: int = 80
const BASE_SEED: int = 7
const FOOT_RADIUS_MAX: float = 0.075  ## drag radii up to this count as a foot, the rest as a body or weapon
const TICK_S: float = 1.0 / 60.0
const AMBIENT_TINT: Color = Color(1.0, 0.9, 0.82)  ## warm fill for shade (sky ambient is blue: olive on orange sand)
const AMBIENT_GAIN: float = 1.05
const AMBIENT_REFRESH_S: float = 0.5
const GRAIN_COLOR: Color = Color(0.62, 0.43, 0.22)  ## linear
const DUST_COLOR: Color = Color(0.80, 0.64, 0.44)
const DEPTH_PER_WIDTH: float = 0.85
const BODY_RADIUS_MIN: float = 0.16  ## stamps wider than this are bodies, not feet
const FLOOR_SHADER: Shader = preload("res://game/sand/sand_floor.gdshader")

var radius: float = 11.0
var extent: float = 11.6
var n: int = 0
var texels_per_m: float = 40.0
var rim_gain: float = 1.0
## Perf harness: with profile_on, _process adds its sections' milliseconds to `prof` (pools, grains, sweep, flush).
var profile_on: bool = false
var prof: Dictionary = {}

var _h: PackedFloat32Array = PackedFloat32Array()
var _base: PackedFloat32Array = PackedFloat32Array()  ## permanent piles (wall drifts, heaps), metres
var _blood: PackedFloat32Array = PackedFloat32Array()
var _wet: PackedFloat32Array = PackedFloat32Array()
var _dry: PackedFloat32Array = PackedFloat32Array()
var _pal: PackedByteArray = PackedByteArray()  ## blood palette slot per texel (0 or 1)
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
const POOL_MIN_GROW: float = 0.6  ## texels a spreading pool's edge must grow before it is repainted
var _pools: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _puffs: Array[CPUParticles3D] = []
var _next_puff: int = 0
var _fx: SandFx = SandFx.new(1)
var _grain_capacity: int = 1
var _pool_step_s: float = 0.0
var _upload_interval: float = 1.0 / 30.0
var _pool_acc: float = 0.0
var _fx_mm: MultiMesh
var _fx_buf: PackedFloat32Array = PackedFloat32Array()
var _fx_shown: int = 0
var _dust: SandDust = SandDust.new(1)
var _dust_mm: MultiMesh
var _dust_buf: PackedFloat32Array = PackedFloat32Array()
var _dust_shown: int = 0
var _mult: float = 1.0  ## quality share of the per-event spray counts
var _lift: float = 0.0  ## visual sand surface height above the flat collider, metres
var _last_puff_time: float = -10.0
var _base_tex: ImageTexture
var _ambient_clock: float = 99.0


## Builds maps, mesh and material. radius = arena radius in metres. texels_per_m 40 gives 2.5 cm texels
## (use about 28 on weak phones); mesh_cell is the vertex spacing of the floor mesh in metres. Negative tpm or
## mesh_cell take the GfxQuality level's value. Grain, puff and shader detail counts always follow GfxQuality.
func setup(arena_radius: float = 11.0, tpm: float = -1.0, mesh_cell: float = -1.0) -> void:
	if tpm < 0.0:
		tpm = GfxQuality.pick_f(GfxQuality.SAND_TEXELS_PER_M)
	if mesh_cell < 0.0:
		mesh_cell = GfxQuality.pick_f(GfxQuality.SAND_MESH_CELL)
	_grain_capacity = GfxQuality.pick_i(GfxQuality.SAND_GRAINS)
	_fx = SandFx.new(_grain_capacity)
	_dust = SandDust.new(GfxQuality.pick_i(GfxQuality.SAND_DUST))
	_mult = GfxQuality.pick_f(GfxQuality.SAND_FX_MULT)
	var tun: Tuning = Tuning.shared()
	_lift = tun.sand_lift
	rim_gain = tun.sand_rim_gain
	_pool_step_s = GfxQuality.pick_f(GfxQuality.SAND_POOL_STEP_S)
	_upload_interval = GfxQuality.pick_f(GfxQuality.SAND_UPLOAD_S)
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
	_pal.resize(count)
	_pal.fill(0)
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
	_b_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_h_tex = ImageTexture.create_from_image(_h_img)
	_b_tex = ImageTexture.create_from_image(_b_img)
	_material = ShaderMaterial.new()
	_material.shader = FLOOR_SHADER
	_material.set_shader_parameter("height_tex", _h_tex)
	_material.set_shader_parameter("blood_tex", _b_tex)
	_base = SandMap.build_base(radius, extent, BASE_SEED)
	_base_tex = _make_base_texture()
	_material.set_shader_parameter("base_tex", _base_tex)
	_material.set_shader_parameter("noise_tex", make_noise_texture())
	_material.set_shader_parameter("extent", extent)
	_material.set_shader_parameter("map_n", float(n))
	_material.set_shader_parameter("arena_radius", radius)
	_material.set_shader_parameter("detail", GfxQuality.pick_i(GfxQuality.SAND_DETAIL))
	_material.set_shader_parameter("lift", _lift)
	_material.set_shader_parameter("vtx_cell", mesh_cell)
	_material.set_shader_parameter("hollow_dark", tun.sand_hollow_dark)
	_material.set_shader_parameter("rim_light", tun.sand_rim_light)
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "SandMesh"
	_mesh_node.mesh = build_disc_mesh(radius + 0.35, mesh_cell)
	_mesh_node.material_override = _material
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_node.custom_aabb = AABB(Vector3(-extent, -0.5, -extent), Vector3(extent * 2.0, 1.0, extent * 2.0))
	add_child(_mesh_node)
	_build_particles()
	refresh_ambient()
	_fx.set_ground(Callable(self, "_ground_at"))


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
	var rect: Rect2i = SandMap.apply_stamp(_h, n, c, rx * t, rz * t, yaw, _fit_depth(_visual_depth(depth), minf(rx, rz) * 1.6), pv, rim_gain)
	_mark_h(rect)
	_stamp_fx(pos, maxf(rx, rz), depth, push)


## Visual depth (m) of a requested press depth: the Tuning scale, the extra for falls, and the cap.
func _visual_depth(depth: float) -> float:
	var tun: Tuning = Tuning.shared()
	return SandMap.deepen(depth, tun.sand_depth_scale, tun.sand_deep_from, tun.sand_deep_gain, tun.sand_max_depth)


## A hollow is never deeper than about its own half-width: steeper walls than sand holds read as spikes.
func _fit_depth(d: float, half_width_m: float) -> float:
	return minf(d, half_width_m * DEPTH_PER_WIDTH)


## A body-shaped crater: round presses of `radius_m` laid along a->b (a fallen body's spine or limb), with berms
## round the outline. One fall's worth of grains and dust at the middle.
func stamp_capsule(from: Vector3, to: Vector3, radius_m: float, depth: float, push: Vector3 = Vector3.ZERO) -> void:
	if n == 0:
		return
	var a: Vector2 = Vector2(from.x, from.z)
	var b: Vector2 = Vector2(to.x, to.z)
	var pv: Vector2 = Vector2(push.x, push.z)
	if pv.length() > 1.0:
		pv = pv.normalized()
	var d: float = _fit_depth(_visual_depth(depth), radius_m)
	var t: float = texels_per_m
	_mark_h(SandMap.apply_capsule(_h, n, SandMap.world_to_texel(a.x, a.y, extent, n), SandMap.world_to_texel(b.x, b.y, extent, n),
			radius_m * t, d, pv, rim_gain))
	var mid: Vector2 = a.lerp(b, 0.5)
	_stamp_fx(Vector3(mid.x, 0.0, mid.y), maxf(radius_m, a.distance_to(b) * 0.5), depth, push)


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
	var vd: float = _fit_depth(_visual_depth(depth), radius_m * 1.2)
	for p: Vector2 in pts:
		var c: Vector2 = SandMap.world_to_texel(p.x, p.y, extent, n)
		_mark_h(SandMap.apply_stamp(_h, n, c, radius_m * t, radius_m * t, 0.0, vd, dir * 0.5, gain))
	_drag_fx(a, b, dir, radius_m, depth)


## Sets the look of blood palette slot 0 or 1 (the two fighters): fresh and dried soak colours and a glow strength.
func set_blood_palette(slot: int, fresh: Color, dried: Color, glow: float) -> void:
	if _material == null:
		return
	var sfx: String = "" if slot <= 0 else "1"
	_material.set_shader_parameter("blood_fresh" + sfx, fresh)
	_material.set_shader_parameter("blood_dried" + sfx, dried)
	_material.set_shader_parameter("blood_glow" + sfx, glow)


## Contact-shadow blobs under the fighters (ContactShadow.pack: MAX_BLOBS long, live ones first). An empty array
## clears them.
func set_contacts(blobs: PackedVector4Array) -> void:
	if _material == null:
		return
	if blobs.size() != ContactShadow.MAX_BLOBS:
		blobs.resize(ContactShadow.MAX_BLOBS)
		blobs.fill(Vector4.ZERO)
	_material.set_shader_parameter("contact", blobs)


## Soaks blood in: pools spread a little, small amounts leave dark clumps. `slot` is the bleeding fighter's blood
## palette slot (0 or 1), so red and ichor can lie on the same sand.
func add_blood(pos: Vector3, radius_m: float, litres: float, slot: int = 0) -> void:
	if n == 0:
		return
	var r: float = SandMap.blood_spread_radius(litres, radius_m)
	var strength: float = SandMap.blood_strength(litres, r)
	var c: Vector2 = SandMap.world_to_texel(pos.x, pos.z, extent, n)
	var seed_v: float = _rng.randf_range(0.0, TAU)
	var rect: Rect2i = SandMap.apply_blood(_blood, _wet, _dry, n, c, r * texels_per_m, strength, seed_v, true, _pal, slot)
	_mark_b(rect)
	if r > 0.05 and _pools.size() < 8:
		_pools.append({"c": c, "r0": r * texels_per_m, "r1": r * texels_per_m * 1.3, "t": 0.0, "dur": 2.5,
				"s": strength * 0.8, "seed": seed_v, "slot": slot, "rp": r * texels_per_m})


## Kicks up a dust puff and a burst of grains. vel = initial direction and speed (m/s), amount 0..1.
func spray(pos: Vector3, vel: Vector3, amount: float) -> void:
	if _puffs.is_empty():
		return
	amount = clampf(amount, 0.0, 1.5)
	var dir: Vector3 = vel.normalized() if vel.length() > 0.01 else Vector3.UP
	dir = (dir + Vector3.UP * 0.7).normalized()
	var speed: float = clampf(vel.length() * 0.35, 0.5, 4.0)
	_puff(pos, dir, speed, amount)
	var plan: Dictionary = SandFxPlan.strike(Tuning.shared(), _mult, amount, _rng.randf())
	_fx.burst(pos + Vector3(0.0, 0.02, 0.0), dir, clampf(vel.length() * 0.5 + 1.8, 1.8, 6.5) * (0.7 + 0.4 * amount),
			int(plan["grains"]), 0.75, 0.8 + 0.5 * amount)
	_dust_from(plan, pos, dir, 0.08)
	if amount > 0.5:
		_fx.fountain(pos, 0.1, 1.6 + 1.6 * amount, int(float(plan["grains"]) * 0.35), 1.0)


## Spawns a plan's dust sprites at pos, thrown along dir.
func _dust_from(plan: Dictionary, pos: Vector3, dir: Vector3, radius: float) -> void:
	var nd: int = int(plan["dust"])
	if nd <= 0:
		return
	var tun: Tuning = Tuning.shared()
	_dust.cloud(pos + Vector3(0.0, 0.03 + float(plan["size"]) * 0.3, 0.0), dir, float(plan["speed"]) * 0.45, nd, radius, float(plan["size"]),
			tun.sand_dust_life, tun.sand_dust_alpha)


## One dust puff (round robin over the pool), speed in m/s along dir.
func _puff(pos: Vector3, dir: Vector3, speed: float, amount: float) -> void:
	var puff: CPUParticles3D = _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	_last_puff_time = _time
	if puff.is_inside_tree():
		puff.global_position = pos + Vector3(0.0, 0.03, 0.0)
	else:
		puff.position = pos + Vector3(0.0, 0.03, 0.0)
	puff.direction = dir
	puff.initial_velocity_min = speed * 0.3
	puff.initial_velocity_max = speed
	puff.scale_amount_min = 0.10 + 0.08 * amount
	puff.scale_amount_max = 0.18 + 0.16 * amount
	if puff.is_inside_tree():
		puff.restart()
		puff.emitting = true


## Grains and dust from a footprint, a knee, a fallen body. Feet kick a little on every step (more when running);
## a body press or a hard landing throws a fountain, a burst and a dust cloud by how hard it hit.
func _stamp_fx(pos: Vector3, r: float, depth: float, push: Vector3) -> void:
	var tun: Tuning = Tuning.shared()
	var pl: float = Vector2(push.x, push.z).length()
	var travel: Vector3 = Vector3(push.x, 0.0, push.z).normalized() if pl > 0.05 else Vector3.ZERO
	if r <= BODY_RADIUS_MIN and depth < tun.sand_deep_from:
		var sp: Dictionary = SandFxPlan.step(tun, _mult, pl, _rng.randf())
		var ng: int = int(sp["grains"])
		if pl > 0.3:
			_fx.kick(pos, travel, float(sp["speed"]), ng, 0.9)
		else:
			_fx.fountain(pos, r * 0.5, float(sp["speed"]) * 0.8, ng, 0.8)
		_dust_from(sp, pos, travel + Vector3.UP * 0.4, r * 0.5)
		return
	var fp: Dictionary = SandFxPlan.fall(tun, _mult, depth, _rng.randf())
	var k: float = SandFxPlan.impact_of(depth)
	var n_all: int = int(fp["grains"])
	_fx.fountain(pos, r, float(fp["speed"]), n_all - n_all / 3, 1.0)
	if n_all > 6:
		_fx.burst(pos + Vector3(0.0, 0.02, 0.0), Vector3.UP + travel * 0.5, float(fp["speed"]) * 1.5, n_all / 3, 0.9, 1.0)
	_dust_from(fp, pos, Vector3.UP * 0.5 + travel * 0.5, r)
	if k > 0.35 and _time - _last_puff_time > 0.1 and not _puffs.is_empty():
		_puff(pos, Vector3.UP, 0.6 + k, 0.2 + 0.3 * minf(k, 1.0))


## Kick-up from a foot ploughing, a body sliding or a weapon tip raking the sand: grains fly back, up and aside, a
## weapon tip throws sand forward along its cut. Speed comes from the length of this tick's step.
func _drag_fx(a: Vector2, b: Vector2, dir: Vector2, radius_m: float, depth: float) -> void:
	var speed: float = minf(a.distance_to(b) / TICK_S, 14.0)
	if speed < 0.9:
		return
	var plan: Dictionary = SandFxPlan.slide(Tuning.shared(), _mult, speed, radius_m, _rng.randf())
	var travel: Vector3 = Vector3(dir.x, 0.0, dir.y)
	var at: Vector3 = Vector3(b.x, 0.0, b.y)
	var ng: int = int(plan["grains"])
	if radius_m < 0.04:
		if ng > 0:
			_fx.burst(at + Vector3(0.0, 0.02, 0.0), (travel * 0.7 + Vector3.UP * 0.8).normalized(), 1.5 + speed * 0.35, ng, 0.6, 0.8)
		_dust_from(plan, at, (travel + Vector3.UP).normalized(), 0.04)
		if speed > 4.0 and _time - _last_puff_time > 0.12 and not _puffs.is_empty():
			_puff(at, (travel + Vector3.UP).normalized(), speed * 0.2, 0.3)
	else:
		if ng > 0:
			_fx.kick(at, travel, speed, ng, 1.0 if depth > 0.01 else 0.8)
		_dust_from(plan, at, -travel * 0.6 + Vector3.UP * 0.6, radius_m)
		if speed > 2.4 and _time - _last_puff_time > 0.15 and not _puffs.is_empty():
			_puff(at, Vector3.UP, 0.5 + speed * 0.1, 0.25)


func _ground_at(p: Vector3) -> float:
	return height_at(p)


## Visual height offset in metres at a point (bilinear). Zero outside the map.
func height_at(pos: Vector3) -> float:
	if n == 0:
		return 0.0
	return SandMap.sample_height(_h, n, extent, pos.x, pos.z) + SandMap.sample_base(_base, extent, pos.x, pos.z) \
			+ SandMap.lift_at(pos.x, pos.z, radius, _lift)


## Height of the permanent piles alone (wall drifts and heaps) at a point.
func base_height_at(pos: Vector3) -> float:
	if n == 0:
		return 0.0
	return SandMap.sample_base(_base, extent, pos.x, pos.z)


## Blood palette slot (0 or 1) of the blood at a point.
func blood_slot_at(pos: Vector3) -> int:
	if n == 0:
		return 0
	var t: Vector2 = SandMap.world_to_texel(pos.x, pos.z, extent, n)
	var x: int = int(t.x)
	var y: int = int(t.y)
	if x < 0 or y < 0 or x >= n or y >= n:
		return 0
	return _pal[y * n + x]


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
	set_contacts(PackedVector4Array())
	_h.fill(0.0)
	_blood.fill(0.0)
	_wet.fill(0.0)
	_dry.fill(0.0)
	_pal.fill(0)
	_h_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_b_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_h_dirty.fill(0)
	_b_dirty.fill(0)
	_b_active.fill(0)
	_h_list.clear()
	_b_list.clear()
	_b_active_list.clear()
	_pools.clear()
	_fx.clear()
	_dust.clear()
	_fx_shown = 0
	_dust_shown = 0
	if _dust_mm != null:
		_dust_mm.visible_instance_count = 0
	if _fx_mm != null:
		_fx_mm.visible_instance_count = 0
	_h_upload_pending = true
	_b_upload_pending = true


func _process(delta: float) -> void:
	if n == 0:
		return
	_time += delta
	_since_upload += delta
	var t0: int = Time.get_ticks_usec() if profile_on else 0
	_spread_pools(delta)
	var t1: int = Time.get_ticks_usec() if profile_on else 0
	_update_grains(delta)
	var t2: int = Time.get_ticks_usec() if profile_on else 0
	_ambient_clock += delta
	if _ambient_clock >= AMBIENT_REFRESH_S:
		_ambient_clock = 0.0
		refresh_ambient()
	_sweep_blood()
	var t3: int = Time.get_ticks_usec() if profile_on else 0
	if _since_upload >= _upload_interval:
		flush()
	if profile_on:
		var t4: int = Time.get_ticks_usec()
		prof["pools"] = float(prof.get("pools", 0.0)) + float(t1 - t0) / 1000.0
		prof["grains"] = float(prof.get("grains", 0.0)) + float(t2 - t1) / 1000.0
		prof["sweep"] = float(prof.get("sweep", 0.0)) + float(t3 - t2) / 1000.0
		prof["flush"] = float(prof.get("flush", 0.0)) + float(t4 - t3) / 1000.0


## Warm shade fill from the scene's ambient energy (the engine's own ambient is off for the sand).
func refresh_ambient() -> void:
	var e: float = 0.5
	if is_inside_tree():
		var env: Environment = null
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			env = cam.environment
		if env == null:
			env = get_viewport().find_world_3d().environment
		if env != null:
			e = env.ambient_light_energy
	var c: Color = AMBIENT_TINT * (e * AMBIENT_GAIN)
	_material.set_shader_parameter("sand_ambient", Vector3(c.r, c.g, c.b))


func _update_grains(delta: float) -> void:
	_fx.step(minf(delta, 0.05))
	if _fx.count > 0 or _fx_shown > 0:
		var c: int = _fx.fill_buffer(_fx_buf, GRAIN_COLOR)
		if c > 0:
			_fx_mm.buffer = _fx_buf
		_fx_mm.visible_instance_count = c
		_fx_shown = c
	_dust.step(minf(delta, 0.05))
	if _dust.count > 0 or _dust_shown > 0:
		var dc: int = _dust.fill_buffer(_dust_buf, DUST_COLOR)
		if dc > 0:
			_dust_mm.buffer = _dust_buf
		_dust_mm.visible_instance_count = dc
		_dust_shown = dc


func _make_base_texture() -> ImageTexture:
	var nb: int = SandMap.base_size(extent)
	var im: Image = Image.create_from_data(nb, nb, false, Image.FORMAT_RGBAF, SandMap.base_to_rgba_bytes(_base, extent))
	im.convert(Image.FORMAT_RGBAH)
	return ImageTexture.create_from_image(im)


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
			_b_img.set_pixel(x, y, Color(_blood[i], _wet[i], _dry[i], float(_pal[i])))


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
	if _pools.is_empty():
		return
	_pool_acc += delta  # a step repaints every texel of every pool: do it at a lower rate on weak devices
	if _pool_acc < _pool_step_s:
		return
	delta = _pool_acc
	_pool_acc = 0.0
	var i: int = _pools.size() - 1
	while i >= 0:
		var p: Dictionary = _pools[i]
		var t: float = float(p["t"]) + delta
		p["t"] = t
		var k: float = clampf(t / float(p["dur"]), 0.0, 1.0)
		var r: float = lerpf(float(p["r0"]), float(p["r1"]), 1.0 - (1.0 - k) * (1.0 - k))
		# Repainting at the same radius changes nothing (max-blend): only repaint once the edge moved POOL_MIN_GROW texels.
		if k >= 1.0 or r - float(p["rp"]) >= POOL_MIN_GROW:
			p["rp"] = r
			var rect: Rect2i = SandMap.apply_blood(_blood, _wet, _dry, n, p["c"], r, float(p["s"]), float(p["seed"]), false, _pal, int(p["slot"]))
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
				_b_img.set_pixel(x, y, Color(b, nw, nd, float(_pal[i])))
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
	pm.albedo_color = Color(0.74, 0.58, 0.38)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = pm
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.42))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.6))
	for i in range(GfxQuality.pick_i(GfxQuality.SAND_PUFFS)):
		var p: CPUParticles3D = CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = GfxQuality.pick_i(GfxQuality.SAND_PUFF_AMOUNT)
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
	gm.vertex_color_use_as_albedo = true
	gm.albedo_color = Color(1.0, 1.0, 1.0)
	gm.roughness = 1.0
	gm.metallic_specular = 0.0
	gm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	box.material = gm
	_fx_mm = MultiMesh.new()
	_fx_mm.transform_format = MultiMesh.TRANSFORM_3D
	_fx_mm.use_colors = true
	_fx_mm.mesh = box
	_fx_mm.instance_count = _grain_capacity
	_fx_mm.visible_instance_count = 0
	_fx_buf.resize(_grain_capacity * SandFx.FLOATS_PER_GRAIN)
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Grains"
	mmi.multimesh = _fx_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-extent, -0.5, -extent), Vector3(extent * 2.0, 4.0, extent * 2.0))
	add_child(mmi)
	var dm: StandardMaterial3D = StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = gt
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.disable_receive_shadows = true
	var dq: QuadMesh = QuadMesh.new()
	dq.size = Vector2.ONE
	dq.material = dm
	_dust_mm = MultiMesh.new()
	_dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	_dust_mm.use_colors = true
	_dust_mm.mesh = dq
	_dust_mm.instance_count = _dust.capacity
	_dust_mm.visible_instance_count = 0
	_dust_buf.resize(_dust.capacity * SandDust.FLOATS_PER_SPRITE)
	var dmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	dmi.name = "Dust"
	dmi.multimesh = _dust_mm
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dmi.custom_aabb = AABB(Vector3(-extent, -0.5, -extent), Vector3(extent * 2.0, 6.0, extent * 2.0))
	add_child(dmi)


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
