class_name ScreenPunch
extends CanvasLayer
## Screen-space punch on hard hits, drawn under the aim aid and HUD: a radial blur and colour split pulled toward the
## impact point plus a brief flash, and the finisher's cinematic grade (vignette, desaturation). One full-screen rect
## that is hidden (no cost) whenever nothing is playing. Medium and high graphics read the screen once and take 5 or
## 8 taps; low graphics and reduced motion use a flash-and-vignette overlay that never reads the screen. Envelopes
## come from ScreenPunchLogic. Owned by FeelDirector.

const LAYER: int = 8  ## under the aim aid (9) and the HUD (10)
const FLASH_WARM: Color = Color(1.0, 0.92, 0.78)
const FLASH_BLOOD: Color = Color(1.0, 0.42, 0.3)

const FULL_SHADER: String = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 center = vec2(0.5);
uniform float blur = 0.0;
uniform float chroma = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_col = vec3(1.0, 0.92, 0.78);
uniform float grade = 0.0;
uniform float aspect = 1.777;
uniform int taps = 5;
void fragment() {
	vec2 d = SCREEN_UV - center;
	vec3 acc = vec3(0.0);
	float n = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= taps) { break; }
		float k = 1.0 - blur * float(i) / float(max(taps - 1, 1));
		acc.r += texture(screen_tex, center + d * (k - chroma)).r;
		acc.g += texture(screen_tex, center + d * k).g;
		acc.b += texture(screen_tex, center + d * (k + chroma)).b;
		n += 1.0;
	}
	vec3 c = acc / max(n, 1.0);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float red = smoothstep(0.22, 0.45, c.r - max(c.g, c.b));  // blood keeps its colour in the grade
	c = mix(c, vec3(l), grade * 0.6 * (1.0 - red));
	vec2 q = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float r = length(q) / (0.5 * length(vec2(aspect, 1.0)));
	c *= 1.0 - smoothstep(0.35, 1.0, r) * grade * 0.85;
	vec2 dp = d * vec2(aspect, 1.0);
	c += flash_col * flash * (0.12 + 0.88 * exp(-dot(dp, dp) * 6.0));  // brightest at the impact
	COLOR = vec4(c, 1.0);
}
"""

const LITE_SHADER: String = """
shader_type canvas_item;
render_mode unshaded;
uniform float flash = 0.0;
uniform vec3 flash_col = vec3(1.0, 0.92, 0.78);
uniform float grade = 0.0;
uniform float aspect = 1.777;
uniform vec2 center = vec2(0.5);
void fragment() {
	vec2 q = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float r = length(q) / (0.5 * length(vec2(aspect, 1.0)));
	vec2 dp = (SCREEN_UV - center) * vec2(aspect, 1.0);
	float f = flash * (0.12 + 0.88 * exp(-dot(dp, dp) * 6.0));
	float v = smoothstep(0.35, 1.0, r) * grade * 0.85;
	float a = clamp(f + v, 0.0, 1.0);
	COLOR = vec4(flash_col * (f / max(a, 0.0001)), a);
}
"""

var logic: ScreenPunchLogic = ScreenPunchLogic.new()
var camera: Camera3D = null
var draws: int = 0  ## frames drawn (for the perf probe)

var _rect: ColorRect = null
var _full: ShaderMaterial = null
var _lite: ShaderMaterial = null
var _taps: int = 0


var _clock_real: RealClock = RealClock.new()

func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.name = "Punch"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 1)
	_rect.visible = false
	add_child(_rect)
	_taps = ScreenPunchLogic.taps_for(GfxQuality.level)
	var lite := Shader.new()
	lite.code = LITE_SHADER
	_lite = ShaderMaterial.new()
	_lite.shader = lite
	if _taps > 0:
		var full := Shader.new()
		full.code = FULL_SHADER
		_full = ShaderMaterial.new()
		_full.shader = full


## A hit: `strength` from ScreenPunchLogic.strength_for, `at` the world impact point.
func kick(strength: float, finisher: bool, at: Vector3, reduced_motion: bool) -> void:
	logic.kick(strength, finisher, _screen_uv(at), reduced_motion, Tuning.shared())


func _screen_uv(at: Vector3) -> Vector2:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree() or camera.is_position_behind(at):
		return Vector2(0.5, 0.5)
	var vs: Vector2 = camera.get_viewport().get_visible_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return Vector2(0.5, 0.5)
	return camera.unproject_position(at) / vs


func _process(delta: float) -> void:
	var real: float = _clock_real.step(delta, Engine.time_scale)
	logic.step(real)
	var on: bool = logic.active()
	_rect.visible = on
	if not on:
		return
	var tun: Tuning = Tuning.shared()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vs.x / maxf(vs.y, 1.0)
	var blur: float = logic.blur(tun)
	var chroma: float = logic.chroma(tun)
	var use_full: bool = _full != null and (blur > 0.0005 or chroma > 0.0002 or logic.grade > 0.001)
	var m: ShaderMaterial = _full if use_full else _lite
	if _rect.material != m:
		_rect.material = m
	var col: Color = FLASH_BLOOD if logic.finisher else FLASH_WARM
	m.set_shader_parameter("flash", logic.flash(tun))
	m.set_shader_parameter("flash_col", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("grade", logic.grade)
	m.set_shader_parameter("aspect", aspect)
	m.set_shader_parameter("center", logic.center)
	if use_full:
		m.set_shader_parameter("blur", blur)
		m.set_shader_parameter("chroma", chroma)
		m.set_shader_parameter("taps", _taps if blur > 0.0005 else 1)  # the grade alone needs one tap
	draws += 1
