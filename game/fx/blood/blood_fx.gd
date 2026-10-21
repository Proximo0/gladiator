class_name BloodFx
extends Node3D
## Blood presentation: pooled CPU droplets (BloodSim), mist sprites (BloodMist), arterial spurts, wounds that
## drip, bloodied weapons, body stains. Never part of the fight state; keep it at the world origin.
## Wire up: add as a child, `sand = sand_surface`, `track(fighter)` per fighter, `set_quality(0..2)`.

const MASK_BODIES: int = 6  ## physics layers 2 (bodies) and 3 (weapons)
const STAIN_RING: int = 22
const MAX_WOUNDS: int = 28
const SPLAT_CELL: float = 0.07
const MAX_SPLAT_CALLS: int = 48
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
	var anchor_vel: Vector3 = Vector3.ZERO
	var prev_pulse: float = 0.0

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

class _BfJet extends RefCounted:
	var target: Node3D = null
	var lpos: Vector3 = Vector3.ZERO
	var ldir: Vector3 = Vector3.UP
	var strength: float = 1.0
	var attacker: Object = null
	var age: float = 0.0
	var blood_cb: Callable = Callable()

class _BfTracked extends RefCounted:
	var fighter: Node = null
	var side: int = 0
	var weapon_blood: float = 0.0
	var last_tip: Vector3 = Vector3.ZERO
	var tip_vel: Vector3 = Vector3.ZERO
	var have_tip: bool = false
	var drip_acc: float = 0.0
	var fling_acc: float = 0.0

var sand: Node = null:  ## duck-typed SandSurface: add_blood(pos, radius, litres), height_at(pos)
	set(value):
		sand = value
		_height_fn = Callable()
		if sand != null and sand.has_method("height_at"):
			_height_fn = Callable(sand, "height_at")
var quality: int = 1
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
var _tracked: Array = []
var _by_side: Dictionary = {}
var _spurts: Array = []
var _wounds: Array = []
var _jets: Array = []
var _splat: Dictionary = {}
var _blood_cb: Callable = Callable()
var _ray_query: PhysicsRayQueryParameters3D = null
var _ray_cursor: int = 0
var _stain_mats: Array[ShaderMaterial] = []
var _stain_mesh: QuadMesh = null
var _height_fn: Callable = Callable()
var _reach: PackedVector3Array = PackedVector3Array()
var _free_this_step: int = 0


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
	_mm_drops = MultiMeshInstance3D.new()
	_mm_drops.name = "Droplets"
	_mm_drops.material_override = drop_mat
	_mm_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm_drops.multimesh = _make_multimesh(BloodMesh.teardrop(7), true)
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
	for i: int in 4:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = stain_shader
		m.set_shader_parameter("seed", float(i) * 0.31)
		_stain_mats.append(m)
	sim = BloodSim.new(BloodMath.budget(quality))
	mist = BloodMist.new(BloodMath.mist_budget(quality))
	_apply_sizes()


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
	_mm_drops.multimesh.instance_count = 0
	_mm_drops.multimesh.instance_count = sim.capacity
	_mm_drops.multimesh.visible_instance_count = 0
	_mm_mist.multimesh.instance_count = 0
	_mm_mist.multimesh.instance_count = mist.capacity
	_mm_mist.multimesh.visible_instance_count = 0


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if sim != null:
		_apply_sizes()


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
	if sim != null:
		sim.count = 0
		mist.count = 0


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
	if wound < 0.5:
		return
	var contact: String = str(event.get("contact", "edge"))
	var point: Vector3 = event.get("point", Vector3.ZERO)
	var into: Vector3 = event.get("normal", Vector3.UP)
	into = into.normalized() if into.length_squared() > 0.0001 else Vector3.UP
	var out: Vector3 = -into
	var rel: Vector3 = event.get("rel_vel", Vector3.ZERO)
	var spd: float = rel.length()
	var sdir: Vector3 = rel / spd if spd > 0.2 else out
	var n: int = roundi(BloodMath.spray_count(wound, contact) * BloodMath.rate_mult(quality))
	var edge: bool = contact == "edge"
	var arc: float = clampf(spd * 0.04, 0.04, 0.4) if edge else 0.02
	var side: Vector3 = sdir.cross(out)
	for i: int in n:
		var p: Vector3 = point - sdir * (rng.randf() * arc) + _jit(0.012)
		var v: Vector3 = sdir * spd * rng.randf_range(0.10, 0.55) * (1.0 if edge else 0.4)
		v += out * rng.randf_range(0.7, 3.4) * (1.0 if edge else 0.7)
		v += side * rng.randf_range(-0.7, 0.7) + _jit(0.9)
		var r: float = BloodMath.drop_radius(rng.randf(), 0.0030, 0.0110)
		sim.emit(p, v, r, 2.0 if edge else 1.2, 5.0, rng.randf())
	var puffs: int = clampi(2 + roundi(wound * 0.08), 2, 8) if contact != "flat" else 1
	for i: int in puffs:
		var mv: Vector3 = out * rng.randf_range(0.3, 1.5) + sdir * spd * 0.08 + _jit(0.4)
		mist.emit(point + _jit(0.03), mv, 0.05, rng.randf_range(0.16, 0.30), rng.randf_range(0.35, 0.75),
				0.5, rng.randf() * TAU)
	var atk: _BfTracked = _by_side.get(int(event.get("attacker", -1)))
	if atk != null:
		atk.weapon_blood = minf(atk.weapon_blood + clampf((cut + pierce) * 0.025, 0.0, 1.0), 1.0)
	var tgt: _BfTracked = _by_side.get(int(event.get("target", -1)))
	var tf: Object = tgt.fighter if tgt != null else emitter
	var node: Node3D = _part_node(tf, str(event.get("part", "")))
	if node != null and cut + pierce > 2.0:
		var w: float = clampf(2.0 + wound * 0.2, 2.0, 14.0)
		add_wound(node, node.to_local(point), w, _blood_reader(tf))
	if node != null and (contact == "point" or pierce > cut * 1.5) and pierce > 4.0:
		var j: _BfJet = _BfJet.new()
		j.target = node
		j.lpos = node.to_local(point)
		j.ldir = node.global_transform.basis.inverse() * out
		j.strength = clampf(pierce / 25.0, 0.35, 1.4)
		j.attacker = atk.fighter if atk != null else null
		j.blood_cb = _blood_reader(tf)
		_jets.append(j)


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
	if anchor != null:
		var outward: Vector3 = point - anchor.global_position
		if nrm.dot(outward) < 0.0:
			nrm = -nrm
	match kind:
		"bleed":
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 2.0 + strength * 3.0, cb)
		"sever":
			start_spurt(anchor, point, nrm, strength, "sever", cb)
			_burst(point, nrm, 34, 2.0, 7.0, 0.5, 0.0075)
		"behead":
			start_spurt(anchor, point, (nrm + Vector3.UP * 0.35).normalized(), strength, "behead", cb)
			_burst(point, nrm, 46, 2.5, 8.0, 0.5, 0.008)
		"gut":
			start_spurt(anchor, point, nrm, strength, "gut", cb)
			_burst(point, nrm, 30, 0.8, 3.2, 0.7, 0.011)
			if anchor != null:
				add_wound(anchor, anchor.to_local(point), 14.0, cb, 0.011)


