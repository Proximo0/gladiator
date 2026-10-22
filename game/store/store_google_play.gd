class_name StoreGooglePlay
extends Store
## Android store: Google Play Billing through the GodotGooglePlayBilling plugin (an Android plugin; add it in the
## export preset, it registers the engine singleton "GodotGooglePlayBilling"). NOT WIRED YET: until the plugin is
## present every call reports "Store unavailable", so a build can never grant an outfit for free.
##
## To finish (see docs/shop.md for the Play Console side). With `var _bp: Object = Engine.get_singleton("GodotGooglePlayBilling")`:
##  1. Connect signals: connected, disconnected, connect_error, product_details_query_completed(list),
##     product_details_query_error(code, msg), query_purchases_response(result), purchases_updated(list),
##     purchase_error(code, msg), purchase_acknowledged(token), purchase_consumed(token).
##  2. _bp.startConnection(). On `connected`: _bp.queryProductDetails(PackedStringArray(products()), "inapp") and
##     _bp.queryPurchases("inapp"). Each product detail has product_id and one_time_purchase_offer_details.
##     formatted_price: store it in _prices[product_id] and emit products_changed.
##  3. purchase(pid): _bp.purchase(pid) (older plugin versions: purchase(pid) after querySkuDetails). On
##     purchases_updated with purchase_state == PURCHASED: _grant(product id), _finish(pid, true, ""), then
##     _bp.acknowledgePurchase(purchase_token) within 3 days or Google refunds it. Outfits are non-consumable:
##     never consume them.
##  4. restore_purchases(): _bp.queryPurchases("inapp"), grant (and acknowledge if needed) every PURCHASED entry,
##     then emit restore_finished.
##  5. Send errors (user cancelled, item already owned, billing unavailable) to _finish(pid, false, text); an
##     "already owned" error also means _grant(pid).


func backend_name() -> String:
	return "google_play"


func is_available() -> bool:
	return false  # becomes Engine.has_singleton("GodotGooglePlayBilling") once the steps above are written
