class_name SfxLogic
extends RefCounted
## Pure sound-selection logic for SfxDirector: which sound for which event, volume curves, variant picking.
## No nodes, no clock, no global RNG (callers pass a seeded RandomNumberGenerator). Unit-tested in test_sfx_logic.gd.
## Sound keys are "<category>/<name>"; files are res://assets/audio/<category>/<name>_<n>.wav (n from 1).

const AUDIO_DIR: String = "res://assets/audio/"

## Variants per sound; test_sfx_assets checks this against assets/audio/manifest.json and the files on disk.
const VARIANTS: Dictionary = {
	"impact/clang_steel": 5, "impact/ring_steel": 3, "impact/thunk_wood": 4, "impact/bat_crack": 4,
	"impact/bat_tink": 4, "impact/body_thud": 5, "impact/fist_punch": 4, "impact/flesh_cut": 5,
	"impact/flesh_pierce": 4, "impact/bone_crack": 4, "impact/armor_clank": 4, "impact/mail_jingle": 4,
	"impact/leather_slap": 4, "impact/helm_knock": 3, "impact/drop_sand": 4, "impact/drop_sand_metal": 4,
	"gore/sever": 3, "gore/behead": 3, "gore/gut": 3, "gore/run_through": 3, "gore/spurt_hiss": 3,
	"gore/blood_spatter_sand": 5,
	"move/whoosh_slow": 5, "move/whoosh_mid": 5, "move/whoosh_fast": 5, "move/footstep_sand": 6,
	"move/body_fall_sand": 4, "move/sand_impact": 5, "move/armor_rattle": 4,
	"voice/grunt": 5, "voice/pain_light": 4, "voice/pain_heavy": 4, "voice/death_gurgle": 3,
	"crowd/amb_low": 1, "crowd/amb_high": 1, "crowd/gasp": 3, "crowd/cheer": 3, "crowd/roar": 3,
	"crowd/boo": 2, "crowd/chant": 2, "crowd/finisher_roar": 2,
	"move/footstep_run": 4, "move/roll_whoosh": 3, "move/roll_thud": 3, "move/whoosh_heavy": 4,
	"move/whoosh_cleave": 4, "impact/heavy_thump": 4, "impact/cleave_chop": 4, "gore/gush_pulse": 5,
	"gore/gut_squelch": 4, "gore/gut_flop": 5, "ui/unlock_sting": 2,
}

## Base level per sound in dB (the files are peak-normalised, this evens out how loud each should sit).
const BASE_DB: Dictionary = {
	"impact/clang_steel": -4.0, "impact/ring_steel": -8.0, "impact/thunk_wood": -4.0, "impact/bat_crack": -3.0,
	"impact/bat_tink": -6.0, "impact/body_thud": -2.0, "impact/fist_punch": -4.0, "impact/flesh_cut": -6.0,
	"impact/flesh_pierce": -5.0, "impact/bone_crack": -3.0, "impact/armor_clank": -6.0, "impact/mail_jingle": -8.0,
	"impact/leather_slap": -6.0, "impact/helm_knock": -2.0, "impact/drop_sand": -6.0, "impact/drop_sand_metal": -6.0,
	"gore/sever": -3.0, "gore/behead": -2.0, "gore/gut": -4.0, "gore/run_through": -3.0, "gore/spurt_hiss": -10.0,
	"gore/blood_spatter_sand": -14.0,
	"move/whoosh_slow": -10.0, "move/whoosh_mid": -8.0, "move/whoosh_fast": -6.0, "move/footstep_sand": -12.0,
	"move/body_fall_sand": -3.0, "move/sand_impact": -12.0, "move/armor_rattle": -20.0,
	"voice/grunt": -8.0, "voice/pain_light": -6.0, "voice/pain_heavy": -4.0, "voice/death_gurgle": -6.0,
	"crowd/amb_low": -12.0, "crowd/amb_high": -10.0, "crowd/gasp": -8.0, "crowd/cheer": -8.0, "crowd/roar": -6.0,
	"crowd/boo": -8.0, "crowd/chant": -8.0, "crowd/finisher_roar": -3.0,
	"move/footstep_run": -10.0, "move/roll_whoosh": -8.0, "move/roll_thud": -5.0, "move/whoosh_heavy": -6.0,
	"move/whoosh_cleave": -6.0, "impact/heavy_thump": -2.0, "impact/cleave_chop": -4.0, "gore/gush_pulse": -8.0,
	"gore/gut_squelch": -5.0, "gore/gut_flop": -7.0, "ui/unlock_sting": -6.0,
}