## Public: start an arterial spurt. anchor may be null (then world point and dir are used as they are).
func start_spurt(anchor: Node3D, point: Vector3, dir: Vector3, strength: float, kind: String,
		blood_cb: Callable = Callable()) -> void:
	var s: _BfSpurt = _BfSpurt.new()
	s.kind = kind
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
		"behead":
			s.tau = 20.0
			s.max_rate = 1200.0
			s.v_min = 2.0
			s.v_max = 6.8
			s.spread = 0.08
			s.r_min = 0.0035
			s.r_max = 0.0095
			s.stretch = 4.5
			s.base_flow = 0.3
			var lean: float = rng.randf() * TAU
			var axis: Vector3 = s.ldir
			var side: Vector3 = axis.cross(Vector3(cos(lean), 0.0, sin(lean))).normalized()
			if side.length_squared() > 0.5:
				s.ldir = axis.rotated(side, 0.75)
		"gut":
			s.tau = 16.0
			s.max_rate = 220.0
			s.v_min = 0.6
			s.v_max = 2.8
			s.spread = 0.55
			s.r_min = 0.004
			s.r_max = 0.011
			s.stretch = 1.0
			s.base_flow = 0.35
		"jet":
			s.tau = 0.35
			s.dur = 0.5
			s.heart = false
			s.max_rate = 420.0
			s.v_min = 3.5
			s.v_max = 7.5
			s.spread = 0.07
			s.base_flow = 1.0
		_:
			s.tau = 13.0
			s.max_rate = 560.0
			s.v_min = 1.2
			s.v_max = 6.0
			s.base_flow = 0.22
			s.spread = 0.12
			s.r_min = 0.003
			s.r_max = 0.0085
			s.stretch = 4.0
	s.last_origin = point
	_spurts.append(s)


