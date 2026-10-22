class_name HitFx
extends Node3D
## Visual hit feedback, presentation only (never touches physics or fight state): a very short flash on the struck
## part, and a burst of sparks (with a brief light) for metal on metal. Everything is scaled by FeelLogic.impact so a
## tap stays quiet. Owned by MatchPresenter.

const SPARK_POOL: int = 6
const SPARK_AMOUNT: int = 40
const SPARK_LIFE: float = 0.38
const SPARK_SPEED_MIN: float = 2.5
const SPARK_SPEED_MAX: float = 7.0
const SPARK_SPREAD_DEG: float = 55.0
const SPARK_SEED: int = 4711
const LIGHT_ENERGY: float = 3.0
const LIGHT_S: float = 0.06
const MAX_FLASHES: int = 6
const FLASH_COLOR: Color = Color(1.0, 0.93, 0.8)

var _flashes: Array = []  ## {nodes: Array, mat: StandardMaterial3D, age, dur, power}
var _sparks: Array[CPUParticles3D] = []
var _next_spark: int = 0
var _light: OmniLight3D = null
var _light_t: float = 0.0
var _energy_hit: bool = false  ## the hit being burst involves a laser blade: cyan sparks
var _ramp_fire: Gradient = null
var _ramp_energy: Gradient = null


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.022
	mesh.height = 0.044
	mesh.radial_segments = 4
	mesh.rings = 2
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.7, 0.25)
	smat.emission_energy_multiplier = 4.0
	mesh.material = smat
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	grad.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	_ramp_fire = grad
	_ramp_energy = Gradient.new()
	_ramp_energy.set_color(0, Color(0.85, 1.0, 0.96, 1.0))
	_ramp_energy.set_color(1, Color(0.1, 0.9, 0.75, 0.0))
	for i: int in SPARK_POOL:
		var p := CPUParticles3D.new()
		p.mesh = mesh
		p.amount = SPARK_AMOUNT
		p.lifetime = SPARK_LIFE
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 1.0
		p.lifetime_randomness = 0.4
		p.direction = Vector3.UP
		p.spread = SPARK_SPREAD_DEG
		p.initial_velocity_min = SPARK_SPEED_MIN
		p.initial_velocity_max = SPARK_SPEED_MAX
		p.gravity = Vector3(0.0, -9.8, 0.0)
		p.color_ramp = grad
		p.use_fixed_seed = true
		p.seed = SPARK_SEED + i
		p.top_level = true
		p.local_coords = false
		add_child(p)
		_sparks.append(p)
	if GfxQuality.SPARK_LIGHT[clampi(GfxQuality.level, 0, 2)]:
		_light = OmniLight3D.new()
		_light.omni_range = 3.5
		_light.light_color = Color(1.0, 0.8, 0.5)
		_light.light_energy = 0.0
		_light.shadow_enabled = false
		_light.top_level = true
		add_child(_light)


## Flash and sparks for one resolved hit. `victim` is the struck Fighter (or null), `imp` its FeelLogic impact.
func on_hit(ev: Dictionary, victim: Object, imp: float) -> void:
	var tun: Tuning = Tuning.shared()
	var power: float = FeelLogic.flash_strength(imp, tun)
	if power > 0.0 and victim != null:
		_flash(_flash_nodes(ev, victim), power, tun.feel_flash_s)
	var mats: Array = materials(ev, victim)
	_energy_hit = str(mats[0]) == "energy" or str(mats[1]) == "energy"
	var n: int = FeelLogic.spark_count(ev, str(mats[0]), str(mats[1]), str(mats[2]), imp, tun)
	if n > 0:
		var scaled: int = roundi(n * GfxQuality.pick_f(GfxQuality.SPARK_MULT))
		_burst(ev, maxi(scaled, 1))


