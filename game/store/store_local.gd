class_name StoreLocal
extends Store
## Dev store: buying is instant and free, and the owned list is saved in user://. Never used in a release build (see
## StoreFactory). In scripted runs (tests, captures, headless) nothing is read or written: the set lives in memory.

const SAVE_PATH: String = "user://store_local.json"

var persist: bool = false
var path: String = SAVE_PATH


## `p_persist` should be `not Flags.is_scripted_run()`; the factory passes it, tests leave it false.
func _init(p_persist: bool = false, p_path: String = SAVE_PATH) -> void:
	persist = p_persist
	path = p_path
	if persist:
		_owned = parse_owned(_read())


func backend_name() -> String:
	return "local"


func is_available() -> bool:
	return true


func purchase(product_id: String) -> Signal:
	if not is_known(product_id):
		_finish(product_id, false, "Unknown product")
		return purchase_finished
	_grant(product_id)
	_save()
	_finish(product_id, true, "")
	return purchase_finished


func restore_purchases() -> void:
	if persist:
		var disk: Dictionary = parse_owned(_read())
		for k: Variant in disk:
			_grant(str(k))
	restore_finished.emit(true, "")


## Dev helper: forget every purchase.
func clear() -> void:
	_owned.clear()
	_save()
	products_changed.emit()


static func serialize_owned(owned_ids: Array) -> String:
	var ids: Array = owned_ids.duplicate()
	ids.sort()
	return JSON.stringify({"owned": ids})


## {product id: true} from saved text; a bad file gives an empty set and unknown ids are dropped.
static func parse_owned(text: String) -> Dictionary:
	var out: Dictionary = {}
	var json := JSON.new()
	var data: Variant = json.data if (text != "" and json.parse(text) == OK) else null
	if data is Dictionary and (data as Dictionary).get("owned", []) is Array:
		for p: Variant in (data as Dictionary)["owned"]:
			if OutfitRules.outfit_for_product(str(p)) != "":
				out[str(p)] = true
	return out


func _read() -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _save() -> void:
	if not persist:
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(serialize_owned(owned()))
