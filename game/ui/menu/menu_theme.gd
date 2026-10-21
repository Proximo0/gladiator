class_name MenuTheme
extends RefCounted
## Roman look for every menu: bronze and parchment on dark stone, Pompeian red and ochre accents, Greek-key rules.
## Sizes are in layout units (see MenuFlow: one unit is about a pixel on a 1920x1080 screen).

const BRONZE: Color = BloodMeter.BRONZE
const OCHRE: Color = BloodMeter.OCHRE
const PARCHMENT: Color = BloodMeter.PARCHMENT
const RED: Color = BloodMeter.POMPEIAN_RED
const INK: Color = Color(0.11, 0.102, 0.09)
const PANEL_BG: Color = Color(0.09, 0.07, 0.055, 0.86)
const BUTTON_BG: Color = Color(0.17, 0.12, 0.08, 0.92)
const BUTTON_HOT: Color = Color(0.42, 0.14, 0.1, 0.96)
const DIM_TEXT: Color = Color(0.62, 0.55, 0.42)
const FONT_BODY: int = 34
const FONT_SMALL: int = 28
const FONT_HEAD: int = 44
const ROW_H: float = 68.0

static var _cache: Theme = null
static var _caps: Font = null


## Wide-set bold capitals (Trajan-like proportions without a licensed font).
static func caps_font() -> Font:
	if _caps == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.5
		fv.spacing_glyph = 3
		_caps = fv
	return _caps


static func box(bg: Color, border: Color, border_w: int = 3, pad: float = 14.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(2)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.5
	s.content_margin_bottom = pad * 0.5
	return s


static func theme() -> Theme:
	if _cache != null:
		return _cache
	var t := Theme.new()
	t.default_font = caps_font()
	t.default_font_size = FONT_BODY
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_color", "Button", PARCHMENT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM_TEXT)
	t.set_font_size("font_size", "Button", FONT_BODY)
	t.set_stylebox("normal", "Button", box(BUTTON_BG, BRONZE.darkened(0.4)))
	t.set_stylebox("hover", "Button", box(BUTTON_HOT, OCHRE))
	t.set_stylebox("pressed", "Button", box(BUTTON_HOT.darkened(0.2), OCHRE))
	t.set_stylebox("focus", "Button", box(BUTTON_HOT, OCHRE, 5))
	t.set_stylebox("disabled", "Button", box(BUTTON_BG.darkened(0.3), BRONZE.darkened(0.7)))
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, BRONZE, 3, 20.0))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 14)
	t.set_stylebox("slider", "HSlider", box(Color(0.3, 0.22, 0.12), BRONZE.darkened(0.3), 2, 6.0))
	t.set_stylebox("grabber_area", "HSlider", box(OCHRE.darkened(0.2), OCHRE, 2, 6.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(OCHRE, Color.WHITE, 2, 6.0))
	var knob := _knob(30)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_icon("grabber_disabled", "HSlider", knob)
	t.set_constant("center_grabber", "HSlider", 1)
	_cache = t
	return t


static func _knob(px: int) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c: float = float(px) * 0.5
	for y: int in px:
		for x: int in px:
			var d: float = Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
			if d < c - 1.0:
				img.set_pixel(x, y, PARCHMENT if d > c - 6.0 else BRONZE)
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = FONT_BODY, colour: Color = PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, ROW_H)
	b.focus_mode = Control.FOCUS_ALL
	return b


## Greek-key rule across `rect` (call from a draw handler).
static func draw_meander(ci: CanvasItem, x: float, y: float, width: float, cell: float = 14.0) -> void:
	var w: float = floorf(width / cell) * cell
	var x0: float = x + (width - w) * 0.5
	for seg: PackedVector2Array in BloodMeter.meander_cells(w, cell, Vector2(x0, y)):
		ci.draw_polyline(seg, OCHRE, 3.0, true)
	ci.draw_line(Vector2(x0, y + cell + 6.0), Vector2(x0 + w, y + cell + 6.0), BRONZE, 2.0)


static func dim_rect() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.03, 0.02, 0.015, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
