class_name StoreEpic
extends Store
## PC store: Epic Games Store through Epic Online Services (EOS) Ecom. NOT WIRED YET: every call reports "Store
## unavailable", so a release build can never grant an outfit for free. docs/shop.md has the Epic portal steps.
##
## To finish (needs an EOS GDExtension or a small C++ module exposing the EOS SDK; the EOS SDK is C):
##  1. Init EOS_Platform with the product, sandbox, deployment and client ids from the Epic Dev Portal, and log the
##     player in with Epic Account Services (EOS_Auth_Login via the launcher: `-AUTH_TYPE=exchangecode`,
##     `-AUTH_PASSWORD`, `-epicuserid` command line args that the Epic launcher passes).
##  2. Offers: EOS_Ecom_QueryOffers (LocalUserId) then EOS_Ecom_CopyOfferByIndex for each offer. Match an offer to a
##     product by its catalog offer id: keep the mapping offer id = the product id from data/outfits.json
##     (sandblood.outfit.samurai / .alien). CurrentPrice64 and CurrencyCode give the price: format them into
##     _prices[product_id] and emit products_changed.
##  3. purchase(pid): EOS_Ecom_Checkout with the offer id. The Epic overlay opens. The result callback gives
##     EOS_Success (then _grant and _finish(pid, true, "")), EOS_Ecom_PurchaseCanceled or an error (_finish false).
##  4. Entitlements: EOS_Ecom_QueryEntitlements, then EOS_Ecom_GetEntitlementsCount / CopyEntitlementByIndex. An
##     entitlement whose id matches a product is owned. Call it at launch and from restore_purchases() (an Epic
##     purchase is tied to the account, so "restore" is just a re-query; emit restore_finished after).
##  5. Outfits are durable (not consumable), so never call EOS_Ecom_RedeemEntitlements.


func backend_name() -> String:
	return "epic"


func is_available() -> bool:
	return false  # flip when the steps above are written
