class_name FightCamera
extends Camera3D
## Third-person fight camera. `target` is the fighter we look over the shoulder of, `look_at_node` the opponent.
## Modes: "follow" (over the shoulder), "orbit" (slow turn around the pair), "wide" (side-on, frames both).
## All framing maths is in static functions so it can be unit tested.

const FOV_EXTRA_MAX: float = 18.0  ## most the lens widens to keep both fighters framed, degrees
const WALL_MARGIN: float = 0.7  ## how far inside the wall the camera stays
const SQUEEZE_FREE_M: float = 0.8  ## how far outside the wall the follow pose may be (it just comes in) before it swings aside, m
const SQUEEZE_FULL_M: float = 2.0  ## overshoot at which the swing round the look point is complete, m
const SQUEEZE_UNWIND_RAD_S: float = 1.0  ## fastest the wall swing turns back as the fighter steps off the wall, rad/s
const SQUEEZE_UNWIND_CUT_RAD: float = 0.5  ## held back this far from where it wants to be, the swing cuts there, rad
## Aim and height: look a little below head height from above, so the fighters sit in the lower-middle of the frame
## with sand under their feet and the wall kept to the top third.
const FOLLOW_LOOK_Y: float = 0.9
const WIDE_LOOK_Y: float = 0.6
const WIDE_HEIGHT: float = 4.4
## Vertical room above and below the screen centre (half-heights): less above, so heads clear the top, and less
## below, so there is sand under the feet and the fighters sit in the lower-middle of the frame.
const FRAME_UP: float = 1.0
const FRAME_DOWN: float = 0.75
const SQUEEZE_RATE_IN: float = 6.0  ## per second the squeeze blend rises
const SQUEEZE_RATE_OUT: float = 1.2  ## per second it falls: slower, so it does not flicker at the wall
const SQUEEZE_DEADBAND: float = 0.12  ## the target must drop this far below the blend before it starts to fall
const MODES: PackedStringArray = ["follow", "orbit", "wide"]

var target: Node3D
var look_at_node: Node3D
var mode: String = "follow"
var arena_radius: float = 11.0
var follow_distance: float = 3.4
var follow_height: float = 2.3
var shoulder: float = 0.7
var follow_rate: float = 5.0
var orbit_yaw: float = 0.0
var orbit_speed: float = 0.3

## Impact state (kick, shake, zoom punch). The presenter feeds it through `hit_impact`.
var shake: CameraShake = CameraShake.new()

## Finisher / death shot (see FinaleShot) and the node it watches.
var finale: FinaleShot = FinaleShot.new()
var _finale_victim: Node3D = null
var finale_head: Node3D = null  ## the victim's head part; tracked once `finale_head_free` (the presenter sets it)
var finale_head_free: bool = false
var _squeeze_t: float = 0.0  ## how far the follow shot has swung round at the wall, 0..1 of a quarter turn (read by sims)
var _prime_wait: int = 0  ## physics ticks left before a restart primes the camera

var _look_point: Vector3 = Vector3.ZERO
var _base_pos: Vector3 = Vector3.ZERO
var _primed: bool = false
var _base_fov: float = 0.0
var _fov_extra: float = 0.0
var _last_me: Vector3 = Vector3.ZERO  ## last finite fighter positions, kept when a pelvis goes NaN or is freed
var _last_opp: Vector3 = Vector3(0.0, 0.0, -3.0)
var _have_last: bool = false
var aspect_override: float = 0.0  ## width / height to frame for instead of the viewport's (sims and captures); 0 = viewport
var dbg_want_pos: Vector3 = Vector3.ZERO  ## the unsmoothed pose this frame wanted (sims measure lag against it)
var dbg_want_look: Vector3 = Vector3.ZERO
var _frame_scale: float = 1.0  ## Engine.time_scale seen last frame: the speed this frame's delta was scaled by
var cuts: int = 0  ## camera cuts so far (the wall swing changing sides), for sims
## Motion lead: the smoothed velocity of the wanted pose, fed forward so a moving fighter is not trailed by
## v / follow_rate metres (1.2 m strafing, 0.8 m in a roll before this).
var _vel_pos: Vector3 = Vector3.ZERO
var _vel_look: Vector3 = Vector3.ZERO
var _prev_want_pos: Vector3 = Vector3.ZERO
var _prev_want_look: Vector3 = Vector3.ZERO
var _side_sign: float = 0.0  ## side of the fight line the wall-squeeze shot films from, latched while it is in use
var _swing_rot: float = 0.0  ## the wall swing last frame (signed, rad), so it unwinds at a bounded rate
var _side_prev: Vector3 = Vector3.ZERO  ## last side-on camera position: the wall turn keeps to the end of the arc nearest it
var _side_have: bool = false
var _victim_owner: Node = null  ## the finale victim's fighter (anything with is_limb_cut), polled for a later beheading
var _head_seen: bool = false  ## the finale has already reacted to the head coming free
var _finale_scale: float = 0.0


