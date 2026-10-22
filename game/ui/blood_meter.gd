class_name BloodMeter
extends Control
## One fighter's blood gauge: a glass vial with a bronze rim showing litres left out of FULL_BLOOD. The shown level
## drains toward FighterHealth.blood every frame, drips fall from the neck at a rate that follows bleed_rate, a
## heartbeat halo pulses faster as the blood drops, the colour goes from deep red to brown-black at
## Tuning.blood_death, and a thin stamina arc sits beside the vial. Presentation only: every number the maths uses is
## a static function so the unit tests can check it.

const METER_SIZE: Vector2 = Vector2(240.0, 372.0)  ## Design size (unit scale 1); the HUD lays it out at unit * this.
const COMPACT_SIZE: Vector2 = Vector2(240.0, 112.0)  ## Portrait phones: name band, horizontal blood bar, litres and a stamina ring.
const FULL_BLOOD: float = 5.0  ## Litres at full. Matches FighterHealth.START_BLOOD.
const DRAIN_SPEED: float = 6.0  ## How fast the shown level follows the real blood (1/s).
const DRIP_MIN_RATE: float = 0.002  ## bleed_rate (L/s) below which nothing drips.
const DRIP_FULL_RATE: float = 1.0  ## bleed_rate (L/s) that gives the fastest drips.
const DRIP_HZ_MIN: float = 0.4
const DRIP_HZ_MAX: float = 6.0
const HEART_CALM_HZ: float = 1.0
const HEART_FAST_HZ: float = 3.4
const PULSE_CALM: float = 0.25
const PULSE_FAST: float = 1.0
const RED_ABOVE: float = 0.5  ## Danger fraction above which the colour is fully deep red.
const DEEP_RED: Color = Color(0.56, 0.04, 0.05)
const BROWN_BLACK: Color = Color(0.12, 0.04, 0.03)
const GLASS_BACK: Color = Color(0.14, 0.07, 0.05, 0.6)
const BRONZE: Color = Color(0.7, 0.5, 0.22)
const PARCHMENT: Color = Color(0.9, 0.82, 0.64)
const POMPEIAN_RED: Color = Color(0.557, 0.165, 0.118)
const OCHRE: Color = Color(0.784, 0.565, 0.18)
const BLACK_BORDER: Color = Color(0.11, 0.102, 0.09)
const MEANDER_CELL: float = 8.0
const MEANDER_STROKE: float = 2.0
const MEANDER_Y: float = 296.0  ## Top of the meander rule above the readout.
const INK: Color = Color(0.17, 0.1, 0.06)
const WARN_TEXT: Color = Color(0.98, 0.5, 0.38)
const STAMINA_COLOR: Color = Color(0.86, 0.68, 0.32)
const STAMINA_TRACK: Color = Color(0.3, 0.22, 0.12, 0.8)
const HEADER_H: float = 44.0
const VIAL_X: float = 20.0
const VIAL_Y: float = 54.0
const VIAL_W: float = 120.0
const VIAL_H: float = 236.0
const LIQUID_TOP_INSET: float = 6.0
const LIQUID_BOTTOM_INSET: float = 2.0
const SHOULDER_FRAC: float = 0.26  ## Where the neck meets the shoulder, as a fraction of the vial height.
const NECK_FRAC: float = 0.5  ## Neck half-width as a fraction of the bulb radius.
const ARC_CENTER: Vector2 = Vector2(190.0, 172.0)
const ARC_RADIUS: float = 30.0
const ARC_STEPS: int = 12
const COMPACT_RING_R: float = 22.0
const DROP_RADIUS: float = 4.0
const DROP_OFFSET: float = 0.5  ## Second drop's phase offset within the drip cycle.
const MIN_PX_NAME: float = 16.0  ## Smallest on-screen text height (px) for each readout, so a small meter stays legible.
const MIN_PX_READOUT: float = 20.0
const MIN_PX_LATIN: float = 12.0
const MIN_PX_PERCENT: float = 13.0
const MIN_PX_SMALL: float = 11.0

