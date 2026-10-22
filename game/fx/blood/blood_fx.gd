class_name BloodFx
extends Node3D
## Blood presentation: pooled CPU droplets (BloodSim), mist sprites (BloodMist), arterial spurts, wounds that
## drip, bloodied weapons, body stains. Never part of the fight state; keep it at the world origin.
## Wire up: add as a child, `sand = sand_surface`, `set_palette(side, palette)` and `track(fighter)` per fighter,
## `set_quality(0..2)`. Each fighter's blood has a palette slot (its side, 0 or 1): droplets, mist, decals, pools, the
## sand soak and body stains all carry the slot of the fighter it came from, so red and ichor can share the arena.

const MASK_BODIES: int = 6  ## physics layers 2 (bodies) and 3 (weapons)
const PALETTE_SLOTS: int = 2  ## one blood palette per fighter side
const STAIN_BUCKETS: int = 4
const STAIN_VARIANTS: int = 4
const MAX_WOUNDS: int = 40
const MAX_SPURTS: int = 14
const MAX_SPURT_EMIT: int = 40
const SPLAT_CELL: float = 0.07
const STUMP_PARENT: Dictionary = {
	"head": "torso", "upper_arm_l": "torso", "upper_arm_r": "torso",
	"forearm_l": "upper_arm_l", "forearm_r": "upper_arm_r",
	"thigh_l": "pelvis", "thigh_r": "pelvis", "shin_l": "thigh_l", "shin_r": "thigh_r",
}

class _BfSpurt extends RefCounted:
	var anchor: Node3D = null
	var lpos: Vector3 = Vector3.ZERO
	var ldir: Vector3 = Vector3.UP
	var wpos: Vector3 = Vector3.ZERO
	var wdir: Vector3 = Vector3.UP
	var last_origin: Vector3 = Vector3.ZERO
	var strength: float = 1.0
	var age: float = 0.0
	var phase: float = 0.0
	var tau: float = 14.0
	var dur: float = 40.0
	var spread: float = 0.12
	var v_min: float = 1.5
	var v_max: float = 7.5
	var max_rate: float = 300.0
	var r_min: float = 0.0022
	var r_max: float = 0.0062
	var stretch: float = 2.5
	var heart: bool = true
	var base_flow: float = 0.10
	var acc: float = 0.0
	var consumed: float = 0.0
	var blood_cb: Callable = Callable()
	var kind: String = "sever"
	var slot: int = 0
	var anchor_vel: Vector3 = Vector3.ZERO
	var prev_pulse: float = 0.0
	var fountain: bool = false  ## the beheading fountain: ignores the fighter's blood, several jets
	var streams: int = 1
	var share: float = 1.0  ## strength of this fountain relative to a neck (the head's trail is smaller)
	var up_bias: float = 0.6
	var stream_acc: PackedFloat32Array = PackedFloat32Array()
	var pool_slot: int = -1
	var pool_acc: float = 0.0
	var sand_acc: float = 0.0
	var sand_timer: float = 0.0
	var hold: float = -1.0  ## fountain full-strength seconds (negative: the beheading fountain's)
	var rate: float = -1.0  ## droplets per second per jet at full flow (negative: the beheading fountain's)
	var v_scale: float = 1.0  ## exit speed relative to the fountain's
	var pool_rate: float = -1.0  ## presentation litres per second poured on the sand (negative: the fountain's)
	var drop_scale: float = -1.0  ## droplet size multiplier (negative: the fountain's)

class _BfWound extends RefCounted:
	var anchor: Node3D = null
	var lpos: Vector3 = Vector3.ZERO
	var rate: float = 3.0
	var acc: float = 0.0
	var half_life: float = 14.0
	var last: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var blood_cb: Callable = Callable()
	var r_scale: float = 1.0
	var owner: Object = null
	var slot: int = 0

class _BfJet extends RefCounted:
	var target: Node3D = null
	var lpos: Vector3 = Vector3.ZERO
	var ldir: Vector3 = Vector3.UP
	var strength: float = 1.0
	var attacker: Object = null
	var age: float = 0.0
	var blood_cb: Callable = Callable()
	var slot: int = 0

class _BfTracked extends RefCounted:
	var fighter: Node = null
	var side: int = 0
	var slot: int = 0  ## palette slot of this fighter's own blood
	var weapon_slot: int = 0  ## palette slot of the blood on this fighter's weapon (the victim's)
	var weapon_blood: float = 0.0
	var last_tip: Vector3 = Vector3.ZERO
	var tip_vel: Vector3 = Vector3.ZERO
	var have_tip: bool = false
	var drip_acc: float = 0.0
	var fling_acc: float = 0.0
	var pool_acc: float = 0.0
	var pool_litres: float = 0.0
	var pool_slot: int = -1
	var pool_pos: Vector3 = Vector3.ZERO
	var trail_acc: float = 0.0

var sand: Node = null:  ## duck-typed SandSurface: add_blood(pos, radius, litres), height_at(pos)
	set(value):
		sand = value
		_height_fn = Callable()
		if sand != null and sand.has_method("height_at"):
			_height_fn = Callable(sand, "height_at")
		_push_sand_palettes()
var quality: int = 1
var palettes: Array = [BloodPalette.red(), BloodPalette.red()]  ## BloodPalette per slot (a fighter's side)
var profile_on: bool = false
var prof: Dictionary = {}
var auto_step: bool = true  ## false: the owner calls step(dt) (render scripts, tests)
var gravity: float = 9.8
var sim: BloodSim = null
var mist: BloodMist = null
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Last step's numbers for perf checks.
var stat_emitted: int = 0
var stat_rays: int = 0
var stat_splat_calls: int = 0

var _mm_drops: MultiMeshInstance3D = null
var _mm_mist: MultiMeshInstance3D = null
var _mm_decals: MultiMeshInstance3D = null
var decals: BloodDecals = null
var _clock: float = 0.0
var _stain_list: Array = []
var _sweep_cursor: int = 0
var _tracked: Array = []
var _by_side: Dictionary = {}
var _spurts: Array = []
var _wounds: Array = []
var _jets: Array = []
var _splat: Dictionary = {}
var _blood_cb: Callable = Callable()
var _ray_query: PhysicsRayQueryParameters3D = null
var _ray_cursor: int = 0
var _stain_mats: Array = []  ## [slot][bucket][variant] -> ShaderMaterial, fresh to dried
var _drop_mat: ShaderMaterial = null
var _mist_mat: ShaderMaterial = null
var _decal_mat: ShaderMaterial = null
var _stain_mesh: QuadMesh = null
var _height_fn: Callable = Callable()
var _reach: PackedVector3Array = PackedVector3Array()
var _free_this_step: int = 0
var guts: GutSim = null
var _mm_guts: MultiMeshInstance3D = null
var _gut_rope_cols: Array = []  ## [slot][variant] -> Color
var _gut_blob_cols: Array = []
var stat_gut_ms: float = 0.0


func _init() -> void:
	rng.seed = 1337


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build()
	set_process(auto_step)


