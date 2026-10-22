class_name ScreenPunchLogic
extends RefCounted
## Envelope of the screen-space punch on a hard hit: radial blur and colour split toward the impact point, a brief
## flash (warm, red-tinted on a finisher) and the finisher's cinematic grade (vignette and desaturation). Each kick
## decays as (1 - age/len)^2; a new kick takes the stronger of the two. Reduced motion keeps only a softened flash
## and the grade (no blur, no colour split). Pure. Unit-tested in test_screen_punch_logic.gd.

const REDUCED_FLASH_MULT: float = 0.5
const FINISHER_LEN_MULT: float = 1.6
const FINISHER_MULT: float = 1.3  ## a finisher punches harder than any ordinary full-impact hit
const TAPS_BY_LEVEL: Array[int] = [0, 5, 8]  ## radial taps per graphics level; 0 = no screen read (flash only)

var strength: float = 0.0  ## 0..1 of the current kick at its start
var age: float = 0.0
var length: float = 0.0
var finisher: bool = false
var reduced: bool = false
var grade: float = 0.0  ## 0..1 cinematic grade, set by the caller every frame
var center: Vector2 = Vector2(0.5, 0.5)  ## impact point in screen UV


## 0..1 punch for a hit of impact `imp`: 0 under `feel_punch_min`, 1 for a finisher.
static func strength_for(ev: Dictionary, imp: float, tun: Tuning) -> float:
	if FeelLogic.is_finisher(ev):
		return 1.0
	if imp < tun.feel_punch_min:
		return 0.0
	var span: float = maxf(1.0 - tun.feel_punch_min, 0.001)
	var s: float = 0.35 + 0.65 * clampf((imp - tun.feel_punch_min) / span, 0.0, 1.0)
	if bool(ev.get("hit_on_weapon", false)):
		s *= 0.6
	return s


static func taps_for(level: int) -> int:
	return TAPS_BY_LEVEL[clampi(level, 0, TAPS_BY_LEVEL.size() - 1)]


func kick(p_strength: float, p_finisher: bool, p_center: Vector2, p_reduced: bool, tun: Tuning) -> void:
	if p_strength <= 0.0:
		return
	if current() > p_strength and not p_finisher:
		return
	strength = clampf(p_strength, 0.0, 1.0)
	finisher = p_finisher
	reduced = p_reduced
	center = Vector2(clampf(p_center.x, 0.0, 1.0), clampf(p_center.y, 0.0, 1.0))
	age = 0.0
	length = tun.feel_punch_s * (FINISHER_LEN_MULT if p_finisher else 1.0)


func step(dt: float) -> void:
	if dt > 0.0 and is_finite(dt):
		age += dt


## Envelope of the current kick now (0 once it has run out).
func current() -> float:
	if length <= 0.0 or age >= length:
		return 0.0
	var a: float = 1.0 - age / length
	return strength * a * a


func blur(tun: Tuning) -> float:
	return 0.0 if reduced else current() * tun.feel_punch_blur * _mult()


func chroma(tun: Tuning) -> float:
	return 0.0 if reduced else current() * tun.feel_punch_chroma * _mult()


func flash(tun: Tuning) -> float:
	return minf(current() * tun.feel_punch_flash * _mult() * (REDUCED_FLASH_MULT if reduced else 1.0), 1.0)


func _mult() -> float:
	return FINISHER_MULT if finisher else 1.0


## Anything to draw this frame.
func active() -> bool:
	return current() > 0.001 or grade > 0.001


func reset() -> void:
	strength = 0.0
	age = 0.0
	length = 0.0
	grade = 0.0