var health: FighterHealth = null
var display_name: String = ""
var shown_blood: float = FULL_BLOOD
var drip_phase: float = 0.0
var heart_phase: float = 0.0
var flow_phase: float = 0.0
var unit: float = 1.0  ## Layout scale: the control is METER_SIZE * unit and geometry is drawn scaled; text is sized separately.
var px_scale: float = 1.0  ## On-screen pixels per control unit (for the text size floors).
var compact: bool = false  ## Short horizontal layout for portrait phones (see COMPACT_SIZE).
var _started: bool = false
var _frame: StyleBoxFlat = null
var _meander: PackedVector2Array = PackedVector2Array()  ## Segment pairs of the rule above the readout (built once).


func _init() -> void:
	custom_minimum_size = METER_SIZE
	size = METER_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color(0.09, 0.07, 0.05, 0.82)
	_frame.border_color = BRONZE
	_frame.set_border_width_all(3)
	_frame.set_corner_radius_all(10)
	_meander = meander_segments(size.x - 16.0, MEANDER_CELL, Vector2(8.0, MEANDER_Y))


## Per-size layout: geometry scales by `u`, text gets its own sizes (never below its on-screen pixel floor, given
## `px` on-screen pixels per control unit) so it is drawn crisp instead of being a scaled-up small font.
func configure(u: float, px: float, compact_layout: bool = false) -> void:
	u = maxf(u, 0.1)
	px = maxf(px, 0.01)
	if is_equal_approx(u, unit) and is_equal_approx(px, px_scale) and compact_layout == compact:
		return
	unit = u
	px_scale = px
	compact = compact_layout
	custom_minimum_size = design_size() * u
	size = custom_minimum_size
	queue_redraw()


## Design size of the current layout (unit scale 1).
func design_size() -> Vector2:
	return COMPACT_SIZE if compact else METER_SIZE


## Font size in control units: `base` scaled with the meter, but no smaller than `min_px` on screen.
func text_size(base: float, min_px: float) -> int:
	return maxi(roundi(base * unit), ceili(min_px / px_scale))


## Binds a fighter and its name. The first frame after binding snaps the level instead of draining to it.
func bind(h: FighterHealth, name_text: String) -> void:
	health = h
	display_name = name_text
	_started = false
	queue_redraw()