func _build() -> void:
	if _mm_drops != null:
		return
	var drop_mat: ShaderMaterial = ShaderMaterial.new()
	drop_mat.shader = load("res://game/fx/blood/blood_drop.gdshader")
	var mist_mat: ShaderMaterial = ShaderMaterial.new()
	mist_mat.shader = load("res://game/fx/blood/blood_mist.gdshader")
	_drop_mat = drop_mat
	_mist_mat = mist_mat
	_mm_drops = MultiMeshInstance3D.new()
	_mm_drops.name = "Droplets"
	_mm_drops.material_override = drop_mat
	_mm_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm_drops.multimesh = _make_multimesh(BloodMesh.for_quality(quality), true)
	add_child(_mm_drops)
	_mm_mist = MultiMeshInstance3D.new()
	_mm_mist.name = "Mist"
	_mm_mist.material_override = mist_mat
	_mm_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	_mm_mist.multimesh = _make_multimesh(quad, false)
	add_child(_mm_mist)
	_stain_mesh = QuadMesh.new()
	_stain_mesh.size = Vector2.ONE
	var stain_shader: Shader = load("res://game/fx/blood/blood_stain.gdshader")
	for _s: int in PALETTE_SLOTS:
		var by_bucket: Array = []
		for b: int in STAIN_BUCKETS:
			var row: Array = []
			for i: int in STAIN_VARIANTS:
				var m: ShaderMaterial = ShaderMaterial.new()
				m.shader = stain_shader
				m.set_shader_parameter("seed", float(i) * 0.31)
				row.append(m)
			by_bucket.append(row)
		_stain_mats.append(by_bucket)
	var decal_mat: ShaderMaterial = ShaderMaterial.new()
	decal_mat.shader = load("res://game/fx/blood/blood_decal.gdshader")
	_decal_mat = decal_mat
	var dq: QuadMesh = QuadMesh.new()
	dq.size = Vector2.ONE
	dq.orientation = PlaneMesh.FACE_Y
	_mm_decals = MultiMeshInstance3D.new()
	_mm_decals.name = "Decals"
	_mm_decals.material_override = decal_mat
	_mm_decals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm_decals.multimesh = _make_multimesh(dq, false)
	add_child(_mm_decals)
	var gut_mat: StandardMaterial3D = StandardMaterial3D.new()
	gut_mat.vertex_color_use_as_albedo = true
	gut_mat.vertex_color_is_srgb = true
	gut_mat.roughness = 0.3
	gut_mat.metallic_specular = 0.35
	var gut_mesh: SphereMesh = SphereMesh.new()
	gut_mesh.radius = 1.0
	gut_mesh.height = 2.0
	gut_mesh.radial_segments = 10
	gut_mesh.rings = 6
	_mm_guts = MultiMeshInstance3D.new()
	_mm_guts.name = "Guts"
	_mm_guts.material_override = gut_mat
	_mm_guts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gmm: MultiMesh = MultiMesh.new()
	gmm.transform_format = MultiMesh.TRANSFORM_3D
	gmm.use_colors = true
	gmm.mesh = gut_mesh
	gmm.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 30, 80))
	_mm_guts.multimesh = gmm
	add_child(_mm_guts)
	guts = GutSim.new()
	sim = BloodSim.new(BloodMath.budget(quality))
	mist = BloodMist.new(BloodMath.mist_budget(quality))
	decals = BloodDecals.new(BloodMath.decal_budget(quality))
	_apply_sizes()
	for slot: int in PALETTE_SLOTS:
		_apply_palette(slot)


## Gives palette slot `slot` (a fighter's side, 0 or 1) its blood palette. Safe before or after the fighters are tracked.
func set_palette(slot: int, pal: BloodPalette) -> void:
	var k: int = clampi(slot, 0, PALETTE_SLOTS - 1)
	palettes[k] = pal if pal != null else BloodPalette.red()
	if _drop_mat != null:
		_apply_palette(k)
	_push_sand_palette(k)


func palette_of(slot: int) -> BloodPalette:
	return palettes[clampi(slot, 0, PALETTE_SLOTS - 1)] as BloodPalette


## Pushes palette `slot` into the droplet, mist, decal and stain materials.
func _apply_palette(slot: int) -> void:
	var pal: BloodPalette = palette_of(slot)
	var sfx: String = "" if slot == 0 else "1"
	_drop_mat.set_shader_parameter("blood_bright" + sfx, pal.drop_bright())
	_drop_mat.set_shader_parameter("blood_dark" + sfx, pal.drop_dark())
	_drop_mat.set_shader_parameter("blood_glow" + sfx, pal.emission)
	_mist_mat.set_shader_parameter("mist_color" + sfx, pal.mist_color())
	_decal_mat.set_shader_parameter("fresh_c" + str(slot), pal.decal_fresh())
	_decal_mat.set_shader_parameter("old_c" + str(slot), pal.decal_dried())
	_decal_mat.set_shader_parameter("glow" + str(slot), pal.emission)
	_apply_gut_colors(slot, pal)
	var by_bucket: Array = _stain_mats[slot]
	for b: int in STAIN_BUCKETS:
		var dry: float = (float(b) + 0.35) / float(STAIN_BUCKETS)
		for m: ShaderMaterial in (by_bucket[b] as Array):
			m.set_shader_parameter("blood_color", pal.stain_color(dry))
			m.set_shader_parameter("gloss", 1.0 - 0.75 * dry)
			m.set_shader_parameter("glow", (0.3 + pal.emission) * (1.0 - dry))


func _apply_gut_colors(slot: int, pal: BloodPalette) -> void:
	while _gut_rope_cols.size() < PALETTE_SLOTS:
		_gut_rope_cols.append([])
		_gut_blob_cols.append([])
	var ropes_c: Array = []
	var blobs_c: Array = []
	for i: int in 5:
		ropes_c.append(pal.gut_color(float(i) / 4.0))
		blobs_c.append(pal.organ_color(float(i) / 4.0))
	_gut_rope_cols[slot] = ropes_c
	_gut_blob_cols[slot] = blobs_c
	if guts != null:
		guts.dirty = true


func _push_sand_palette(slot: int) -> void:
	if sand != null and sand.has_method("set_blood_palette"):
		var pal: BloodPalette = palette_of(slot)
		sand.call("set_blood_palette", slot, pal.sand_fresh(), pal.sand_dried(), pal.emission)


func _push_sand_palettes() -> void:
	for slot: int in PALETTE_SLOTS:
		_push_sand_palette(slot)


func _make_multimesh(mesh: Mesh, drops: bool) -> MultiMesh:
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = drops
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 30, 80))
	return mm


func _apply_sizes() -> void:
	sim.resize(BloodMath.budget(quality))
	mist.resize(BloodMath.mist_budget(quality))
	decals.resize(BloodMath.decal_budget(quality))
	_mm_decals.multimesh.instance_count = 0
	_mm_decals.multimesh.instance_count = decals.capacity
	_mm_decals.multimesh.visible_instance_count = 0
	_mm_drops.multimesh.instance_count = 0
	_mm_drops.multimesh.instance_count = sim.capacity
	_mm_drops.multimesh.visible_instance_count = 0
	_mm_mist.multimesh.instance_count = 0
	_mm_mist.multimesh.instance_count = mist.capacity
	_mm_mist.multimesh.visible_instance_count = 0
	var tn: Tuning = Tuning.shared()
	var segs: int = BloodMath.gut_segs(tn.gut_segs, quality)
	guts.clear()
	guts.set_caps(BloodMath.gut_cap(tn.gut_max_ropes, quality), BloodMath.gut_cap(tn.gut_max_blobs, quality))
	_mm_guts.multimesh.instance_count = 0
	_mm_guts.multimesh.instance_count = guts.max_instances(segs_cap_for(tn))
	_mm_guts.multimesh.visible_instance_count = 0
	guts.reserve(_mm_guts.multimesh.instance_count)


## Longest rope any gut spill may use (points per string), for sizing the instance buffer.
func segs_cap_for(tn: Tuning) -> int:
	return maxi(BloodMath.gut_segs(tn.gut_segs, quality), 2)


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if sim != null:
		_apply_sizes()
	if _mm_drops != null:
		_mm_drops.multimesh.mesh = BloodMesh.for_quality(quality)


## Default source of remaining blood (litres) for spurts that have no fighter of their own.
func set_blood_source(source: Callable) -> void:
	_blood_cb = source


func track(f: Node) -> void:
	if f == null or _find_tracked(f) != null:
		return
	var t: _BfTracked = _BfTracked.new()
	t.fighter = f
	var side_v: Variant = f.get("side")
	t.side = int(side_v) if side_v != null else _tracked.size()
	t.slot = clampi(t.side, 0, PALETTE_SLOTS - 1)
	t.weapon_slot = t.slot
	_tracked.append(t)
	_by_side[t.side] = t
	if f.has_signal("hit"):
		f.connect("hit", on_hit.bind(f))
	if f.has_signal("gore"):
		f.connect("gore", on_gore.bind(f))


func untrack(f: Node) -> void:
	var t: _BfTracked = _find_tracked(f)
	if t == null:
		return
	if f.has_signal("hit") and f.is_connected("hit", on_hit.bind(f)):
		f.disconnect("hit", on_hit.bind(f))
	if f.has_signal("gore") and f.is_connected("gore", on_gore.bind(f)):
		f.disconnect("gore", on_gore.bind(f))
	_tracked.erase(t)
	_by_side.erase(t.side)


