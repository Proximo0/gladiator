class_name LoadoutScreen
extends Control
## Pick weapon, off hand and armor before a fight, with a rotating 3D preview. Vs CPU: the player's column, the
## preview, and the opponent's column (random, shown and re-rollable, or custom) with a difficulty pick.
## Local 2P: a column per player. Start emits start(mode).

signal start(mode: String)
signal back

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
	_preview.show_loadouts([LoadoutRules.sanitize(state.loadouts[0]), LoadoutRules.sanitize(b)])
	var left: String = LoadoutRules.display_name(str(state.loadouts[0]["weapon"]))
	var right: String = LoadoutRules.display_name(str(b["weapon"]))
	_vs.text = "%s  VS  %s" % [left, right]


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
