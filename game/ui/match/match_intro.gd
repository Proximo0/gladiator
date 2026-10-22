class_name MatchIntro
extends CanvasLayer
## The pre-fight intro's picture: letterbox bars, two bronze-rimmed name plates (name, weapon, CPU style or rating)
## with a VS medallion between them, then the "PVGNATE! / Fight!" stinger. It only draws what `show_at(timeline)`
## says; MatchShow owns the clock, the camera and the input hold. Landscape: plates side by side in the upper third
## (clear of the blood meters); portrait: stacked, with the medallion between. Laid out in units like MenuFlow (a
## landscape unit is a 1920x1080 design pixel, a portrait screen is 1000 units wide).

const LAYER: int = 55  ## above the HUD (10) and the touch buttons (20), below the menus (60)
const PORTRAIT_UNITS: float = 1000.0
const PLATE_W: float = 640.0
const PLATE_W_PORTRAIT: float = 820.0
const NAME_FONT: int = 66
const WEAPON_FONT: int = 34
const SUB_FONT: int = 28
const STINGER_FONT: int = 168
const STINGER_SUB_FONT: int = 60
const MEDALLION_R: float = 74.0
const BAR_FRAC: float = 0.1  ## letterbox bar height, share of the screen height
const BAR_COLOR: Color = Color(0.02, 0.015, 0.01, 0.82)
const OUTLINE: Color = Color(0.12, 0.05, 0.03, 0.95)
const STINGER_BAND: Color = Color(0.16, 0.03, 0.02, 0.72)
const STINGER_GOLD: Color = Color(0.98, 0.86, 0.52)

var _root: Control
var _bars: Array[ColorRect] = []
var _plates: Array[PanelContainer] = []
var _medallion: Control
var _stinger: Control
var _stinger_latin: Label
var _stinger_english: Label
var _hint: Label
var _units: Vector2 = Vector2(1920.0, 1080.0)
var _portrait: bool = false


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = MenuTheme.theme()
	add_child(_root)
	for i: int in 2:
		var bar := ColorRect.new()
		bar.color = BAR_COLOR
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bar)
		_bars.append(bar)
	_medallion = Control.new()
	_medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medallion.size = Vector2(MEDALLION_R * 2.0, MEDALLION_R * 2.0)
	_medallion.pivot_offset = _medallion.size * 0.5
	_medallion.draw.connect(_draw_medallion)
	_root.add_child(_medallion)
	_stinger = Control.new()
	_stinger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stinger.size = Vector2(1400.0, 320.0)
	_stinger.pivot_offset = _stinger.size * 0.5
	_stinger.draw.connect(_draw_stinger_rules)
	_root.add_child(_stinger)
	_stinger_latin = _line(_stinger, "PVGNATE!", STINGER_FONT, STINGER_GOLD, 18.0, 16)
	_stinger_english = _line(_stinger, "Fight!", STINGER_SUB_FONT, MenuTheme.OCHRE, 210.0, 12)
	_hint = MenuTheme.label("Tap to skip" if TouchControls.active() else "Any button skips", MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)


func _line(parent: Control, text: String, px: int, colour: Color, top: float, outline: int) -> Label:
	var l: Label = MenuTheme.label(text, px, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0.0, top)
	l.size = Vector2(parent.size.x, float(px) * 1.3)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	parent.add_child(l)
	return l


## The two plates in screen order (MatchReport.plates_for); `skippable` shows the skip hint.
func setup(plates: Array, skippable: bool) -> void:
	for p: PanelContainer in _plates:
		p.queue_free()
	_plates.clear()
	for i: int in mini(plates.size(), 2):
		var p: PanelContainer = _make_plate(plates[i] as Dictionary, i == 0)
		_root.add_child(p)
		_plates.append(p)
	_root.move_child(_medallion, -1)
	_root.move_child(_stinger, -1)
	_hint.visible = skippable