const MAX_COORD: float = 60.0  ## fighter positions are clamped to this box (a flung ragdoll must not drag the camera)


## True when every component is a finite number.
static func is_finite_v3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## `v` with each component limited to +-MAX_COORD.
static func limit_coord(v: Vector3) -> Vector3:
	return Vector3(clampf(v.x, -MAX_COORD, MAX_COORD), clampf(v.y, -MAX_COORD, MAX_COORD), clampf(v.z, -MAX_COORD, MAX_COORD))


## Unit vector on the ground from a to b. Falls back to -Z when they coincide.
static func flat_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() < 0.001:
		return Vector3(0.0, 0.0, -1.0)
	return d.normalized()


## Frame-rate independent blend factor for exponential smoothing at `rate` per second.
static func smooth_factor(rate: float, delta: float) -> float:
	if not is_finite(rate) or not is_finite(delta):
		return 0.0
	return 1.0 - exp(-maxf(rate, 0.0) * maxf(delta, 0.0))


## Over-the-shoulder pose: behind and above `me`, shifted to the right shoulder, looking at a point between us
## that leans toward the opponent. Returns {"pos": Vector3, "look": Vector3}.
static func follow_pose(me: Vector3, opp: Vector3, distance: float, height: float, shoulder_off: float, close: float = 0.0, close_shoulder: float = 0.0, close_height: float = 0.0) -> Dictionary:
	shoulder_off += close * close_shoulder
	height += close * close_height
	var f: Vector3 = flat_dir(me, opp)
	var right: Vector3 = f.cross(Vector3.UP)
	var pos: Vector3 = me - f * distance + right * shoulder_off + Vector3(0.0, height, 0.0)
	var look: Vector3 = me.lerp(opp, 0.6) + Vector3(0.0, FOLLOW_LOOK_Y, 0.0)
	return {"pos": pos, "look": look}


## 1 at melee range (separation <= near), 0 at or beyond far, smooth between. Moves the follow camera off the line
## through your back so the opponent is not hidden behind you.
static func close_blend(sep: float, near: float, far: float) -> float:
	if far <= near:
		return 1.0 if sep <= near else 0.0
	var t: float = clampf((far - sep) / (far - near), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Side-on pose that fits both fighters. Distance grows with their separation.
static func wide_pose(a: Vector3, b: Vector3, fov_deg: float, height: float, min_distance: float,
		arena_r: float = 0.0) -> Dictionary:
	var mid: Vector3 = (a + b) * 0.5
	var f: Vector3 = flat_dir(a, b)
	var side: Vector3 = f.cross(Vector3.UP)
	var sep: float = Vector2(a.x - b.x, a.z - b.z).length()
	var dist: float = wide_distance(sep, fov_deg, min_distance)
	# Near the wall the outer side would be pushed into the wall (a close-up of nothing): film from the inner side.
	if arena_r > 0.0:
		var outer: Vector3 = mid + side * dist
		var inner: Vector3 = mid - side * dist
		if Vector2(outer.x, outer.z).length() > arena_r and Vector2(inner.x, inner.z).length() < Vector2(outer.x, outer.z).length():
			side = -side
	var pos: Vector3 = mid + side * dist + Vector3(0.0, height, 0.0)
	return {"pos": pos, "look": mid + Vector3(0.0, WIDE_LOOK_Y, 0.0)}


## Distance at which two points `sep` apart fit within the horizontal field of view (with margin).
static func wide_distance(sep: float, fov_deg: float, min_distance: float) -> float:
	var half: float = tan(deg_to_rad(fov_deg) * 0.5)
	return maxf(min_distance, (sep * 0.5 + 1.6) / maxf(half, 0.1))


## Camera orbiting `center` at yaw/pitch (radians) and `distance`. Yaw 0 puts the camera on +Z.
static func orbit_pose(center: Vector3, yaw: float, pitch: float, distance: float) -> Dictionary:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return {"pos": center + dir * distance, "look": center}


## A Tuning field, or `fallback` when this build's Tuning has no such row yet.
static func tuned(tun: Tuning, field: String, fallback: float) -> float:
	if tun == null:
		return fallback
	var v: Variant = tun.get(field)
	return float(v) if v is float or v is int else fallback


## Vertical field of view for `aspect`: on a portrait screen it widens until the horizontal view is at least
## `min_hfov` degrees (a kept vertical lens leaves a 33 degree slit at 9:16), at most `max_extra` degrees wider.
static func lens_for_aspect(fov_deg: float, aspect: float, min_hfov: float, max_extra: float) -> float:
	if aspect >= 1.0 or aspect <= 0.0:
		return fov_deg
	var need: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(min_hfov) * 0.5) / aspect))
	return clampf(need, fov_deg, fov_deg + max_extra)


