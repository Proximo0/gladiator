class_name LoadoutPanel
extends PanelContainer
## One fighter's loadout column: weapon, off hand and four armor slots as pickers, and a stat card for the item
## last focused. Emits loadout_changed(loadout). Extra rows (the CPU's difficulty, say) go in through add_row().

signal loadout_changed(loadout: Dictionary)

const ROW_H: float = 58.0

var weapon_picker: MenuPicker
var offhand_picker: MenuPicker
var armor_pickers: Dictionary = {}
var _header: Label
var _rows: VBoxContainer
var _card_name: Label
var _card_line: Label
var _bars: Dictionary = {}
var _all: Array[MenuPicker] = []
var _quiet: bool = false


func _init() -> void:
	theme = MenuTheme.theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_header = MenuTheme.label("", 38, MenuTheme.OCHRE)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_header)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	v.add_child(_rows)
	var wl: Array = []
	for id: String in LoadoutRules.main_weapons():
		wl.append([id, LoadoutRules.display_name(id)])
	weapon_picker = _add_picker("Weapon", wl)
	var ol: Array = []
	for id: String in LoadoutRules.offhands():
		ol.append([id, LoadoutRules.display_name(id)])
	offhand_picker = _add_picker("Off hand", ol)
	for s: Array in LoadoutRules.ARMOR_SLOTS:
		var items: Array = []
		for id: String in LoadoutRules.armor_options(str(s[0])):
			items.append([id, LoadoutRules.display_name(id)])
		armor_pickers[str(s[0])] = _add_picker(str(s[1]), items)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	v.add_child(card)
	_card_name = MenuTheme.label("", 34, MenuTheme.PARCHMENT)
	_card_name.clip_text = true
	card.add_child(_card_name)
	_card_line = MenuTheme.label("", 24, MenuTheme.DIM_TEXT)
	_card_line.clip_text = true
	card.add_child(_card_line)
	for k: Array in [["cut", "CUT"], ["blunt", "BLUNT"], ["pierce", "PIERCE"]]:
		var bar := MenuStatBar.new(str(k[1]))
		card.add_child(bar)
		_bars[str(k[0])] = bar


func _add_picker(title: String, items: Array) -> MenuPicker:
	var p := MenuPicker.new()
	p.custom_minimum_size = Vector2(0.0, ROW_H)
	p.setup(title, items)
	p.changed.connect(func(_id: String) -> void: _on_picker(p))
	p.focus_entered.connect(_show_card.bind(p))
	p.mouse_entered.connect(_show_card.bind(p))
	_rows.add_child(p)
	_all.append(p)
	return p


## An extra row above the pickers (after the header).
func add_row(c: Control, at_top: bool = true) -> void:
	_rows.add_child(c)
	if at_top:
		_rows.move_child(c, 0)


func set_header(text: String) -> void:
	_header.text = text


func loadout() -> Dictionary:
	var armor: Dictionary = {}
	for slot: String in armor_pickers:
		var id: String = (armor_pickers[slot] as MenuPicker).current_id()
		if id != "":
			armor[slot] = id
	var off: String = "" if LoadoutRules.offhand_blocked(weapon_picker.current_id()) else offhand_picker.current_id()
	return {"weapon": weapon_picker.current_id(), "offhand": off, "armor": armor}


func set_loadout(l: Dictionary) -> void:
	var clean: Dictionary = LoadoutRules.sanitize(l)
	_quiet = true
	weapon_picker.select(str(clean["weapon"]), false)
	_refresh_offhand(str(clean["offhand"]))
	for slot: String in armor_pickers:
		(armor_pickers[slot] as MenuPicker).select(str((clean["armor"] as Dictionary).get(slot, "")), false)
	_quiet = false
	_show_card(weapon_picker)


## Greys out every picker (the opponent is random: shown, not editable).
func set_locked(locked: bool) -> void:
	for p: MenuPicker in _all:
		p.enabled = not locked
	if not locked:
		_refresh_offhand(offhand_picker.current_id())


func first_focus() -> Control:
	return weapon_picker


func _refresh_offhand(wanted: String) -> void:
	var blocked: bool = LoadoutRules.offhand_blocked(weapon_picker.current_id())
	if blocked:
		offhand_picker.items = [["", "Two-handed grip"]]
		offhand_picker.index = 0
		offhand_picker.enabled = false
	else:
		var ol: Array = []
		for id: String in LoadoutRules.offhands():
			ol.append([id, LoadoutRules.display_name(id)])
		offhand_picker.items = ol
		offhand_picker.enabled = true
		offhand_picker.select(wanted, false)
	offhand_picker.queue_redraw()


func _on_picker(p: MenuPicker) -> void:
	if _quiet:
		return
	if p == weapon_picker:
		var keep: String = offhand_picker.current_id() if offhand_picker.enabled else LoadoutRules.DEFAULT_OFFHAND
		_refresh_offhand(keep)
	_show_card(p)
	loadout_changed.emit(loadout())


func _show_card(p: MenuPicker) -> void:
	var id: String = p.current_id()
	var stats: Dictionary
	if p == weapon_picker or p == offhand_picker:
		stats = LoadoutRules.weapon_stats(id)
	else:
		stats = LoadoutRules.armor_stats(id)
	var l: Dictionary = loadout()
	_card_name.text = str(stats["name"]) if id != "" else "%s: none" % p.title
	_card_line.text = str(stats["line"]) if id != "" else "Carrying %.1f kg in all" % LoadoutRules.total_mass(l)
	for k: String in _bars:
		(_bars[k] as MenuStatBar).fraction = float(stats[k]) if id != "" else 0.0
		(_bars[k] as MenuStatBar).queue_redraw()