func clear() -> void:
	_spurts.clear()
	_wounds.clear()
	_jets.clear()
	_splat.clear()
	if guts != null:
		guts.clear()
	if sim != null:
		sim.count = 0
		mist.count = 0
		decals.clear()
	for mi: Variant in _stain_list:
		if is_instance_valid(mi):
			(mi as Node).queue_free()
	_stain_list.clear()


func live_droplets() -> int:
	return sim.count if sim != null else 0


func _find_tracked(f: Object) -> _BfTracked:
	for t: _BfTracked in _tracked:
		if t.fighter == f:
			return t
	return null


func _process(delta: float) -> void:
	step(delta)


# --- Events ---------------------------------------------------------------------------------------------

func on_hit(event: Dictionary, emitter: Object = null) -> void:
	var cut: float = float(event.get("cut", 0.0))
	var pierce: float = float(event.get("pierce", 0.0))
	var blunt: float = float(event.get("blunt", 0.0))
	var wound: float = cut + pierce + 0.3 * blunt
	if wound <= 0.0 and not event.has("cut") and not event.has("pierce"):
		wound = float(event.get("total", 0.0))
	if bool(event.get("glanced", false)):
		wound *= 0.4
	if wound < 0.25:
		return
	var contact: String = str(event.get("contact", "edge"))
	var point: Vector3 = event.get("point", Vector3.ZERO)
	var into: Vector3 = event.get("normal", Vector3.UP)
	into = into.normalized() if into.length_squared() > 0.0001 else Vector3.UP
	var out: Vector3 = -into
	var rel: Vector3 = event.get("rel_vel", Vector3.ZERO)
	var spd: float = rel.length()
	var sdir: Vector3 = rel / spd if spd > 0.2 else out
	var tgt: _BfTracked = _by_side.get(int(event.get("target", -1)))
	var tf: Object = tgt.fighter if tgt != null else emitter
	var vslot: int = _slot_of(tf)  ## the blood that flies is the wounded fighter's
	var n: int = roundi(BloodMath.spray_count(wound, contact) * BloodMath.rate_mult(quality))
	var edge: bool = contact == "edge"
	var arc: float = clampf(spd * 0.05, 0.05, 0.5) if edge else 0.03
	var side: Vector3 = sdir.cross(out)
	var big: float = clampf(wound / 40.0, 0.0, 1.0)  ## harder hits throw further and fatter
	for i: int in n:
		var p: Vector3 = point - sdir * (rng.randf() * arc) + _jit(0.012)
		var v: Vector3 = sdir * spd * rng.randf_range(0.10, 0.6) * (1.0 if edge else 0.4)
		v += out * rng.randf_range(0.9, 3.4 + 2.2 * big) * (1.0 if edge else 0.7)
		v += side * rng.randf_range(-0.9, 0.9) + _jit(0.9)
		var r: float = BloodMath.drop_radius(rng.randf(), 0.0028, 0.0085 + 0.003 * big)
		sim.emit(p, v, r, 3.0 if edge else 1.6, 5.0, rng.randf(), vslot)
	if edge and n > 6:  ## a fan of long arcing streaks along the swing, thrown off the blade
		for i: int in clampi(n / 5, 2, 24):
			var ang: float = rng.randf_range(-0.5, 0.5)
			var v2: Vector3 = (sdir.rotated(Vector3.UP, ang) * rng.randf_range(0.45, 1.0) * maxf(spd, 2.0)
					+ out * rng.randf_range(0.5, 2.0) + Vector3(0, rng.randf_range(0.5, 2.0), 0))
			sim.emit(point - sdir * rng.randf() * arc, v2, BloodMath.drop_radius(rng.randf(), 0.0035, 0.009),
					4.5, 5.0, rng.randf(), vslot)
	var puffs: int = clampi(3 + roundi(wound * 0.12), 3, 12) if contact != "flat" else 2
	for i: int in puffs:
		var mv: Vector3 = out * rng.randf_range(0.3, 1.5) + sdir * spd * 0.08 + _jit(0.4)
		mist.emit(point + _jit(0.03), mv, 0.05, rng.randf_range(0.16, 0.30), rng.randf_range(0.35, 0.75),
				0.5, rng.randf() * TAU, vslot)
	var atk: _BfTracked = _by_side.get(int(event.get("attacker", -1)))
	if atk != null:
		atk.weapon_blood = minf(atk.weapon_blood + clampf((cut + pierce) * 0.04 + blunt * 0.004, 0.0, 1.0), 1.0)
		atk.weapon_slot = vslot
		if cut + pierce > 1.0 or wound > 3.0:
			_coat_weapon(atk.fighter, wound, vslot)
	var node: Node3D = _part_node(tf, str(event.get("part", "")))
	if node != null:
		_hit_stains(node, point, wound, sdir, vslot)
	if node != null and cut + pierce > 1.5:
		var w: float = clampf(3.0 + wound * 0.5, 3.0, 30.0)
		add_wound(node, node.to_local(point), w, _blood_reader(tf), 1.0, vslot)
		_wound_owner_tag(tf)
	if node != null and (contact == "point" or pierce > cut * 1.5) and pierce > 4.0:
		var j: _BfJet = _BfJet.new()
		j.target = node
		j.lpos = node.to_local(point)
		j.ldir = node.global_transform.basis.inverse() * out
		j.strength = clampf(pierce / 25.0, 0.35, 1.4)
		j.attacker = atk.fighter if atk != null else null
		j.blood_cb = _blood_reader(tf)
		j.slot = vslot
		_jets.append(j)


func _wound_owner_tag(f: Object) -> void:
	if not _wounds.is_empty():
		(_wounds[_wounds.size() - 1] as _BfWound).owner = f


func on_gore(event: Dictionary, f: Object = null) -> void:
	var kind: String = str(event.get("kind", "bleed"))
	var part: String = str(event.get("part", ""))
	var point: Vector3 = event.get("point", Vector3.ZERO)
	var amount: float = float(event.get("amount", 1.0))
	var strength: float = clampf(amount if amount > 0.0 else 1.0, 0.5, 1.5)
	var nrm: Vector3 = event.get("normal", Vector3.UP)
	nrm = nrm.normalized() if nrm.length_squared() > 0.0001 else Vector3.UP
	var anchor_name: String = part
	if kind == "sever" or kind == "behead":
		anchor_name = str(STUMP_PARENT.get(part, part if part != "head" else "torso"))
	var anchor: Node3D = _part_node(f, anchor_name)
	var cb: Callable = _blood_reader(f)
	var gslot: int = _slot_of(f)
	if anchor != null:
		var outward: Vector3 = point - anchor.global_position
		if nrm.dot(outward) < 0.0:
			nrm = -nrm
	match kind:
		"bleed":
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 4.0 + strength * 6.0, cb, 1.0, gslot)
				_wound_owner_tag(f)
		"sever":
			start_spurt(anchor, point, nrm, strength, "sever", cb, gslot)
			_burst(point, nrm, 90, 2.0, 8.5, 0.55, 0.0070, gslot)
			_ground_splash(point, 24, gslot)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 22.0, cb, 1.3, gslot)
				_wound_owner_tag(f)
		"behead":
			start_spurt(anchor, point, (nrm + Vector3.UP * 0.35).normalized(), strength, "behead", cb, gslot)
			var head: Node3D = _part_node(f, "head")
			if head != null and Tuning.shared().fountain_head_share > 0.0:
				var hdir: Vector3 = -nrm  ## the head's cut face looks back at the neck
				start_spurt(head, point, hdir, strength, "fountain_head", Callable(), gslot)
			_burst(point, nrm, 130, 2.5, 9.5, 0.55, 0.0078, gslot)
			_ground_splash(point, 34, gslot)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 26.0, cb, 1.4, gslot)
				_wound_owner_tag(f)
		"gut":
			start_spurt(anchor, point, nrm, strength, "gut", cb, gslot)
			_spill_guts(anchor, point, nrm, gslot, 1.0)
			_burst(point, nrm, 170, 0.8, 5.5, 0.9, 0.0095, gslot)
			_ground_splash(point, 48, gslot)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 30.0, cb, 1.5, gslot)
				_wound_owner_tag(f)
		"run_through":
			var exit_pt: Vector3 = point - nrm * Tuning.shared().gut_exit_depth
			start_spurt(anchor, point, nrm, strength, "gut", cb, gslot)
			if Tuning.shared().gut_exit_streams > 0.0:
				start_spurt(anchor, exit_pt, -nrm, strength, "gut_exit", cb, gslot)
			_spill_guts(anchor, point, nrm, gslot, 1.0)
			_spill_guts(anchor, exit_pt, -nrm, gslot, 0.0)  ## a few chunks fly out of the back as well
			_burst(point, nrm, 150, 1.0, 6.0, 0.7, 0.012, gslot)
			_burst(exit_pt, -nrm, 150, 1.5, 8.0, 0.5, 0.012, gslot)
			_ground_splash(point, 40, gslot)
			_ground_splash(exit_pt, 40, gslot)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 26.0, cb, 1.4, gslot)
				_wound_owner_tag(f)
		"pummel":
			var pup: Vector3 = (nrm + Vector3.UP * 0.6).normalized()
			_burst(point, pup, 70, 1.2, 5.0, 0.9, 0.007, gslot)
			_ground_splash(point, 16, gslot)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 20.0, cb, 1.3, gslot)
				_wound_owner_tag(f)
				_hit_stains(anchor, point, 30.0, Vector3.DOWN, gslot)
		"skull_crush":
			var up: Vector3 = (nrm + Vector3.UP * 0.8).normalized()
			_burst(point, up, 120, 1.5, 7.0, 1.0, 0.0075, gslot)
			_ground_splash(point, 22, gslot)
			start_spurt(anchor, point, up, strength * 0.8, "jet", cb, gslot)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 24.0, cb, 1.4, gslot)
				_wound_owner_tag(f)
			if anchor != null:
				_hit_stains(anchor, point, 40.0, Vector3.DOWN, gslot)


