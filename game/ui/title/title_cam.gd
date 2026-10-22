class_name TitleCam
extends RefCounted
## The title backdrop's camera path, pure: a slow, low drift around two gladiators on the sand, never repeating
## exactly, always looking at them. `frame_x` puts the pair off centre (0 = centre, 0.3 = a third of the way to the
## right edge) so a menu on the left side of a landscape screen leaves them in view.

const SUBJECT: Vector3 = Vector3(0.0, 1.05, 0.0)
const ANGLE0: float = 0.3  ## start bearing (rad): just off the pair's side, both in profile
const DRIFT: float = 0.016  ## rad/s of slow orbit
const SWAY: float = 0.32  ## rad of the slower back-and-forth on top
const RADIUS: float = 5.6
const RADIUS_SWAY: float = 0.7
const HEIGHT: float = 1.3
const HEIGHT_SWAY: float = 0.3


## Camera {"pos": Vector3, "target": Vector3} at time `t` seconds, for a vertical field of view `vfov_deg` and a
## viewport `aspect` (width / height).
static func pose(t: float, frame_x: float, vfov_deg: float, aspect: float) -> Dictionary:
	var a: float = ANGLE0 + t * DRIFT + SWAY * sin(t * 0.043)
	var r: float = RADIUS + RADIUS_SWAY * sin(t * 0.061 + 0.7)
	var h: float = HEIGHT + HEIGHT_SWAY * sin(t * 0.052 + 1.9)
	var pos: Vector3 = SUBJECT + Vector3(cos(a) * r, h - SUBJECT.y, sin(a) * r)
	var fwd: Vector3 = (SUBJECT - pos).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var tan_h: float = tan(deg_to_rad(vfov_deg) * 0.5) * maxf(aspect, 0.1)
	var dist: float = SUBJECT.distance_to(pos)
	# Looking `d` to the left of the pair puts them frame_x of the half-width right of centre.
	var d: float = frame_x * dist * tan_h
	return {"pos": pos, "target": SUBJECT - right * d}