func add_wound(anchor: Node3D, local_pos: Vector3, drips_per_sec: float, blood_cb: Callable = Callable(),
		r_scale: float = 1.0) -> void:
	var w: _BfWound = _BfWound.new()
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
	_update_tracked(dt)
	_update_jets(dt)
	_update_spurts(dt)
	_update_wounds(dt)
	_refresh_reach()
	var grace: float = 0.05
	var r2: float = 1.9 * 1.9
	sim.step(dt, gravity, _height_fn, _reach, r2, grace)
	_process_rays()
	_process_impacts()
	sim.compact()
	mist.step(dt)
	_flush_splats()
	stat_emitted = maxi(sim.count - before, 0)
	_upload()


func _upload() -> void:
	var mm: MultiMesh = _mm_drops.multimesh
	mm.buffer = sim.buf
	mm.visible_instance_count = sim.count
	var mm2: MultiMesh = _mm_mist.multimesh
	mm2.buffer = mist.buf
	mm2.visible_instance_count = mist.count


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
		var blood: float = _read_blood(s.blood_cb, full - s.consumed)
		var res: float = BloodMath.reserve(blood, full, death)
		var press: float = BloodMath.pressure(res)
		var pulse_v: float = 1.0
		if s.heart:
			s.phase += dt * BloodMath.heart_rate_bpm(res) / 60.0
			pulse_v = BloodMath.pulse(s.phase)
			if pulse_v > 0.55 and s.prev_pulse <= 0.55 and press > 0.1:
				mist.emit(origin, dir * 0.8 * press, 0.04, 0.12 + 0.12 * press, 0.4, 0.3, rng.randf() * TAU)
			s.prev_pulse = pulse_v
		var flow: float = s.strength * press * exp(-s.age / s.tau) * (s.base_flow + (1.0 - s.base_flow) * pulse_v)
		if s.heart and press <= 0.0:
			_spurts.erase(s)
			continue
		var speed: float = BloodMath.spurt_speed(flow, s.v_min, s.v_max)
		var want: float = flow * s.max_rate * BloodMath.rate_mult(quality) * dt + s.acc
		var n: int = mini(int(want), 16)
		s.acc = want - float(int(want))
		s.consumed += float(n) * 0.00002 * BloodMath.VOLUME_BOOST * 4.0 if not s.blood_cb.is_valid() else 0.0
		for j: int in n:
			var frac: float = (float(j) + rng.randf()) / float(maxi(n, 1))
			var ta: float = dt * (1.0 - frac)
			var d: Vector3 = BloodMath.cone_dir(dir, s.spread * (1.0 + 0.8 * (1.0 - flow)), rng.randf(), rng.randf())
			var v: Vector3 = d * speed * rng.randf_range(0.88, 1.12) + s.anchor_vel * 0.8
			var p: Vector3 = s.last_origin.lerp(origin, frac) + v * ta + Vector3(0, -0.5 * gravity * ta * ta, 0)
			var r: float = BloodMath.drop_radius(rng.randf(), s.r_min, s.r_max) * (0.7 + 0.5 * minf(flow, 1.0)) * 1.7
			sim.emit(p, v, r, s.stretch, 6.0, rng.randf())
		s.last_origin = origin


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
		if w.rate < 0.3:
			_wounds.erase(w)
			continue
		w.acc += w.rate * press * BloodMath.rate_mult(quality) * dt
		while w.acc >= 1.0:
			w.acc -= 1.0
			var v: Vector3 = w.vel * 0.7 + _jit(0.15)
			var r: float = rng.randf_range(0.0036, 0.0060) * w.r_scale
			sim.emit(pos + _jit(0.012), v, r, 0.6, 5.0, rng.randf())


func _update_tracked(dt: float) -> void:
	for t: _BfTracked in _tracked:
		var f: Object = t.fighter
		if f == null or not is_instance_valid(f):
			continue
		t.weapon_blood = maxf(t.weapon_blood - dt * 0.004, 0.0)
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
				sim.emit(p, v, rng.randf_range(0.0018, 0.0055), 2.5, 4.0, rng.randf())
				t.weapon_blood = maxf(t.weapon_blood - 0.004, 0.0)
		elif spd < 1.8:
			t.drip_acc += wb * 4.0 * dt
			if t.drip_acc >= 1.0:
				t.drip_acc -= 1.0
				sim.emit(tip + _jit(0.01), t.tip_vel * 0.3 + _jit(0.05), rng.randf_range(0.0030, 0.0046), 0.6,
						4.0, rng.randf())
				t.weapon_blood = maxf(t.weapon_blood - 0.006, 0.0)


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
			start_spurt(j.target, wpos, dir, j.strength, "jet", j.blood_cb)
			_burst(wpos, dir, 14, 1.0, 4.0, 0.4, 0.006)
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
			_stain(col as Node3D, res["position"], res["normal"], sim.vel_of(i), sim.radius_of(i))
		if sim.vel_of(i).length() > 5.0 and rng.randf() < 0.3:
			mist.emit(res["position"], res["normal"] * 0.5, 0.03, 0.10, 0.35, 0.25, rng.randf() * TAU)
	_ray_cursor = (_ray_cursor + budget) % maxi(n, 1)


