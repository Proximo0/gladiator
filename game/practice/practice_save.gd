class_name PracticeSave
extends RefCounted
## Remembers whether the player finished (or was already offered) Practice. Kept in user://practice.json when
## `persist` is on; callers pass `not Flags.is_scripted_run()`, so tests, captures and gates never write player data.

const SAVE_PATH: String = "user://practice.json"

var completed: bool = false
var offered: bool = false
var persist: bool = false
var path: String = SAVE_PATH

static var _shared: PracticeSave = null


func _init(p_persist: bool = false, p_path: String = SAVE_PATH) -> void:
	persist = p_persist
	path = p_path
	if persist and FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			completed = bool((d as Dictionary).get("completed", false))
			offered = bool((d as Dictionary).get("offered", false))


static func shared() -> PracticeSave:
	if _shared == null:
		_shared = PracticeSave.new(not Flags.is_scripted_run())
	return _shared


## Replaces the shared instance (tests).
static func open_shared(p_persist: bool, p_path: String = SAVE_PATH) -> PracticeSave:
	_shared = PracticeSave.new(p_persist, p_path)
	return _shared


## True when Quick Match should first offer Practice: never done it, never offered, and a real player run.
func should_offer() -> bool:
	return persist and not completed and not offered


func mark_offered() -> void:
	offered = true
	_save()


func mark_completed() -> void:
	completed = true
	offered = true
	_save()


func _save() -> void:
	if not persist:
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"completed": completed, "offered": offered}))
