class_name FightCamera
extends Camera3D
## Third-person fight camera. `target` is the fighter we look over the shoulder of, `look_at_node` the opponent.
## Modes: "follow" (over the shoulder), "orbit" (slow turn around the pair), "wide" (side-on, frames both).
## All framing maths is in static functions so it can be unit tested.

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

var _look_point: Vector3 = Vector3.ZERO
var _primed: bool = false


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
static func wide_pose(a: Vector3, b: Vector3, fov_deg: float, height: float, min_distance: float) -> Dictionary:
	var mid: Vector3 = (a + b) * 0.5
	var f: Vector3 = flat_dir(a, b)
	var side: Vector3 = f.cross(Vector3.UP)
	var sep: float = Vector2(a.x - b.x, a.z - b.z).length()
	var pos: Vector3 = mid + side * wide_distance(sep, fov_deg, min_distance) + Vector3(0.0, height, 0.0)
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


func set_mode(new_mode: String) -> void:
	if MODES.has(new_mode):
		mode = new_mode


## Jump straight to the framed pose on the next update.
func snap() -> void:
	_primed = false
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
			pose = wide_pose(me, opp, fov, 3.2, 6.0)
		_:
			pose = follow_pose(me, opp, follow_distance, follow_height, shoulder)
	var want_pos: Vector3 = clamp_to_arena(pose["pos"], arena_radius, 0.7, 0.5)
	var want_look: Vector3 = pose["look"]
	if not _primed:
		global_position = want_pos
		_look_point = want_look
		_primed = true
	else:
		var k: float = smooth_factor(follow_rate, delta)
		global_position = global_position.lerp(want_pos, k)
		_look_point = _look_point.lerp(want_look, smooth_factor(follow_rate * 1.5, delta))
	if global_position.distance_to(_look_point) > 0.05:
		look_at(_look_point, Vector3.UP)
