class_name MatchConfig
extends RefCounted
## Pure, seeded match setup: random loadouts over every weapon, offhand and armor mix, random brain personalities,
## gladiator names, and `normalize()`, which fills every missing key of a Match config. Same seed, same match.

const MODES: PackedStringArray = ["bot_vs_bot", "player_vs_cpu", "local_2p", "practice"]
const DEFAULT_TIME_LIMIT_S: float = 180.0
const SHIELD_CHANCE: float = 0.5
const FISTS_SHIELD_CHANCE: float = 0.15
## Pick weights per weapon id (unknown ids weigh 1). Fists are rare so most matches have steel in them.
const WEAPON_WEIGHT: Dictionary = {
	"fists": 0.35, "rake": 0.6, "bat": 0.7, "club": 0.9, "gladius": 1.4, "longsword": 1.0, "axe": 1.0, "spear": 1.0,
}
const NAMES: PackedStringArray = [
	"Spartacus", "Crixus", "Priscus", "Verus", "Flamma", "Carpophorus", "Tetraites", "Hermes", "Oenomaus",
	"Felix", "Marcus", "Atticus", "Gannicus", "Varro", "Cassius", "Lucan",
]


## {"weapon", "offhand", "armor": {slot: armor id}}. Draws a fixed number of random values, so loadout k of a seed
## never depends on the earlier loadouts' contents.
static func random_loadout(rng: RandomNumberGenerator) -> Dictionary:
	var weapons: Array = []
	var shields: Array = []
	var ids: PackedStringArray = CombatData.weapon_ids()
	var sorted_ids: Array = Array(ids)
	sorted_ids.sort()
	for wid: String in sorted_ids:
		if str(CombatData.weapon(wid).get("shape", "")) == "shield":
			shields.append(wid)
		else:
			weapons.append(wid)
	var weapon: String = _weighted(weapons, rng.randf())
	var def: Dictionary = CombatData.weapon(weapon)
	var shield_roll: float = rng.randf()
	var shield_pick: float = rng.randf()
	var offhand: String = ""
	var chance: float = FISTS_SHIELD_CHANCE if weapon == "fists" else SHIELD_CHANCE
	if not shields.is_empty() and not bool(def.get("two_handed", false)) and shield_roll < chance:
		offhand = str(shields[int(shield_pick * float(shields.size())) % shields.size()])
	return {"weapon": weapon, "offhand": offhand, "armor": random_armor(rng)}


## Armor mix: a per-fighter level (0 = bare .. 1 = fully armored) decides how many slots get a piece, and a roll
## per slot picks one of that slot's pieces (light to heavy). Slots are the armor defs' `part` names.
static func random_armor(rng: RandomNumberGenerator) -> Dictionary:
	var by_slot: Dictionary = {}
	var aids: Array = Array(CombatData.armor_ids())
	aids.sort()
	for aid: String in aids:
		var slot: String = str(CombatData.armor(aid).get("part", ""))
		if slot == "":
			continue
		if not by_slot.has(slot):
			by_slot[slot] = []
		(by_slot[slot] as Array).append(aid)
	var level: float = rng.randf()
	var out: Dictionary = {}
	var slots: Array = by_slot.keys()
	slots.sort()
	for slot: String in slots:
		var take: float = rng.randf()
		var style: float = rng.randf()
		var pieces: Array = by_slot[slot]
		pieces.sort_custom(_by_weight)
		if take < level:
			out[slot] = pieces[int(style * float(pieces.size())) % pieces.size()]
	return out


static func _by_weight(a: String, b: String) -> bool:
	return float(CombatData.armor(a).get("mass", 0.0)) < float(CombatData.armor(b).get("mass", 0.0))


static func _weighted(ids: Array, roll: float) -> String:
	if ids.is_empty():
		return "fists"
	var total: float = 0.0
	for id: String in ids:
		total += float(WEAPON_WEIGHT.get(id, 1.0))
	var acc: float = 0.0
	var target: float = roll * total
	for id: String in ids:
		acc += float(WEAPON_WEIGHT.get(id, 1.0))
		if target < acc:
			return id
	return str(ids[ids.size() - 1])


## {"preset": name, "aggression": jittered}: one of the FighterBrain presets with a little spread.
static func random_personality(rng: RandomNumberGenerator) -> Dictionary:
	var names: Array = FighterBrain.PRESETS.keys()
	names.sort()
	var pick: String = str(names[int(rng.randf() * float(names.size())) % names.size()])
	var base: Dictionary = FighterBrain.preset(pick)
	var agg: float = clampf(float(base.get("aggression", 0.5)) + rng.randf_range(-0.12, 0.12), 0.0, 1.0)
	return {"preset": pick, "aggression": agg}


## Two distinct gladiator names for a seed.
static func names_for(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var a: int = rng.randi_range(0, NAMES.size() - 1)
	var b: int = (a + 1 + rng.randi_range(0, NAMES.size() - 2)) % NAMES.size()
	return [NAMES[a], NAMES[b]]


## The full config: every key present. Loadouts and personalities are always drawn (so overriding one does not
## change the other); given values then replace the drawn ones.
static func normalize(config: Dictionary, default_seed: int) -> Dictionary:
	var out: Dictionary = {}
	var mode: String = str(config.get("mode", "bot_vs_bot"))
	out["mode"] = mode if MODES.has(mode) else "bot_vs_bot"
	var seed_value: int = int(config.get("seed", default_seed))
	out["seed"] = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var loadouts: Array = [random_loadout(rng), random_loadout(rng)]
	var personalities: Array = [random_personality(rng), random_personality(rng)]
	var given_l: Array = config.get("loadouts", [])
	var given_p: Array = config.get("personalities", [])
	for i: int in 2:
		if i < given_l.size() and given_l[i] is Dictionary:
			loadouts[i] = (given_l[i] as Dictionary).duplicate(true)
		if i < given_p.size() and given_p[i] is Dictionary:
			personalities[i] = (given_p[i] as Dictionary).duplicate(true)
	out["loadouts"] = loadouts
	out["personalities"] = personalities
	out["presentation"] = bool(config.get("presentation", true))
	out["time_limit_s"] = maxf(float(config.get("time_limit_s", DEFAULT_TIME_LIMIT_S)), 1.0)
	out["loop"] = bool(config.get("loop", out["presentation"] and out["mode"] == "bot_vs_bot"))
	return out


## One-line description of a loadout, for logs: "gladius+shield_round [helm_iron mail]".
static func describe(loadout: Dictionary) -> String:
	var s: String = str(loadout.get("weapon", "fists"))
	var off: String = str(loadout.get("offhand", ""))
	if off != "":
		s += "+" + off
	var armor: Dictionary = loadout.get("armor", {})
	var ids: Array = armor.values()
	ids.sort()
	return "%s [%s]" % [s, " ".join(PackedStringArray(ids))]