func _process(delta: float) -> void:
	if health == null:
		return
	var death: float = Tuning.shared().blood_death
	if not _started:
		shown_blood = health.blood
		_started = true
	else:
		shown_blood = smooth_toward(shown_blood, health.blood, delta, DRAIN_SPEED)
	var hz: float = drip_hz(health.bleed_rate)
	drip_phase = fposmod(drip_phase + hz * delta, 1.0)
	flow_phase = fposmod(flow_phase + hz * 0.5 * delta, 1.0)
	heart_phase = fposmod(heart_phase + heartbeat_hz(shown_blood, death, FULL_BLOOD) * delta, 1.0)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if compact:
		_draw_compact(font)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(unit, unit))
	draw_style_box(_frame, Rect2(Vector2.ZERO, METER_SIZE))
	_draw_header(font)
	draw_multiline(_meander, OCHRE, MEANDER_STROKE, true)  # one call for the whole rule

	var rect: Rect2 = vial_rect()
	var cx: float = rect.get_center().x
	var death: float = Tuning.shared().blood_death
	var level: float = shown_blood
	var outline: PackedVector2Array = vial_outline(rect)
	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	var y_level: float = level_y(rect, level)
	var col: Color = blood_color(level, death, FULL_BLOOD)
	var bleed: float = health.bleed_rate if health != null else 0.0
	var hz: float = drip_hz(bleed)
	var dead: bool = health != null and health.dead
	var pulse: float = 0.0
	if not dead:
		pulse = heartbeat_shape(heart_phase) * pulse_strength(level, death, FULL_BLOOD)

	# Heartbeat halo: a red stroke around the glass that swells on each beat.
	draw_polyline(closed, Color(0.9, 0.12, 0.1, 0.1 + 0.5 * pulse), 2.0 + 6.0 * pulse, true)
	draw_colored_polygon(outline, GLASS_BACK)

	var liquid: PackedVector2Array = clip_below(outline, y_level)
	if liquid.size() >= 3:
		draw_colored_polygon(liquid, col)
		var hw: float = maxf(half_width(rect, y_level) - 3.0, 0.0)
		draw_line(Vector2(cx - hw, y_level), Vector2(cx + hw, y_level), col.lightened(0.35), 2.5, true)

	# Flow streaks inside the liquid, moving down at the drip speed.
	if hz > 0.0 and y_level < rect.end.y - 14.0:
		var streaks: PackedVector2Array = PackedVector2Array()
		for k: int in 3:
			var p: float = fposmod(flow_phase + float(k) / 3.0, 1.0)
			var y: float = lerpf(y_level + 6.0, rect.end.y - 8.0, p)
			var x: float = cx + float(k - 1) * VIAL_W * 0.21
			streaks.append(Vector2(x, y))
			streaks.append(Vector2(x, y + 12.0))
		draw_multiline(streaks, Color(1.0, 0.8, 0.7, 0.22), 2.0)

	# Blood-death marker: a faint dashed line at the level where the fighter dies.
	var y_mark: float = level_y(rect, death)
	var hm: float = half_width(rect, y_mark)
	var dash_x: float = cx - hm
	var dashes: PackedVector2Array = PackedVector2Array()
	while dash_x < cx + hm:
		dashes.append(Vector2(dash_x, y_mark))
		dashes.append(Vector2(minf(dash_x + 6.0, cx + hm), y_mark))
		dash_x += 10.0
	if dashes.size() >= 2:
		draw_multiline(dashes, Color(0.95, 0.9, 0.75, 0.4), 1.5)

	# Drips: a short bronze spout, then droplets falling into the liquid.
	draw_rect(Rect2(cx - 7.0, rect.position.y - 10.0, 14.0, 10.0), BRONZE)
	if hz > 0.0:
		for k: int in 2:
			var p: float = fposmod(drip_phase + DROP_OFFSET * float(k), 1.0)
			var y: float = lerpf(rect.position.y - 2.0, y_level, p * p)
			draw_circle(Vector2(cx, y), DROP_RADIUS, col.lightened(0.2))

	# Glass rim, reflections, then the readout.
	draw_polyline(closed, BRONZE, 3.0, true)
	var nw: float = rect.size.x * 0.5 * NECK_FRAC
	var cy: float = _bulb_centre_y(rect)
	var r: float = rect.size.x * 0.5
	draw_line(Vector2(cx - nw * 0.5, rect.position.y + 12.0), Vector2(cx - nw * 0.5, rect.position.y + VIAL_H * SHOULDER_FRAC - 6.0), Color(1, 1, 1, 0.25), 3.0, true)
	draw_arc(Vector2(cx, cy), r * 0.72, PI * 1.12, PI * 1.42, 8, Color(1, 1, 1, 0.25), 3.0, true)

	var readout_col: Color = PARCHMENT if danger_frac(level, death, FULL_BLOOD) >= 0.3 else WARN_TEXT

	# Stamina arc beside the vial.
	var stamina: float = health.stamina if health != null else 1.0
	draw_arc(ARC_CENTER, ARC_RADIUS, 0.0, TAU, 48, STAMINA_TRACK, 4.0, true)
	if stamina > 0.001:
		draw_arc(ARC_CENTER, ARC_RADIUS, -PI * 0.5, -PI * 0.5 + stamina_span(stamina), 48, STAMINA_COLOR, 5.0, true)

	# Text last, at identity scale and its own sizes (crisp at every layout size).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text(font, Vector2(0.0, 332.0), "%.1f L" % level, METER_SIZE.x, 32.0, MIN_PX_READOUT, readout_col)
	_text(font, Vector2(0.0, 358.0), "SANGUIS", METER_SIZE.x, 16.0, MIN_PX_LATIN, OCHRE)
	_text(font, Vector2(ARC_CENTER.x - 30.0, ARC_CENTER.y + 6.0), "%d%%" % roundi(stamina * 100.0), 60.0, 17.0, MIN_PX_PERCENT, PARCHMENT)
	_text(font, Vector2(ARC_CENTER.x - 46.0, ARC_CENTER.y + 50.0), "VIRES", 92.0, 18.0, MIN_PX_PERCENT, PARCHMENT)
	_text(font, Vector2(ARC_CENTER.x - 46.0, ARC_CENTER.y + 70.0), "Stamina", 92.0, 15.0, MIN_PX_SMALL, PARCHMENT)