## Public: start an arterial spurt. anchor may be null (then world point and dir are used as they are).
func start_spurt(anchor: Node3D, point: Vector3, dir: Vector3, strength: float, kind: String,
		blood_cb: Callable = Callable(), slot: int = 0) -> void:
	var s: _BfSpurt = _BfSpurt.new()
	s.kind = kind
	s.slot = slot
	s.strength = strength
	s.anchor = anchor
	if anchor != null:
		s.lpos = anchor.to_local(point)
		s.ldir = anchor.global_transform.basis.inverse() * dir.normalized()
	else:
		s.lpos = point
		s.ldir = dir.normalized()
	s.blood_cb = blood_cb
	s.phase = rng.randf() * 0.2
	match kind:
		"behead", "fountain_head":
			s.fountain = true
			var tn: Tuning = Tuning.shared()
			var head_trail: bool = kind == "fountain_head"
			s.streams = 1 if head_trail else BloodMath.fountain_streams(tn.fountain_streams, quality)
			s.share = tn.fountain_head_share if head_trail else 1.0
			s.up_bias = tn.fountain_up_bias * (0.4 if head_trail else 1.0)
			s.dur = tn.fountain_dur * (0.5 if head_trail else 1.0)
			s.stream_acc.resize(s.streams)
			s.phase = rng.randf()
			s.r_min = 0.0026
			s.r_max = 0.0075
			s.stretch = 3.0
		"gut", "gut_exit":
			var gt: Tuning = Tuning.shared()
			var is_exit: bool = kind == "gut_exit"
			s.fountain = true
			s.streams = BloodMath.fountain_streams(gt.gut_exit_streams if is_exit else gt.gut_streams, quality)
			s.up_bias = gt.gut_up_bias
			s.dur = gt.gut_dur
			s.hold = gt.gut_hold
			s.rate = gt.gut_rate
			s.v_scale = gt.gut_v_scale * (gt.gut_exit_v_scale if is_exit else 1.0)
			s.pool_rate = gt.gut_pool * (0.6 if is_exit else 1.0)
			s.drop_scale = gt.fountain_drop_scale * 0.9
			s.stream_acc.resize(s.streams)
			s.phase = rng.randf()
			s.r_min = 0.0028
			s.r_max = 0.0078
			s.stretch = 2.6
		"jet":
			s.tau = 1.4
			s.dur = 3.5
			s.heart = false
			s.max_rate = 700.0
			s.v_min = 3.5
			s.v_max = 8.5
			s.spread = 0.07
			s.r_min = 0.0026
			s.r_max = 0.0065
			s.stretch = 4.5
			s.base_flow = 1.0
		_:
			s.tau = 16.0
			s.dur = 45.0
			s.max_rate = 1300.0
			s.v_min = 1.5
			s.v_max = 8.5
			s.base_flow = 0.12
			s.spread = 0.1
			s.r_min = 0.0026
			s.r_max = 0.0072
			s.stretch = 4.5
	s.last_origin = point
	_spurts.append(s)
	if _spurts.size() > MAX_SPURTS:
		_spurts.pop_front()


func add_wound(anchor: Node3D, local_pos: Vector3, drips_per_sec: float, blood_cb: Callable = Callable(),
		r_scale: float = 1.0, slot: int = 0) -> void:
	var w: _BfWound = _BfWound.new()
	w.slot = slot
	w.anchor = anchor
	w.lpos = local_pos
	w.rate = drips_per_sec
	w.blood_cb = blood_cb
	w.r_scale = r_scale
	w.last = anchor.to_global(local_pos)
	_wounds.append(w)
	if _wounds.size() > MAX_WOUNDS:
		_wounds.pop_front()


# --- Step -----------------------------------------------------------------------------------------------

func step(dt_in: float) -> void:
	if sim == null:
		_build()
	var dt: float = clampf(dt_in, 0.0, 0.05)
	stat_emitted = 0
	if dt <= 0.0:
		return
	gravity = Tuning.shared().gravity
	var before: int = sim.count
	var t0: int = _mark(0)
	_update_tracked(dt)
	_update_jets(dt)
	_update_spurts(dt)
	_update_wounds(dt)
	_update_guts(dt)
	_refresh_reach()
	var t1: int = _mark(t0, "emit")
	var grace: float = 0.05
	var r2: float = 1.9 * 1.9
	sim.step(dt, gravity, _height_fn, _reach, r2, grace)
	var t2: int = _mark(t1, "sim")
	_process_rays()
	_process_impacts()
	var t3: int = _mark(t2, "rays")
	sim.compact()
	var ta: int = _mark(t3, "compact")
	mist.step(dt)
	var tb: int = _mark(ta, "mist")
	_flush_splats()
	var tc: int = _mark(tb, "flush_splats")
	decals.step(dt)
	var t4: int = _mark(tc, "decals")
	_clock += dt
	_sweep_stains()
	stat_emitted = maxi(sim.count - before, 0)
	var t5: int = _mark(t4, "stains")
	_upload()
	_mark(t5, "upload")


## Profiling aid for tests/perf: with profile_on, step() adds each section's milliseconds to `prof`.
func _mark(since: int, key: String = "") -> int:
	if not profile_on:
		return 0
	var now: int = Time.get_ticks_usec()
	if key != "":
		prof[key] = float(prof.get(key, 0.0)) + float(now - since) / 1000.0
	return now


func _upload() -> void:
	var mm: MultiMesh = _mm_drops.multimesh
	mm.buffer = sim.buf
	mm.visible_instance_count = sim.count
	var mm2: MultiMesh = _mm_mist.multimesh
	mm2.buffer = mist.buf
	mm2.visible_instance_count = mist.count
	var mm3: MultiMesh = _mm_decals.multimesh
	mm3.buffer = decals.buf
	mm3.visible_instance_count = decals.count
	if guts.dirty:
		var gn: int = guts.write(_gut_rope_cols, _gut_blob_cols)
		var mm4: MultiMesh = _mm_guts.multimesh
		mm4.buffer = guts.buf
		mm4.visible_instance_count = gn


func _refresh_reach() -> void:
	_reach.clear()
	for t: _BfTracked in _tracked:
		var f: Node3D = t.fighter as Node3D
		if f == null or not is_instance_valid(f):
			continue
		var c: Node3D = _part_node(f, "pelvis")
		_reach.append((c if c != null else f).global_position + Vector3(0, 0.6, 0))


