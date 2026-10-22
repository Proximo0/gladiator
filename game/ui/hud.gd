class_name HUD
extends CanvasLayer
## In-fight HUD: a blood meter per fighter (player bottom-left, opponent bottom-right) and a centre banner for big
## moments. There is no health bar. Call track() once the two fighters exist, and announce() for big moments.
## announce() takes "LATIN / English" (for example "MORS / Death"): the Latin is set large in Roman capitals with the
## English beneath it, between ochre meander rules. Text without a slash is shown as one line.
## Layout is in 1920x1080 design units (the project stretches canvas_items), so it holds at 1280x720 and on phones.

const HUD_LAYER: int = 10  ## Below the tuning panel (100).
const MARGIN: float = 24.0
const BANNER_Y_FRAC: float = 0.24  ## Banner top, as a fraction of the design height.
const METER_WIDTH_FRAC: float = 0.14  ## Meter width as a share of the screen width, within the pixel limits below.
const METER_MIN_PX: float = 170.0
const METER_MAX_PX: float = 210.0
const METER_MIN_UNIT: float = 0.8
const METER_MAX_UNIT: float = 4.0
const BANNER_TARGET_PX: float = 360.0  ## On-screen width the banner aims for.
const BANNER_MAX_SCALE: float = 3.0
const BANNER_FIT_FRAC: float = 0.9  ## Widest banner line, as a share of the viewport width.
const BANNER_W: float = 1200.0
const BANNER_H: float = 280.0
const LATIN_FONT: int = 120
const ENGLISH_FONT: int = 56
const LATIN_TOP: float = 40.0
const ENGLISH_TOP: float = 176.0
const RULE_TOP: float = 14.0  ## Meander rule above the Latin line.
const RULE_BOTTOM: float = 252.0  ## Meander rule below the English line.
const RULE_CELL: float = 14.0
const RULE_STROKE: float = 3.0
const OUTLINE_PX: int = 14
const BANNER_FADE_IN_S: float = 0.15
const BANNER_HOLD_S: float = 1.6
const BANNER_FADE_OUT_S: float = 0.6
const LATIN_TEXT: Color = Color(0.92, 0.84, 0.66)
const ENGLISH_TEXT: Color = Color(0.85, 0.77, 0.58, 0.9)
const OUTLINE_COLOR: Color = Color(0.12, 0.05, 0.03, 0.9)
const SEPARATOR: String = " / "

var player_meter: BloodMeter = null
var opponent_meter: BloodMeter = null
var _banner: Control = null
var _latin: Label = null
var _english: Label = null
var _banner_tween: Tween = null
var _text_w: float = 0.0  ## widest banner line, px at scale 1
var _rules: PackedVector2Array = PackedVector2Array()  ## Meander segments of both rules (one multiline call).
var _hairlines: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	layer = HUD_LAYER
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	player_meter = BloodMeter.new()
	root.add_child(player_meter)

	opponent_meter = BloodMeter.new()
	root.add_child(opponent_meter)

	_banner = Control.new()
	_banner.size = Vector2(BANNER_W, BANNER_H)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	_banner.visible = false  # an idle banner costs nothing: no draw calls for its rules and text
	_build_rules()
	_banner.draw.connect(_draw_banner_rules)
	root.add_child(_banner)

	_latin = _make_line(LATIN_TOP, LATIN_FONT, LATIN_TEXT)
	_english = _make_line(ENGLISH_TOP, ENGLISH_FONT, ENGLISH_TEXT)