## Ground direction from `mid` for a camera `dist` metres out: `dir` when that stays inside `lim`, else the nearest
## direction that does. The directions that fit form an arc centred on the arena centre; of its two ends the one
## nearer the camera's current position `prefer` is used (`use_prefer`), else the one nearer `dir`. Never flips to the
## far side of the fight, so the camera does not sweep through the fighters.
static func fit_dir(mid: Vector3, dir: Vector3, dist: float, lim: float, prefer: Vector3 = Vector3.ZERO,
		use_prefer: bool = false) -> Vector3:
	var r: float = Vector2(mid.x, mid.z).length()
	if lim <= 0.0 or r < 0.01 or dist <= 0.0:
		return dir
	if Vector2(mid.x + dir.x * dist, mid.z + dir.z * dist).length() <= lim:
		return dir
	var c: float = (r * r + dist * dist - lim * lim) / (2.0 * dist * r)
	var a_in: float = atan2(-mid.x, -mid.z)
	if c >= 1.0:
		return Vector3(sin(a_in), 0.0, cos(a_in))
	var half: float = acos(clampf(c, -1.0, 1.0))
	var e1 := Vector3(sin(a_in + half), 0.0, cos(a_in + half))
	var e2 := Vector3(sin(a_in - half), 0.0, cos(a_in - half))
	if use_prefer:
		var p1: float = Vector2(mid.x + e1.x * dist - prefer.x, mid.z + e1.z * dist - prefer.z).length()
		var p2: float = Vector2(mid.x + e2.x * dist - prefer.x, mid.z + e2.z * dist - prefer.z).length()
		return e1 if p1 <= p2 else e2
	return e1 if e1.dot(dir) >= e2.dot(dir) else e2


## Farthest distance along unit ground direction `d` from `from` that stays inside `lim` of the arena centre (0 when
## `from` itself is outside).
static func ray_fit(from: Vector3, d: Vector3, lim: float) -> float:
	var l := Vector2(from.x, from.z)
	var dd := Vector2(d.x, d.z)
	var c: float = l.length_squared() - lim * lim
	if c > 0.0:
		return 0.0
	var b: float = l.dot(dd)
	return -b + sqrt(maxf(b * b - c, 0.0))


## A follow camera at `pos` looking at `look`, kept inside `lim`. While `pos` is under `free_m` outside the wall it
## only comes in along its line. Further out it swings round `look` (keeping height) toward the nearest direction
## where it fits `free_m` closer (fit_dir), fully once `full_m` outside; the swing eases in with that radial overshoot
## (smoothstep), so it never jumps, and stops at `max_rad` (past side-on it would film the fighter's face). `sign`
## (+1 / -1) keeps the way round it already took; 0 picks the shorter way. `prev_rot` is the swing last time (the
## returned "rot") and `max_unwind` how far it may shrink in one call (rad): a big swing (the long way round, after a
## cut) would otherwise unwind across the whole fight in a few frames as the fighter steps off the wall. Once the
## held-back swing is more than `unwind_cut` from where it wants to be, it cuts there instead.
## Returns {"pos", "sign", "amount" 0..1, "rot" (signed swing, rad), "cut" true when it changed ways or cut back}.
static func swing_inside(pos: Vector3, look: Vector3, lim: float, free_m: float, full_m: float, sign: float = 0.0,
		max_rad: float = 1.75, prev_rot: float = 0.0, max_unwind: float = INF, unwind_cut: float = INF) -> Dictionary:
	var out: Dictionary = {"pos": pos, "sign": 0.0, "amount": 0.0, "rot": 0.0, "cut": false}
	var o := Vector3(pos.x - look.x, 0.0, pos.z - look.z)
	var rh: float = o.length()
	if lim <= 0.0 or rh < 0.01:
		return out
	var d: Vector3 = o / rh
	if Vector2(pos.x, pos.z).length() <= lim:
		if absf(prev_rot) <= max_unwind or absf(prev_rot) - max_unwind > unwind_cut:
			out["cut"] = absf(prev_rot) > max_unwind
			return out
		return _swung(out, look, d, rh, pos.y, lim, prev_rot - signf(prev_rot) * max_unwind, signf(prev_rot))
	var excess: float = Vector2(pos.x, pos.z).length() - lim
	var r_in: float = maxf(rh - free_m, 0.5)
	var s: float = 0.0
	if full_m > free_m:
		s = clampf((excess - free_m) / (full_m - free_m), 0.0, 1.0)
	elif excess > free_m:
		s = 1.0
	s = s * s * (3.0 - 2.0 * s)
	var sg: float = sign
	var rot: float = 0.0
	if s > 0.0:
		# The directions that fit form an arc round the arena-centre direction; reach its near end going the way
		# already taken. Only when that way can no longer reach the arc (past `max_rad`) and the other way can,
		# change sides, and say so ("cut"): the camera then cuts instead of sweeping through the fight.
		var lp := Vector2(look.x, look.z)
		var c: float = (lp.length_squared() + r_in * r_in - lim * lim) / maxf(2.0 * r_in * lp.length(), 0.0001)
		var half: float = acos(clampf(c, -1.0, 1.0)) if lp.length() > 0.01 else PI
		var a_in: float = atan2(-look.z, -look.x)  # Vector2 angle of the inward direction
		var a_d: float = atan2(d.z, d.x)
		var pos_way: float = fposmod(a_in - half - a_d, TAU)  # rotating +: first reach the arc's lower end
		var neg_way: float = fposmod(a_d - (a_in + half), TAU)  # rotating -: first reach its upper end
		if sg == 0.0:
			sg = 1.0 if pos_way <= neg_way else -1.0
		elif sg > 0.0 and pos_way > max_rad + 0.3 and neg_way < max_rad:
			sg = -1.0
			out["cut"] = true
		elif sg < 0.0 and neg_way > max_rad + 0.3 and pos_way < max_rad:
			sg = 1.0
			out["cut"] = true
		var ang: float = pos_way if sg > 0.0 else -neg_way
		if absf(wrapf(a_d - a_in, -PI, PI)) <= half:
			ang = 0.0  # it already fits that close in: no swing
		ang = clampf(ang, -max_rad, max_rad)
		rot = ang * s
	var shrink: bool = absf(rot) < absf(prev_rot) - max_unwind or (rot * prev_rot < 0.0 and absf(prev_rot) > max_unwind)
	if not out["cut"] and shrink:
		var held: float = prev_rot - signf(prev_rot) * max_unwind
		if absf(held - rot) > unwind_cut:
			out["cut"] = true
		else:
			rot = held
			sg = signf(prev_rot)
	return _swung(out, look, d, rh, pos.y, lim, rot, sg)


