class_name WeaponUnlocks
extends RefCounted
## Play-to-unlock weapons (docs/weapons_unlocks.md). A weapon def with `"unlock": {"stat": <counter>, "count": n}` is
## earned once the player's PlayerProgress counter `stat` reaches n; a weapon with neither "unlock" nor
## "requires_outfit" is a starter and always free. Earned weapons reach the gating path as tokens in the same `owned`
## list LoadoutRules already takes for premium weapons (`access()`), so sanitize / main_weapons gate both kinds.
## Pure: progress is the counters dictionary (PlayerProgress.counters), never a file.

const TOKEN_PREFIX: String = "sandblood.unlock."
## Counter id -> [singular, plural] wording of the milestone ("Win 1 fight", "Win 4 fights").
const STAT_WORDS: Dictionary = {
	"matches": ["Play %d fight", "Play %d fights"],
	"wins": ["Win %d fight", "Win %d fights"],
	"ranked_wins": ["Win %d ranked Quick Match", "Win %d ranked Quick Matches"],
}


## {"stat", "count"} for an unlockable weapon, {} for a starter, a premium weapon or an unknown id.
static func rule(weapon_id: String) -> Dictionary:
	var d: Dictionary = CombatData.weapon(weapon_id)
	var u: Variant = d.get("unlock", null)
	if not (u is Dictionary) or str(d.get("requires_outfit", "")) != "":
		return {}
	var stat: String = str((u as Dictionary).get("stat", ""))
	var count: int = int((u as Dictionary).get("count", 0))
	if not STAT_WORDS.has(stat) or count <= 0:
		return {}
	return {"stat": stat, "count": count}


static func is_unlockable(weapon_id: String) -> bool:
	return not rule(weapon_id).is_empty()


## Every unlockable weapon id, in data order.
static func unlockable_ids() -> Array:
	var out: Array = []
	for id: String in CombatData.weapon_ids():
		if is_unlockable(id):
			out.append(id)
	return out


## The entitlement token for an earned weapon, as it sits in an `owned` list.
static func token(weapon_id: String) -> String:
	return TOKEN_PREFIX + weapon_id


static func _count(progress: Dictionary, stat: String) -> int:
	return maxi(int(progress.get(stat, 0)), 0)


## True for a starter, and for an unlockable weapon whose milestone `progress` has reached. Premium weapons are not
## decided here (LoadoutRules checks their outfit).
static func is_unlocked(weapon_id: String, progress: Dictionary) -> bool:
	var r: Dictionary = rule(weapon_id)
	if r.is_empty():
		return true
	return _count(progress, str(r["stat"])) >= int(r["count"])


## The unlockable weapons `progress` has earned, in data order.
static func earned_ids(progress: Dictionary) -> Array:
	var out: Array = []
	for id: String in unlockable_ids():
		if is_unlocked(id, progress):
			out.append(id)
	return out


## The `owned` list for LoadoutRules: the store's product ids plus a token per earned weapon (every unlockable weapon
## with `unlock_all`, the --unlock-all bypass; never pass it for a ranked match).
static func access(store_owned: Array, progress: Dictionary, unlock_all: bool) -> Array:
	var out: Array = store_owned.duplicate()
	for id: String in (unlockable_ids() if unlock_all else earned_ids(progress)):
		out.append(token(id))
	return out


## "Win 4 fights" ("" for a weapon with no milestone).
static func requirement_text(weapon_id: String) -> String:
	var r: Dictionary = rule(weapon_id)
	if r.is_empty():
		return ""
	var n: int = int(r["count"])
	var words: Array = STAT_WORDS[str(r["stat"])]
	return str(words[0 if n == 1 else 1]) % n


## "Win 4 fights (1/4)": the milestone with how far `progress` has got ("" for a weapon with no milestone).
static func progress_text(weapon_id: String, progress: Dictionary) -> String:
	var r: Dictionary = rule(weapon_id)
	if r.is_empty():
		return ""
	var n: int = int(r["count"])
	return "%s (%d/%d)" % [requirement_text(weapon_id), mini(_count(progress, str(r["stat"])), n), n]


## Weapons unlocked by going from `before` to `after` (data order), for the "Unlocked:" line after a fight.
static func newly_unlocked(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for id: String in unlockable_ids():
		if not is_unlocked(id, before) and is_unlocked(id, after):
			out.append(id)
	return out
