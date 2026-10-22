class_name HUD
extends CanvasLayer
## In-fight HUD: a blood meter per fighter (player bottom-left, opponent bottom-right), a match clock and a centre
## banner for big moments. There is no health bar. Call track() once the two fighters exist, bind_clock() with the
## Match, and announce() for big moments.
## The clock shows fight time (Match.fight_ticks(): from the intro's release) as m:ss, then counts down the last
## CLOCK_COUNTDOWN_S seconds of the time limit in warning red with a pop each second; hidden in practice (no limit).
## Placement: bottom centre between the meters with mouse/pad; on touch, which owns the lower screen, in the top row
## left of the centred pause button (landscape) or under the player's meter, mirroring the pause button (portrait).
## announce() takes "LATIN / English" (for example "MORS / Death"): the Latin is set large in Roman capitals with the
## English beneath it, between ochre meander rules. Text without a slash is shown as one line.
## Layout is in 1920x1080 design units (the project stretches canvas_items), so it holds at 1280x720 and on phones.

const HUD_LAYER: int = 10  ## Below the tuning panel (100).
const MARGIN: float = 24.0
const BANNER_Y_FRAC: float = 0.24  ## Banner top, as a fraction of the design height.
const METER_WIDTH_FRAC: float = 0.14  ## Meter width as a share of the screen width, within the pixel limits below.
const METER_MIN_PX: float = 170.0
const METER_MAX_PX: float = 210.0
const TOUCH_EDGE_PX: float = 8.0  ## Touch layout: gap from the screen edge to the meters, which then sit at the top.
const TOUCH_METER_HEIGHT_FRAC: float = 0.42  ## Touch: a meter is at most this share of the screen height.
const TOUCH_METER_MIN_PX: float = 140.0
const COMPACT_GAP_FRAC: float = 0.03  ## Portrait: gap between the two meters and to the screen edges, share of screen width.
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
const CLOCK_COUNTDOWN_S: float = 30.0  ## The clock counts down over the last this many seconds of the time limit.
const CLOCK_TEXT_PX: float = 30.0  ## On-screen font size of the clock, whatever the screen.
const CLOCK_PAD_PX: float = 6.0  ## On-screen padding inside the clock plaque (vertical; double sideways).
const CLOCK_GAP_PX: float = 8.0  ## On-screen gap to the pause button or the meter it sits beside.
const CLOCK_POP: float = 1.18  ## Countdown: scale of the pop on each new second.
const CLOCK_POP_S: float = 0.25
const CLOCK_TEXT: Color = Color(0.92, 0.84, 0.66)
const CLOCK_WARN: Color = Color(0.98, 0.42, 0.3)
const CLOCK_BACK: Color = Color(0.1, 0.06, 0.04, 0.72)
const PAUSE_DESIGN: float = 96.0  ## MenuTheme.pause_button side in menu layout units (MenuFlow places it).

var player_meter: BloodMeter = null
var opponent_meter: BloodMeter = null
var _banner: Control = null
var _latin: Label = null
var _english: Label = null
var _banner_tween: Tween = null
var _text_w: float = 0.0  ## widest banner line, px at scale 1
var _rules: PackedVector2Array = PackedVector2Array()  ## Meander segments of both rules (one multiline call).
var _hairlines: PackedVector2Array = PackedVector2Array()
var _clock: PanelContainer = null
var _clock_label: Label = null
var _clock_box: StyleBoxFlat = null
var _clock_source: Node = null  ## the Match (duck-typed: fight_ticks(), config, over)
var _clock_tween: Tween = null


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
	_build_clock(root)


func _build_clock(root: Control) -> void:
	_clock = PanelContainer.new()
	_clock.name = "Clock"
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_box = StyleBoxFlat.new()
	_clock_box.bg_color = CLOCK_BACK
	_clock_box.border_color = BloodMeter.BRONZE
	_clock_box.set_corner_radius_all(8)
	_clock.add_theme_stylebox_override("panel", _clock_box)
	_clock_label = Label.new()
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_clock_label.text = "0:00"
	_clock.add_child(_clock_label)
	_clock.visible = false
	root.add_child(_clock)


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


## True for a portrait touch screen: the meters use the short horizontal layout so they leave the arena visible.
static func is_compact(screen_w: float, screen_h: float, touch: bool) -> bool:
	return touch and screen_h > screen_w


## Layout unit for the meters on a screen `screen_w` px wide: the meter is about 16% of the screen width, held between
## METER_MIN_PX and METER_MAX_PX on screen (so a phone gets a real, readable meter), as a multiple of the design size.
static func meter_px(screen_w: float, screen_h: float = 0.0, touch: bool = false) -> float:
	if is_compact(screen_w, screen_h, touch):
		return (screen_w * (1.0 - 3.0 * COMPACT_GAP_FRAC)) * 0.5
	var w: float = clampf(screen_w * METER_WIDTH_FRAC, METER_MIN_PX, METER_MAX_PX)
	if touch and screen_h > 0.0:  # a short landscape phone: keep the meters clear of the thumb buttons below them
		w = minf(w, maxf(screen_h * TOUCH_METER_HEIGHT_FRAC * BloodMeter.METER_SIZE.x / BloodMeter.METER_SIZE.y, TOUCH_METER_MIN_PX))
	return w