## Fills swing_inside's result for a swing of `rot` (rad) of the ground direction `d` round `look`.
static func _swung(out: Dictionary, look: Vector3, d: Vector3, rh: float, y: float, lim: float, rot: float, sg: float) -> Dictionary:
	var rv: Vector2 = Vector2(d.x, d.z).rotated(rot)
	var dir := Vector3(rv.x, 0.0, rv.y)
	out["amount"] = absf(rot) / (PI * 0.5)
	out["rot"] = rot
	out["sign"] = sg
	var r: float = minf(rh, ray_fit(look, dir, lim))
	out["pos"] = Vector3(look.x + dir.x * r, y, look.z + dir.z * r)
	return out


## Ground angle (radians) between `a` and `b` as seen from `pivot`.
static func swing_angle(a: Vector3, b: Vector3, pivot: Vector3) -> float:
	var u := Vector2(a.x - pivot.x, a.z - pivot.z)
	var v := Vector2(b.x - pivot.x, b.z - pivot.z)
	if u.length() < 0.001 or v.length() < 0.001:
		return 0.0
	return absf(u.angle_to(v))


## Which side of the fight line (+1 along flat_dir(a, b) x UP, or -1) a side-on shot should use. `by_camera`: the side
## the camera `cam` is already on (stable, no cuts); otherwise the side with more room inside `lim`.
static func pick_side(a: Vector3, b: Vector3, fov_deg: float, min_distance: float, lim: float, cam: Vector3,
		by_camera: bool) -> float:
	var mid: Vector3 = (a + b) * 0.5
	var s: Vector3 = flat_dir(a, b).cross(Vector3.UP)
	if by_camera:
		return 1.0 if (cam - mid).dot(s) >= 0.0 else -1.0
	var dist: float = wide_distance(Vector2(a.x - b.x, a.z - b.z).length(), fov_deg, min_distance)
	var room_p: float = lim - Vector2(mid.x + s.x * dist, mid.z + s.z * dist).length()
	var room_n: float = lim - Vector2(mid.x - s.x * dist, mid.z - s.z * dist).length()
	if lim > 0.0 and room_p >= 0.0 and room_n >= 0.0:
		return 1.0 if (cam - mid).dot(s) >= 0.0 else -1.0
	return 1.0 if room_p >= room_n else -1.0