func _update_spurts(dt: float) -> void:
	var i: int = _spurts.size() - 1
	var full: float = BloodMath.FULL_BLOOD
	var death: float = Tuning.shared().blood_death
	while i >= 0:
		var s: _BfSpurt = _spurts[i]
		i -= 1
		s.age += dt
		if s.age > s.dur:
			_spurts.erase(s)
			continue
		var origin: Vector3 = s.lpos
		var dir: Vector3 = s.ldir
		if s.anchor != null:
			if not is_instance_valid(s.anchor):
				_spurts.erase(s)
				continue
			var xf: Transform3D = s.anchor.global_transform
			origin = xf * s.lpos
			dir = (xf.basis * s.ldir).normalized()
			s.anchor_vel = s.anchor_vel.lerp((origin - s.last_origin) / dt, 0.5)
		if s.fountain:
			_emit_fountain(s, origin, dir, dt)
			s.last_origin = origin
			continue
		var blood: float = _read_blood(s.blood_cb, full - s.consumed)
		var res: float = BloodMath.reserve(blood, full, death)
		var press: float = BloodMath.pressure(res)
		var pulse_v: float = 1.0
		if s.heart:
			s.phase += dt * BloodMath.heart_rate_bpm(res) / 60.0
			pulse_v = BloodMath.pulse(s.phase)
			if pulse_v > 0.55 and s.prev_pulse <= 0.55 and press > 0.1:
				mist.emit(origin, dir * 0.8 * press, 0.04, 0.12 + 0.12 * press, 0.4, 0.3, rng.randf() * TAU, s.slot)
			s.prev_pulse = pulse_v
		var gush: float = 1.0 + 1.4 * exp(-s.age / 0.6)  ## the first second is a hard gush
		var flow: float = s.strength * press * exp(-s.age / s.tau) * (s.base_flow + (1.0 - s.base_flow) * pulse_v) * gush
		if s.heart and press <= 0.0:
			_spurts.erase(s)
			continue
		var speed: float = BloodMath.spurt_speed(flow * 0.85, s.v_min, s.v_max)
		var want: float = flow * s.max_rate * BloodMath.rate_mult(quality) * dt + s.acc
		var n: int = mini(int(want), MAX_SPURT_EMIT)
		s.acc = want - float(int(want))
		s.consumed += float(n) * 0.00002 * BloodMath.VOLUME_BOOST * 4.0 if not s.blood_cb.is_valid() else 0.0
		for j: int in n:
			var frac: float = (float(j) + rng.randf()) / float(maxi(n, 1))
			var ta: float = dt * (1.0 - frac)
			var d: Vector3 = BloodMath.cone_dir(dir, s.spread * (1.0 + 0.8 * (1.0 - flow)), rng.randf(), rng.randf())
			var v: Vector3 = d * speed * rng.randf_range(0.88, 1.12) + s.anchor_vel * 0.8
			var p: Vector3 = s.last_origin.lerp(origin, frac) + v * ta + Vector3(0, -0.5 * gravity * ta * ta, 0)
			var r: float = BloodMath.drop_radius(rng.randf(), s.r_min, s.r_max) * (0.75 + 0.45 * minf(flow, 1.0))
			sim.emit(p, v, r, s.stretch, 6.0, rng.randf(), s.slot)
		s.last_origin = origin


## The beheading fountain. Presentation only: it never reads or changes the fighter's blood. Several jets leave the
## neck (or the head's cut face), aimed mostly up, swaying and circling, pulsing like a heartbeat and tapering off.
func _emit_fountain(s: _BfSpurt, origin: Vector3, axis: Vector3, dt: float) -> void:
	var tn: Tuning = Tuning.shared()
	var hold: float = tn.fountain_hold if s.hold < 0.0 else s.hold
	var env: float = BloodMath.fountain_envelope(s.age, hold, s.dur)
	if env <= 0.0:
		_spurts.erase(s)
		return
	s.phase += dt * tn.fountain_bpm / 60.0
	var gush: float = 1.0 + tn.fountain_gush * exp(-s.age / 0.7)
	var beat: float = BloodMath.fountain_pulse(s.phase, tn.fountain_pulse_floor)
	var flow: float = s.strength * s.share * env * beat
	var fresh: bool = beat > 0.6 and s.prev_pulse <= 0.6
	s.prev_pulse = beat
	var room: float = BloodMath.fountain_headroom(sim.free_slots(), sim.capacity, tn.fountain_headroom)
	var per_jet_cap: int = maxi(int(tn.fountain_emit_cap / float(s.streams)), 1)
	var rate: float = (tn.fountain_rate if s.rate < 0.0 else s.rate) * BloodMath.rate_mult(quality) * room
	var speed: float = BloodMath.spurt_speed((beat - tn.fountain_pulse_floor) / maxf(1.0 - tn.fountain_pulse_floor, 0.01) * minf(env + 0.15, 1.0), tn.fountain_v_min, tn.fountain_v_max) * s.v_scale
	var dscale: float = tn.fountain_drop_scale if s.drop_scale < 0.0 else s.drop_scale
	for k: int in s.streams:
		var jet_dir: Vector3 = BloodMath.fountain_dir(axis, s.up_bias, tn.fountain_fan, tn.fountain_wobble, tn.fountain_swirl,
				k, s.streams, s.age)
		var drift: float = tn.fountain_drift
		if drift > 0.0:
			var kf: float = float(k)
			jet_dir = (jet_dir + Vector3(sin(s.age * 5.3 + kf * 1.9) + 0.6 * sin(s.age * 11.7 + kf * 4.1),
					0.5 * sin(s.age * 4.1 + kf * 2.7), sin(s.age * 6.7 + kf * 3.3) + 0.6 * sin(s.age * 13.1 + kf)) * 0.11 * drift).normalized()
		var mist_n: float = flow * tn.fountain_fine_mist * BloodMath.rate_mult(quality) * room * dt
		for m: int in int(mist_n + rng.randf()):
			mist.emit(origin + jet_dir * rng.randf_range(0.05, 0.6), jet_dir * rng.randf_range(2.0, 5.5) + _jit(0.9 * drift + 0.2),
					0.02, rng.randf_range(0.12, 0.26), rng.randf_range(0.4, 0.9), 0.22, rng.randf() * TAU, s.slot)
		if fresh and room > 0.0:
			for m: int in int(tn.fountain_mist):
				mist.emit(origin + jet_dir * 0.1, jet_dir * rng.randf_range(1.0, 2.4) + _jit(0.5), 0.06,
						rng.randf_range(0.35, 0.6), rng.randf_range(0.7, 1.2), 0.4, rng.randf() * TAU, s.slot)
		var want: float = flow * gush * rate * dt + s.stream_acc[k]
		var n: int = mini(int(want), per_jet_cap)
		s.stream_acc[k] = minf(want - float(int(want)), 1.0)
		for j: int in n:
			var frac: float = (float(j) + rng.randf()) / float(maxi(n, 1))
			var ta: float = dt * (1.0 - frac)
			var vm: Vector3 = BloodMath.fountain_drop_mult(rng.randf(), rng.randf(), rng.randf(), tn.fountain_size_var, tn.fountain_gout)
			var d: Vector3 = BloodMath.cone_dir(jet_dir, (0.05 + 0.05 * (1.0 - minf(flow, 1.0))) * (1.0 + 1.2 * drift), rng.randf(), rng.randf())
			var v: Vector3 = d * speed * vm.y * rng.randf_range(0.9, 1.1) + s.anchor_vel * 0.8 + _jit(0.35 * drift)
			var p: Vector3 = s.last_origin.lerp(origin, frac) + v * ta + Vector3(0, -0.5 * gravity * ta * ta, 0)
			var r: float = BloodMath.drop_radius(rng.randf(), s.r_min, s.r_max) * dscale * (0.7 + 0.5 * minf(flow, 1.0)) * vm.x
			sim.emit(p, v, r, s.stretch, 6.0, rng.randf(), s.slot)
	# Pools on the sand under the body, poured while the fountain runs (a head's trail makes none).
	var pool_rate: float = tn.fountain_pool if s.pool_rate < 0.0 else s.pool_rate
	if s.share >= 1.0 and pool_rate > 0.0:
		var ground: Vector3 = Vector3(origin.x, _ground_y(origin) + 0.006, origin.z)
		var l: float = pool_rate * env * (0.5 + 0.5 * beat) * dt * BloodMath.rate_mult(quality)
		s.pool_acc += l
		s.sand_acc += l
		s.sand_timer += dt
		if s.pool_acc >= 0.01:
			s.pool_slot = decals.feed(s.pool_slot, ground, s.pool_acc, rng.randf(), s.slot)
			s.pool_acc = 0.0
		if s.sand_timer >= 0.25 and sand != null and sand.has_method("add_blood"):
			var at: Vector3 = ground + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
			sand.call("add_blood", at, BloodMath.splat_radius(s.sand_acc), s.sand_acc, s.slot)
			s.sand_acc = 0.0
			s.sand_timer = 0.0


