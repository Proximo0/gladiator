class_name TitleLogo
extends Control
## The SANDBLOOD wordmark, drawn in code: SAND in carved bronze and BLOOD in blood red, each letter cut deep (a
## stepped dark extrusion under it, a lit top rim, a dark outline), the fill shaded top to bottom with a slow sheen
## passing across, and blood running off the bottom of BLOOD. `px` is the cap height's font size in layout units;
## the control asks for exactly the room the mark needs (minimum size), so containers can centre or left-align it.

const WORD_A: String = "SAND"
const WORD_B: String = "BLOOD"
const DEPTH_STEPS: int = 7
const DEPTH_EM: float = 0.075  ## extrusion depth, as a fraction of the font size
const SPACING_EM: float = 0.04
const DRIPS: Array = [[0.12, 0.5, 0.05], [0.33, 0.85, 0.06], [0.52, 0.32, 0.045], [0.71, 1.0, 0.065], [0.9, 0.55, 0.05]]  ## [x in BLOOD 0..1, length 0..1, width em]
const BRONZE_FILL: Color = Color(0.86, 0.62, 0.3)
const BRONZE_DEEP: Color = Color(0.27, 0.15, 0.06)
const BLOOD_FILL: Color = Color(0.72, 0.07, 0.05)
const BLOOD_DEEP: Color = Color(0.2, 0.01, 0.01)
const RIM_A: Color = Color(1.0, 0.9, 0.66)
const RIM_B: Color = Color(1.0, 0.5, 0.42)
const INK_EDGE: Color = Color(0.06, 0.025, 0.015, 0.95)

const FILL_SHADER: String = """
shader_type canvas_item;
uniform float top_y = 0.0;
uniform float bottom_y = 100.0;
uniform float width = 600.0;
varying vec2 lp;
void vertex() { lp = VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float t = clamp((lp.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
	// Cast metal: bright upper face, a hot band, then falling into shadow toward the base.
	float shade = mix(1.38, 0.52, t) + 0.38 * exp(-pow((t - 0.3) / 0.07, 2.0));
	// A sheen that sweeps across every few seconds, slanted.
	float s = fract(TIME * 0.12) * 1.8 - 0.4;
	float x = lp.x / max(width, 1.0) + t * 0.18;
	shade += 0.55 * exp(-pow((x - s) / 0.035, 2.0));
	// Pitting and wear, so it reads as a cast or carved surface rather than flat paint.
	float grit = hash(floor(lp * 0.45)) * 0.16 - 0.08;
	COLOR.rgb = COLOR.rgb * (shade + grit);
}
"""

var px: float = 160.0:
	set(v):
		px = v
		_refit()
var _fill: Control
var _mat: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = Control.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = FILL_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_fill.material = _mat
	_fill.draw.connect(_draw_fill)
	add_child(_fill)
	_refit()


static func font() -> Font:
	return MenuTheme.caps_font()