## Portrait layout: name band, a horizontal blood bar (death line marked) with the litres under it, stamina ring beside.
func _draw_compact(font: Font) -> void:
	var death: float = Tuning.shared().blood_death
	var level: float = shown_blood
	var danger: float = danger_frac(level, death, FULL_BLOOD)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(unit, unit))
	draw_style_box(_frame, Rect2(Vector2.ZERO, COMPACT_SIZE))
	var band: Rect2 = Rect2(Vector2(4.0, 4.0), Vector2(COMPACT_SIZE.x - 8.0, 30.0))
	draw_rect(band, BLACK_BORDER)
	draw_rect(band.grow(-2.0), PARCHMENT)
	draw_rect(band, BRONZE, false, 2.0)
	var bar: Rect2 = compact_bar_rect()
	draw_rect(bar, GLASS_BACK)
	var fill: Rect2 = Rect2(bar.position, Vector2(bar.size.x * level_frac(level, FULL_BLOOD), bar.size.y)).grow_individual(0.0, -2.0, 0.0, -2.0)
	fill.position.x = bar.position.x
	if fill.size.x > 0.5:
		var col: Color = blood_color(level, death, FULL_BLOOD)
		draw_rect(fill, col)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 3.0)), col.lightened(0.3))
	var mark_x: float = bar.position.x + bar.size.x * level_frac(death, FULL_BLOOD)
	draw_line(Vector2(mark_x, bar.position.y), Vector2(mark_x, bar.end.y), Color(0.95, 0.9, 0.75, 0.55), 1.5)
	var pulse: float = 0.0
	if health != null and not health.dead:
		pulse = heartbeat_shape(heart_phase) * pulse_strength(level, death, FULL_BLOOD)
	draw_rect(bar.grow(1.0 + 2.0 * pulse), Color(0.9, 0.12, 0.1, 0.2 + 0.6 * pulse), false, 2.0)
	draw_rect(bar, BRONZE, false, 3.0)
	var ring: Vector2 = compact_ring_centre()
	var stamina: float = health.stamina if health != null else 1.0
	draw_arc(ring, COMPACT_RING_R, 0.0, TAU, 40, STAMINA_TRACK, 5.0, true)
	if stamina > 0.001:
		draw_arc(ring, COMPACT_RING_R, -PI * 0.5, -PI * 0.5 + stamina_span(stamina), 40, STAMINA_COLOR, 6.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text(font, Vector2(0.0, 27.0), display_name.to_upper(), COMPACT_SIZE.x, 24.0, MIN_PX_NAME, INK)
	var readout_col: Color = PARCHMENT if danger >= 0.3 else WARN_TEXT
	_text(font, Vector2(bar.position.x, 98.0), "%.1f L" % level, bar.size.x, 30.0, MIN_PX_READOUT, readout_col)
	_text(font, Vector2(ring.x - 30.0, ring.y + 7.0), "%d" % roundi(stamina * 100.0), 60.0, 20.0, MIN_PX_PERCENT, PARCHMENT)


static func compact_bar_rect() -> Rect2:
	return Rect2(12.0, 44.0, 156.0, 30.0)


static func compact_ring_centre() -> Vector2:
	return Vector2(200.0, 70.0)


## One centred string at a control-local position and width (design units), sized per layout.
func _text(font: Font, at: Vector2, text: String, width: float, base: float, min_px: float, col: Color) -> void:
	draw_string(font, at * unit, text, HORIZONTAL_ALIGNMENT_CENTER, width * unit, text_size(base, min_px), col)


func _draw_header(font: Font) -> void:
	var band: Rect2 = Rect2(Vector2(4.0, 4.0), Vector2(METER_SIZE.x - 8.0, HEADER_H - 6.0))
	draw_rect(band, BLACK_BORDER)
	draw_rect(band.grow(-2.0), PARCHMENT)
	draw_rect(band, BRONZE, false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text(font, Vector2(0.0, 30.0), display_name.to_upper(), METER_SIZE.x, 28.0, MIN_PX_NAME, INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(unit, unit))


static func vial_rect() -> Rect2:
	return Rect2(VIAL_X, VIAL_Y, VIAL_W, VIAL_H)


static func _bulb_centre_y(rect: Rect2) -> float:
	return rect.end.y - rect.size.x * 0.5


## Closed outline of the vial (flask: neck, sloped shoulder, round bulb at the bottom), clockwise on screen.
static func vial_outline(rect: Rect2) -> PackedVector2Array:
	var cx: float = rect.get_center().x
	var r: float = rect.size.x * 0.5
	var top: float = rect.position.y
	var cy: float = _bulb_centre_y(rect)
	var nw: float = r * NECK_FRAC
	var sh: float = top + rect.size.y * SHOULDER_FRAC
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(cx - nw, top))
	pts.append(Vector2(cx + nw, top))
	pts.append(Vector2(cx + nw, sh))
	pts.append(Vector2(cx + r, cy))
	for i: int in range(1, ARC_STEPS):
		var theta: float = PI * float(i) / float(ARC_STEPS)
		pts.append(Vector2(cx + r * cos(theta), cy + r * sin(theta)))
	pts.append(Vector2(cx - r, cy))
	pts.append(Vector2(cx - nw, sh))
	return pts


## Greek key (meander) band of `width` px starting at origin, one polyline per cell, mirrored every other cell.
static func meander_cells(width: float, cell: float, origin: Vector2) -> Array:
	var out: Array = []
	if cell <= 0.0:
		return out
	var unit: PackedVector2Array = meander_unit()
	for k: int in int(floor(width / cell)):
		var x0: float = origin.x + float(k) * cell
		var mirror: bool = k % 2 == 1
		var pts: PackedVector2Array = PackedVector2Array()
		for f: Vector2 in unit:
			var fx: float = 1.0 - f.x if mirror else f.x
			pts.append(Vector2(x0 + fx * cell, origin.y + f.y * cell))
		out.append(pts)
	return out


## The same band as `meander_cells`, flattened to line segment pairs for one `draw_multiline` call (one draw call
## instead of one per cell).
static func meander_segments(width: float, cell: float, origin: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for seg: PackedVector2Array in meander_cells(width, cell, origin):
		for i: int in range(seg.size() - 1):
			out.append(seg[i])
			out.append(seg[i + 1])
	return out


## One cell of the Greek key in unit coordinates (0..1 across and down, y down).
static func meander_unit() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.67), Vector2(0.33, 0.67), Vector2(0.33, 0.33), Vector2(0.67, 0.33), Vector2(0.67, 1.0)])


