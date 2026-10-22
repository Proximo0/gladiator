class_name KillcamOverlay
extends CanvasLayer
## The instant replay's frame: cinema bars top and bottom, a blinking "REPLAY" tag and a skip hint. Draws nothing
## else; KillCam shows and hides it.

const OVERLAY_LAYER: int = 20  ## over the HUD (10), under the tuning panel (100)
const BAR_FRAC: float = 0.1
const TAG_PX: int = 34
const HINT_PX: int = 22
const RED: Color = Color(0.86, 0.12, 0.08)
const INK: Color = Color(0.95, 0.9, 0.8)

var _top: ColorRect = null
var _bottom: ColorRect = null
var _tag: Label = null
var _hint: Label = null
var _age: float = 0.0


func _init() -> void:
	layer = OVERLAY_LAYER
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_top = _bar(root)
	_bottom = _bar(root)
	_tag = _label(root, TAG_PX, RED, "●  REPLAY")
	_hint = _label(root, HINT_PX, INK, "")


func _bar(root: Control) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _label(root: Control, px: int, col: Color, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(l)
	return l


## Skip hint for the device in use: a tap on touch screens, any button otherwise.
static func hint_text(touch: bool) -> String:
	return "Tap to skip" if touch else "Press any button to skip"


func show_replay(touch: bool) -> void:
	_hint.text = hint_text(touch)
	_age = 0.0
	visible = true
	_layout()


func hide_replay() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta / maxf(Engine.time_scale, 0.001)
	_tag.modulate.a = 1.0 if fmod(_age, 1.0) < 0.7 else 0.35
	_layout()


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	var bar_h: float = roundf(vp.y * BAR_FRAC)
	var k: float = clampf(vp.y / 720.0, 0.6, 2.0)
	_top.position = Vector2.ZERO
	_top.size = Vector2(vp.x, bar_h)
	_bottom.position = Vector2(0.0, vp.y - bar_h)
	_bottom.size = Vector2(vp.x, bar_h)
	_tag.add_theme_font_size_override("font_size", roundi(TAG_PX * k))
	_hint.add_theme_font_size_override("font_size", roundi(HINT_PX * k))
	var pad: float = maxf(24.0 * k, vp.x * 0.03)
	_tag.position = Vector2(pad, 0.0)
	_tag.size = Vector2(vp.x * 0.5, bar_h)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.position = Vector2(vp.x * 0.4, vp.y - bar_h)
	_hint.size = Vector2(vp.x * 0.6 - pad, bar_h)
