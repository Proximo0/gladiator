class_name LoadoutScreen
extends Control
## Pick weapon, off hand and armor before a fight, with a rotating 3D preview. Vs CPU: the player's column, the
## preview, and the opponent's column (random, shown and re-rollable, or custom) with a difficulty pick.
## Local 2P: a column per player. Start emits start(mode).

signal start(mode: String)
signal back
signal shop  ## the player wants the outfit shop ("Get in shop" on a locked outfit)

var mode: String = "player_vs_cpu"
var state: MenuState

var _title: Label
var _scroll: ScrollContainer
var _body: BoxContainer
var _panel_a: LoadoutPanel
var _panel_b: LoadoutPanel
var _mid: VBoxContainer
var _preview: LoadoutPreview
var _vs: Label
var _reroll: Button
var _cpu_mode: MenuPicker
var _cpu_diff: MenuPicker
var _cpu_level: MenuPicker
var _diff_note: Label
var _start: Button
var _back: Button
var _outfit_rows: Array[Control] = []  ## per side: the picker row (a VBox with picker, lock note, shop button)
var _outfit_pickers: Array[MenuPicker] = []
var _outfit_notes: Array[Label] = []
var _outfit_locks: Array[Control] = []
var _outfit_shop: Array[Button] = []
var _browsing: Array[String] = [OutfitRules.DEFAULT_ID, OutfitRules.DEFAULT_ID]  ## what each picker shows (maybe locked)


func _init(p_state: MenuState) -> void:
	state = p_state
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.012, 0.62)
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
	_title = MenuTheme.label("ARMA / Choose your arms", 52, MenuTheme.PARCHMENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_body = BoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 20)
	_scroll.add_child(_body)

	_panel_a = LoadoutPanel.new()
	_panel_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_a.loadout_changed.connect(_on_a)
	_panel_a.add_row(_make_outfit_row(0))
	_body.add_child(_panel_a)

	_mid = VBoxContainer.new()
	_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mid.size_flags_stretch_ratio = 1.1
	_preview = LoadoutPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(300.0, 520.0)
	_mid.add_child(_preview)
	_vs = MenuTheme.label("", 30, MenuTheme.PARCHMENT)
	_vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs.clip_text = true
	_mid.add_child(_vs)
	_reroll = MenuTheme.button("Re-roll opponent")
	_reroll.pressed.connect(_on_reroll)
	_mid.add_child(_reroll)
	_body.add_child(_mid)

	_panel_b = LoadoutPanel.new()
	_panel_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_b.loadout_changed.connect(_on_b)
	_panel_b.add_row(_make_outfit_row(1))
	_cpu_mode = MenuPicker.new()
	_cpu_mode.custom_minimum_size = Vector2(0.0, LoadoutPanel.ROW_H)
	_cpu_mode.setup("Loadout", [[MenuState.CPU_RANDOM, "Random"], [MenuState.CPU_CUSTOM, "Pick"]])
	_cpu_mode.changed.connect(_on_cpu_mode)
	_cpu_diff = MenuPicker.new()
	_cpu_diff.custom_minimum_size = Vector2(0.0, LoadoutPanel.ROW_H)
	var dl: Array = []
	for p: Array in MenuState.PERSONALITIES:
		dl.append([str(p[0]), str(p[1])])
	_cpu_diff.setup("Style", dl)
	_cpu_diff.changed.connect(_on_diff)
	_cpu_level = MenuPicker.new()
	_cpu_level.custom_minimum_size = Vector2(0.0, LoadoutPanel.ROW_H)
	var ll: Array = []
	for d: Array in MenuState.DIFFICULTIES:
		ll.append([str(d[0]), str(d[1])])
	_cpu_level.setup("Difficulty", ll)
	_cpu_level.changed.connect(_on_level)
	_panel_b.add_row(_cpu_level)
	_panel_b.add_row(_cpu_diff)
	_panel_b.add_row(_cpu_mode)
	_diff_note = MenuTheme.label("", 22, MenuTheme.DIM_TEXT)
	_diff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_note.custom_minimum_size = Vector2(0.0, 84.0)
	_panel_b.add_row(_diff_note, false)
	_body.add_child(_panel_b)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 40)
	root.add_child(foot)
	_back = MenuTheme.button("Back", 300.0)
	_back.pressed.connect(func() -> void: back.emit())
	foot.add_child(_back)
	_start = MenuTheme.button("FIGHT!", 420.0)
	_start.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.RED, MenuTheme.OCHRE, 4))
	_start.pressed.connect(func() -> void: start.emit(mode))
	foot.add_child(_start)
	resized.connect(_relayout)