## Spills guts from a wound: `rope_share` of the normal number of intestine strings (0 for chunks only) plus organ
## chunks. Presentation only; they hang from the anchor part at the wound and then lie on the sand.
func _spill_guts(anchor: Node3D, point: Vector3, nrm: Vector3, slot: int, rope_share: float) -> void:
	var tn: Tuning = Tuning.shared()
	var n_ropes: int = roundi(tn.gut_ropes * rope_share * BloodMath.gut_mult(quality))
	var segs: int = BloodMath.gut_segs(tn.gut_segs, quality)
	var side: Vector3 = nrm.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	for i: int in n_ropes:
		var off: Vector3 = side * rng.randf_range(-0.1, 0.1) + Vector3(0, rng.randf_range(-0.05, 0.05), 0)
		var lean: float = (float(i) + 0.5) / float(maxi(n_ropes, 1)) * 2.0 - 1.0  ## strings fan out left to right
		var dir: Vector3 = (nrm + Vector3.DOWN * rng.randf_range(0.1, 0.5) + side * (lean * 1.6 + rng.randf_range(-0.3, 0.3))).normalized()
		var r: GutRope = GutRope.new()
		r.setup(segs, tn.gut_seg_len * rng.randf_range(0.7, 1.3), tn.gut_radius * rng.randf_range(0.85, 1.15),
				tn.gut_pay_time * rng.randf_range(0.8, 1.2), point + off, dir, tn.gut_eject * rng.randf_range(0.7, 1.2),
				tn.gut_push, slot, rng.randf(), side * (lean * tn.gut_sway))
		if anchor != null:
			r.set_meta("node", anchor)
			r.set_meta("lpos", anchor.to_local(point + off))
		guts.add_rope(r)
	var n_blobs: int = roundi(tn.gut_blobs * BloodMath.gut_mult(quality) * (1.0 if rope_share > 0.0 else 0.5))
	for j: int in n_blobs:
		var v: Vector3 = nrm * tn.gut_eject * rng.randf_range(0.5, 1.6) + Vector3(0, rng.randf_range(0.6, 2.2), 0) \
				+ side * rng.randf_range(-1.0, 1.0)
		guts.add_blob(point + _jit(0.04), v, tn.gut_blob_radius * rng.randf_range(0.7, 1.3), rng.randf() * TAU, slot, rng.randf())


func _update_guts(dt: float) -> void:
	if guts == null:
		return
	var t0: int = Time.get_ticks_usec() if profile_on else 0
	var tn: Tuning = Tuning.shared()
	var anchors: PackedVector3Array = PackedVector3Array()
	for r: GutRope in guts.ropes:
		var node: Variant = r.get_meta("node", null)
		if node is Node3D and is_instance_valid(node):
			anchors.append((node as Node3D).to_global(r.get_meta("lpos") as Vector3))
		else:
			anchors.append(r.anchor)
	guts.step(dt, gravity, anchors, _height_fn, tn.gut_damp, tn.gut_friction, tn.gut_sleep_speed, tn.gut_sleep_time,
			tn.gut_bounce)
	for r: GutRope in guts.ropes:  # blood dripping off the hanging tips
		if r.asleep or r.age > tn.gut_drip_time or tn.gut_drip <= 0.0:
			continue
		var want: float = tn.gut_drip * BloodMath.rate_mult(quality) * dt * (1.0 - r.age / maxf(tn.gut_drip_time, 0.1))
		if rng.randf() < want:
			sim.emit(r.pos[r.n - 1] + _jit(0.02), Vector3(0, -0.3, 0) + _jit(0.25),
					rng.randf_range(0.004, 0.009), 1.2, 5.0, rng.randf(), r.slot)
	var l: float = tn.gut_smear
	for i: int in guts.touches.size():  # where a string or chunk first lands: a smear and a pool on the sand
		var at: Vector3 = guts.touches[i]
		var sl: int = guts.touch_slots[i]
		if l <= 0.0:
			break
		var ground: Vector3 = Vector3(at.x, _ground_y(at) + 0.006, at.z)
		decals.add(ground, l, rng.randf(), sl)
		if sand != null and sand.has_method("add_blood"):
			sand.call("add_blood", ground, BloodMath.splat_radius(l * 1.5), l, sl)
		for k: int in roundi(10.0 * BloodMath.rate_mult(quality)):
			sim.emit(at + Vector3(0, 0.05, 0), Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(0.8, 2.2), rng.randf_range(-1.2, 1.2)),
					BloodMath.drop_radius(rng.randf(), 0.0035, 0.008), 2.0, 5.0, rng.randf(), sl)
	if profile_on:
		stat_gut_ms += float(Time.get_ticks_usec() - t0) / 1000.0


func _update_wounds(dt: float) -> void:
	var i: int = _wounds.size() - 1
	var full: float = BloodMath.FULL_BLOOD
	var death: float = Tuning.shared().blood_death
	while i >= 0:
		var w: _BfWound = _wounds[i]
		i -= 1
		if w.anchor == null or not is_instance_valid(w.anchor):
			_wounds.erase(w)
			continue
		var pos: Vector3 = w.anchor.to_global(w.lpos)
		w.vel = w.vel.lerp((pos - w.last) / dt, 0.4)
		w.last = pos
		var blood: float = _read_blood(w.blood_cb, full)
		var press: float = BloodMath.pressure(BloodMath.reserve(blood, full, death))
		w.rate *= pow(0.5, dt / w.half_life)
		var eff: float = w.rate
		if w.owner != null and is_instance_valid(w.owner):  ## a fighter who is still bleeding keeps dripping
			var hv: Variant = w.owner.get("health")
			if hv is Object:
				var br: Variant = (hv as Object).get("bleed_rate")
				if br != null:
					eff = maxf(eff, minf(float(br) * 14.0, 12.0))
		if eff < 0.3:
			_wounds.erase(w)
			continue
		w.acc += eff * press * BloodMath.rate_mult(quality) * dt
		while w.acc >= 1.0:
			w.acc -= 1.0
			var v: Vector3 = w.vel * 0.7 + _jit(0.15)
			var r: float = rng.randf_range(0.0042, 0.0080) * w.r_scale
			sim.emit(pos + _jit(0.012), v, r, 0.9, 5.0, rng.randf(), w.slot)
			if w.vel.length() > 1.5 and rng.randf() < 0.5:  ## a moving wound flings a streak behind it
				sim.emit(pos + _jit(0.01), w.vel * rng.randf_range(0.3, 0.6) + _jit(0.5), r * 0.8, 3.5, 3.0,
						rng.randf(), w.slot)