func _stain(body: Node3D, pos: Vector3, normal: Vector3, vel: Vector3, r: float) -> void:
	var ring: Array = body.get_meta("bfx_stains", []) as Array
	var next: int = int(body.get_meta("bfx_next", 0))
	var mi: MeshInstance3D
	if ring.size() < STAIN_RING:
		mi = MeshInstance3D.new()
		mi.mesh = _stain_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		ring.append(mi)
		body.set_meta("bfx_stains", ring)
	else:
		mi = ring[next % STAIN_RING]
		body.set_meta("bfx_next", next + 1)
	mi.material_override = _stain_mats[rng.randi() % _stain_mats.size()]
	var nrm: Vector3 = normal.normalized()
	var tang: Vector3 = vel - nrm * vel.dot(nrm)
	if tang.length_squared() < 0.01:
		tang = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT)
	tang = tang.normalized()
	var bit: Vector3 = nrm.cross(tang)
	var width: float = clampf(r * 11.0, 0.015, 0.09) * rng.randf_range(0.8, 1.3)
	var stretch: float = 1.0 + clampf(vel.length() * 0.12, 0.0, 2.2)
	var basis: Basis = Basis(tang * width * stretch, bit * width, nrm)
	mi.global_transform = Transform3D(basis, pos + nrm * 0.003)


func _process_impacts() -> void:
	var cap: int = sim.free_slots() + sim.imp_pos.size()
	for k: int in sim.imp_pos.size():
		var p: Vector3 = sim.imp_pos[k]
		var v: Vector3 = sim.imp_vel[k]
		var r: float = sim.imp_rad[k]
		var cell: Vector2i = BloodMath.splat_cell(p.x, p.z, SPLAT_CELL)
		var lit: float = BloodMath.droplet_litres(r)
		var acc: Vector4 = _splat.get(cell, Vector4.ZERO)
		_splat[cell] = Vector4(acc.x + p.x * lit, acc.y + p.y * lit, acc.z + p.z * lit, acc.w + lit)
		var spd: float = v.length()
		if spd > 3.2 and r > 0.0024 and cap > 4 and rng.randf() < 0.45:
			var kids: int = 2 + (rng.randi() % 2)
			for c: int in kids:
				var kv: Vector3 = Vector3(v.x * 0.3, absf(v.y) * 0.22 + 0.5, v.z * 0.3) + _jit(0.9)
				sim.emit(p + Vector3(0, 0.004, 0), kv, r * rng.randf_range(0.35, 0.55), 1.5, 2.0, rng.randf())
		if spd > 5.0 and rng.randf() < 0.12:
			mist.emit(p + Vector3(0, 0.02, 0), Vector3(v.x * 0.05, 0.4, v.z * 0.05), 0.03, 0.11, 0.3, 0.22,
					rng.randf() * TAU)


func _flush_splats() -> void:
	stat_splat_calls = 0
	if sand == null or _splat.is_empty() or not sand.has_method("add_blood"):
		_splat.clear()
		return
	for cell: Vector2i in _splat.keys():
		if stat_splat_calls >= MAX_SPLAT_CALLS:
			break
		var a: Vector4 = _splat[cell]
		_splat.erase(cell)
		if a.w <= 0.0:
			continue
		sand.call("add_blood", Vector3(a.x / a.w, a.y / a.w, a.z / a.w), BloodMath.splat_radius(a.w), a.w)
		stat_splat_calls += 1


# --- Helpers --------------------------------------------------------------------------------------------

func _burst(point: Vector3, dir: Vector3, count: int, v_min: float, v_max: float, spread: float,
		r_max: float) -> void:
	var n: int = roundi(count * BloodMath.rate_mult(quality))
	for i: int in n:
		var d: Vector3 = BloodMath.cone_dir(dir, spread, rng.randf(), rng.randf())
		var v: Vector3 = d * rng.randf_range(v_min, v_max)
		sim.emit(point + _jit(0.02), v, BloodMath.drop_radius(rng.randf(), 0.002, r_max), 2.0, 5.0, rng.randf())
	for i: int in clampi(n / 6, 2, 8):
		mist.emit(point + _jit(0.04), dir * rng.randf_range(0.5, 2.0) + _jit(0.4), 0.06,
				rng.randf_range(0.2, 0.38), rng.randf_range(0.45, 0.9), 0.38, rng.randf() * TAU)


func _jit(amount: float) -> Vector3:
	return Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * amount


func _part_node(f: Object, part: String) -> Node3D:
	if f == null or part == "":
		return null
	var v: Variant = f.get(part)
	if v is Node3D:
		return v as Node3D
	return null


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
