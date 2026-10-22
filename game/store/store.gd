class_name Store
extends RefCounted
## The cash-shop interface every backend implements (StoreLocal for dev, StoreStub for tests, StoreGooglePlay on
## Android, StoreEpic on PC). Products are cosmetic outfits keyed by product id (see OutfitRules.product_id).
## The owned set is a list of product ids. Purchases finish through `purchase_finished`, possibly many frames later,
## so a caller connects first, then calls purchase(). Nothing here touches the match: outfits are cosmetic only.

signal purchase_finished(product_id: String, ok: bool, message: String)
signal restore_finished(ok: bool, message: String)
signal products_changed  ## prices arrived or the owned set changed

var _owned: Dictionary = {}  ## product id -> true
var _prices: Dictionary = {}  ## product id -> localized price label from the store


## Short backend name for logs and the shop footer ("local", "stub", "google_play", "epic").
func backend_name() -> String:
	return "base"


## False when purchases cannot work here (a store not wired, no network). The shop then shows "Store unavailable".
func is_available() -> bool:
	return false


## Product ids the shop lists.
func products() -> Array:
	return OutfitRules.premium_ids().map(func(id: String) -> String: return OutfitRules.product_id(id))


## Ask the store for current prices (a backend may do this asynchronously and then emit products_changed).
func refresh_products() -> void:
	pass


## The label to show: the store's localized price when known, else the data file's fallback.
func price_label(product_id: String) -> String:
	if _prices.has(product_id):
		return str(_prices[product_id])
	return OutfitRules.fallback_price(OutfitRules.outfit_for_product(product_id))


## Start a purchase. Always ends with purchase_finished(product_id, ok, message). Returns that signal to await.
func purchase(product_id: String) -> Signal:
	_finish(product_id, false, "Store unavailable")
	return purchase_finished


## Re-grant everything the account owns (a new device, a reinstall). Ends with restore_finished.
func restore_purchases() -> void:
	restore_finished.emit(false, "Store unavailable")


## Owned product ids.
func owned() -> Array:
	return _owned.keys()


func owns(product_id: String) -> bool:
	return _owned.has(product_id)


func _grant(product_id: String) -> void:
	if product_id == "" or _owned.has(product_id):
		return
	_owned[product_id] = true
	products_changed.emit()


func _finish(product_id: String, ok: bool, message: String) -> void:
	purchase_finished.emit(product_id, ok, message)


## Whether `product_id` is one this game sells.
func is_known(product_id: String) -> bool:
	return OutfitRules.outfit_for_product(product_id) != ""
