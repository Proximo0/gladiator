class_name PreviewFrame
extends Control
## The loadout screen's 3D preview in its frame: a warm pool of light behind the plinth, bronze corner brackets, the
## LoadoutPreview itself (drag across it to turn it), and, while a locked weapon is browsed, a banner over its foot
## with a padlock, the weapon's name, what unlocks it and a progress bar.

var preview: LoadoutPreview
var _banner: PanelContainer
var _lock_name: Label
var _lock_why: Label
var _bar: Control
var _frac: float = 0.0
var _dragging: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	preview = LoadoutPreview.new()
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.07, 0.045, 0.035, 0.9), MenuTheme.OCHRE, 2, 12.0))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(row)
	var lock := LoadoutScreen.OutfitLockIcon.new()
	lock.custom_minimum_size = Vector2(34.0, 40.0)
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lock)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_lock_name = MenuTheme.label("", 30, MenuTheme.PARCHMENT)
	_lock_name.clip_text = true
	col.add_child(_lock_name)
	_lock_why = MenuTheme.label("", 22, MenuTheme.OCHRE)
	_lock_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_lock_why)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0.0, 10.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(func() -> void:
		_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), Color(0.2, 0.14, 0.09))
		_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(_bar.size.x * _frac, _bar.size.y)), MenuTheme.RED.lightened(0.1))
		_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), MenuTheme.BRONZE.darkened(0.2), false, 2.0))
	col.add_child(_bar)
	resized.connect(_fit_banner)


## Shows the lock banner for `weapon_id` ("" hides it): `why` says what unlocks it, `frac` (0..1, or -1 for no bar)
## how far along the player is.
func set_lock(weapon_id: String, why: String, frac: float) -> void:
	_banner.visible = weapon_id != ""
	if weapon_id == "":
		return
	_lock_name.text = "%s  -  LOCKED" % LoadoutRules.display_name(weapon_id).to_upper()
	_lock_why.text = why
	_frac = clampf(frac, 0.0, 1.0)
	_bar.visible = frac >= 0.0
	_bar.queue_redraw()
	_fit_banner()


func lock_visible() -> bool:
	return _banner.visible


func _fit_banner() -> void:
	var w: float = minf(size.x - 24.0, 620.0)
	_lock_why.custom_minimum_size.x = maxf(w - 90.0, 60.0)  # wrap at the banner's width, not one word per line
	_banner.reset_size()
	_banner.size.x = w
	_banner.position = Vector2((size.x - w) * 0.5, size.y - _banner.get_combined_minimum_size().y - 12.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		preview.drag((event as InputEventMouseMotion).relative.x)  # a finger arrives as the emulated mouse


## A warm pool of light on the floor of the frame and bronze brackets in its corners.
func _draw() -> void:
	# A dark backing so the arena behind the menu never reads as part of the preview.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.035, 0.025, 0.86))
	var c: Vector2 = Vector2(size.x * 0.5, size.y * 0.62)
	var r: float = maxf(size.x, size.y) * 0.62
	for i: int in 40:  # many faint discs: a smooth pool, no visible bands
		var k: float = 1.0 - float(i) / 40.0
		draw_circle(c, r * k * k, Color(0.85, 0.45, 0.18, 0.012))
	var b: Color = MenuTheme.BRONZE
	var l: float = minf(size.x, size.y) * 0.08
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		var sx: float = 1.0 if corner.x == 0.0 else -1.0
		var sy: float = 1.0 if corner.y == 0.0 else -1.0
		var p: Vector2 = corner + Vector2(sx * 6.0, sy * 6.0)
		draw_polyline(PackedVector2Array([p + Vector2(0.0, sy * l), p, p + Vector2(sx * l, 0.0)]), b, 3.0)
