class_name Tuning
extends RefCounted
## Template for live-tunable gameplay numbers (pattern from the skate project's PhysicsTuning).
## Game code reads `Tuning.shared().<field>` every tick instead of hard-coding numbers, so a tuning panel,
## replays, sims and presets can change the feel without touching code.
## Add a row to FIELDS and a matching `var` below; nothing else is needed.
## Presets are JSON dictionaries of {field: value}; unknown keys are ignored.

signal changed(field: String, value: float)

## [field, default, min, max, step, group, doc]. The order here is the order a tuning panel shows.
const FIELDS: Array = [
	["gravity", 9.8, 5.0, 30.0, 0.1, "World", "Gravity, m/s². Real is 9.8."],
	["arena_radius", 11.0, 6.0, 20.0, 0.5, "World", "Radius of the arena wall, m."],
	["move_speed", 2.5, 0.5, 8.0, 0.1, "Movement", "Walk speed on sand, m/s."],
	["sprint_speed", 4.5, 1.0, 10.0, 0.1, "Movement", "Sprint speed on sand, m/s."],
	["arm_force", 900.0, 100.0, 4000.0, 25.0, "Arms", "Max force the weapon hand can apply toward its target, N."],
	["damage_min_speed", 3.0, 0.0, 10.0, 0.1, "Damage", "Weapon-to-target speed below which a contact does no damage, m/s."],
	["blood_death", 2.5, 0.5, 5.0, 0.1, "Damage", "Blood volume (litres) below which a fighter dies."],
	["dmg_cut_scale", 0.25, 0.05, 1.0, 0.01, "Damage", "Cut damage points per joule of edged energy (before armor and weapon cut_factor)."],
	["dmg_pierce_scale", 0.9, 0.1, 3.0, 0.05, "Damage", "Pierce damage points per joule of point energy."],
	["dmg_blunt_scale", 0.1, 0.02, 0.5, 0.01, "Damage", "Blunt damage points per joule (before armor and weapon blunt_factor)."],
	["dmg_sever_cut", 40.0, 10.0, 120.0, 1.0, "Damage", "Cut points (after armor) that sever a forearm at full hp; other parts scale from this."],
	["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Damage", "Cut or pierce points (after armor) on torso/pelvis that gut."],
	["dmg_stagger_ref", 150.0, 30.0, 600.0, 5.0, "Damage", "Blunt energy (J, after armor) that gives full stagger."],
	["dmg_knock_scale", 0.3, 0.0, 2.0, 0.05, "Damage", "Knockback impulse per N·s of hit momentum."],
	["dmg_bleed_cut", 0.004, 0.0, 0.05, 0.001, "Damage", "Bleed rate (L/s) per cut point."],
	["dmg_bleed_pierce", 0.003, 0.0, 0.05, 0.001, "Damage", "Bleed rate (L/s) per pierce point."],
	["dmg_bleed_sever", 0.4, 0.0, 2.0, 0.05, "Damage", "Extra bleed rate (L/s) from a severed limb."],
	["dmg_bleed_gut", 0.35, 0.0, 2.0, 0.05, "Damage", "Extra bleed rate (L/s) from a gutting."],
	["dmg_wear_loss", 0.6, 0.0, 1.0, 0.05, "Damage", "Fraction of an armor piece's resistance lost at full wear."],
	["dmg_glance_frac", 0.15, 0.0, 1.0, 0.01, "Damage", "A sharp hit is a glance when armor leaves less than this fraction of its cut+pierce."],
	["blood_faint", 3.5, 2.6, 5.0, 0.1, "Health", "Blood (L) below which consciousness is capped; zero at blood_death."],
	["health_head_ko", 0.03, 0.0, 0.2, 0.005, "Health", "Consciousness lost per blunt point on the head."],
	["health_stagger_ko", 0.05, 0.0, 0.5, 0.01, "Health", "Consciousness lost per unit of stagger on any part."],
	["health_clot", 0.02, 0.0, 0.5, 0.005, "Health", "Bleed rate decay per second (clotting)."],
	["health_consc_recover", 0.03, 0.0, 0.5, 0.005, "Health", "Consciousness recovery per second."],
	["health_stamina_recover", 0.2, 0.0, 1.0, 0.01, "Health", "Stamina recovered per second at rest."],
	["health_stamina_drain", 0.3, 0.0, 1.0, 0.01, "Health", "Stamina drained per second at full exertion."],
]

static var _shared: Tuning = null

var gravity: float
var arena_radius: float
var move_speed: float
var sprint_speed: float
var arm_force: float
var damage_min_speed: float
var blood_death: float
var dmg_cut_scale: float
var dmg_pierce_scale: float
var dmg_blunt_scale: float
var dmg_sever_cut: float
var dmg_gut: float
var dmg_stagger_ref: float
var dmg_knock_scale: float
var dmg_bleed_cut: float
var dmg_bleed_pierce: float
var dmg_bleed_sever: float
var dmg_bleed_gut: float
var dmg_wear_loss: float
var dmg_glance_frac: float
var blood_faint: float
var health_head_ko: float
var health_stagger_ko: float
var health_clot: float
var health_consc_recover: float
var health_stamina_recover: float
var health_stamina_drain: float


func _init() -> void:
	reset()


## The tuning the game uses unless it is given its own. A tuning panel edits this one.
static func shared() -> Tuning:
	if _shared == null:
		_shared = Tuning.new()
	return _shared


static func field_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in FIELDS:
		out.append(f[0])
	return out


static func field_info(field: String) -> Dictionary:
	for f: Array in FIELDS:
		if f[0] == field:
			return {"name": f[0], "default": f[1], "min": f[2], "max": f[3], "step": f[4], "group": f[5], "doc": f[6]}
	return {}


func reset() -> void:
	for f: Array in FIELDS:
		set(f[0], float(f[1]))


## Sets one field, clamped to its range. Returns false for an unknown field.
func set_value(field: String, value: float) -> bool:
	var info: Dictionary = field_info(field)
	if info.is_empty():
		return false
	var v: float = clampf(value, float(info["min"]), float(info["max"]))
	set(field, v)
	changed.emit(field, v)
	return true


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		d[f[0]] = get(f[0])
	return d


## Applies known keys from `d` (others are ignored). Returns the number of fields applied.
func apply_dict(d: Dictionary) -> int:
	var n: int = 0
	for key: Variant in d:
		if set_value(str(key), float(d[key])):
			n += 1
	return n


## Only the fields that differ from the defaults: what a preset needs to store.
func diff_from_defaults() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		if not is_equal_approx(float(get(f[0])), float(f[1])):
			d[f[0]] = get(f[0])
	return d


func copy_from(other: Tuning) -> void:
	apply_dict(other.to_dict())


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t", false))
	return OK


## Loads a preset file over the current values. Returns false if the file is missing or not a JSON object.
func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	apply_dict(parsed)
	return true
