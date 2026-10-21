class_name FightCamera
extends Camera3D
## Third-person fight camera. `target` is the fighter we look over the shoulder of, `look_at_node` the opponent.
## Modes: "follow" (over the shoulder), "orbit" (slow turn around the pair), "wide" (side-on, frames both).
## All framing maths is in static functions so it can be unit tested.

const FOV_EXTRA_MAX: float = 18.0  ## most the lens widens to keep both fighters framed, degrees
const WALL_MARGIN: float = 0.7  ## how far inside the wall the camera stays
const SQUEEZE_FREE_M: float = 0.8  ## wall push-in the follow shot tolerates before it moves aside
const SQUEEZE_FULL_M: float = 2.0  ## further push-in over which it blends fully into the side-on shot
const MODES: PackedStringArray = ["follow", "orbit", "wide"]

var target: Node3D
var look_at_node: Node3D
var mode: String = "follow"
var arena_radius: float = 11.0
var follow_distance: float = 3.4
var follow_height: float = 1.9
var shoulder: float = 0.7
var follow_rate: float = 5.0
var orbit_yaw: float = 0.0
var orbit_speed: float = 0.3

## Impact state (kick, shake, zoom punch). The presenter feeds it through `hit_impact`.
var shake: CameraShake = CameraShake.new()

var _look_point: Vector3 = Vector3.ZERO
var _base_pos: Vector3 = Vector3.ZERO
var _primed: bool = false
var _base_fov: float = 0.0
var _fov_extra: float = 0.0


## Unit vector on the ground from a to b. Falls back to -Z when they coincide.
static func flat_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() < 0.001:
		return Vector3(0.0, 0.0, -1.0)
	return d.normalized()


## Frame-rate independent blend factor for exponential smoothing at `rate` per second.
static func smooth_factor(rate: float, delta: float) -> float:
	return 1.0 - exp(-maxf(rate, 0.0) * maxf(delta, 0.0))


## Over-the-shoulder pose: behind and above `me`, shifted to the right shoulder, looking at a point between us
## that leans toward the opponent. Returns {"pos": Vector3, "look": Vector3}.
static func follow_pose(me: Vector3, opp: Vector3, distance: float, height: float, shoulder_off: float) -> Dictionary:
	var f: Vector3 = flat_dir(me, opp)
	var right: Vector3 = f.cross(Vector3.UP)
	var pos: Vector3 = me - f * distance + right * shoulder_off + Vector3(0.0, height, 0.0)
	var look: Vector3 = me.lerp(opp, 0.6) + Vector3(0.0, 1.3, 0.0)
	return {"pos": pos, "look": look}


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
	return {"pos": pos, "look": mid + Vector3(0.0, 1.0, 0.0)}


## Distance at which two points `sep` apart fit within the horizontal field of view (with margin).
static func wide_distance(sep: float, fov_deg: float, min_distance: float) -> float:
	var half: float = tan(deg_to_rad(fov_deg) * 0.5)
	return maxf(min_distance, (sep * 0.5 + 1.6) / maxf(half, 0.1))


## Camera orbiting `center` at yaw/pitch (radians) and `distance`. Yaw 0 puts the camera on +Z.
static func orbit_pose(center: Vector3, yaw: float, pitch: float, distance: float) -> Dictionary:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return {"pos": center + dir * distance, "look": center}


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
		worst = maxf(worst, maxf(absf(v.dot(right)) / (z * th), absf(v.dot(up)) / (z * tv)))
	return worst


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
	return minf(pull, max_pull)


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


## Jump straight to the framed pose on the next update.
func snap() -> void:
	_primed = false
	_fov_extra = 0.0
	shake.clear()
	if _base_fov > 0.0:
		fov = _base_fov
	update_camera(0.0)


func _process(delta: float) -> void:
	update_camera(delta)


func update_camera(delta: float) -> void:
	if target == null or not is_inside_tree():
		return
	var me: Vector3 = target.global_position
	var opp: Vector3 = look_at_node.global_position if look_at_node != null else me + Vector3(0.0, 0.0, -3.0)
	var pose: Dictionary
	match mode:
		"orbit":
			orbit_yaw += orbit_speed * delta
			var sep_o: float = Vector2(me.x - opp.x, me.z - opp.z).length()
			pose = orbit_pose((me + opp) * 0.5 + Vector3(0, 1.1, 0), orbit_yaw, 0.28, wide_distance(sep_o, fov, 5.0))
		"wide":
			pose = wide_pose(me, opp, fov, 3.2, 6.0, arena_radius - WALL_MARGIN)
		_:
			pose = follow_pose(me, opp, follow_distance, follow_height, shoulder)
	var tun: Tuning = Tuning.shared()
	if _base_fov <= 0.0:
		_base_fov = fov
	var aspect: float = 16.0 / 9.0
	if get_viewport() != null:
		var vs: Vector2 = get_viewport().get_visible_rect().size
		if vs.y > 1.0:
			aspect = vs.x / vs.y
	var pts: Array = frame_points(me) + frame_points(opp)
	var look_pt: Vector3 = pose["look"]
	var raw_pos: Vector3 = pose["pos"]
	# Keep both fighters on screen: pull back along the view line, then widen the lens if the wall stops the camera.
	var pull: float = pull_back_for(raw_pos, look_pt, _base_fov, aspect, pts, tun.feel_frame_margin, tun.feel_frame_pull_max)
	var away: Vector3 = (raw_pos - look_pt).normalized() if raw_pos.distance_to(look_pt) > 0.001 else Vector3.ZERO
	var want_pos: Vector3 = clamp_to_arena(raw_pos + away * pull, arena_radius, WALL_MARGIN, 0.5)
	var want_look: Vector3 = look_pt
	if mode == "follow":
		# Squeezed against the wall behind the fighter: slide toward a side-on shot from the inner side.
		var squeeze: float = want_pos.distance_to(raw_pos + away * pull)
		if squeeze > SQUEEZE_FREE_M:
			var alt: Dictionary = wide_pose(me, opp, _base_fov, 3.2, 6.0, arena_radius - WALL_MARGIN)
			var t: float = clampf((squeeze - SQUEEZE_FREE_M) / SQUEEZE_FULL_M, 0.0, 1.0)
			want_pos = want_pos.lerp(clamp_to_arena(alt["pos"], arena_radius, WALL_MARGIN, 0.5), t)
			want_look = want_look.lerp(alt["look"], t)
	var ratio: float = frame_ratio(want_pos, want_look, _base_fov, aspect, pts)
	var want_extra: float = fov_to_fit(ratio, _base_fov, tun.feel_frame_margin, FOV_EXTRA_MAX) - _base_fov
	if not _primed:
		_base_pos = want_pos
		_look_point = want_look
		_fov_extra = want_extra
		_primed = true
	else:
		var k: float = smooth_factor(follow_rate, delta)
		_base_pos = _base_pos.lerp(want_pos, k)
		_look_point = _look_point.lerp(want_look, smooth_factor(follow_rate * 1.5, delta))
		_fov_extra = lerpf(_fov_extra, want_extra, k)
	var fx: Dictionary = shake.update(delta)
	global_position = _base_pos + (fx["offset"] as Vector3)
	if global_position.distance_to(_look_point) > 0.05:
		look_at(_look_point, Vector3.UP)
	global_position += global_transform.basis * (fx["jitter"] as Vector3)
	if absf(float(fx["roll"])) > 0.00001:
		rotate_object_local(Vector3(0.0, 0.0, 1.0), float(fx["roll"]))
	fov = clampf(_base_fov + _fov_extra - float(fx["fov"]), 20.0, 120.0)