## Side-on pose that fits both fighters, from side `side_sign` of the fight line, turned toward the arena centre as
## far as the wall needs (see fit_dir). Continuous in the fighters' positions, unlike wide_pose's side flip.
static func side_pose(a: Vector3, b: Vector3, fov_deg: float, height: float, min_distance: float, lim: float,
		side_sign: float, prefer: Vector3 = Vector3.ZERO, use_prefer: bool = false) -> Dictionary:
	var mid: Vector3 = (a + b) * 0.5
	var s: Vector3 = flat_dir(a, b).cross(Vector3.UP) * (1.0 if side_sign >= 0.0 else -1.0)
	var dist: float = wide_distance(Vector2(a.x - b.x, a.z - b.z).length(), fov_deg, min_distance)
	var d: Vector3 = fit_dir(mid, s, dist, lim, prefer, use_prefer)
	return {"pos": mid + d * dist + Vector3(0.0, height, 0.0), "look": mid + Vector3(0.0, WIDE_LOOK_Y, 0.0)}


## One step of the motion lead: velocity of a wanted point from its last position, smoothed at `rate` per second
## and limited to `vmax`. A jump over `cut_m` in one frame is a cut (a mode or framing change), not motion.
static func step_lead(vel: Vector3, prev: Vector3, now: Vector3, delta: float, rate: float, vmax: float, cut_m: float) -> Vector3:
	if delta <= 0.0 or not is_finite_v3(prev) or not is_finite_v3(now):
		return vel
	var dp: Vector3 = now - prev
	var raw: Vector3 = Vector3.ZERO if dp.length() > cut_m else dp / delta
	return vel.lerp(raw, smooth_factor(rate, delta)).limit_length(vmax)


## Keeps a camera position inside the wall (flat radius <= arena_radius - margin) and above the sand.
static func clamp_to_arena(pos: Vector3, arena_r: float, margin: float, min_height: float) -> Vector3:
	var out: Vector3 = pos
	var flat := Vector2(pos.x, pos.z)
	var limit: float = maxf(arena_r - margin, 0.5)
	if flat.length() > limit:
		flat = flat.normalized() * limit
		out.x = flat.x
		out.z = flat.y
	out.y = maxf(out.y, min_height)
	return out


## Worst framing ratio of `points` seen from `pos` looking at `look`: the largest share of the half field of view
## (vertical `fov_deg`, width from `aspect`) any point takes. At or under 1 everything is on screen; behind the camera
## counts as far outside.
static func frame_ratio(pos: Vector3, look: Vector3, fov_deg: float, aspect: float, points: Array) -> float:
	var fwd: Vector3 = (look - pos)
	if fwd.length() < 0.001:
		return 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(fwd)
	var tv: float = maxf(tan(deg_to_rad(fov_deg) * 0.5), 0.01)
	var th: float = tv * maxf(aspect, 0.2)
	var worst: float = 0.0
	for p: Vector3 in points:
		var v: Vector3 = p - pos
		var z: float = v.dot(fwd)
		if z < 0.1:
			return 99.0
		var yn: float = v.dot(up) / (z * tv)  ## vertical, in half-heights from the screen centre (up positive)
		var vert: float = yn / FRAME_UP if yn > 0.0 else -yn / FRAME_DOWN
		worst = maxf(worst, maxf(absf(v.dot(right)) / (z * th), vert))
	return worst


## Where `p` lands vertically on screen when `pos` looks at `look`: 0 top edge, 1 bottom edge (vertical fov `fov_deg`).
static func screen_y(pos: Vector3, look: Vector3, fov_deg: float, p: Vector3) -> float:
	var fwd: Vector3 = (look - pos).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(fwd)
	var v: Vector3 = p - pos
	var z: float = maxf(v.dot(fwd), 0.1)
	return 0.5 - 0.5 * v.dot(up) / (z * tan(deg_to_rad(fov_deg) * 0.5))


## Metres to pull `pos` straight back from `look` (steps of 0.25 m, at most `max_pull`) until `points` sit inside
## `margin` of the half field of view.
static func pull_back_for(pos: Vector3, look: Vector3, fov_deg: float, aspect: float, points: Array, margin: float,
		max_pull: float) -> float:
	var away: Vector3 = pos - look
	if away.length() < 0.001:
		return 0.0
	away = away.normalized()
	var pull: float = 0.0
	while pull < max_pull and frame_ratio(pos + away * pull, look, fov_deg, aspect, points) > margin:
		pull += 0.25
	pull = minf(pull, max_pull)
	if pull <= 0.0 or frame_ratio(pos + away * pull, look, fov_deg, aspect, points) > margin:
		return pull
	# Refine inside the last step, so the pull changes smoothly instead of in 0.25 m jumps.
	var lo: float = maxf(pull - 0.25, 0.0)
	var hi: float = pull
	for _i: int in 5:
		var m: float = (lo + hi) * 0.5
		if frame_ratio(pos + away * m, look, fov_deg, aspect, points) > margin:
			lo = m
		else:
			hi = m
	return hi


