class_name CombatData
extends RefCounted
## Weapon, armor and body-part definitions loaded once from data/weapons.json and data/armor.json.
## Lookups return copies, so callers may edit them freely.

const WEAPONS_PATH: String = "res://data/weapons.json"
const ARMOR_PATH: String = "res://data/armor.json"

static var _weapons: Dictionary = {}
static var _armor: Dictionary = {}
static var _parts: Dictionary = {}
static var _weapon_order: PackedStringArray = PackedStringArray()
static var _armor_order: PackedStringArray = PackedStringArray()
static var _loaded: bool = false


## Weapon def, or {} for an unknown id.
static func weapon(id: String) -> Dictionary:
	_load()
	if not _weapons.has(id):
		return {}
	var d: Dictionary = _weapons[id]
	return d.duplicate(true)


## Armor def, or {} for an unknown id.
static func armor(id: String) -> Dictionary:
	_load()
	if not _armor.has(id):
		return {}
	var d: Dictionary = _armor[id]
	return d.duplicate(true)


static func weapon_ids() -> PackedStringArray:
	_load()
	return _weapon_order.duplicate()


static func armor_ids() -> PackedStringArray:
	_load()
	return _armor_order.duplicate()


## Body part def {hp, sever (sever threshold multiplier, 0 = cannot be severed), blunt_mult}, or {}.
static func part_info(part: String) -> Dictionary:
	_load()
	if not _parts.has(part):
		return {}
	var d: Dictionary = _parts[part]
	return d.duplicate(true)


static func part_names() -> PackedStringArray:
	_load()
	var out := PackedStringArray()
	for k: Variant in _parts:
		out.append(str(k))
	return out


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		var d: Dictionary = parsed
		return d
	return {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var w: Dictionary = _read_json(WEAPONS_PATH)
	var a: Dictionary = _read_json(ARMOR_PATH)
	var parts: Variant = w.get("parts", {})
	if parts is Dictionary:
		_parts = parts
	for item: Variant in w.get("weapons", []):
		if item is Dictionary:
			var d: Dictionary = item
			var id: String = str(d.get("id", ""))
			if id != "":
				_weapons[id] = d
				_weapon_order.append(id)
	for item: Variant in a.get("armor", []):
		if item is Dictionary:
			var d: Dictionary = item
			var id: String = str(d.get("id", ""))
			if id != "":
				_armor[id] = d
				_armor_order.append(id)
