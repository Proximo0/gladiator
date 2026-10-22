class_name TouchFeel
extends RefCounted
## Pure touch mapping (tests/unit/test_touch_feel.gd): finger offset to stick units through a dead zone and response
## curve, the floating anchor that follows a finger past the ring, finger sizes from the screen and its dpi, and the
## per-tick button shaping (hold-GRAB auto-repeat with CROUCH, toggles). TouchControls feeds it screen events.

const STICK_DEAD: float = 0.12  ## of the stick radius: a resting thumb's wobble does not walk
const STICK_FULL: float = 0.9  ## full speed before the ring edge, so the thumb need not stretch
const STICK_EXPO: float = 0.0  ## 0 = linear after the dead zone
const AIM_DEAD: float = 0.03  ## of the aim radius: only the touch-down jitter, the hand stays precise
const AIM_FULL: float = 1.0
const AIM_EXPO: float = 0.0  ## linear: the hand moves as far as the finger, like the mouse
const GRAB_PULSE_TICKS: int = 6  ## hold GRAB: the GRAB bit repeats on/off at this period (the grab takes on a press)
const MM_PER_INCH: float = 25.4


## Offset (screen, y down) over `radius` to -1..1 (y down still): radial dead zone `dead` and full output at `full`
## (fractions of the radius), rescaled so output starts from 0 at the dead zone edge; `expo` blends in a cubic.
static func shape(offset: Vector2, radius: float, dead: float, full: float, expo: float) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var n: float = offset.length() / radius
	if n <= dead or n <= 0.0:
		return Vector2.ZERO
	var m: float = clampf((n - dead) / maxf(full - dead, 0.0001), 0.0, 1.0)
	m = lerpf(m, m * m * m, clampf(expo, 0.0, 1.0))
	return offset / (n * radius) * m


## Shaped offset to FighterInput units (y up), -1000..1000.
static func to_units(v: Vector2) -> Vector2i:
	return Vector2i(roundi(v.x * FighterInput.AXIS_MAX), roundi(-v.y * FighterInput.AXIS_MAX))


static func stick_units(offset: Vector2, radius: float) -> Vector2i:
	return to_units(shape(offset, radius, STICK_DEAD, STICK_FULL, STICK_EXPO))


static func aim_units(offset: Vector2, radius: float) -> Vector2i:
	return to_units(shape(offset, radius, AIM_DEAD, AIM_FULL, AIM_EXPO))


## The floating anchor follows a finger that leaves the ring, so the finger always sits on or inside it: reversing
## direction answers at once instead of after the finger travels back to the ring (dead travel reads as lag).
static func follow_anchor(anchor: Vector2, finger: Vector2, radius: float) -> Vector2:
	var off: Vector2 = finger - anchor
	if radius <= 0.0 or off.length() <= radius:
		return anchor
	return finger - off.normalized() * radius


## A size in on-screen px: `frac` of the screen's short side, bounded by millimetres when the dpi is known (a phone
## reports it; 0 = unknown, then `min_px` is the only floor).
static func size_px(short_px: float, frac: float, dpi: float, min_mm: float, max_mm: float, min_px: float) -> float:
	var px: float = maxf(short_px * frac, min_px)
	if dpi > 0.0:
		px = clampf(px, min_mm / MM_PER_INCH * dpi, max_mm / MM_PER_INCH * dpi)
	return px


## Buttons sent this tick from the held and toggled bits. `grab_ticks` counts the ticks GRAB has been held (0 = not
## held): while held the fighter crouches and GRAB repeats, so one held thumb bends down and picks a weapon up.
static func tick_buttons(held: int, toggled: int, grab_ticks: int) -> int:
	var out: int = (held | toggled) & ~FighterInput.GRAB
	if grab_ticks > 0:
		out |= FighterInput.CROUCH
		if ((grab_ticks - 1) / GRAB_PULSE_TICKS) % 2 == 0:
			out |= FighterInput.GRAB
	return out