## Field of view (degrees) at which `points` fit inside `margin`, from the ratio measured at `fov_deg`; capped at
## `fov_deg + max_extra`.
static func fov_to_fit(ratio: float, fov_deg: float, margin: float, max_extra: float) -> float:
	if ratio <= margin:
		return fov_deg
	var t: float = tan(deg_to_rad(fov_deg) * 0.5) * ratio / maxf(margin, 0.1)
	return minf(rad_to_deg(2.0 * atan(t)), fov_deg + max_extra)


## Points that must stay on screen for a fighter at pelvis position `p`: feet on the sand and head height.
static func frame_points(p: Vector3) -> Array:
	return [Vector3(p.x, 0.0, p.z), Vector3(p.x, p.y + 0.8, p.z)]


## A resolved hit: kick toward `dir`, shake, and (for a finisher) a zoom punch. `strength` 0..1 is the camera strength
## from FeelLogic; `scale` the master motion scale (0 under reduced motion).
func hit_impact(dir: Vector3, strength: float, finisher: bool, scale: float) -> void:
	var tun: Tuning = Tuning.shared()
	shake.add_hit(dir, strength, tun, scale)
	if finisher:
		shake.add_zoom(tun.feel_zoom_deg, maxf(strength, 0.6), tun, scale)


func set_mode(new_mode: String) -> void:
	if MODES.has(new_mode):
		mode = new_mode


## One step of the squeeze blend with hysteresis: rises quickly toward `target`, holds while the target is within
## `deadband` below it, and falls slowly beyond that. The deadband shrinks with the blend (deadband * t), so a small
## leftover blend still falls to 0 instead of sticking at `deadband` for ever.
static func step_squeeze(t: float, target: float, delta: float, rate_in: float, rate_out: float, deadband: float) -> float:
	if target > t:
		return lerpf(t, target, smooth_factor(rate_in, delta))
	if target < t - deadband * minf(t / 0.5, 1.0) or t < 0.002:
		return lerpf(t, target, smooth_factor(rate_out, delta))
	return t


## Starts the finisher / death shot around `victim`. Does nothing under reduced motion (`scale` 0).
func start_finale(attacker_pos: Vector3, victim: Node3D, hit_pos: Vector3, scale: float, head: Node3D = null) -> void:
	if scale <= 0.0 or not is_instance_valid(victim) or not is_finite_v3(attacker_pos) or not is_finite_v3(victim.global_position):
		return
	_finale_victim = victim
	_finale_scale = scale
	_victim_owner = null
	var n: Node = victim
	for _i: int in 3:
		if n == null:
			break
		if n.has_method("is_limb_cut"):
			_victim_owner = n
			break
		n = n.get_parent()
	finale_head = head
	finale_head_free = false
	_head_seen = false
	finale.start(limit_coord(attacker_pos), limit_coord(victim.global_position), limit_coord(hit_pos), Tuning.shared(),
			arena_radius, WALL_MARGIN)


## Jump straight to the framed pose on the next update.
func snap() -> void:
	_primed = false
	_squeeze_t = 0.0
	_prime_wait = 0
	finale.clear()
	_finale_victim = null
	_victim_owner = null
	_head_seen = false
	_side_sign = 0.0
	_swing_rot = 0.0
	_side_have = false
	finale_head = null
	finale_head_free = false
	_fov_extra = 0.0
	shake.clear()
	if _base_fov > 0.0:
		fov = _base_fov
	update_camera(0.0)


## Like snap(), but waits `ticks` physics ticks first so freshly placed ragdolls have settled into their first pose.
func snap_after_ticks(ticks: int) -> void:
	snap()
	_prime_wait = maxi(ticks, 0)


func _physics_process(_delta: float) -> void:
	if _prime_wait > 0:
		_prime_wait -= 1


## Real (unscaled) seconds for a frame `delta` that ran under `time_scale`: the camera's kick spring, zoom, shake and
## finale timings must not stretch in the end-of-match slow motion.
static func real_delta(delta: float, time_scale: float) -> float:
	if not is_finite(delta) or not is_finite(time_scale):
		return 0.0
	return delta / clampf(time_scale, 0.05, 1.0) if time_scale < 1.0 else delta


## Real seconds for this frame's `delta`. Godot scaled the delta by the speed in force when the frame started, which
## is the one seen last frame, not `scale_now`: dividing by the new speed made the camera's kick, shake, zoom and
## finale timing jump 5x on the first slow-motion frame and run 5x short on the first full-speed one.
func real_frame_delta(delta: float, scale_now: float) -> float:
	var d: float = real_delta(delta, _frame_scale)
	if is_finite(scale_now):
		_frame_scale = scale_now
	return d


