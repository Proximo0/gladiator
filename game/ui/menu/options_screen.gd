class_name OptionsScreen
extends Control
## Volume sliders (master, sfx, crowd), graphics quality (low/medium/high; includes blood), fullscreen, and the controls reference page.

signal back

var settings: MenuSettings
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _main: VBoxContainer
var _controls_page: VBoxContainer
var _quality: MenuPicker
var _fullscreen: MenuPicker
var _first: Control
var _on_controls: bool = false
var _controls_back: Button


func _init(p_settings: MenuSettings) -> void:
	settings = p_settings
	theme = MenuTheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.012, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(1000.0, 0.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.name = "Scroll"
	add_child(scroll)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_main()
	_build_controls()
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_left", 28)
	holder.add_theme_constant_override("margin_right", 28)
	holder.add_theme_constant_override("margin_top", 20)
	holder.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(holder)
	holder.add_child(_main)
	holder.add_child(_controls_page)
	_controls_page.visible = false
	resized.connect(_relayout)


func _panel(inner: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(inner)
	return p


func _build_main() -> void:
	_main = VBoxContainer.new()
	_main.alignment = BoxContainer.ALIGNMENT_CENTER
	_main.add_theme_constant_override("separation", 16)
	var head := MenuTheme.label("OPTIONES / Options", 52)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main.add_child(head)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var panel := _panel(v)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(900.0, 0.0)
	_main.add_child(panel)
	v.add_child(MenuTheme.label("Sound", MenuTheme.FONT_SMALL, MenuTheme.OCHRE))
	for k: Array in [["master", "Master"], ["sfx", "Effects"], ["crowd", "Crowd"]]:
		v.add_child(_slider_row(str(k[0]), str(k[1])))
	v.add_child(MenuTheme.label("Graphics", MenuTheme.FONT_SMALL, MenuTheme.OCHRE))
	_quality = MenuPicker.new()
	_quality.custom_minimum_size = Vector2(0.0, MenuTheme.ROW_H)
	_quality.setup("Graphics", MenuSettings.QUALITY_NAMES, str(settings.gfx_quality))
	_quality.changed.connect(func(id: String) -> void:
		settings.gfx_quality = int(id)
		settings.save_file())
	v.add_child(_quality)
	if not OS.has_feature("mobile"):
		_fullscreen = MenuPicker.new()
		_fullscreen.custom_minimum_size = Vector2(0.0, MenuTheme.ROW_H)
		_fullscreen.setup("Fullscreen", [["0", "Off"], ["1", "On"]], "1" if settings.fullscreen else "0")
		_fullscreen.changed.connect(func(id: String) -> void:
			settings.fullscreen = id == "1"
			settings.apply()
			settings.save_file())
		v.add_child(_fullscreen)
	v.add_child(MenuTheme.label("Feel", MenuTheme.FONT_SMALL, MenuTheme.OCHRE))
	var motion := MenuPicker.new()
	motion.custom_minimum_size = Vector2(0.0, MenuTheme.ROW_H)
	motion.setup("Reduced motion (no camera shake)", [["0", "Off"], ["1", "On"]], "1" if settings.reduced_motion else "0")
	motion.changed.connect(func(id: String) -> void:
		settings.reduced_motion = id == "1"
		settings.apply()
		settings.save_file())
	v.add_child(motion)
	var rumble := MenuPicker.new()
	rumble.custom_minimum_size = Vector2(0.0, MenuTheme.ROW_H)
	rumble.setup("Controller rumble and vibration", [["1", "On"], ["0", "Off"]], "1" if settings.rumble else "0")
	rumble.changed.connect(func(id: String) -> void:
		settings.rumble = id == "1"
		settings.apply()
		settings.save_file())
	v.add_child(rumble)
	var controls := MenuTheme.button("Controls")
	controls.pressed.connect(_show_controls.bind(true))
	v.add_child(controls)
	var back_btn := MenuTheme.button("Back", 320.0)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func() -> void: back.emit())
	_main.add_child(back_btn)
	_first = _sliders["master"]


func _slider_row(key: String, title: String) -> Control:
	var row := HBoxContainer.new()
	var l := MenuTheme.label(title, MenuTheme.FONT_SMALL)
	l.custom_minimum_size = Vector2(230.0, 0.0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(settings.volumes[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(300.0, MenuTheme.ROW_H)
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var pct := MenuTheme.label("%d%%" % roundi(s.value * 100.0), MenuTheme.FONT_SMALL)
	pct.custom_minimum_size = Vector2(100.0, 0.0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	s.value_changed.connect(func(v: float) -> void:
		settings.volumes[key] = v
		pct.text = "%d%%" % roundi(v * 100.0)
		settings.apply()
		settings.save_file())
	_sliders[key] = s
	_value_labels[key] = pct
	return row


func _build_controls() -> void:
	_controls_page = VBoxContainer.new()
	_controls_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_controls_page.add_theme_constant_override("separation", 14)
	var head := MenuTheme.label("REGVLAE / Controls", 52)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_page.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	for h: String in ["Action", "Keyboard and mouse", "Gamepad"]:
		grid.add_child(MenuTheme.label(h, 24, MenuTheme.OCHRE))
	for r: Array in ControlsText.TABLE:
		for i: int in 3:
			var l := MenuTheme.label(str(r[i]), 24, MenuTheme.PARCHMENT if i > 0 else MenuTheme.PARCHMENT.darkened(0.15))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(250.0, 0.0)
			grid.add_child(l)
	var panel := _panel(grid)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_controls_page.add_child(panel)
	var touch := MenuTheme.label("Touch: left thumb moves; drag on the right side to steer the weapon hand and swing; buttons for thrust, off hand, half-sword, sprint and grab.\nTwo players: player 1 uses the keyboard and mouse, player 2 the gamepad.", 24, MenuTheme.PARCHMENT)
	touch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	touch.custom_minimum_size = Vector2(900.0, 0.0)
	touch.name = "TouchNote"
	_controls_page.add_child(touch)
	_controls_back = MenuTheme.button("Back", 320.0)
	_controls_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_controls_back.pressed.connect(_show_controls.bind(false))
	_controls_page.add_child(_controls_back)


func _show_controls(on: bool) -> void:
	_on_controls = on
	_main.visible = not on
	_controls_page.visible = on
	if on:
		_controls_back.grab_focus()
	else:
		_first.grab_focus()


func open(controls_page: bool = false) -> void:
	_show_controls(controls_page)
	if not controls_page:
		_first.grab_focus()


func _relayout() -> void:
	var wide: float = clampf(size.x - 80.0, 400.0, 1100.0)
	var panel: Control = _main.get_child(1)
	panel.custom_minimum_size = Vector2(minf(wide, 900.0), 0.0)
	(_controls_page.get_node("TouchNote") as Label).custom_minimum_size = Vector2(minf(wide, 900.0), 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _on_controls:
		_show_controls(false)
	else:
		back.emit()
	get_viewport().set_input_as_handled()