## Top-left corners (layout units) of the player's and the opponent's meters, as [Vector2, Vector2]. Mouse and
## keyboard: bottom corners. Touch: top corners, because the thumb buttons own the lower right and the thumbs the
## lower left; `insets` (left, top, right, bottom, screen px) keeps them off notches. `k` is px per layout unit.
static func meter_positions(vp: Vector2, meter: Vector2, k: float, insets: Vector4, touch: bool) -> Array:
	var kk: float = maxf(k, 0.0001)
	if not touch:
		var y: float = vp.y - MARGIN - meter.y
		return [Vector2(MARGIN, y), Vector2(vp.x - MARGIN - meter.x, y)]
	var edge: float = TOUCH_EDGE_PX / kk
	var top: float = insets.y / kk + edge
	return [Vector2(insets.x / kk + edge, top), Vector2(vp.x - insets.z / kk - edge - meter.x, top)]


## On-screen px from the top of a `screen_w` px wide touch screen to the bottom of the meters (for the hint below).
static func touch_block_px(screen_w: float, screen_h: float, inset_top_px: float) -> float:
	var w: float = meter_px(screen_w, screen_h, true)
	var design: Vector2 = BloodMeter.COMPACT_SIZE if is_compact(screen_w, screen_h, true) else BloodMeter.METER_SIZE
	return inset_top_px + TOUCH_EDGE_PX + w * design.y / design.x


func meter_unit(screen_w: float, screen_h: float = 0.0, touch: bool = false) -> float:
	var k: float = get_viewport().get_final_transform().get_scale().x
	return clampf(meter_px(screen_w, screen_h, touch) / (BloodMeter.METER_SIZE.x * k), METER_MIN_UNIT, METER_MAX_UNIT)


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
	_update_clock()
	_layout()


## Places and scales the widgets from the real pixel scale: the project stretches the 1920-unit design with
## "expand", so on a phone the design is squeezed and the meters would be unreadable. Meters grow until they are
## about METER_WIDTH_FRAC of the screen wide; the banner grows to BANNER_TARGET_PX.
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var k: float = get_viewport().get_final_transform().get_scale().x
	if k <= 0.0:
		return
	var touch: bool = TouchControls.active()
	var u: float = meter_unit(vp.x * k, vp.y * k, touch)
	var compact: bool = is_compact(vp.x * k, vp.y * k, touch)
	var design: Vector2 = BloodMeter.COMPACT_SIZE if compact else BloodMeter.METER_SIZE
	var spots: Array = meter_positions(vp, design * u, k, SafeArea.window_insets() if touch else Vector4.ZERO, touch)
	for m: BloodMeter in [player_meter, opponent_meter]:
		m.scale = Vector2.ONE
		m.configure(u, k, compact)
	player_meter.position = spots[0]
	opponent_meter.position = spots[1]
	var bs: float = clampf(BANNER_TARGET_PX / (BANNER_W * k), 1.0, BANNER_MAX_SCALE)
	bs = minf(bs, fit_scale(_text_w, vp.x, BANNER_FIT_FRAC))
	_banner.scale = Vector2(bs, bs)
	_banner.position = Vector2(vp.x * 0.5 - BANNER_W * bs * 0.5, vp.y * BANNER_Y_FRAC)
	if _clock.visible:
		_layout_clock(vp, k, touch, compact, spots[0] as Vector2, design * u)


## Font, padding and border in screen px (so the clock reads the same on a phone and a monitor), then the spot.
func _layout_clock(vp: Vector2, k: float, touch: bool, compact: bool, meter_at: Vector2, meter: Vector2) -> void:
	_clock_label.add_theme_font_size_override("font_size", roundi(CLOCK_TEXT_PX / k))
	_clock_label.add_theme_constant_override("outline_size", maxi(roundi(4.0 / k), 1))
	_clock_label.custom_minimum_size = Vector2(_clock_label.get_theme_font("font").get_string_size("00:00",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, roundi(CLOCK_TEXT_PX / k)).x, 0.0)
	_clock_box.set_border_width_all(maxi(roundi(2.0 / k), 1))
	_clock_box.content_margin_left = CLOCK_PAD_PX * 2.0 / k
	_clock_box.content_margin_right = CLOCK_PAD_PX * 2.0 / k
	_clock_box.content_margin_top = CLOCK_PAD_PX / k
	_clock_box.content_margin_bottom = CLOCK_PAD_PX / k
	var sz: Vector2 = _clock.get_combined_minimum_size()
	_clock.size = sz
	_clock.pivot_offset = sz * 0.5
	var ins: Vector4 = SafeArea.window_insets() if touch else Vector4.ZERO
	_clock.position = clock_position(vp, sz, k, ins, touch, compact, meter_at, meter)