## Half the inner width of the vial at height y (0 outside the bulb).
static func half_width(rect: Rect2, y: float) -> float:
	var r: float = rect.size.x * 0.5
	var nw: float = r * NECK_FRAC
	var sh: float = rect.position.y + rect.size.y * SHOULDER_FRAC
	var cy: float = _bulb_centre_y(rect)
	if y <= sh:
		return nw
	if y <= cy:
		return lerpf(nw, r, (y - sh) / (cy - sh))
	var dy: float = y - cy
	return sqrt(maxf(r * r - dy * dy, 0.0))


## Screen y of the liquid surface when the vial holds `blood` litres (full at the top, empty at the bulb).
static func level_y(rect: Rect2, blood: float) -> float:
	var f: float = level_frac(blood, FULL_BLOOD)
	return lerpf(rect.end.y - LIQUID_BOTTOM_INSET, rect.position.y + LIQUID_TOP_INSET, f)


## Litres as a fraction of full, clamped to 0..1.
static func level_frac(blood: float, full: float) -> float:
	if full <= 0.0:
		return 0.0
	return clampf(blood / full, 0.0, 1.0)


## 0 at blood_death, 1 at full. Above full stays 1, below death stays 0.
static func danger_frac(blood: float, death: float, full: float) -> float:
	var span: float = full - death
	if span <= 0.0:
		return 1.0 if blood > death else 0.0
	return clampf((blood - death) / span, 0.0, 1.0)