## Width of the whole mark at font size `p` (both words, their gap and the letter spacing).
static func mark_width(p: float) -> float:
	var f: Font = font()
	var fs: int = maxi(8, int(p))
	return f.get_string_size(WORD_A, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + f.get_string_size(WORD_B, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x \
			+ p * SPACING_EM * float(WORD_A.length() + WORD_B.length())


## The biggest font size whose mark fits `w` units across, capped at `cap`.
static func fit_px(w: float, cap: float) -> float:
	var p: float = cap * minf(1.0, w / maxf(mark_width(cap), 1.0))
	for _i: int in 20:
		if mark_width(p) <= w:
			break
		p *= 0.97  # glyph sizes round to whole pixels, so the ratio can land a hair over
	return p


func _refit() -> void:
	custom_minimum_size = Vector2(ceilf(mark_width(px)), ceilf(px * (0.86 + DEPTH_EM) + px * 0.42))
	update_minimum_size()
	queue_redraw()
	if _fill != null:
		_fill.queue_redraw()


func _baseline() -> float:
	return px * 0.8


func _origin() -> float:
	return (size.x - mark_width(px)) * 0.5


## Draws each letter of `word` from x, with letter spacing; returns the x after it.
func _word(ci: CanvasItem, word: String, x: float, y: float, col: Color, outline: int = 0) -> float:
	var f: Font = font()
	var fs: int = maxi(8, int(px))
	var cx: float = x
	for ch: String in word:
		if outline > 0:
			ci.draw_string_outline(f, Vector2(cx, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, col)
		else:
			ci.draw_string(f, Vector2(cx, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		cx += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + px * SPACING_EM
	return cx


func _blood_x() -> float:
	var f: Font = font()
	var fs: int = maxi(8, int(px))
	var x: float = _origin()
	for ch: String in WORD_A:
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + px * SPACING_EM
	return x


func _draw() -> void:
	var y: float = _baseline()
	var x0: float = _origin()
	var xb: float = _blood_x()
	var depth: float = px * DEPTH_EM
	var outline: int = maxi(3, int(px * 0.06))
	# Soft cast shadow on whatever is behind.
	for k: int in 3:
		var o: Vector2 = Vector2(px * 0.02, depth + px * (0.03 + 0.02 * float(k)))
		var a: float = 0.22 - 0.06 * float(k)
		_word(self, WORD_A, x0 + o.x, y + o.y, Color(0.0, 0.0, 0.0, a), outline + k * 3)
		_word(self, WORD_B, xb + o.x, y + o.y, Color(0.0, 0.0, 0.0, a), outline + k * 3)
	# Stepped extrusion: the cut sides of the letters, darkest at the back.
	for i: int in range(DEPTH_STEPS, 0, -1):
		var d: float = depth * float(i) / float(DEPTH_STEPS)
		var k2: float = float(i) / float(DEPTH_STEPS)
		_word(self, WORD_A, x0, y + d, BRONZE_DEEP.lerp(INK_EDGE, k2 * 0.6), outline)
		_word(self, WORD_A, x0, y + d, BRONZE_DEEP.lerp(BRONZE_FILL.darkened(0.55), 1.0 - k2))
		_word(self, WORD_B, xb, y + d, BLOOD_DEEP.lerp(INK_EDGE, k2 * 0.6), outline)
		_word(self, WORD_B, xb, y + d, BLOOD_DEEP.lerp(BLOOD_FILL.darkened(0.55), 1.0 - k2))
	# Dark outline round the face, then a lit rim along the top edge.
	_word(self, WORD_A, x0, y, INK_EDGE, outline)
	_word(self, WORD_B, xb, y, INK_EDGE, outline)
	_word(self, WORD_A, x0, y - px * 0.018, RIM_A)
	_word(self, WORD_B, xb, y - px * 0.018, RIM_B)
	_draw_drips(xb, y)


## Blood running down from the base of BLOOD: tapering runs that end in a drop, and a few spatter dots.
func _draw_drips(xb: float, y: float) -> void:
	var f: Font = font()
	var w_b: float = f.get_string_size(WORD_B, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(px))).x + px * SPACING_EM * float(WORD_B.length())
	var top: float = y + px * DEPTH_EM * 0.6
	var max_len: float = px * 0.36
	for d: Array in DRIPS:
		var x: float = xb + w_b * float(d[0])
		var ln: float = max_len * float(d[1])
		var w: float = px * float(d[2])
		var pts := PackedVector2Array([Vector2(x - w * 0.6, top - px * 0.04), Vector2(x + w * 0.6, top - px * 0.04),
				Vector2(x + w * 0.32, top + ln), Vector2(x - w * 0.32, top + ln)])
		draw_colored_polygon(pts, BLOOD_DEEP.lerp(BLOOD_FILL, 0.55))
		draw_circle(Vector2(x, top + ln), w * 0.48, BLOOD_DEEP.lerp(BLOOD_FILL, 0.6))
		draw_circle(Vector2(x - w * 0.12, top + ln - w * 0.12), w * 0.14, Color(1.0, 0.6, 0.55, 0.55))  # wet glint
	for i: int in 7:
		var u: float = fmod(float(i) * 0.6180339 + 0.13, 1.0)
		var p: Vector2 = Vector2(xb + w_b * u, top + max_len * (0.25 + 0.6 * fmod(float(i) * 0.37, 1.0)))
		draw_circle(p, px * (0.008 + 0.006 * fmod(float(i) * 0.71, 1.0)), BLOOD_FILL.darkened(0.25))


func _draw_fill() -> void:
	var y: float = _baseline()
	_mat.set_shader_parameter("top_y", y - px * 0.72)
	_mat.set_shader_parameter("bottom_y", y)
	_mat.set_shader_parameter("width", maxf(size.x, 1.0))
	_word(_fill, WORD_A, _origin(), y, BRONZE_FILL)
	_word(_fill, WORD_B, _blood_x(), y, BLOOD_FILL)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
		if _fill != null:
			_fill.queue_redraw()