## Weapon classes by id (a def has no class field): heavy blunt weapons thump and whoosh low, cleavers chop.
const HEAVY_BLUNT_IDS: PackedStringArray = ["sledgehammer", "mace", "warhammer"]
const CLEAVE_IDS: PackedStringArray = ["falchion", "machete", "halberd", "axe"]
## Sounds that yield (are dropped, not stealing a slot) when the player pool is nearly full.
const LOW_PRIORITY: PackedStringArray = [
	"move/footstep_sand", "move/footstep_run", "move/armor_rattle", "move/sand_impact", "move/whoosh_slow",
	"move/whoosh_mid", "gore/blood_spatter_sand", "gore/spurt_hiss", "gore/gut_flop", "gore/gush_pulse",
]
const POOL_RESERVE: int = 5
## Footsteps: at or above this fraction of sprint speed a step is a running one.
const RUN_FRACTION: float = 0.75

## Energy (J) at which an impact reaches 63 percent intensity; below MIN_ENERGY nothing sounds.
const ENERGY_REF: float = 70.0
const MIN_ENERGY: float = 1.0
const QUIET_DB: float = -22.0
## Damage points that make a body hit audibly break bone (blunt on head or limbs / on torso and pelvis).
const BONE_BLUNT_LIMB: float = 8.0
const BONE_BLUNT_CORE: float = 18.0
## Plate lets nothing of the flesh sound through unless real damage got past it.
const PLATE_THROUGH: float = 2.0
const RING_INTENSITY: float = 0.45
const PAIN_MIN: float = 3.0
const PAIN_HEAVY: float = 18.0
const WHOOSH_SLOW_MAX: float = 7.0
const WHOOSH_MID_MAX: float = 11.0
const WHOOSH_MIN_SPEED: float = 3.5
## Heavy and cleaving weapons only whoosh on a real swing: higher minimum tip speed and a longer cooldown.
const WHOOSH_MIN_HEAVY: float = 6.5
const WHOOSH_MIN_CLEAVE: float = 5.0
const WHOOSH_CD_HEAVY: float = 1.0
const WHOOSH_CD_CLEAVE: float = 0.6
## Voice limits: at most this many sounds of a group at once (a new low-priority one is dropped, an important
## one replaces the oldest of its group), and at most this many layers of one hit.
const GROUP_CAPS: Dictionary = {"step": 4, "rattle": 2, "whoosh": 3, "move": 4, "gore_loop": 4, "impact": 9, "gore": 4, "voice": 4}
const MAX_HIT_LAYERS: int = 3
## Low-priority and ambient sounds are dropped once this many voices are busy (the pool is 28: about 78 percent).
const SOFT_TOTAL_CAP: int = 22
## Longest a sound is allowed to ring (s) before a short fade cuts it; keys not listed play to their end.
const MAX_LEN: Dictionary = {
	"move/body_fall_sand": 0.6, "move/whoosh_heavy": 0.4, "move/whoosh_cleave": 0.4, "move/whoosh_slow": 0.35,
	"move/whoosh_mid": 0.35, "move/whoosh_fast": 0.35, "move/roll_whoosh": 0.45, "move/roll_thud": 0.35,
	"impact/ring_steel": 1.0, "impact/helm_knock": 0.8, "impact/clang_steel": 0.7, "impact/heavy_thump": 0.5,
	"impact/bat_tink": 0.4, "impact/mail_jingle": 0.45, "gore/spurt_hiss": 0.5, "gore/gush_pulse": 0.4,
	"gore/gut_squelch": 0.6, "move/footstep_sand": 0.26, "move/footstep_run": 0.26, "move/armor_rattle": 0.26,
	"move/sand_impact": 0.3, "impact/body_thud": 0.4, "impact/flesh_cut": 0.4, "impact/flesh_pierce": 0.4,
	"impact/leather_slap": 0.3, "gore/blood_spatter_sand": 0.4,
}
const CUT_FADE: float = 0.08
const SPLATTER_MIN_TOTAL: float = 4.0

const ARMOR_RANK: Dictionary = {"": 0, "cloth": 1, "leather": 2, "mail": 3, "plate": 4}