## Top-left corner (layout units) of a clock `clock` big. Mouse/pad: bottom centre, just above the render-toggles
## line (RenderToggles, always at the bottom centre).
## Touch landscape: the top row, right edge CLOCK_GAP_PX left of the centred pause button (MenuFlow's layout).
## Touch portrait (`compact`): under the player's meter (`meter_at`, `meter`), mirroring the pause button.
static func clock_position(vp: Vector2, clock: Vector2, k: float, insets: Vector4, touch: bool, compact: bool,
		meter_at: Vector2, meter: Vector2) -> Vector2:
	var kk: float = maxf(k, 0.0001)
	var gap: float = CLOCK_GAP_PX / kk
	if not touch:
		return Vector2((vp.x - clock.x) * 0.5, vp.y - diag_clear() - gap - clock.y)
	if compact:
		return Vector2(meter_at.x, meter_at.y + meter.y + gap)
	var pause: float = pause_side(vp, kk)
	var top: float = insets.y / kk + TOUCH_EDGE_PX / kk
	return Vector2(vp.x * 0.5 - pause * 0.5 - gap - clock.x, top + maxf(pause - clock.y, 0.0) * 0.5)


## Layout units the bottom-centre render-toggles plate takes (offset 8, padding 6 each side, one line of text).
static func diag_clear() -> float:
	return 8.0 + 12.0 + float(RenderToggles.FONT_SIZE) * 1.5


## Side of MenuFlow's touch pause button in HUD layout units: its menu layer is scaled by `s` (1 on a landscape
## screen, vp.x / PORTRAIT_UNITS otherwise) and the button is at least PAUSE_MIN_PX on screen.
static func pause_side(vp: Vector2, k: float) -> float:
	var s: float = 1.0 if vp.y <= 0.0 or vp.x / vp.y >= 1.2 else vp.x / MenuFlow.PORTRAIT_UNITS
	return maxf(PAUSE_DESIGN * s, MenuFlow.PAUSE_MIN_PX / maxf(k, 0.0001))


## True while the clock counts down: a time limit is set and at most CLOCK_COUNTDOWN_S of it is left.
static func clock_counts_down(fight_s: float, limit_s: float) -> bool:
	return limit_s > 0.0 and limit_s - fight_s <= CLOCK_COUNTDOWN_S


## The clock's text: fight time as m:ss (whole seconds gone), or in the countdown the seconds left, rounded up so it
## reads 0:01 until the limit and 0:00 at it.
static func clock_text(fight_s: float, limit_s: float) -> String:
	var secs: int = maxi(floori(maxf(fight_s, 0.0)), 0)
	if clock_counts_down(fight_s, limit_s):
		secs = maxi(ceili(limit_s - maxf(fight_s, 0.0) - 0.0001), 0)
	return "%d:%02d" % [secs / 60, secs % 60]


## Reads the clock from `source` (the Match: fight_ticks(), config["time_limit_s"], is_practice(), over) each frame.
## Null hides it.
func bind_clock(source: Node) -> void:
	_clock_source = source
	_clock_label.text = ""
	_update_clock()


func _update_clock() -> void:
	var src: Node = _clock_source
	if src == null or not is_instance_valid(src) or not src.has_method("fight_ticks") or bool(src.call("is_practice")):
		_clock.visible = false
		return
	_clock.visible = true
	if bool(src.get("over")) and _clock_label.text != "":
		return  # frozen on the final second (the match tick runs on through the victory pause)
	var cfg: Dictionary = src.get("config")
	var limit_s: float = float(cfg.get("time_limit_s", 0.0))
	var fight_s: float = float(int(src.call("fight_ticks"))) / float(Engine.physics_ticks_per_second)
	var text: String = clock_text(fight_s, limit_s)
	if text == _clock_label.text:
		return
	var warn: bool = clock_counts_down(fight_s, limit_s)
	_clock_label.text = text
	_clock_label.add_theme_color_override("font_color", CLOCK_WARN if warn else CLOCK_TEXT)
	_clock_box.border_color = CLOCK_WARN if warn else BloodMeter.BRONZE
	if warn and is_inside_tree():
		if _clock_tween != null and _clock_tween.is_valid():
			_clock_tween.kill()
		_clock.scale = Vector2(CLOCK_POP, CLOCK_POP)
		_clock_tween = create_tween()
		_clock_tween.tween_property(_clock, "scale", Vector2.ONE, CLOCK_POP_S)


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