func _make_plate(d: Dictionary, left: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = MenuTheme.box(MenuTheme.PANEL_BG, MenuTheme.BRONZE, 4, 26.0)
	# A Pompeian red band on the outer edge, as on a painted cartouche.
	if left:
		sb.border_width_left = 16
	else:
		sb.border_width_right = 16
	sb.border_color = MenuTheme.BRONZE
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	var n: Label = MenuTheme.label(str(d.get("name", "")), NAME_FONT, MenuTheme.PARCHMENT)
	n.add_theme_color_override("font_outline_color", OUTLINE)
	n.add_theme_constant_override("outline_size", 10)
	n.horizontal_alignment = align
	n.clip_text = true
	v.add_child(n)
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(0.0, 26.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func() -> void: MenuTheme.draw_meander(rule, 0.0, 2.0, rule.size.x, 12.0, 2.5))
	v.add_child(rule)
	var w: Label = MenuTheme.label(str(d.get("weapon", "")), WEAPON_FONT, MenuTheme.OCHRE)
	w.horizontal_alignment = align
	w.clip_text = true
	v.add_child(w)
	var s: Label = MenuTheme.label(str(d.get("sub", "")), SUB_FONT, MenuTheme.DIM_TEXT)
	s.horizontal_alignment = align
	s.clip_text = true
	v.add_child(s)
	return p


## Places everything for the timeline's current moment.
func show_at(tl: IntroTimeline) -> void:
	_layout()
	var k: float = tl.plate_in()
	var h: float = _units.y * BAR_FRAC
	_bars[0].position = Vector2(0.0, -h + h * k)
	_bars[0].size = Vector2(_units.x, h)
	_bars[1].position = Vector2(0.0, _units.y - h * k)
	_bars[1].size = Vector2(_units.x, h)
	var pw: float = PLATE_W_PORTRAIT if _portrait else PLATE_W
	for i: int in _plates.size():
		var p: PanelContainer = _plates[i]
		p.custom_minimum_size = Vector2(pw, 0.0)
		p.size = Vector2(pw, 0.0)
		p.reset_size()
		var home: Vector2 = _plate_home(i, pw, p.size.y)
		var off: float = (1.0 - k) * (_units.x * 0.6 + pw) * (-1.0 if i == 0 else 1.0)
		p.position = home + Vector2(off, 0.0)
		p.modulate.a = clampf(k * 1.5, 0.0, 1.0)
	var mid: Vector2 = _medallion_centre()
	_medallion.position = mid - _medallion.size * 0.5
	_medallion.scale = Vector2.ONE * maxf(k, 0.01)
	_medallion.modulate.a = k
	var st: Vector2 = tl.stinger()
	_stinger.visible = st.x > 0.0
	if _stinger.visible:
		var fit: float = minf(1.0, _units.x * 0.94 / _stinger.size.x)
		_stinger.position = Vector2(_units.x * 0.5, _units.y * 0.36) - _stinger.size * 0.5
		_stinger.scale = Vector2.ONE * st.x * fit
		_stinger.modulate.a = st.y
	_hint.visible = _hint.visible and tl.phase() == IntroTimeline.PLATES
	_hint.size = Vector2(_units.x, 40.0)
	_hint.position = Vector2(0.0, _units.y - h * k + (h - 40.0) * 0.5)
	_hint.modulate.a = k


func _plate_home(i: int, pw: float, ph: float) -> Vector2:
	if _portrait:
		var x: float = (_units.x - pw) * 0.5
		var gap: float = MEDALLION_R + 14.0
		var cy: float = _units.y * 0.3
		return Vector2(x, cy - gap - ph) if i == 0 else Vector2(x, cy + gap)
	var margin: float = _units.x * 0.05
	var y: float = _units.y * 0.15
	return Vector2(margin, y) if i == 0 else Vector2(_units.x - margin - pw, y)


func _medallion_centre() -> Vector2:
	if _portrait:
		return Vector2(_units.x * 0.5, _units.y * 0.3)
	var y: float = _units.y * 0.15
	if not _plates.is_empty():
		y += _plates[0].size.y * 0.5
	return Vector2(_units.x * 0.5, y)


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920.0, 1080.0)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	_portrait = vp.x / vp.y < 1.2
	var s: float = vp.x / PORTRAIT_UNITS if _portrait else 1.0
	_root.scale = Vector2(s, s)
	_units = vp / s
	_root.size = _units


func _draw_medallion() -> void:
	var c: Vector2 = _medallion.size * 0.5
	_medallion.draw_circle(c + Vector2(0.0, 6.0), MEDALLION_R, Color(0.0, 0.0, 0.0, 0.5))
	_medallion.draw_circle(c, MEDALLION_R, MenuTheme.BRONZE.darkened(0.25))
	_medallion.draw_circle(c, MEDALLION_R - 8.0, MenuTheme.RED.darkened(0.15))
	_medallion.draw_arc(c, MEDALLION_R - 14.0, 0.0, TAU, 48, MenuTheme.OCHRE, 3.0, true)
	var f: Font = MenuTheme.caps_font()
	var px: int = 64
	var sz: Vector2 = f.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, px)
	var at: Vector2 = c + Vector2(-sz.x * 0.5, f.get_ascent(px) * 0.5 - 6.0)
	_medallion.draw_string_outline(f, at, "VS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, 8, OUTLINE)
	_medallion.draw_string(f, at, "VS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, MenuTheme.PARCHMENT)


func _draw_stinger_rules() -> void:
	# A dark band behind the words, fading out at both ends, so they read over sky, stands or sand.
	var w: float = _stinger.size.x
	var y0: float = 26.0
	var y1: float = _stinger.size.y - 36.0
	var solid: Color = STINGER_BAND
	var clear: Color = Color(solid.r, solid.g, solid.b, 0.0)
	_stinger.draw_polygon(PackedVector2Array([Vector2(0.0, y0), Vector2(w * 0.25, y0), Vector2(w * 0.25, y1), Vector2(0.0, y1)]),
			PackedColorArray([clear, solid, solid, clear]))
	_stinger.draw_rect(Rect2(w * 0.25, y0, w * 0.5, y1 - y0), solid)
	_stinger.draw_polygon(PackedVector2Array([Vector2(w * 0.75, y0), Vector2(w, y0), Vector2(w, y1), Vector2(w * 0.75, y1)]),
			PackedColorArray([solid, clear, clear, solid]))
	MenuTheme.draw_meander(_stinger, _stinger.size.x * 0.2, 0.0, _stinger.size.x * 0.6, 16.0, 3.5)
	MenuTheme.draw_meander(_stinger, _stinger.size.x * 0.2, _stinger.size.y - 30.0, _stinger.size.x * 0.6, 16.0, 3.5)