static func variant_count(key: String) -> int:
	return int(VARIANTS.get(key, LaserSynth.variant_count(key)))


static func path_for(key: String, index: int) -> String:
	return "%s%s_%d.wav" % [AUDIO_DIR, key, index + 1]


static func base_db(key: String) -> float:
	return float(BASE_DB.get(key, -6.0))


## Random variant index, never the same as `last` when the sound has more than one.
static func pick_variant(key: String, rng: RandomNumberGenerator, last: int) -> int:
	var n: int = variant_count(key)
	if n <= 1:
		return 0
	var i: int = rng.randi_range(0, n - 1)
	if i == last:
		i = (i + 1 + rng.randi_range(0, n - 2)) % n
	return i


## 0..1 loudness from impact energy (J): saturating curve.
static func intensity(energy: float) -> float:
	if energy < MIN_ENERGY:
		return 0.0
	return clampf(1.0 - exp(-energy / ENERGY_REF), 0.0, 1.0)


## dB offset for an intensity: 0 at full, QUIET_DB at nothing.
static func intensity_db(inten: float) -> float:
	return lerpf(QUIET_DB, 0.0, pow(clampf(inten, 0.0, 1.0), 0.6))


## Heavier hits sound a little lower, light ones a little higher.
static func impact_pitch(inten: float) -> float:
	return clampf(1.12 - 0.22 * inten, 0.8, 1.2)


static func _layer(key: String, gain_db: float, pitch: float = 1.0, delay: float = 0.0) -> Dictionary:
	return {"key": key, "gain_db": gain_db, "pitch": pitch, "delay": delay}


## Material of a held weapon from its def: "fist", "wood", "aluminium", "steel" or "shield".
## A def may carry its own "material" ("aluminium", "wood", "steel", "iron").
static func weapon_material(def: Dictionary) -> String:
	var m: String = str(def.get("material", ""))
	if m == "aluminum" or m == "aluminium" or m == "metal_bat":
		return "aluminium"
	if m == "energy":
		return "energy"
	if m == "steel" or m == "iron":
		return "steel"
	if m == "wood":
		return "wood"
	match str(def.get("shape", "")):
		"fist":
			return "fist"
		"sword", "axe", "spear":
			return "steel"
		"shield":
			return "shield"
		"rake", "bat", "club":
			return "wood"
	return "wood"


## Armor kind a worn set of kinds presents to a blow: the hardest outermost one ("" for none).
static func armor_kind_of(kinds: Array) -> String:
	var best: String = ""
	for k: Variant in kinds:
		var ks: String = str(k)
		if int(ARMOR_RANK.get(ks, 0)) > int(ARMOR_RANK.get(best, 0)):
			best = ks
	return best


## Armor kind over a part from armor ids (looked up in CombatData).
static func armor_kind_for(armor_ids: Array) -> String:
	var kinds: Array = []
	for aid: Variant in armor_ids:
		kinds.append(str(CombatData.armor(str(aid)).get("kind", "")))
	return armor_kind_of(kinds)


## True for materials that ring when struck by steel (anything metal).
static func _is_metal(m: String) -> bool:
	return m == "steel" or m == "aluminium"


