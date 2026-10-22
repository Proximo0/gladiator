class_name ShopScreen
extends Control
## The outfit shop, in the Roman menu style: a card per outfit with a rotating 3D preview of a fighter wearing it, its
## price (the store's localized label, else the data file's) and a Buy / Equip / Equipped button, plus Restore
## Purchases and Back. Outfits are cosmetic only. Purchases go through state.store (see game/store/).

signal back

var state: MenuState

var _title: Label
var _scroll: ScrollContainer
var _cards: BoxContainer
var _status: Label
var _restore: Button
var _back: Button
var _card: Dictionary = {}  ## outfit id -> {"button": Button, "price": Label, "preview": LoadoutPreview}
var _busy: String = ""  ## product id of a purchase in flight


func _init(p_state: MenuState) -> void:
	state = p_state
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.012, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28.0
	root.offset_right = -28.0
	root.offset_top = 14.0
	root.offset_bottom = -16.0
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	_title = MenuTheme.label("MERCATUS / Outfitters", 52, MenuTheme.PARCHMENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	var sub := MenuTheme.label("Outfits change how you look, never how you fight.", MenuTheme.FONT_SMALL, MenuTheme.DIM_TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_cards = BoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 20)
	_scroll.add_child(_cards)
	for id: String in OutfitRules.ids():
		_cards.add_child(_make_card(id))
	_status = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.OCHRE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 40)
	root.add_child(foot)
	_back = MenuTheme.button("Back", 300.0)
	_back.pressed.connect(func() -> void: back.emit())
	foot.add_child(_back)
	_restore = MenuTheme.button("Restore Purchases", 420.0)
	_restore.pressed.connect(_on_restore)
	foot.add_child(_restore)
	state.store.purchase_finished.connect(_on_purchase_finished)
	state.store.restore_finished.connect(_on_restore_finished)
	state.store.products_changed.connect(_refresh)
	resized.connect(_relayout)


func _make_card(id: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var nm := MenuTheme.label(OutfitRules.display_name(id), 40, MenuTheme.OCHRE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var pv := LoadoutPreview.new()
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.custom_minimum_size = Vector2(260.0, 380.0)
	v.add_child(pv)
	var blurb := MenuTheme.label(OutfitRules.blurb(id), 22, MenuTheme.DIM_TEXT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.custom_minimum_size = Vector2(0.0, 60.0)
	v.add_child(blurb)
	var price := MenuTheme.label("", 34, MenuTheme.PARCHMENT)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(price)
	var btn: Button = MenuTheme.button("")
	btn.pressed.connect(_on_card_button.bind(id))
	v.add_child(btn)
	_card[id] = {"button": btn, "price": price, "preview": pv}
	return card


func open() -> void:
	_status.text = ""
	_busy = ""
	state.store.refresh_products()
	_refresh()
	for id: String in _card:
		var l: Dictionary = OutfitRules.with_outfit(LoadoutRules.default_loadout(), id)
		((_card[id] as Dictionary)["preview"] as LoadoutPreview).show_loadouts([l])
	_relayout()
	_first_button().grab_focus()


func _first_button() -> Control:
	for id: String in _card:
		var b: Button = (_card[id] as Dictionary)["button"]
		if not b.disabled:
			return b
	return _back


## Button text and price line for outfit `id` right now.
func card_state(id: String) -> Dictionary:
	var owned: Array = state.store.owned()
	var price: String = state.store.price_label(OutfitRules.product_id(id))
	if not OutfitRules.is_premium(id) or owned.has(OutfitRules.product_id(id)):
		var worn: bool = state.outfit_for(0) == id
		return {"button": "Equipped" if worn else "Equip", "price": "Owned" if OutfitRules.is_premium(id) else "Free", "disabled": worn}
	if not state.store.is_available():
		return {"button": "Not available", "price": price, "disabled": true}
	if _busy != "":
		return {"button": "Buying..." if _busy == OutfitRules.product_id(id) else "Buy  " + price, "price": price, "disabled": true}
	return {"button": "Buy  " + price, "price": price, "disabled": false}


func _refresh() -> void:
	for id: String in _card:
		var c: Dictionary = card_state(id)
		var e: Dictionary = _card[id]
		(e["button"] as Button).text = str(c["button"])
		(e["button"] as Button).disabled = bool(c["disabled"])
		(e["price"] as Label).text = str(c["price"])
	_restore.disabled = _busy != ""


func _on_card_button(id: String) -> void:
	if OutfitRules.can_equip(id, state.store.owned()):
		state.set_outfit(0, id)
		_status.text = "%s equipped." % OutfitRules.display_name(id)
		_refresh()
		return
	var pid: String = OutfitRules.product_id(id)
	_busy = pid
	_status.text = "Contacting the store..."
	_refresh()
	state.store.purchase(pid)


func _on_purchase_finished(product_id: String, ok: bool, message: String) -> void:
	_busy = ""
	var id: String = OutfitRules.outfit_for_product(product_id)
	if ok and id != "":
		state.set_outfit(0, id)
		_status.text = "%s is yours, and equipped." % OutfitRules.display_name(id)
	else:
		_status.text = "Purchase failed: %s" % (message if message != "" else "cancelled")
	_refresh()


func _on_restore() -> void:
	_status.text = "Restoring..."
	state.store.restore_purchases()


func _on_restore_finished(ok: bool, message: String) -> void:
	_status.text = "Purchases restored." if ok else "Restore failed: %s" % message
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back.emit()
		get_viewport().set_input_as_handled()


## Landscape: cards side by side. Portrait: stacked, scrolling.
func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_cards.vertical = portrait
	_title.add_theme_font_size_override("font_size", 40 if portrait else 52)