func _update_tracked(dt: float) -> void:
	for t: _BfTracked in _tracked:
		var f: Object = t.fighter
		if f == null or not is_instance_valid(f):
			continue
		_feed_pool(t, dt)
		t.weapon_blood = maxf(t.weapon_blood - dt * 0.003, 0.0)
		if t.weapon_blood < 0.015 and _jets.is_empty():
			t.have_tip = false
			continue
		var tip: Vector3 = Vector3.ZERO
		var hand: Vector3 = Vector3.ZERO
		if f.has_method("debug_frame"):
			var d: Dictionary = f.call("debug_frame")
			tip = d.get("tip_pos", Vector3.ZERO)
			hand = d.get("hand_pos", tip)
		if t.have_tip:
			t.tip_vel = t.tip_vel.lerp((tip - t.last_tip) / dt, 0.6)
		t.last_tip = tip
		t.have_tip = true
		if t.weapon_blood < 0.015:
			continue
		var spd: float = t.tip_vel.length()
		var wb: float = t.weapon_blood
		if spd > 2.5:
			t.fling_acc += wb * spd * 7.0 * BloodMath.rate_mult(quality) * dt
			while t.fling_acc >= 1.0:
				t.fling_acc -= 1.0
				var p: Vector3 = hand.lerp(tip, rng.randf_range(0.35, 1.0))
				var v: Vector3 = t.tip_vel * rng.randf_range(0.25, 0.7) + _jit(0.8)
				sim.emit(p, v, rng.randf_range(0.0018, 0.0055), 2.5, 4.0, rng.randf(), t.weapon_slot)
				t.weapon_blood = maxf(t.weapon_blood - 0.004, 0.0)
		elif spd < 1.8:
			t.drip_acc += wb * 4.0 * dt
			if t.drip_acc >= 1.0:
				t.drip_acc -= 1.0
				sim.emit(tip + _jit(0.01), t.tip_vel * 0.3 + _jit(0.05), rng.randf_range(0.0030, 0.0046), 0.6,
						4.0, rng.randf(), t.weapon_slot)
				t.weapon_blood = maxf(t.weapon_blood - 0.006, 0.0)


## Pools spread under a bleeding fighter who is down (or dead). The litres are a presentation number, scaled
## up so a pool reads; they are never read back by the fight.
func _feed_pool(t: _BfTracked, dt: float) -> void:
	var f: Object = t.fighter
	var hv: Variant = f.get("health")
	if not (hv is Object):
		return
	var h: Object = hv as Object
	var br: float = float(h.get("bleed_rate")) if h.get("bleed_rate") != null else 0.0
	var dead: bool = bool(h.get("dead")) if h.get("dead") != null else false
	var core: Node3D = _part_node(f, "torso")
	if core == null:
		core = _part_node(f, "pelvis")
	if core == null:
		return
	var low: bool = core.global_position.y < 0.55
	var ooze: float = br + (0.05 if dead else 0.0)
	if not low or ooze <= 0.0 or t.pool_litres > 7.0:
		return
	t.pool_acc += ooze * BloodMath.POOL_VISUAL_MULT * dt
	if t.pool_acc < 0.004:
		return
	var l: float = t.pool_acc
	t.pool_acc = 0.0
	t.pool_litres += l
	var p: Vector3 = core.global_position + Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
	if t.pool_slot < 0:
		t.pool_pos = Vector3(p.x, _ground_y(p) + 0.006, p.z)
	t.pool_slot = decals.feed(t.pool_slot, t.pool_pos, l, rng.randf(), t.slot)


func _ground_y(p: Vector3) -> float:
	if _height_fn.is_valid():
		return float(_height_fn.call(Vector3(p.x, 0.0, p.z)))
	return 0.0


func _ground_splash(point: Vector3, count: int, slot: int = 0) -> void:
	var n: int = roundi(count * BloodMath.rate_mult(quality))
	for i: int in n:
		var d: Vector3 = BloodMath.cone_dir(Vector3.DOWN, 1.15, rng.randf(), rng.randf())
		sim.emit(point + _jit(0.03), d * rng.randf_range(1.2, 5.0), BloodMath.drop_radius(rng.randf(), 0.003, 0.010),
				3.0, 4.0, rng.randf(), slot)


func _update_jets(dt: float) -> void:
	var i: int = _jets.size() - 1
	while i >= 0:
		var j: _BfJet = _jets[i]
		i -= 1
		j.age += dt
		if j.target == null or not is_instance_valid(j.target) or j.age > 2.5:
			_jets.erase(j)
			continue
		var wpos: Vector3 = j.target.to_global(j.lpos)
		var withdrawn: bool = false
		var t: _BfTracked = _find_tracked(j.attacker) if j.attacker != null else null
		if t != null and t.have_tip and j.age > 0.08:
			withdrawn = t.last_tip.distance_to(wpos) > 0.28
		elif t == null or not t.have_tip:
			withdrawn = j.age > 0.3
		if withdrawn:
			var dir: Vector3 = (j.target.global_transform.basis * j.ldir).normalized()
			start_spurt(j.target, wpos, dir, j.strength, "jet", j.blood_cb, j.slot)
			_burst(wpos, dir, 14, 1.0, 4.0, 0.4, 0.006, j.slot)
			_jets.erase(j)


# --- Droplet collisions ---------------------------------------------------------------------------------

func _process_rays() -> void:
	stat_rays = 0
	var n: int = sim.near_idx.size()
	if n == 0 or not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters3D.new()
		_ray_query.collision_mask = MASK_BODIES
		_ray_query.collide_with_areas = false
	var budget: int = mini(n, BloodMath.ray_budget(quality))
	for k: int in budget:
		var idx: int = (k + _ray_cursor) % n
		var i: int = sim.near_idx[idx]
		if sim.dead[i] != 0:
			continue
		var p: Vector3 = sim.pos_of(i)
		_ray_query.from = sim.near_from[idx]
		_ray_query.to = p
		var res: Dictionary = space.intersect_ray(_ray_query)
		stat_rays += 1
		if res.is_empty():
			continue
		sim.kill(i)
		var col: Object = res.get("collider")
		if col is Node3D:
			_stain(col as Node3D, res["position"], res["normal"], sim.vel_of(i), sim.radius_of(i), sim.slot_of(i))
		if sim.vel_of(i).length() > 5.0 and rng.randf() < 0.3:
			mist.emit(res["position"], res["normal"] * 0.5, 0.03, 0.10, 0.35, 0.25, rng.randf() * TAU, sim.slot_of(i))
	_ray_cursor = (_ray_cursor + budget) % maxi(n, 1)


## A fresh stain quad on `body` (a ring per body, oldest reused). Registered for ageing.
func _new_stain(body: Node3D, slot: int = 0) -> MeshInstance3D:
	var ring: Array = body.get_meta("bfx_stains", []) as Array
	var next: int = int(body.get_meta("bfx_next", 0))
	var cap: int = BloodMath.stain_budget(quality)
	var mi: MeshInstance3D = null
	if ring.size() < cap:
		mi = MeshInstance3D.new()
		mi.mesh = _stain_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		ring.append(mi)
		body.set_meta("bfx_stains", ring)
		_stain_list.append(mi)
	else:
		mi = ring[next % ring.size()] as MeshInstance3D
		body.set_meta("bfx_next", next + 1)
		if mi == null or not is_instance_valid(mi):
			return null
	var variant: int = rng.randi() % STAIN_VARIANTS
	mi.set_meta("born", _clock)
	mi.set_meta("bk", 0)
	mi.set_meta("var", variant)
	mi.set_meta("slot", slot)
	mi.material_override = ((_stain_mats[slot] as Array)[0] as Array)[variant]
	return mi


## Ages stains: swaps fresh bright red for drying and dried materials, a few per frame.
func _sweep_stains() -> void:
	var n: int = _stain_list.size()
	if n == 0:
		return
	for k: int in mini(n, 24):
		var i: int = (_sweep_cursor + k) % n
		var mi: MeshInstance3D = _stain_list[i] as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			_stain_list[i] = null
			continue
		var bk: int = BloodMath.stain_bucket(_clock - float(mi.get_meta("born", 0.0)), STAIN_BUCKETS)
		if bk != int(mi.get_meta("bk", 0)):
			mi.set_meta("bk", bk)
			mi.material_override = ((_stain_mats[int(mi.get_meta("slot", 0))] as Array)[bk] as Array)[int(mi.get_meta("var", 0))]
	_sweep_cursor = (_sweep_cursor + 24) % n
	if _sweep_cursor < 24 and _stain_list.has(null):
		_stain_list = _stain_list.filter(func(x: Variant) -> bool: return x != null)


func _place_stain(body: Node3D, pos: Vector3, normal: Vector3, tang: Vector3, along: float, across: float,
		slot: int = 0) -> void:
	var mi: MeshInstance3D = _new_stain(body, slot)
	if mi == null:
		return
	var nrm: Vector3 = normal.normalized()
	var tg: Vector3 = tang - nrm * tang.dot(nrm)
	if tg.length_squared() < 0.0001:
		tg = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT)
	tg = tg.normalized()
	var bit: Vector3 = nrm.cross(tg)
	mi.global_transform = Transform3D(Basis(tg * along, bit * across, nrm), pos + nrm * 0.003)