func open(p_mode: String) -> void:
	mode = p_mode
	var two: bool = mode == "local_2p"
	if not two and state.cpu_loadout_mode == MenuState.CPU_RANDOM and state.cpu_seed == 1:
		state.cpu_seed = int(Time.get_ticks_usec() & 0x7fffffff)
	_panel_a.set_header("YOU" if not two else "PLAYER 1  -  mouse and keys")
	_panel_b.set_header("PLAYER 2  -  gamepad" if two else "OPPONENT")
	_panel_a.set_loadout(state.loadouts[0])
	_outfit_rows[1].visible = two
	refresh_outfits()
	_cpu_mode.visible = not two
	_cpu_diff.visible = not two
	_cpu_level.visible = not two
	_diff_note.visible = not two
	_reroll.visible = not two
	_cpu_mode.select(state.cpu_loadout_mode, false)
	_cpu_diff.select(state.cpu_personality, false)
	_cpu_level.select(state.cpu_difficulty, false)
	_sync_opponent()
	_relayout()
	_panel_a.first_focus().grab_focus()


func focus_start() -> void:
	_start.grab_focus()


func _sync_opponent() -> void:
	var two: bool = mode == "local_2p"
	var random_cpu: bool = (not two) and state.cpu_loadout_mode == MenuState.CPU_RANDOM
	_panel_b.set_locked(false)
	_panel_b.set_loadout(state.cpu_shown_loadout() if not two else state.loadouts[1])
	_panel_b.set_locked(random_cpu)
	_reroll.visible = random_cpu
	_diff_note.text = _note_text()
	_refresh_preview()


func _note_for(id: String) -> String:
	for p: Array in MenuState.PERSONALITIES:
		if str(p[0]) == id:
			return str(p[2])
	return ""


func _note_text() -> String:
	return "%s  %s" % [_note_for(state.cpu_personality), AiDifficulty.note(state.cpu_difficulty)]


func _refresh_preview() -> void:
	var two: bool = mode == "local_2p"
	var b: Dictionary = state.loadouts[1] if (two or state.cpu_loadout_mode == MenuState.CPU_CUSTOM) else state.cpu_shown_loadout()
	var left_look: Dictionary = OutfitRules.with_outfit(LoadoutRules.sanitize(state.loadouts[0]), _browsing[0])
	var right_look: Dictionary = LoadoutRules.sanitize(b)
	if two:
		right_look = OutfitRules.with_outfit(right_look, _browsing[1])
	_preview.show_loadouts([left_look, right_look])
	var left: String = LoadoutRules.display_name(str(state.loadouts[0]["weapon"]))
	var right: String = LoadoutRules.display_name(str(b["weapon"]))
	_vs.text = "%s  VS  %s" % [left, right]