func _process(delta: float) -> void:
	update_camera(real_frame_delta(delta, Engine.time_scale))


func update_camera(delta: float) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree() or not is_inside_tree():
		return
	if not is_finite(delta):
		delta = 0.0
	if _prime_wait > 0:
		return
	var me: Vector3 = target.global_position
	var opp: Vector3 = me + Vector3(0.0, 0.0, -3.0)
	if is_instance_valid(look_at_node) and look_at_node.is_inside_tree():
		opp = look_at_node.global_position
	# A pelvis that went NaN/inf keeps the last good framing; a flung one is limited to a box around the arena.
	if not is_finite_v3(me) or not is_finite_v3(opp):
		if not _have_last:
			return
		me = _last_me
		opp = _last_opp
	me = limit_coord(me)
	opp = limit_coord(opp)
	_last_me = me
	_last_opp = opp
	_have_last = true
	var tun: Tuning = Tuning.shared()
	if _base_fov <= 0.0:
		_base_fov = fov
	var aspect: float = 16.0 / 9.0
	if get_viewport() != null:
		var vs: Vector2 = get_viewport().get_visible_rect().size
		if vs.y > 1.0:
			aspect = vs.x / vs.y
	if aspect_override > 0.0:
		aspect = aspect_override
	var lens: float = lens_for_aspect(_base_fov, aspect, tuned(tun, "feel_cam_min_hfov", 50.0), 25.0)
	var lim: float = arena_radius - WALL_MARGIN
	var hfov: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(lens) * 0.5) * aspect))
	var fit_fov: float = minf(lens, hfov)  ## the narrower of the two views: what a side-on shot must fit both fighters in
	var pose: Dictionary
	match mode:
		"orbit":
			orbit_yaw += orbit_speed * delta
			var sep_o: float = Vector2(me.x - opp.x, me.z - opp.z).length()
			pose = orbit_pose((me + opp) * 0.5 + Vector3(0, 1.1, 0), orbit_yaw, 0.28, wide_distance(sep_o, fit_fov, 5.0))
		"wide":
			# The side the camera is already on (no cut across the fighters); turned inward at the wall.
			var sgn: float = pick_side(me, opp, fit_fov, 6.0, lim, _base_pos, _primed)
			pose = side_pose(me, opp, fit_fov, WIDE_HEIGHT, 6.0, lim, sgn, _side_prev, _side_have and _primed)
			_side_prev = pose["pos"]
			_side_have = true
		_:
			var sep_f: float = Vector2(me.x - opp.x, me.z - opp.z).length()
			var close: float = close_blend(sep_f, tun.feel_close_near, tun.feel_close_far)
			pose = follow_pose(me, opp, follow_distance, follow_height, shoulder, close, tun.feel_close_shoulder, tun.feel_close_height)
	var pts: Array = frame_points(me) + frame_points(opp)
	var cut: bool = false  ## the framing changed sides: cut to it rather than sweep across
	var look_pt: Vector3 = pose["look"]
	var raw_pos: Vector3 = pose["pos"]
	# Keep both fighters on screen: pull back along the view line, then widen the lens if the wall stops the camera.
	var pull: float = pull_back_for(raw_pos, look_pt, lens, aspect, pts, tun.feel_frame_margin, tun.feel_frame_pull_max)
	var away: Vector3 = (raw_pos - look_pt).normalized() if raw_pos.distance_to(look_pt) > 0.001 else Vector3.ZERO
	var want_pos: Vector3 = clamp_to_arena(raw_pos + away * pull, arena_radius, WALL_MARGIN, 0.5)
	var want_look: Vector3 = look_pt
	if mode == "follow":
		# Backed against the wall: swing round the look point to the nearest angle that fits inside it, after first
		# allowing the camera SQUEEZE_FREE_M closer. Continuous, so it never sweeps through the fighters; it turns back
		# at most SQUEEZE_UNWIND_RAD_S and cuts back when it falls SQUEEZE_UNWIND_CUT_RAD behind.
		var free_pos: Vector3 = raw_pos + away * pull
		var sw: Dictionary = swing_inside(free_pos, look_pt, lim, SQUEEZE_FREE_M, SQUEEZE_FULL_M, _side_sign if _primed else 0.0,
				1.75, _swing_rot if _primed else 0.0, SQUEEZE_UNWIND_RAD_S * delta, SQUEEZE_UNWIND_CUT_RAD)
		var swung: Vector3 = sw["pos"]
		_squeeze_t = float(sw["amount"])
		_side_sign = float(sw["sign"])
		_swing_rot = float(sw["rot"])
		cut = bool(sw["cut"])
		want_pos = clamp_to_arena(swung, arena_radius, WALL_MARGIN, 0.5)
	# A beheading after the finale began (or after it ended): the shot re-aims on the head (FinaleShot.head_free).
	if not finale_head_free and is_instance_valid(_victim_owner) and bool(_victim_owner.call("is_limb_cut", "head")):
		finale_head_free = true
	if finale_head_free and not _head_seen and _finale_scale > 0.0 and is_instance_valid(_finale_victim):
		_head_seen = true
		var vp0: Vector3 = _finale_victim.global_position
		if is_finite_v3(vp0):
			finale.head_free(limit_coord(vp0))
	var fin_w: float = 0.0
	if finale.active:
		var vp: Vector3 = me
		if is_instance_valid(_finale_victim) and _finale_victim.is_inside_tree() and is_finite_v3(_finale_victim.global_position):
			vp = limit_coord(_finale_victim.global_position)
		var hp: Vector3 = FinaleShot.NO_HEAD
		if finale_head_free and is_instance_valid(finale_head) and finale_head.is_inside_tree() and is_finite_v3(finale_head.global_position):
			hp = limit_coord(finale_head.global_position)
		finale.update(delta, vp, hp)
		fin_w = finale.weight
		if finale.active and fin_w > 0.0:
			var f_look: Vector3 = finale.look()
			var f_raw: Vector3 = finale.pos()
			var f_pts: Array = frame_points(vp) + [f_look]
			if finale.has_head():
				f_pts.append(finale.head_point())
			var f_pull: float = pull_back_for(f_raw, f_look, lens, aspect, f_pts, tun.feel_frame_margin, tun.feel_frame_pull_max)
			var f_away: Vector3 = (f_raw - f_look).normalized()
			var f_pos: Vector3 = clamp_to_arena(f_raw + f_away * f_pull, arena_radius, WALL_MARGIN, 0.4)
			want_pos = want_pos.lerp(f_pos, fin_w)
			want_look = want_look.lerp(f_look, fin_w)
	dbg_want_pos = want_pos
	dbg_want_look = want_look
	var ratio: float = frame_ratio(want_pos, want_look, lens, aspect, pts)
	var want_extra: float = (fov_to_fit(ratio, lens, tun.feel_frame_margin, FOV_EXTRA_MAX) - _base_fov) * (1.0 - fin_w) \
			+ (lens - _base_fov) * fin_w
	if cut:
		cuts += 1
	if not _primed or cut:
		_base_pos = want_pos
		_look_point = want_look
		_fov_extra = want_extra
		_vel_pos = Vector3.ZERO
		_vel_look = Vector3.ZERO
		_primed = true
	else:
		# Lead: move with the wanted pose's own velocity, then close the remaining gap at follow_rate. Without it a
		# fighter moving at v is trailed by v / follow_rate metres.
		var l_rate: float = tuned(tun, "feel_cam_lead_rate", 8.0)
		var l_max: float = tuned(tun, "feel_cam_lead_max", 9.0)
		var l_cut: float = tuned(tun, "feel_cam_cut_m", 0.3)
		_vel_pos = step_lead(_vel_pos, _prev_want_pos, want_pos, delta, l_rate, l_max, l_cut)
		_vel_look = step_lead(_vel_look, _prev_want_look, want_look, delta, l_rate, l_max, l_cut)
		var k: float = smooth_factor(follow_rate, delta)
		_base_pos = (_base_pos + _vel_pos * delta).lerp(want_pos, k)
		_look_point = (_look_point + _vel_look * delta).lerp(want_look, smooth_factor(follow_rate * 1.5, delta))
		_base_pos = clamp_to_arena(_base_pos, arena_radius, WALL_MARGIN, 0.4)
		_fov_extra = lerpf(_fov_extra, want_extra, k)
	_prev_want_pos = want_pos
	_prev_want_look = want_look
	var fx: Dictionary = shake.update(delta)
	if not is_finite_v3(_base_pos) or not is_finite_v3(_look_point) or not is_finite(_fov_extra):
		_primed = false  # state poisoned: re-prime from the next good pose instead of keeping NaN for ever
		return
	global_position = _base_pos + (fx["offset"] as Vector3)
	if global_position.distance_to(_look_point) > 0.05:
		look_at(_look_point, Vector3.UP)
	global_position += global_transform.basis * (fx["jitter"] as Vector3)
	global_position = clamp_to_arena(global_position, arena_radius, WALL_MARGIN, 0.3)  # shake never pokes through the wall
	if absf(float(fx["roll"])) > 0.00001:
		rotate_object_local(Vector3(0.0, 0.0, 1.0), float(fx["roll"]))
	fov = clampf(_base_fov + _fov_extra - float(fx["fov"]), 20.0, 120.0)
