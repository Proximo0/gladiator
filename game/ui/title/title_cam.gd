class_name TitleCam
extends RefCounted
## The title backdrop's camera path, pure: a slow, low drift around two gladiators on the sand, never repeating
## exactly, always looking at them. `frame_x` puts the pair off centre (0 = centre, 0.3 = a third of the way to the
## right edge) so a menu on the left side of a landscape screen leaves them in view. On a tall screen the pair must
## also fit the open band between the portrait title's mark and its tiles (`band`, a fraction of the screen height,
## centred `frame_y` of the half-height above the middle): the camera pulls back as far as the arena allows, then
## widens its lens.

const SUBJECT: Vector3 = Vector3(0.0, 1.05, 0.0)
const ANGLE0: float = 0.3  ## start bearing (rad): just off the pair's side, both in profile
const DRIFT: float = 0.016  ## rad/s of slow orbit
const SWAY: float = 0.32  ## rad of the slower back-and-forth on top
const RADIUS: float = 5.6
const RADIUS_SWAY: float = 0.7
const HEIGHT: float = 1.3
const HEIGHT_SWAY: float = 0.3
const PAIR_HALF_W: float = 2.3  ## m either side of the centre the pair takes (1.75 m apart each way, arms, shield)
const PAIR_H: float = 2.3  ## m of height the pair takes (head and a raised weapon)
const FIT_W: float = 0.85  ## the pair's half-width fills at most this much of the half-screen
const PULL_MAX: float = 1.4  ## the farthest pull-back (x RADIUS): the camera stays well inside the 11 m wall


## Camera {"pos": Vector3, "target": Vector3, "fov": vertical degrees} at time `t` seconds, for a vertical field of
## view `vfov_deg` and a viewport `aspect` (width / height). A wide screen keeps `vfov_deg` and the base path.
static func pose(t: float, frame_x: float, vfov_deg: float, aspect: float, frame_y: float = 0.0, band: float = 1.0) -> Dictionary:
	var asp: float = maxf(aspect, 0.1)
	var bh: float = clampf(band, 0.05, 1.0)
	var tan_v: float = tan(deg_to_rad(vfov_deg) * 0.5)
	# Pull back until the pair fits across the screen and inside the band, as far as PULL_MAX.
	var need: float = maxf(PAIR_HALF_W / (FIT_W * tan_v * asp), PAIR_H / (2.0 * bh * tan_v))
	var k: float = clampf(need / RADIUS, 1.0, PULL_MAX)
	# Still too tight at the nearest point of the sway: widen the lens instead.
	var near: float = (RADIUS - RADIUS_SWAY) * k
	tan_v = maxf(tan_v, maxf(PAIR_HALF_W / (FIT_W * near * asp), PAIR_H / (2.0 * bh * near)))
	var a: float = ANGLE0 + t * DRIFT + SWAY * sin(t * 0.043)
	var r: float = (RADIUS + RADIUS_SWAY * sin(t * 0.061 + 0.7)) * k
	var h: float = (HEIGHT + HEIGHT_SWAY * sin(t * 0.052 + 1.9) - SUBJECT.y) * k  # same downward angle when pulled back
	var pos: Vector3 = SUBJECT + Vector3(cos(a) * r, h, sin(a) * r)
	var fwd: Vector3 = (SUBJECT - pos).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var dist: float = SUBJECT.distance_to(pos)
	# Looking `dx` to the left of the pair puts them frame_x of the half-width right of centre; `dy` below, frame_y up.
	var dx: float = frame_x * dist * tan_v * asp
	var dy: float = frame_y * dist * tan_v
	return {"pos": pos, "target": SUBJECT - right * dx - Vector3.UP * dy, "fov": rad_to_deg(atan(tan_v)) * 2.0}
