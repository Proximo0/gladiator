class_name LoadoutRules
extends RefCounted
## Pure rules for the loadout screen, read from the weapon and armor data files: which weapons can be a main weapon,
## which items fill the off hand, which armor fits each slot, whether the off hand is blocked, and the short stat
## readouts. A loadout is the dictionary Fighter.setup() takes: {"weapon", "offhand", "armor": {slot: armor id}}.

## [slot (the armor defs' `part`), screen label], top to bottom.
const ARMOR_SLOTS: Array = [["head", "Helmet"], ["torso", "Body"], ["upper_arm_l", "Arms"], ["thigh_l", "Legs"]]
const DEFAULT_WEAPON: String = "gladius"
const DEFAULT_OFFHAND: String = "shield_round"
const DEFAULT_ARMOR: Dictionary = {"head": "helm_leather", "torso": "cuirass_leather"}
## Largest factor in the data, so the stat bars fill sensibly (an axe cuts at 1.15).
const BAR_MAX: float = 1.2


static func is_shield(id: String) -> bool:
	return str(CombatData.weapon(id).get("shape", "")) == "shield"


## Premium weapons come with an outfit (weapon def "requires_outfit"); this is what a locked one becomes.
const PREMIUM_FALLBACK: String = "longsword"


## The outfit id a weapon needs ("" for a free weapon).
static func required_outfit(weapon_id: String) -> String:
	return str(CombatData.weapon(weapon_id).get("requires_outfit", ""))


static func is_premium_weapon(weapon_id: String) -> bool:
	return required_outfit(weapon_id) != ""


## True when `weapon_id` is free, or `owned` (the store's product ids) holds its outfit. `owned` null means "do not
## check" (bots, dev runs, network loadouts the host cannot verify).
static func weapon_unlocked(weapon_id: String, owned: Variant) -> bool:
	var need: String = required_outfit(weapon_id)
	if need == "" or not (owned is Array):
		return true
	return (owned as Array).has(OutfitRules.product_id(need))


## Main-hand weapon ids in data order (fists first); shields are never a main weapon. With `owned` (an array of
## product ids) a premium weapon is listed only when its outfit is owned; null lists all of them.
static func main_weapons(owned: Variant = null) -> Array:
	var out: Array = []
	for id: String in CombatData.weapon_ids():
		if not is_shield(id) and weapon_unlocked(id, owned):
			out.append(id)
	return out


## Off-hand ids: "" (empty) then every shield.
static func offhands() -> Array:
	var out: Array = [""]
	for id: String in CombatData.weapon_ids():
		if is_shield(id):
			out.append(id)
	return out


static func two_handed(weapon_id: String) -> bool:
	return bool(CombatData.weapon(weapon_id).get("two_handed", false))


## The off hand is blocked while a two-handed weapon is in the main hand.
static func offhand_blocked(weapon_id: String) -> bool:
	return two_handed(weapon_id)


## "" (none) then the pieces for `slot`, lightest first.
static func armor_options(slot: String) -> Array:
	var ids: Array = []
	for id: String in CombatData.armor_ids():
		if str(CombatData.armor(id).get("part", "")) == slot:
			ids.append(id)
	ids.sort_custom(_lighter)
	return [""] + ids


static func _lighter(a: String, b: String) -> bool:
	return float(CombatData.armor(a).get("mass", 0.0)) < float(CombatData.armor(b).get("mass", 0.0))


static func slot_names() -> Array:
	var out: Array = []
	for s: Array in ARMOR_SLOTS:
		out.append(str(s[0]))
	return out


static func default_loadout() -> Dictionary:
	return sanitize({"weapon": DEFAULT_WEAPON, "offhand": DEFAULT_OFFHAND, "armor": DEFAULT_ARMOR})


