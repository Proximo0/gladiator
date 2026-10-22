class_name LoadoutPanel
extends PanelContainer
## One fighter's loadout column: weapon, off hand and four armor slots as pickers, and a stat card for the item
## last focused. Emits loadout_changed(loadout). Extra rows (the CPU's difficulty, say) go in through add_row().
## Locked weapons (premium without the outfit, play-to-unlock not yet earned; see set_weapon_access) stay in the list,
## greyed with a padlock; browsing one shows its stats and a note with what unlocks it, while the loadout keeps the
## last usable weapon ("Fighting with ..."). Locked shields and armor pieces are greyed the same way; picking one
## carries the round shield or the slot's default piece, and the stat card says what unlocks it.

signal loadout_changed(loadout: Dictionary)

const ROW_H: float = 58.0
const ROW_COMPACT_H: float = 48.0
const ROW_TIGHT_H: float = 44.0  ## landscape screens too short for the full column (the opponent's has 9 rows and a card)

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
var _access: Variant = null  ## the `owned` list weapons are checked against (null: everything usable)
var _progress: Dictionary = {}  ## PlayerProgress counters, for the "(1/4)" in the lock note
var _usable_weapon: String = ""  ## the weapon the loadout really carries (the browsed one unless it is locked)
var _lock_note: Label
var _card: Control
var _compact: bool = false
var _tight: bool = false


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
	_usable_weapon = weapon_picker.current_id()
	_lock_note = MenuTheme.label("", 24, MenuTheme.OCHRE)
	_lock_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lock_note.visible = false
	_rows.add_child(_lock_note)
	var ol: Array = []
	for id: String in LoadoutRules.offhands():
		ol.append([id, LoadoutRules.display_name(id)])
	offhand_picker = _add_picker("Off hand", ol)
	for s: Array in LoadoutRules.ARMOR_SLOTS:
		var items: Array = []
		armor_pickers[str(s[0])] = _add_picker(str(s[1]), _armor_items(str(s[0])))
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	v.add_child(card)
	_card = card
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


## Portrait phones: shorter rows and a smaller header, and optionally no stat card, so both panels fit the screen.
func set_compact(compact: bool, show_card: bool = true, tight: bool = false) -> void:
	_compact = compact
	_tight = tight and not compact
	_card.visible = show_card or not compact
	_header.add_theme_font_size_override("font_size", 30 if (compact or _tight) else 38)
	var row_h: float = ROW_COMPACT_H if compact else (ROW_TIGHT_H if _tight else ROW_H)
	for c: Node in _rows.get_children():
		if c is MenuPicker:
			(c as MenuPicker).custom_minimum_size.y = row_h
	_rows.add_theme_constant_override("separation", 5 if (compact or _tight) else 8)
	(_card as VBoxContainer).add_theme_constant_override("separation", 0 if _tight else 4)
	_card_name.add_theme_font_size_override("font_size", 30 if _tight else 34)
	for k: Variant in _bars:
		(_bars[k] as Control).custom_minimum_size.y = 26.0 if _tight else 30.0


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
		if id != "" and (armor_pickers[slot] as MenuPicker).is_locked():
			id = str(LoadoutRules.DEFAULT_ARMOR.get(slot, ""))
		if id != "":
			armor[slot] = id
	var off: String = "" if LoadoutRules.offhand_blocked(_usable_weapon) else offhand_picker.current_id()
	if off != "" and offhand_picker.is_locked():
		off = LoadoutRules.DEFAULT_OFFHAND
	return {"weapon": _usable_weapon, "offhand": off, "armor": armor}


## The loadout as browsed: the weapon and armor on show even when locked (for the preview).
func browsed_loadout() -> Dictionary:
	var l: Dictionary = loadout()
	l["weapon"] = weapon_picker.current_id()
	if offhand_picker.enabled:
		l["offhand"] = offhand_picker.current_id()
	for slot: String in armor_pickers:
		var id: String = (armor_pickers[slot] as MenuPicker).current_id()
		if id != "":
			(l["armor"] as Dictionary)[slot] = id
		else:
			(l["armor"] as Dictionary).erase(slot)
	if LoadoutRules.offhand_blocked(weapon_picker.current_id()):
		l["offhand"] = ""
	return l