func _stain(body: Node3D, pos: Vector3, normal: Vector3, vel: Vector3, r: float, slot: int = 0) -> void:
	var width: float = clampf(r * 11.0, 0.015, 0.09) * rng.randf_range(0.8, 1.3)
	var stretch: float = 1.0 + clampf(vel.length() * 0.12, 0.0, 2.2)
	var nrm: Vector3 = normal.normalized()
	_place_stain(body, pos, nrm, vel - nrm * vel.dot(nrm), width * stretch, width, slot)


## Blood soaking a body part where it was hit: a wet patch smeared along the blow plus runnels that run down.
func _hit_stains(node: Node3D, point: Vector3, wound: float, sdir: Vector3, slot: int = 0) -> void:
	var out: Vector3 = point - node.global_position
	if out.length_squared() < 0.0001:
		out = Vector3.UP
	out = out.normalized()
	var w0: float = clampf(0.035 + wound * 0.003, 0.04, 0.12)
	_place_stain(node, point, out, sdir, w0 * 1.4, w0, slot)
	var runs: int = clampi(int(wound / 7.0), 0, 4)
	for k: int in runs:
		var p: Vector3 = point + _jit(w0 * 0.5)
		var len_m: float = rng.randf_range(0.08, 0.2) * (1.0 + wound / 40.0)
		_place_stain(node, p, out, Vector3.DOWN, len_m, rng.randf_range(0.012, 0.028), slot)


## Blood on a weapon: stains along the blade, two crossed quads so either flat face shows it.
func _coat_weapon(f: Object, wound: float, slot: int = 0) -> void:
	if f == null or not is_instance_valid(f):
		return
	var wv: Variant = f.get("weapon")
	if not (wv is Node3D):
		wv = f.get("fist_r")
	if not (wv is Node3D):
		return
	var w: Node3D = wv as Node3D
	var tipv: Variant = w.get("tip_local")
	var tip_l: Vector3 = tipv if tipv is Vector3 else Vector3(0, 0, -0.5)
	if tip_l.length() < 0.05:
		return
	var axis: Vector3 = tip_l.normalized()
	var p1: Vector3 = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var p2: Vector3 = axis.cross(p1)
	var n: int = clampi(1 + int(wound / 10.0), 1, 3)
	for k: int in n:
		var u: float = rng.randf_range(0.4, 1.0)
		var len_m: float = rng.randf_range(0.07, 0.16) * clampf(tip_l.length() * 1.6, 0.4, 1.5)
		var wid: float = rng.randf_range(0.035, 0.06)
		var pos: Vector3 = tip_l * u
		for flip: int in 2:
			var mi: MeshInstance3D = _new_stain(w, slot)
			if mi == null:
				continue
			var a: Vector3 = p1 if flip == 0 else p2
			var nn: Vector3 = p2 if flip == 0 else p1
			mi.transform = Transform3D(Basis(axis * len_m, a * wid, nn), pos)


func _process_impacts() -> void:
	var cap: int = sim.free_slots() + sim.imp_pos.size()
	for k: int in sim.imp_pos.size():
		var p: Vector3 = sim.imp_pos[k]
		var v: Vector3 = sim.imp_vel[k]
		var r: float = sim.imp_rad[k]
		var cs: Vector2i = BloodMath.splat_cell(p.x, p.z, SPLAT_CELL)
		var pslot: int = sim.imp_slot[k]
		var cell: Vector3i = Vector3i(cs.x, cs.y, pslot)  ## one accumulator per cell and blood colour
		var lit: float = BloodMath.droplet_litres(r)
		var acc: Vector4 = _splat.get(cell, Vector4.ZERO)
		_splat[cell] = Vector4(acc.x + p.x * lit, acc.y + p.y * lit, acc.z + p.z * lit, acc.w + lit)
		var spd: float = v.length()
		if spd > 3.2 and r > 0.0024 and cap > 4 and rng.randf() < 0.45:
			var kids: int = 2 + (rng.randi() % 2)
			for c: int in kids:
				var kv: Vector3 = Vector3(v.x * 0.3, absf(v.y) * 0.22 + 0.5, v.z * 0.3) + _jit(0.9)
				sim.emit(p + Vector3(0, 0.004, 0), kv, r * rng.randf_range(0.35, 0.55), 1.5, 2.0, rng.randf(), pslot)
		if spd > 5.0 and rng.randf() < 0.12:
			mist.emit(p + Vector3(0, 0.02, 0), Vector3(v.x * 0.05, 0.4, v.z * 0.05), 0.03, 0.11, 0.3, 0.22,
					rng.randf() * TAU, pslot)


func _flush_splats() -> void:
	stat_splat_calls = 0
	if _splat.is_empty():
		return
	var has_sand: bool = sand != null and sand.has_method("add_blood")
	var max_calls: int = BloodMath.splat_calls(quality)
	var area_left: float = BloodMath.splat_area(quality)  ## big splats cost texels^2: the rest wait a frame (cells merge)
	for cell: Vector3i in _splat.keys():
		if stat_splat_calls >= max_calls or area_left <= 0.0:
			break
		var a: Vector4 = _splat[cell]
		_splat.erase(cell)
		if a.w <= 0.0:
			continue
		var at: Vector3 = Vector3(a.x / a.w, a.y / a.w, a.z / a.w)
		decals.add(at + Vector3(0, 0.006, 0), a.w, rng.randf(), cell.z)
		if has_sand:
			var sr: float = BloodMath.splat_radius(a.w)
			sand.call("add_blood", at, sr, a.w, cell.z)
			area_left -= maxf(sr, 0.05) * maxf(sr, 0.05) / 0.0025
		stat_splat_calls += 1
	if _splat.size() > 4 * max_calls:
		_splat.clear()


# --- Helpers --------------------------------------------------------------------------------------------

func _burst(point: Vector3, dir: Vector3, count: int, v_min: float, v_max: float, spread: float,
		r_max: float, slot: int = 0) -> void:
	var n: int = roundi(count * BloodMath.rate_mult(quality))
	for i: int in n:
		var d: Vector3 = BloodMath.cone_dir(dir, spread, rng.randf(), rng.randf())
		var v: Vector3 = d * rng.randf_range(v_min, v_max)
		sim.emit(point + _jit(0.02), v, BloodMath.drop_radius(rng.randf(), 0.002, r_max), 2.0, 5.0, rng.randf(), slot)
	for i: int in clampi(n / 5, 3, 16):
		mist.emit(point + _jit(0.04), dir * rng.randf_range(0.5, 2.5) + _jit(0.4), 0.07,
				rng.randf_range(0.25, 0.5), rng.randf_range(0.5, 1.1), 0.5, rng.randf() * TAU, slot)


func _jit(amount: float) -> Vector3:
	return Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * amount


func _part_node(f: Object, part: String) -> Node3D:
	if f == null or part == "":
		return null
	var pv: Variant = f.get("parts")  ## Fighter keeps its body parts in a `parts` dictionary
	if pv is Dictionary and (pv as Dictionary).has(part):
		var pn: Variant = (pv as Dictionary)[part]
		if pn is Node3D and is_instance_valid(pn):
			return pn as Node3D
		return null
	var v: Variant = f.get(part)
	if v is Node3D:
		return v as Node3D
	return null


## Palette slot of a tracked fighter's blood (0 when unknown).
func _slot_of(f: Object) -> int:
	var t: _BfTracked = _find_tracked(f) if f != null else null
	return t.slot if t != null else 0


func _blood_reader(f: Object) -> Callable:
	if f == null:
		return Callable()
	return Callable(self, "_read_fighter_blood").bind(f)


func _read_fighter_blood(f: Object) -> float:
	if f == null or not is_instance_valid(f):
		return BloodMath.FULL_BLOOD
	var h: Variant = f.get("health")
	if h is Object:
		var b: Variant = (h as Object).get("blood")
		if b != null:
			return float(b)
	return BloodMath.FULL_BLOOD


func _read_blood(cb: Callable, fallback: float) -> float:
	if cb.is_valid():
		return float(cb.call())
	if _blood_cb.is_valid():
		return float(_blood_cb.call())
	return fallback
