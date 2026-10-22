# Shop and outfits

Sandblood sells cosmetic outfits (Samurai, Alien). They never change a stat, a hitbox, mass or a rule, so they are fair
in ranked online. The owner asked for $5 each.

## Price: $4.99 or $5.00
Stores sell from price tiers, not free-form prices. Google Play and Epic both offer $4.99 and $5.00 as tiers in USD,
but $4.99 is the usual "5 dollar" price point and is what `data/outfits.json` uses as `fallback_price`. Pick one tier
per store and set the same one on both outfits. In the game the displayed price is always the store's localized
label (`Store.price_label`); the fallback only shows while the store has not answered. **Decision needed: $4.99
(assumed) or $5.00.** Changing it is a store-side edit plus the fallback string.

## Pieces
- `data/outfits.json`: `default` (free), `samurai` and `alien` (premium), each with a name, blurb, store
  `product_id` (`sandblood.outfit.samurai`, `sandblood.outfit.alien`), `fallback_price` and a `palette`.
- `game/logic/outfit_rules.gd` (`OutfitRules`): ids, product lookup, palette, entitlement (`usable_id`, `can_equip`),
  and the loadout key `"outfit"` (`with_outfit`, `outfit_of`). A loadout without the key is the default outfit.
- `game/store/`: `Store` (interface: `products`, `price_label`, `purchase(product_id) -> Signal`, `restore_purchases`,
  `owned`, signals `purchase_finished`, `restore_finished`, `products_changed`), `StoreLocal` (dev: instant and free,
  owned list in `user://store_local.json`, memory only in scripted runs), `StoreStub` (tests), `StoreGooglePlay` and
  `StoreEpic` (documented stubs, report "Store unavailable" until wired) and `StoreFactory.create()`.
- `MenuState.store` holds the store; `MenuState.set_outfit` refuses a locked outfit and `to_config` puts
  `"outfit"` in the human loadouts, falling back to the default when not owned.
- `ShopScreen` (`game/ui/menu/shop_screen.gd`): a card per outfit with a rotating preview, price, Buy / Equip /
  Equipped, and Restore Purchases. The loadout screen has an Outfit picker; a locked outfit shows a lock, a note
  and a "Get in shop" button (signal `LoadoutScreen.shop`).

## Which store backend runs
`StoreFactory.create()`: `--store=local|google_play|epic` forces one. Otherwise debug builds and `--dev` get
`StoreLocal`; a release build on Android gets `StoreGooglePlay`, anything else `StoreEpic`. A release build never gets
`StoreLocal`, so nothing is ever given away. Until a real backend is written its `is_available()` is false and the shop
shows "Not available" on the Buy button.

## Entitlements
Checked on the local player's own pick (`OutfitRules.usable_id` against `store.owned()`) when the outfit is picked and
again when the match config is built (a refund drops you back to the default). Online, the outfit id rides in the
loadout and the other side just draws it: no entitlement check, because it is cosmetic and cannot affect play. An
unknown id from the network draws as the default.

## Art
`FighterArt` loads `res://assets/outfits/<outfit>/<part>.glb` per part when the file exists (same 13 part names as
`assets/body/`; one `head`, no `head_b`). Missing parts fall back to the base body tinted with the outfit `palette`:
`cloth` recolours "cloth" surfaces, `armor` (plus `metal`, `rough`) replaces "skin" surfaces on the parts listed in
`covered`, and an optional `skin` replaces the skin tone on uncovered parts. The seeded skin tone never shows on a
covered part. Outfit art keeps its own materials, except "skin"-named surfaces on uncovered parts, which still take the
skin tone. Dismemberment caps always come from `assets/body/`.

## Epic Games Store (PC, the chosen store)
Backend: `StoreEpic`, using EOS Ecom (offers and entitlements). Steps on the Epic side:
1. Get onboarded as a publisher: create an Epic Games account for the organization, accept the agreements in the
   Epic Games Dev Portal (dev.epicgames.com/portal), and apply for Epic Games Store distribution. EGS store
   onboarding (store page, age rating, review, tax and bank details) is required before real purchases work, and
   takes weeks, so start it early.
2. Create the Product for Sandblood, then a Sandbox and a Deployment (a Dev and a Live one). Create a Client policy
   with Ecom access and note the product id, sandbox id, deployment id, client id and secret.
3. In the Store / Catalog section (Epic Games Store, "Manage Store Items" / catalog items), create one item per outfit:
   type Durable, named Samurai Outfit and Alien Outfit, with the id exactly `sandblood.outfit.samurai` and
   `sandblood.outfit.alien`.
4. Create an Offer for each item (the offer is what a player buys). Set the price in the offer's pricing section
   (USD base price, the other regions follow Epic's regional price tiers: choose the $4.99 or $5.00 tier). Publish the
   items and offers to the Live sandbox when the store page is approved. Use the Dev sandbox to test.
5. Wire `StoreEpic` (steps are in its file comment): login with Epic Account Services, query offers, checkout, query
   entitlements at launch and on Restore Purchases. Entitlements are durable: never redeem them.
6. The build ships through the Epic launcher / Epic Games Store build upload (BuildPatch Tool); players must launch
   via the launcher so the exchange code is passed.

## Google Play (Android)
Backend: `StoreGooglePlay` with the GodotGooglePlayBilling plugin (steps in its file comment). In Play Console: create
the app, then Monetize > In-app products: two managed products with ids `sandblood.outfit.samurai` and
`sandblood.outfit.alien`, a price each ($4.99 or $5.00), status Active. Upload a build signed with the app's key to a
testing track and add licence testers. Acknowledge each purchase within 3 days (non-consumable).

## Other stores
Steam would be a `StoreSteam` over the Steamworks inventory / microtransaction API. Not planned.

## For the other workers
See the lead's notes: the title screen needs a Shop entry that opens `ShopScreen`; the online lobby and START carry the
`"outfit"` key; `LoadoutRules.sanitize` strips it today (see the report).
