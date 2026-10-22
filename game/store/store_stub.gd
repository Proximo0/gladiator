class_name StoreStub
extends Store
## Scriptable store for tests: choose the result of the next purchase and restore, set prices, and optionally hold a
## purchase pending until complete_pending() is called (to test the "buying..." state).

var result_ok: bool = true
var result_message: String = ""
var hold: bool = false  ## true: purchase() waits for complete_pending()
var restore_grants: Array = []  ## product ids a restore returns
var restore_ok: bool = true
var purchase_calls: Array = []
var restore_calls: int = 0
var available: bool = true
var _pending: String = ""


func backend_name() -> String:
	return "stub"


func is_available() -> bool:
	return available


func set_price(product_id: String, label: String) -> void:
	_prices[product_id] = label
	products_changed.emit()


func purchase(product_id: String) -> Signal:
	purchase_calls.append(product_id)
	if not available:
		_finish(product_id, false, "Store unavailable")
	elif not is_known(product_id):
		_finish(product_id, false, "Unknown product")
	elif hold:
		_pending = product_id
	else:
		_resolve(product_id)
	return purchase_finished


func complete_pending() -> void:
	if _pending != "":
		var p: String = _pending
		_pending = ""
		_resolve(p)


func _resolve(product_id: String) -> void:
	if result_ok:
		_grant(product_id)
	_finish(product_id, result_ok, result_message)


func restore_purchases() -> void:
	restore_calls += 1
	if restore_ok:
		for p: Variant in restore_grants:
			if is_known(str(p)):
				_grant(str(p))
	restore_finished.emit(restore_ok, "" if restore_ok else "Restore failed")