func _make_line(top: float, font_px: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.position = Vector2(0.0, top)
	label.size = Vector2(BANNER_W, float(font_px) * 1.4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_PX)
	_banner.add_child(label)
	return label


## Layout unit for the meters on a screen `screen_w` px wide: the meter is about 16% of the screen width, held between
## METER_MIN_PX and METER_MAX_PX on screen (so a phone gets a real, readable meter), as a multiple of the design size.
static func meter_px(screen_w: float) -> float:
	return clampf(screen_w * METER_WIDTH_FRAC, METER_MIN_PX, METER_MAX_PX)


func meter_unit(screen_w: float) -> float:
	var k: float = get_viewport().get_final_transform().get_scale().x
	return clampf(meter_px(screen_w) / (BloodMeter.METER_SIZE.x * k), METER_MIN_UNIT, METER_MAX_UNIT)


## Scale at which a line `text_w` wide fits `frac` of `vp_w` (no limit for an empty line).
static func fit_scale(text_w: float, vp_w: float, frac: float) -> float:
	if text_w <= 1.0:
		return BANNER_MAX_SCALE
	return maxf(vp_w * frac / text_w, 0.05)


## Pixel width of `text` in the label's font, outline included.
func _line_w(label: Label, text: String) -> float:
	if text == "":
		return 0.0
	var f: Font = label.get_theme_font("font")
	var px: int = label.get_theme_font_size("font_size")
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x + float(OUTLINE_PX)


func _process(_delta: float) -> void:
	_layout()


## Places and scales the widgets from the real pixel scale: the project stretches the 1920-unit design with
## "expand", so on a phone the design is squeezed and the meters would be unreadable. Meters grow until they are
## about METER_WIDTH_FRAC of the screen wide; the banner grows to BANNER_TARGET_PX.
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var k: float = get_viewport().get_final_transform().get_scale().x
	if k <= 0.0:
		return
	var u: float = meter_unit(vp.x * k)
	var w: float = BloodMeter.METER_SIZE.x * u
	var meter_y: float = vp.y - MARGIN - BloodMeter.METER_SIZE.y * u
	for m: BloodMeter in [player_meter, opponent_meter]:
		m.scale = Vector2.ONE
		m.configure(u, k)
	player_meter.position = Vector2(MARGIN, meter_y)
	opponent_meter.position = Vector2(vp.x - MARGIN - w, meter_y)
	var bs: float = clampf(BANNER_TARGET_PX / (BANNER_W * k), 1.0, BANNER_MAX_SCALE)
	bs = minf(bs, fit_scale(_text_w, vp.x, BANNER_FIT_FRAC))
	_banner.scale = Vector2(bs, bs)
	_banner.position = Vector2(vp.x * 0.5 - BANNER_W * bs * 0.5, vp.y * BANNER_Y_FRAC)


## Shows the two fighters' blood meters. `health_a` is the player (bottom-left), `health_b` the opponent (bottom-right).
func track(health_a: FighterHealth, health_b: FighterHealth, name_a: String, name_b: String) -> void:
	player_meter.bind(health_a, name_a)
	opponent_meter.bind(health_b, name_b)


## Flashes a banner in the centre: "LATIN / English" or one line of text. Fades in, holds, fades out.
## A new call replaces the one showing.
func announce(text: String) -> void:
	var latin: String = text
	var english: String = ""
	var at: int = text.find(SEPARATOR)
	if at >= 0:
		latin = text.substr(0, at)
		english = text.substr(at + SEPARATOR.length())
	_latin.text = latin.strip_edges().to_upper()
	_english.text = english.strip_edges()
	_english.visible = english != ""
	_text_w = maxf(_line_w(_latin, _latin.text), _line_w(_english, _english.text))
	_banner.queue_redraw()
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.visible = true
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, BANNER_FADE_IN_S)
	_banner_tween.tween_interval(BANNER_HOLD_S)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, BANNER_FADE_OUT_S)
	_banner_tween.tween_callback(func() -> void: _banner.visible = false)


## Meander rules above and below the banner text, with a bronze hairline under each. Built once as segment lists.
func _build_rules() -> void:
	var span: float = BANNER_W * 0.32
	var x0: float = BANNER_W * 0.5 - span
	for y: float in [RULE_TOP, RULE_BOTTOM]:
		_rules.append_array(BloodMeter.meander_segments(span * 2.0, RULE_CELL, Vector2(x0, y)))
		_hairlines.append(Vector2(x0, y + RULE_CELL + 6.0))
		_hairlines.append(Vector2(x0 + span * 2.0, y + RULE_CELL + 6.0))


func _draw_banner_rules() -> void:
	_banner.draw_multiline(_rules, BloodMeter.OCHRE, RULE_STROKE, true)
	_banner.draw_multiline(_hairlines, BloodMeter.BRONZE, 2.0)
