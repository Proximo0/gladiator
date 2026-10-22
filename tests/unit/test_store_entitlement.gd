extends TestCase
## MenuState + store: outfits are picked only when owned, and the match gets the outfit id in the loadout.

const SAM: String = "sandblood.outfit.samurai"


func _state() -> MenuState:
	var m := MenuState.new()
	m.store = StoreStub.new()
	return m


func test_locked_outfit_cannot_be_picked() -> void:
	var m: MenuState = _state()
	assert_false(m.set_outfit(0, "samurai"))
	assert_eq(m.outfit_for(0), "default")
	assert_true(m.set_outfit(0, "default"))


func test_buy_then_pick() -> void:
	var m: MenuState = _state()
	m.store.purchase(SAM)
	assert_true(m.set_outfit(0, "samurai"))
	assert_eq(m.outfit_for(0), "samurai")
	assert_false(m.set_outfit(1, "alien"))


func test_config_carries_outfit_only_when_owned() -> void:
	var m: MenuState = _state()
	m.outfits[0] = "samurai"  # a stale pick, never bought
	var cfg: Dictionary = m.to_config("player_vs_cpu", 3)
	assert_eq(OutfitRules.outfit_of((cfg["loadouts"] as Array)[0]), "default")
	m.store.purchase(SAM)
	cfg = m.to_config("player_vs_cpu", 3)
	assert_eq(OutfitRules.outfit_of((cfg["loadouts"] as Array)[0]), "samurai")
	assert_eq((cfg["loadouts"] as Array).size(), 1)
	var two: Dictionary = m.to_config("local_2p", 3)
	assert_eq(OutfitRules.outfit_of((two["loadouts"] as Array)[0]), "samurai")
	assert_eq(OutfitRules.outfit_of((two["loadouts"] as Array)[1]), "default")


func test_refund_drops_back_to_default() -> void:
	var m: MenuState = _state()
	var stub: StoreStub = m.store as StoreStub
	stub.purchase(SAM)
	m.set_outfit(0, "samurai")
	stub._owned.clear()
	assert_eq(m.outfit_for(0), "default")


func test_remote_outfit_is_just_shown() -> void:
	# An opponent's loadout needs no entitlement here; an unknown id still falls back to the default look.
	assert_eq(OutfitRules.outfit_of({"outfit": "alien"}), "alien")
	assert_eq(OutfitRules.outfit_of({"outfit": "future_outfit"}), "default")


func test_default_config_has_no_outfit_key() -> void:
	var m: MenuState = _state()
	var cfg: Dictionary = m.to_config("player_vs_cpu", 1)
	assert_false(((cfg["loadouts"] as Array)[0] as Dictionary).has("outfit"))