## Lists every main weapon and greys the ones `access` does not unlock (an `owned` list from WeaponUnlocks.access;
## null unlocks all). `progress` (PlayerProgress counters) fills the lock note. Keeps the current pick when usable.
func set_weapon_access(access: Variant, progress: Dictionary = {}) -> void:
	_access = access
	_progress = progress.duplicate()
	var keep: String = weapon_picker.current_id()
	var items: Array = []
	for id: String in LoadoutRules.picker_weapons():
		items.append([id, LoadoutRules.display_name(id), not LoadoutRules.weapon_unlocked(id, access)])
	weapon_picker.items = items
	weapon_picker.index = clampi(weapon_picker.index, 0, items.size() - 1)
	weapon_picker.select(keep, false)
	var was: String = _usable_weapon
	if not LoadoutRules.weapon_unlocked(_usable_weapon, access):
		_usable_weapon = LoadoutRules.PREMIUM_FALLBACK
	if not weapon_picker.is_locked():
		_usable_weapon = weapon_picker.current_id()
	if _usable_weapon != was:
		_refresh_offhand(offhand_picker.current_id() if offhand_picker.enabled else LoadoutRules.DEFAULT_OFFHAND)
	elif offhand_picker.enabled:
		_refresh_offhand(offhand_picker.current_id())
	for slot: String in armor_pickers:
		var ap: MenuPicker = armor_pickers[slot]
		var keep_a: String = ap.current_id()
		ap.items = _armor_items(slot)
		ap.index = clampi(ap.index, 0, ap.items.size() - 1)
		ap.select(keep_a, false)
		ap.queue_redraw()
	_sync_lock_note()


func set_loadout(l: Dictionary) -> void:
	var clean: Dictionary = LoadoutRules.sanitize(l, _access)
	_quiet = true
	weapon_picker.select(str(clean["weapon"]), false)
	_usable_weapon = str(clean["weapon"])
	_sync_lock_note()
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


## [[id, label, locked]] for an armor slot's picker: none, then the slot's pieces lightest first.
func _armor_items(slot: String) -> Array:
	var items: Array = []
	for id: String in LoadoutRules.armor_options(slot):
		items.append([id, LoadoutRules.display_name(id), not LoadoutRules.weapon_unlocked(id, _access)])
	return items


func first_focus() -> Control:
	return weapon_picker


func _refresh_offhand(wanted: String) -> void:
	var blocked: bool = LoadoutRules.offhand_blocked(_usable_weapon)
	if blocked:
		offhand_picker.items = [["", "Two-handed grip"]]
		offhand_picker.index = 0
		offhand_picker.enabled = false
	else:
		var ol: Array = []
		for id: String in LoadoutRules.offhands():
			ol.append([id, LoadoutRules.display_name(id), not LoadoutRules.weapon_unlocked(id, _access)])
		offhand_picker.items = ol
		offhand_picker.enabled = true
		offhand_picker.select(wanted, false)
	offhand_picker.queue_redraw()


func _on_picker(p: MenuPicker) -> void:
	if _quiet:
		return
	if p == weapon_picker:
		if not weapon_picker.is_locked():
			_usable_weapon = weapon_picker.current_id()
		_sync_lock_note()
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
	if id != "" and p != weapon_picker and p.is_locked():
		_card_line.text = "Locked: " + LoadoutRules.lock_reason(id, _access, _progress)
	for k: String in _bars:
		(_bars[k] as MenuStatBar).fraction = float(stats[k]) if id != "" else 0.0
		(_bars[k] as MenuStatBar).queue_redraw()


## Shown under the weapon picker while it is on a locked weapon: what unlocks it and what is carried instead.
func _sync_lock_note() -> void:
	var locked: bool = weapon_picker.is_locked()
	_lock_note.visible = locked
	if locked:
		var why: String = LoadoutRules.lock_reason(weapon_picker.current_id(), _access, _progress)
		_lock_note.text = "Locked: %s. Fighting with %s." % [why, LoadoutRules.display_name(_usable_weapon)]