## A valid copy: unknown weapon becomes fists, a non-shield or blocked off hand is dropped, armor ids must exist and
## fit their slot. Missing keys are filled. `owned` (the local player's store product ids) turns on the premium weapon
## check: a weapon whose outfit is not owned becomes PREMIUM_FALLBACK. The default null trusts the loadout, which is
## what the online host does for a client (it cannot see the client's store; see docs/weapons_premium.md).
static func sanitize(loadout: Dictionary, owned: Variant = null) -> Dictionary:
	var weapon: String = str(loadout.get("weapon", "fists"))
	if CombatData.weapon(weapon).is_empty() or is_shield(weapon):
		weapon = "fists"
	elif not weapon_unlocked(weapon, owned):
		weapon = PREMIUM_FALLBACK
	var off: String = str(loadout.get("offhand", ""))
	if off != "" and (not is_shield(off) or offhand_blocked(weapon)):
		off = ""
	var armor: Dictionary = {}
	var given: Dictionary = loadout.get("armor", {})
	for slot: String in slot_names():
		var id: String = str(given.get(slot, ""))
		if id != "" and str(CombatData.armor(id).get("part", "")) == slot:
			armor[slot] = id
	var out: Dictionary = {"weapon": weapon, "offhand": off, "armor": armor}
	# Outfits are cosmetic: carry a known premium id so the opponent sees it.
	var outfit: String = OutfitRules.clean_id(str(loadout.get("outfit", "default")))
	if outfit != "default":
		out["outfit"] = outfit
	return out


## Total carried mass in kg (weapon, off hand, armor).
static func total_mass(loadout: Dictionary) -> float:
	var m: float = float(CombatData.weapon(str(loadout.get("weapon", ""))).get("mass", 0.0))
	m += float(CombatData.weapon(str(loadout.get("offhand", ""))).get("mass", 0.0))
	var armor: Dictionary = loadout.get("armor", {})
	for slot: Variant in armor:
		m += float(CombatData.armor(str(armor[slot])).get("mass", 0.0))
	return m


## {name, mass, reach, cut, blunt, pierce (0..1 bar fractions), two_handed, line}. Unknown id: name "None".
static func weapon_stats(id: String) -> Dictionary:
	var d: Dictionary = CombatData.weapon(id)
	if d.is_empty():
		return {"name": "None", "mass": 0.0, "reach": 0.0, "cut": 0.0, "blunt": 0.0, "pierce": 0.0,
				"two_handed": false, "line": ""}
	var out: Dictionary = {
		"name": str(d.get("name", id)), "mass": float(d.get("mass", 0.0)), "reach": float(d.get("length", 0.0)),
		"cut": bar(float(d.get("cut_factor", 0.0))), "blunt": bar(float(d.get("blunt_factor", 0.0))),
		"pierce": bar(float(d.get("pierce_factor", 0.0))), "two_handed": bool(d.get("two_handed", false)),
	}
	out["line"] = "%.1f kg  |  reach %.2f m%s" % [out["mass"], out["reach"], "  |  two-handed" if out["two_handed"] else ""]
	return out


## {name, mass, cut, blunt, pierce (0..1), line} for an armor id.
static func armor_stats(id: String) -> Dictionary:
	var d: Dictionary = CombatData.armor(id)
	if d.is_empty():
		return {"name": "None", "mass": 0.0, "cut": 0.0, "blunt": 0.0, "pierce": 0.0, "line": ""}
	var out: Dictionary = {
		"name": str(d.get("name", id)), "mass": float(d.get("mass", 0.0)),
		"cut": clampf(float(d.get("cut_resist", 0.0)), 0.0, 1.0),
		"blunt": clampf(float(d.get("blunt_resist", 0.0)), 0.0, 1.0),
		"pierce": clampf(float(d.get("pierce_resist", 0.0)), 0.0, 1.0),
	}
	out["line"] = "%.1f kg  |  %s" % [out["mass"], str(d.get("kind", ""))]
	return out


static func bar(factor: float) -> float:
	return clampf(factor / BAR_MAX, 0.0, 1.0)


## Display name for a weapon, shield or armor id; "None" for "".
static func display_name(id: String) -> String:
	if id == "":
		return "None"
	var w: Dictionary = CombatData.weapon(id)
	if not w.is_empty():
		return str(w.get("name", id))
	return str(CombatData.armor(id).get("name", id))