static func _weapon_pair_layers(atk: String, other: String, inten: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p: float = impact_pitch(inten)
	if atk == "energy" or other == "energy":
		# A laser blade meeting anything crackles; the other side still sounds a little through it.
		out.append(_layer("synth/laser_clash", 0.0, p))
		if atk == "steel" or other == "steel":
			out.append(_layer("impact/clang_steel", -9.0, p))
		elif atk == "aluminium" or other == "aluminium":
			out.append(_layer("impact/bat_tink", -9.0, p))
		else:
			out.append(_layer("impact/thunk_wood", -10.0, p))
		return out
	if atk == "steel" and other == "steel":
		out.append(_layer("impact/clang_steel", 0.0, p))
		if inten >= RING_INTENSITY:
			out.append(_layer("impact/ring_steel", -5.0, p, 0.01))
	elif atk == "aluminium" or other == "aluminium":
		out.append(_layer("impact/bat_tink", -1.0, p))
		if atk == "steel" or other == "steel":
			out.append(_layer("impact/clang_steel", -8.0, p))
		else:
			out.append(_layer("impact/thunk_wood", -8.0, p))
	elif _is_metal(atk) or _is_metal(other):
		out.append(_layer("impact/thunk_wood", 0.0, p))
		if inten >= 0.5:
			out.append(_layer("impact/clang_steel", -12.0, p))
	elif atk == "fist" or other == "fist":
		out.append(_layer("impact/thunk_wood", -4.0, p))
	else:
		out.append(_layer("impact/bat_crack", -2.0, p))
		out.append(_layer("impact/thunk_wood", -6.0, p))
	return out


static func _flesh_layers(atk: String, contact: String, inten: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p: float = impact_pitch(inten)
	match atk:
		"energy":
			# Cauterising: a dry sizzle more than a wet slice.
			if contact == "edge":
				out.append(_layer("impact/flesh_cut", -6.0, p))
				out.append(_layer("synth/laser_cut", -1.0, p))
			elif contact == "point":
				out.append(_layer("impact/flesh_pierce", -6.0, p))
				out.append(_layer("synth/laser_cut", -1.0, p))
			else:
				out.append(_layer("impact/body_thud", -2.0, p))
		"steel":
			if contact == "edge":
				out.append(_layer("impact/flesh_cut", 0.0, p))
			elif contact == "point":
				out.append(_layer("impact/flesh_pierce", 0.0, p))
			else:
				out.append(_layer("impact/body_thud", 0.0, p))
				out.append(_layer("impact/leather_slap", -8.0, p))
		"aluminium":
			out.append(_layer("impact/body_thud", 0.0, p))
			out.append(_layer("impact/bat_tink", -6.0, p))
		"fist":
			out.append(_layer("impact/fist_punch", 0.0, p))
		"shield":
			out.append(_layer("impact/thunk_wood", -2.0, p))
			out.append(_layer("impact/body_thud", -2.0, p))
		_:
			if contact == "point":
				out.append(_layer("impact/flesh_pierce", -3.0, p))
				out.append(_layer("impact/bat_crack", -4.0, p))
			else:
				out.append(_layer("impact/bat_crack", 0.0, p))
				out.append(_layer("impact/body_thud", -2.0, p))
	return out


static func _armor_layer(kind: String, inten: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p: float = impact_pitch(inten)
	match kind:
		"plate":
			out.append(_layer("impact/armor_clank", 0.0, p))
		"mail":
			out.append(_layer("impact/mail_jingle", -1.0, p))
		"leather":
			out.append(_layer("impact/leather_slap", -2.0, p))
	return out


static func _is_core(part: String) -> bool:
	return part == "torso" or part == "pelvis"


## Layers for one resolved hit. `ev` is the Fighter.hit event (DamageModel input merged with its result),
## `atk_mat` the attacking weapon's material, `other_mat` the struck weapon's material when `hit_on_weapon`,
## `armor_kind` what covers the struck part. Each layer: {key, gain_db, pitch, delay}.
static func impact_plan(ev: Dictionary, atk_mat: String, other_mat: String, armor_kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var energy: float = float(ev.get("energy", 0.0))
	var inten: float = intensity(energy)
	if inten <= 0.0:
		return out
	var db: float = intensity_db(inten)
	var layers: Array[Dictionary] = []
	var wclass: String = weapon_class(str(ev.get("weapon_id", "")))
	if bool(ev.get("hit_on_weapon", false)):
		layers = _weapon_pair_layers(atk_mat, other_mat, inten)
		if wclass == "heavy":
			layers.append(_layer("impact/heavy_thump", -6.0, impact_pitch(inten)))
	else:
		var contact: String = str(ev.get("contact", "blunt"))
		var total: float = float(ev.get("total", 0.0))
		var part: String = str(ev.get("part", ""))
		var glanced: bool = bool(ev.get("glanced", false))
		var armor: Array[Dictionary] = _armor_layer(armor_kind, inten)
		var flesh: Array[Dictionary] = []
		if glanced:
			if armor.is_empty():
				flesh.append(_layer("impact/leather_slap", -10.0, impact_pitch(inten)))
			else:
				flesh = []
		else:
			flesh = _flesh_layers(atk_mat, contact, inten)
		var flesh_db: float = 0.0
		match armor_kind:
			"plate":
				flesh_db = -8.0 if total >= PLATE_THROUGH else -40.0
			"mail":
				flesh_db = -4.0
			"leather":
				flesh_db = -3.0
		for l: Dictionary in flesh:
			if flesh_db > -30.0:
				l["gain_db"] = float(l["gain_db"]) + flesh_db
				layers.append(l)
		layers.append_array(armor)
		if not glanced and atk_mat != "energy":
			if wclass == "heavy":
				layers.append(_layer("impact/heavy_thump", -1.0 if armor_kind != "plate" else -4.0, impact_pitch(inten)))
			elif wclass == "cleave" and contact == "edge" and armor_kind != "plate":
				layers.append(_layer("impact/cleave_chop", -2.0, impact_pitch(inten)))
		# Steel on plate rings as well as clanks (the sparks in FeelLogic fire for the same pair).
		if armor_kind == "plate" and atk_mat == "steel" and inten >= RING_INTENSITY and not glanced:
			layers.append(_layer("impact/ring_steel", -6.0, impact_pitch(inten), 0.01))
		var blunt: float = float(ev.get("blunt", 0.0))
		var bone_min: float = BONE_BLUNT_CORE if _is_core(part) else BONE_BLUNT_LIMB
		if not glanced and blunt >= bone_min and not bool(ev.get("sever", false)):
			layers.append(_layer("impact/bone_crack", clampf((blunt - bone_min) * 0.15, 0.0, 3.0) - 2.0, impact_pitch(inten)))
		if str(ev.get("finisher", "")) == "skull_crush":
			layers.append(_layer("impact/bone_crack", 3.0, 0.9))
		if bool(ev.get("dislodge", false)):
			var id: String = str(ev.get("dislodged_id", ""))
			if id.begins_with("helm"):
				layers.append(_layer("impact/helm_knock", 0.0, 1.0, 0.02))
			else:
				layers.append(_layer("impact/armor_clank", 2.0, 0.9, 0.02))
	for l: Dictionary in layers:
		l["gain_db"] = float(l["gain_db"]) + db
		out.append(l)
	return out


## Gore stinger for a gore event kind, or "".
static func gore_key(kind: String) -> String:
	match kind:
		"sever":
			return "gore/sever"
		"behead":
			return "gore/behead"
		"gut":
			return "gore/gut"
		"run_through":
			return "gore/run_through"
	return ""


## Pain voice for a hit on a body (empty when too small to cry out, or on a weapon, or a beheading).
static func voice_plan(ev: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if bool(ev.get("hit_on_weapon", false)) or bool(ev.get("behead", false)):
		return out
	var total: float = float(ev.get("total", 0.0))
	if total < PAIN_MIN:
		return out
	var db: float = lerpf(-8.0, 0.0, clampf(total / 40.0, 0.0, 1.0))
	if total >= PAIN_HEAVY or bool(ev.get("sever", false)) or bool(ev.get("gut", false)):
		out.append(_layer("voice/pain_heavy", db, 1.0, 0.05))
	else:
		out.append(_layer("voice/pain_light", db, 1.0, 0.05))
	return out


## Chance that a swing at `speed` (m/s) with a weapon of `mass` (kg) draws an effort grunt.
static func grunt_chance(speed: float, mass: float) -> float:
	return clampf((speed - 6.0) * 0.06 + mass * 0.08, 0.0, 0.7)


## Which whoosh for a (predicted peak) swing speed, or "" below the threshold.
static func whoosh_key(speed: float) -> String:
	if speed < WHOOSH_MIN_SPEED:
		return ""
	if speed < WHOOSH_SLOW_MAX:
		return "move/whoosh_slow"
	if speed < WHOOSH_MID_MAX:
		return "move/whoosh_mid"
	return "move/whoosh_fast"


static func whoosh_gain_db(speed: float) -> float:
	return lerpf(-16.0, 0.0, clampf((speed - WHOOSH_MIN_SPEED) / 12.0, 0.0, 1.0))


## Heavier weapons whoosh lower, faster swings a touch higher.
static func whoosh_pitch(speed: float, mass: float) -> float:
	return clampf(1.0 + 0.012 * (speed - 8.0) - 0.05 * (mass - 1.0), 0.75, 1.3)


static func step_gain_db(speed: float) -> float:
	return -8.0 + clampf(speed, 0.0, 6.0)


static func weapon_class(weapon_id: String) -> String:
	if HEAVY_BLUNT_IDS.has(weapon_id):
		return "heavy"
	if CLEAVE_IDS.has(weapon_id):
		return "cleave"
	return ""


static func is_low_priority(key: String) -> bool:
	return LOW_PRIORITY.has(key)


## Footstep sound and gain: running steps crunch harder, a sideways shuffle is lighter. `lateral` 0..1 is the
## share of the ground speed that is sideways.
static func footstep_plan(speed: float, sprint_speed: float, lateral: float) -> Dictionary:
	var run: bool = speed >= sprint_speed * RUN_FRACTION
	var db: float = step_gain_db(speed) - 4.0 * clampf(lateral, 0.0, 1.0)
	return {"key": "move/footstep_run" if run else "move/footstep_sand", "gain_db": db}


## Whoosh key for a swing with a given weapon: heavy and cleaving weapons have their own.
static func whoosh_key_for(speed: float, weapon_id: String) -> String:
	var base: String = whoosh_key(speed)
	if base == "":
		return ""
	match weapon_class(weapon_id):
		"heavy":
			return "move/whoosh_heavy"
		"cleave":
			return "move/whoosh_cleave" if speed >= WHOOSH_SLOW_MAX else base
	return base


## Seconds between arterial spurt pulses: faster when blood is high, slowing as it runs out.
static func spurt_interval(blood_frac: float) -> float:
	return lerpf(1.4, 0.7, clampf(blood_frac, 0.0, 1.0))


## Spurt hiss level (dB) by age in seconds: weakens as the blood drains.
static func spurt_gain_db(age: float, blood_frac: float) -> float:
	return -2.0 - age * 2.5 - (1.0 - clampf(blood_frac, 0.0, 1.0)) * 10.0


## Delay (s) before spatter lands on the sand for a hit at `height` m above the floor.
static func spatter_delay(height: float) -> float:
	return clampf(sqrt(2.0 * maxf(height, 0.0) / 9.8), 0.08, 0.7)


static func whoosh_min_speed(weapon_id: String) -> float:
	match weapon_class(weapon_id):
		"heavy":
			return WHOOSH_MIN_HEAVY
		"cleave":
			return WHOOSH_MIN_CLEAVE
	return WHOOSH_MIN_SPEED


static func whoosh_cooldown(weapon_id: String) -> float:
	match weapon_class(weapon_id):
		"heavy":
			return WHOOSH_CD_HEAVY
		"cleave":
			return WHOOSH_CD_CLEAVE
	return 0.0


## Voice group of a key, for the per-group caps.
static func group_of(key: String) -> String:
	if key == "move/armor_rattle":
		return "rattle"
	if key.begins_with("move/footstep"):
		return "step"
	if key.begins_with("move/whoosh") or key == "move/roll_whoosh":
		return "whoosh"
	if key.begins_with("move/"):
		return "move"
	if key.begins_with("voice/"):
		return "voice"
	if key.begins_with("gore/"):
		return "gore_loop" if is_low_priority(key) else "gore"
	return "impact"


static func group_cap(group: String) -> int:
	return int(GROUP_CAPS.get(group, 8))


## Seconds a sound may play before it is faded out; 0 means to its natural end.
static func max_len(key: String) -> float:
	return float(MAX_LEN.get(key, 0.0))


## Keeps the loudest MAX_HIT_LAYERS layers of one hit (the rest only add mud and cost voices).
static func limit_layers(layers: Array[Dictionary]) -> Array[Dictionary]:
	if layers.size() <= MAX_HIT_LAYERS:
		return layers
	var idx: Array[int] = []
	for i: int in range(layers.size()):
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		return float(layers[a]["gain_db"]) + base_db(str(layers[a]["key"])) > float(layers[b]["gain_db"]) + base_db(str(layers[b]["key"])))
	var keep: Array[int] = idx.slice(0, MAX_HIT_LAYERS)
	keep.sort()
	var out: Array[Dictionary] = []
	for i: int in keep:
		out.append(layers[i])
	return out


## Crowd-bus duck envelope: depth (dB, negative) reached `age` seconds after a stinger, with attack, hold, release.
static func duck_db(age: float, depth: float, attack: float, hold: float, release: float) -> float:
	if age < 0.0:
		return 0.0
	if age < attack:
		return depth * (age / maxf(attack, 0.001))
	if age < attack + hold:
		return depth
	var r: float = (age - attack - hold) / maxf(release, 0.001)
	return depth * (1.0 - clampf(r, 0.0, 1.0))