## Exponential approach from current to target. Frame-rate independent; snaps once it is close enough.
static func smooth_toward(current: float, target: float, delta: float, speed: float) -> float:
	if speed <= 0.0 or delta <= 0.0:
		return current
	var k: float = 1.0 - exp(-speed * delta)
	var out: float = current + (target - current) * k
	return target if absf(target - out) < 0.0005 else out


## Droplets per second for a bleed rate (L/s). Zero when not bleeding, fastest at DRIP_FULL_RATE.
static func drip_hz(bleed_rate: float) -> float:
	if bleed_rate < DRIP_MIN_RATE:
		return 0.0
	var t: float = sqrt(clampf(bleed_rate / DRIP_FULL_RATE, 0.0, 1.0))
	return lerpf(DRIP_HZ_MIN, DRIP_HZ_MAX, t)


## Heartbeat beats per second: calm at full, fast near blood_death.
static func heartbeat_hz(blood: float, death: float, full: float) -> float:
	return lerpf(HEART_FAST_HZ, HEART_CALM_HZ, danger_frac(blood, death, full))


## How strong each beat is: faint at full, strong near blood_death.
static func pulse_strength(blood: float, death: float, full: float) -> float:
	return lerpf(PULSE_FAST, PULSE_CALM, danger_frac(blood, death, full))


## One heartbeat cycle as a 0..1 shape: a lub at phase 0 and a weaker dub at phase 0.2.
static func heartbeat_shape(phase: float) -> float:
	var f: float = fposmod(phase, 1.0)
	var lub: float = exp(-pow(f / 0.06, 2.0))
	var dub: float = 0.6 * exp(-pow((f - 0.2) / 0.06, 2.0))
	return clampf(lub + dub, 0.0, 1.0)


## Liquid colour: deep red when healthy, brown-black at blood_death.
static func blood_color(blood: float, death: float, full: float) -> Color:
	var t: float = clampf(danger_frac(blood, death, full) / RED_ABOVE, 0.0, 1.0)
	return BROWN_BLACK.lerp(DEEP_RED, t)


## Arc length in radians for a stamina fraction.
static func stamina_span(stamina: float) -> float:
	return clampf(stamina, 0.0, 1.0) * TAU


## Sutherland-Hodgman: the part of a convex or concave polygon at or below screen row y (larger y is lower).
static func clip_below(poly: PackedVector2Array, y: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = poly.size()
	for i: int in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var a_in: bool = a.y >= y
		var b_in: bool = b.y >= y
		if a_in:
			out.append(a)
		if a_in != b_in:
			out.append(a.lerp(b, (y - a.y) / (b.y - a.y)))
	return out