## One side's outfit pick: a picker, then (while the choice is locked) a lock icon, a note and a "Get in shop" button.
func _make_outfit_row(side: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var pk := MenuPicker.new()
	pk.custom_minimum_size = Vector2(0.0, LoadoutPanel.ROW_H)
	pk.setup("Outfit", _outfit_items())
	pk.changed.connect(_on_outfit.bind(side))
	box.add_child(pk)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var lock := OutfitLockIcon.new()
	lock.custom_minimum_size = Vector2(30.0, 34.0)
	line.add_child(lock)
	var note := MenuTheme.label("", 22, MenuTheme.OCHRE)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(note)
	line.visible = false
	box.add_child(line)
	var sb: Button = MenuTheme.button("Get in shop")
	sb.custom_minimum_size.y = 48.0
	sb.visible = false
	sb.pressed.connect(func() -> void: shop.emit())
	box.add_child(sb)
	_outfit_rows.append(box)
	_outfit_pickers.append(pk)
	_outfit_notes.append(note)
	_outfit_locks.append(line)
	_outfit_shop.append(sb)
	return box


## [[id, label]] for the picker; a locked outfit's label carries its price.
func _outfit_items() -> Array:
	var owned: Array = state.store.owned()
	var items: Array = []
	for id: String in OutfitRules.ids():
		var label: String = OutfitRules.display_name(id)
		if not OutfitRules.can_equip(id, owned):
			label += "  " + state.store.price_label(OutfitRules.product_id(id))
		items.append([id, label])
	return items


## Re-reads what is owned (call when the screen opens or after a shop visit).
func refresh_outfits() -> void:
	for side: int in 2:
		var pk: MenuPicker = _outfit_pickers[side]
		pk.items = _outfit_items()
		_browsing[side] = state.outfit_for(side)
		pk.select(_browsing[side], false)
		_sync_outfit_row(side)
	_refresh_preview()


func _sync_outfit_row(side: int) -> void:
	var id: String = _browsing[side]
	var locked: bool = not OutfitRules.can_equip(id, state.store.owned())
	_outfit_locks[side].visible = locked
	_outfit_shop[side].visible = locked
	if locked:
		_outfit_notes[side].text = "Locked. Fighting as %s." % OutfitRules.display_name(state.outfit_for(side))


func _on_outfit(id: String, side: int) -> void:
	_browsing[side] = OutfitRules.clean_id(id)
	state.set_outfit(side, _browsing[side])  # refused while locked: the last owned pick stays
	_sync_outfit_row(side)
	_refresh_preview()


func _on_a(l: Dictionary) -> void:
	state.set_loadout(0, l)
	_refresh_preview()


func _on_b(l: Dictionary) -> void:
	if mode == "local_2p" or state.cpu_loadout_mode == MenuState.CPU_CUSTOM:
		state.set_loadout(1, l)
	_refresh_preview()


func _on_cpu_mode(id: String) -> void:
	state.cpu_loadout_mode = id
	if id == MenuState.CPU_CUSTOM:
		state.loadouts[1] = LoadoutRules.sanitize(MenuState.rolled_opponent(state.cpu_seed))
	_sync_opponent()


func _on_diff(id: String) -> void:
	state.cpu_personality = id
	_diff_note.text = _note_text()


func _on_level(id: String) -> void:
	state.cpu_difficulty = AiDifficulty.normalize(id)
	_diff_note.text = _note_text()


func _on_reroll() -> void:
	state.cpu_seed = (state.cpu_seed * 1103515245 + 12345 + int(Time.get_ticks_usec())) & 0x7fffffff
	_sync_opponent()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back.emit()
		get_viewport().set_input_as_handled()


## Landscape: three columns. Portrait: preview on top, then the two columns stacked, scrolling.
func _relayout() -> void:
	var portrait: bool = size.x < size.y * 1.05
	_body.vertical = portrait
	_title.add_theme_font_size_override("font_size", 40 if portrait else 52)
	if portrait:
		_body.move_child(_mid, 0)
		_preview.custom_minimum_size = Vector2(300.0, 460.0)
		_panel_a.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		_body.move_child(_mid, 1)
		_preview.custom_minimum_size = Vector2(300.0, 420.0)


## A small padlock for locked outfits (drawn, so it needs no font glyph).
class OutfitLockIcon extends Control:
	func _draw() -> void:
		var c: Color = MenuTheme.OCHRE
		var w: float = size.x
		var h: float = size.y
		draw_arc(Vector2(w * 0.5, h * 0.42), w * 0.28, PI, TAU, 14, c, 3.0, true)
		draw_line(Vector2(w * 0.22, h * 0.42), Vector2(w * 0.22, h * 0.5), c, 3.0)
		draw_line(Vector2(w * 0.78, h * 0.42), Vector2(w * 0.78, h * 0.5), c, 3.0)
		draw_rect(Rect2(w * 0.1, h * 0.5, w * 0.8, h * 0.42), c)
		draw_circle(Vector2(w * 0.5, h * 0.7), w * 0.08, MenuTheme.INK)
