class_name OutfitRules
extends RefCounted
## Pure rules for cosmetic outfits, read from data/outfits.json: which exist, which are premium (sold in the shop), the
## palette used until an outfit's art lands, and the entitlement check. Outfits never change a stat: the loadout's
## "outfit" key is visual only, so ranked online stays fair. An opponent's outfit is whatever they send; the local
## player's own pick is checked against what the store says they own (usable_id).

const PATH: String = "res://data/outfits.json"
const DEFAULT_ID: String = "default"
const OUTFIT_KEY: String = "outfit"  ## key in a loadout dictionary

static var _defs: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	for id: Variant in (data as Dictionary):
		if (data as Dictionary)[id] is Dictionary:
			_defs[str(id)] = (data as Dictionary)[id]
			_order.append(str(id))


## Every outfit id in data order (default first).
static func ids() -> Array:
	_load()
	return Array(_order)


## Ids sold in the shop.
static func premium_ids() -> Array:
	var out: Array = []
	for id: String in ids():
		if is_premium(id):
			out.append(id)
	return out


static func exists(id: String) -> bool:
	_load()
	return _defs.has(id)


## An id that exists, else "default" (a bad id from the network or an old save is never an error).
static func clean_id(id: Variant) -> String:
	var s: String = str(id)
	return s if exists(s) else DEFAULT_ID


static func def(id: String) -> Dictionary:
	_load()
	if not _defs.has(id):
		return {}
	return (_defs[id] as Dictionary).duplicate(true)


static func display_name(id: String) -> String:
	return str(def(id).get("name", id))


static func blurb(id: String) -> String:
	return str(def(id).get("blurb", ""))


static func is_premium(id: String) -> bool:
	return bool(def(id).get("premium", false))


## Store product id of a premium outfit ("" for the free one).
static func product_id(id: String) -> String:
	return str(def(id).get("product_id", ""))


## Outfit id for a store product id ("" when none).
static func outfit_for_product(pid: String) -> String:
	for id: String in ids():
		if pid != "" and product_id(id) == pid:
			return id
	return ""


## Price label shown when the store has not given a localized one.
static func fallback_price(id: String) -> String:
	return str(def(id).get("fallback_price", ""))


static func palette(id: String) -> Dictionary:
	return (def(id).get("palette", {}) as Dictionary).duplicate(true)


## The blood an outfit's wearer bleeds: fresh and dried colour, glow, and the inner colours of wounds and severed parts
## (data/outfits.json "blood" block). Red when the block is missing, so every other outfit bleeds red.
static func blood_palette(id: String) -> BloodPalette:
	return BloodPalette.from_dict(def(id).get("blood", {}) as Dictionary)


## The blood palette of whoever wears the outfit a loadout carries (what an online client draws for the other side,
## from the loadout it already has: no extra network field).
static func blood_palette_of(loadout: Dictionary) -> BloodPalette:
	return blood_palette(outfit_of(loadout))


## A palette colour by key, `fallback` when missing or empty.
static func color(pal: Dictionary, key: String, fallback: Color) -> Color:
	var v: String = str(pal.get(key, ""))
	return Color.html(v) if v != "" else fallback


## Whether the outfit covers body part `part` (armored: skin tone does not show there).
static func covers(id: String, part: String) -> bool:
	return (palette(id).get("covered", []) as Array).has(part)


## The id the local player may actually wear: `wanted` when free or in `owned`, else the default.
static func usable_id(wanted: Variant, owned: Array) -> String:
	var id: String = clean_id(wanted)
	if not is_premium(id) or owned.has(product_id(id)):
		return id
	return DEFAULT_ID


static func can_equip(id: String, owned: Array) -> bool:
	return exists(id) and usable_id(id, owned) == id


## The outfit a loadout dictionary carries (default when missing or unknown).
static func outfit_of(loadout: Dictionary) -> String:
	return clean_id(loadout.get(OUTFIT_KEY, DEFAULT_ID))


## A copy of `loadout` wearing `id`. The default outfit leaves the key out so old loadouts stay unchanged.
static func with_outfit(loadout: Dictionary, id: String) -> Dictionary:
	var out: Dictionary = loadout.duplicate(true)
	var clean: String = clean_id(id)
	if clean == DEFAULT_ID:
		out.erase(OUTFIT_KEY)
	else:
		out[OUTFIT_KEY] = clean
	return out
