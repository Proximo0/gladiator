class_name PlayerProgress
extends RefCounted
## The player's play counters that unlock weapons (WeaponUnlocks): fights played and won, ranked Quick Matches
## played and won. Kept in user://progress.json when `persist` is on; the caller passes `not Flags.is_scripted_run()`
## (tests, captures and gates never write player data), and a non-persisting instance lives in memory only.
## One shared instance per run (`shared()`, opened by MenuFlow) so every screen sees the same counters.

const SAVE_PATH: String = "user://progress.json"
const STATS: Array[String] = ["matches", "wins", "ranked_matches", "ranked_wins"]
const VERSION: int = 1

var counters: Dictionary = {}
var persist: bool = false
var path: String = SAVE_PATH

static var _shared: PlayerProgress = null


func _init(p_persist: bool = false, p_path: String = SAVE_PATH) -> void:
	persist = p_persist
	path = p_path
	counters = PlayerProgress.clean({})
	if persist:
		_read()


## The run's progress (an in-memory one until `open_shared` is called).
static func shared() -> PlayerProgress:
	if _shared == null:
		_shared = PlayerProgress.new(false)
	return _shared


## Replaces the run's progress with one read from `p_path` (when `p_persist`). MenuFlow calls it once at setup.
static func open_shared(p_persist: bool, p_path: String = SAVE_PATH) -> PlayerProgress:
	_shared = PlayerProgress.new(p_persist, p_path)
	return _shared


## Every counter present, each a whole number >= 0; unknown keys dropped.
static func clean(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in STATS:
		var v: Variant = d.get(k, 0)
		out[k] = maxi(int(v) if (v is int or v is float) else 0, 0)
	return out


func get_count(stat: String) -> int:
	return int(counters.get(stat, 0))


## Counts a finished fight the local player took part in. `won`: this player won it; `ranked`: a rated Quick Match.
## Returns the weapon ids it unlocked (data order) and saves when persisting.
func record_match(won: bool, ranked: bool) -> Array:
	var before: Dictionary = counters.duplicate()
	counters["matches"] = get_count("matches") + 1
	if won:
		counters["wins"] = get_count("wins") + 1
	if ranked:
		counters["ranked_matches"] = get_count("ranked_matches") + 1
		if won:
			counters["ranked_wins"] = get_count("ranked_wins") + 1
	_save()
	return WeaponUnlocks.newly_unlocked(before, counters)


## The rating service's own record (profile games / wins) is the better source for ranked counts: never go below it
## (a reinstall, a second device). Returns the weapons this unlocked.
func sync_ranked(games: int, wins: int) -> Array:
	var before: Dictionary = counters.duplicate()
	counters["ranked_matches"] = maxi(get_count("ranked_matches"), games)
	counters["ranked_wins"] = maxi(get_count("ranked_wins"), mini(wins, maxi(games, 0)))
	if counters != before:
		_save()
	return WeaponUnlocks.newly_unlocked(before, counters)


func to_dict() -> Dictionary:
	return {"version": VERSION, "counters": counters.duplicate()}


func from_dict(d: Dictionary) -> void:
	var c: Variant = d.get("counters", {})
	counters = PlayerProgress.clean(c if c is Dictionary else {})


func _read() -> void:
	if not FileAccess.file_exists(path):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if v is Dictionary:
		from_dict(v)


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))