## [attacker material, struck-weapon material or "", armor kind] for a hit (the same reading SfxDirector uses).
static func materials(ev: Dictionary, victim: Object) -> Array:
	var atk: String = SfxLogic.weapon_material(CombatData.weapon(str(ev.get("weapon_id", ""))))
	var other: String = ""
	if bool(ev.get("hit_on_weapon", false)) and victim != null:
		var held: Variant = victim.get("offhand") if str(ev.get("part", "")) == "forearm_l" else victim.get("weapon")
		if held != null and (held as Object).get("weapon_id") != null:
			other = SfxLogic.weapon_material(CombatData.weapon(str((held as Object).get("weapon_id"))))
		else:
			other = "wood"
	return [atk, other, SfxLogic.armor_kind_for(ev.get("armor_ids", []) as Array)]


func _flash_nodes(ev: Dictionary, victim: Object) -> Array:
	var out: Array = []
	if bool(ev.get("hit_on_weapon", false)):
		var held: Variant = victim.get("offhand") if str(ev.get("part", "")) == "forearm_l" else victim.get("weapon")
		if held is Node:
			_collect_meshes(held as Node, out)
		return out
	var parts: Variant = victim.get("parts")
	if parts is Dictionary and (parts as Dictionary).has(str(ev.get("part", ""))):
		var body: Node = (parts as Dictionary)[str(ev.get("part", ""))]
		for slot: String in ["Look", "ArmorSlot"]:
			var s: Node = body.get_node_or_null(slot)
			if s != null:
				_collect_meshes(s, out)
	return out


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).visible:
		out.append(n)
	for c: Node in n.get_children():
		_collect_meshes(c, out)


func _flash(nodes: Array, power: float, dur: float) -> void:
	if nodes.is_empty():
		return
	for f: Dictionary in _flashes:
		if (f["nodes"] as Array)[0] == nodes[0]:
			f["age"] = 0.0
			f["power"] = maxf(float(f["power"]), power)
			return
	if _flashes.size() >= MAX_FLASHES:
		_end_flash(_flashes[0] as Dictionary)
		_flashes.remove_at(0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, power)
	for m: Variant in nodes:
		(m as MeshInstance3D).material_overlay = mat
	_flashes.append({"nodes": nodes, "mat": mat, "age": 0.0, "dur": dur, "power": power})


func _end_flash(f: Dictionary) -> void:
	for m: Variant in f["nodes"]:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_overlay = null


func _burst(ev: Dictionary, count: int) -> void:
	var p: CPUParticles3D = _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	var at: Vector3 = ev.get("point", Vector3.ZERO)
	var dir: Vector3 = FeelLogic.blow_dir(ev)
	# Sparks fly back off the strike and up: the blade has just stopped against the metal.
	var out: Vector3 = -dir * 0.6 + Vector3.UP * 0.7
	p.global_position = at
	p.direction = out.normalized() if out.length() > 0.01 else Vector3.UP
	p.amount = clampi(count, 1, SPARK_AMOUNT)
	p.color_ramp = _ramp_energy if _energy_hit else _ramp_fire
	p.restart()
	p.emitting = true
	if _light != null:
		_light.global_position = at
		_light.light_energy = LIGHT_ENERGY
		_light_t = LIGHT_S


func _process(delta: float) -> void:
	var i: int = _flashes.size() - 1
	while i >= 0:
		var f: Dictionary = _flashes[i]
		f["age"] = float(f["age"]) + delta
		var dur: float = maxf(float(f["dur"]), 0.001)
		var a: float = float(f["age"]) / dur
		if a >= 1.0:
			_end_flash(f)
			_flashes.remove_at(i)
		else:
			var mat: StandardMaterial3D = f["mat"]
			mat.albedo_color.a = float(f["power"]) * (1.0 - a) * (1.0 - a)
		i -= 1
	if _light != null and _light_t > 0.0:
		_light_t -= delta
		if _light_t <= 0.0:
			_light.light_energy = 0.0
