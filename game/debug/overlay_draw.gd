class_name OverlayDraw
extends RefCounted
## Colour, fade, geometry and text math for FightOverlay. Pure: no Node, no clock. Ages come in as seconds, worked
## out from physics frames by the caller, so a frozen fight keeps its markers still. Shapes come back as line
## segments (pairs of points) so the overlay draws everything in one ImmediateMesh surface.

const TRAIL_LIFE_S: float = 0.5
const CONTACT_LIFE_S: float = 0.6
const KNOCK_LIFE_S: float = 0.6
const KNOCK_M_PER_UNIT: float = 0.1
const KNOCK_MIN_M: float = 0.15
const KNOCK_MAX_M: float = 0.9
const KNOCK_HEAD_MAX_M: float = 0.2
const BLINK_HZ: float = 10.0
const BLINK_DIM: float = 0.35
const CONTACT_MARK_M: float = 0.09
const HAND_MARK_M: float = 0.06
const DIM_ALPHA: float = 0.35

const EDGE_COLOR := Color(1.0, 0.5, 0.1)
const POINT_COLOR := Color(1.0, 0.25, 0.85)
const FLAT_COLOR := Color(0.35, 0.75, 1.0)
const BLUNT_COLOR := Color(1.0, 0.92, 0.3)
const OTHER_COLOR := Color(0.85, 0.85, 0.85)
const TARGET_COLOR := Color(0.3, 0.95, 1.0)
const HAND_COLOR := Color(1.0, 1.0, 1.0)
const GAP_COLOR := Color(1.0, 1.0, 1.0, DIM_ALPHA)
const GUARD_COLOR := Color(0.85, 0.6, 1.0, 0.6)
const KNOCK_COLOR := Color(0.62, 1.0, 0.5)

## Tip speed (m/s) -> colour, piecewise linear. Deliberately never pure green.
const SPEED_STOPS: Array = [
	[0.0, Color(0.3, 0.35, 0.95)],
	[2.0, Color(0.2, 0.85, 0.95)],
	[6.0, Color(1.0, 0.9, 0.2)],
	[12.0, Color(1.0, 0.25, 0.1)],
]


## Trail colour for a tip moving at `speed` m/s.
static func speed_color(speed: float) -> Color:
	var s: float = maxf(speed, 0.0)
	var last: int = SPEED_STOPS.size() - 1
	for i: int in range(1, SPEED_STOPS.size()):
		var hi: float = float(SPEED_STOPS[i][0])
		if s <= hi or i == last:
			var lo: float = float(SPEED_STOPS[i - 1][0])
			var t: float = clampf((s - lo) / maxf(hi - lo, 0.0001), 0.0, 1.0)
			return (SPEED_STOPS[i - 1][1] as Color).lerp(SPEED_STOPS[i][1] as Color, t)
	return OTHER_COLOR


## Contact marker colour for a `contact` kind from the hit event (edge, point, flat, blunt).
static func contact_color(kind: String) -> Color:
	match kind:
		"edge":
			return EDGE_COLOR
		"point":
			return POINT_COLOR
		"flat":
			return FLAT_COLOR
		"blunt":
			return BLUNT_COLOR
		_:
			return OTHER_COLOR


## Seconds between two physics frame counts.
static func age_s(now_frame: int, then_frame: int, ticks_per_s: float) -> float:
	return float(now_frame - then_frame) / maxf(ticks_per_s, 1.0)


## 1 at age 0, falling linearly to 0 at `life_s`, clamped.
static func fade(age: float, life_s: float) -> float:
	if life_s <= 0.0:
		return 0.0
	return clampf(1.0 - age / life_s, 0.0, 1.0)


## Contact flash: fades like `fade`, and blinks at BLINK_HZ (dimmed on every other blink).
static func flash_alpha(age: float, life_s: float) -> float:
	var blink: float = 1.0 if int(floor(maxf(age, 0.0) * BLINK_HZ)) % 2 == 0 else BLINK_DIM
	return fade(age, life_s) * blink


## Arrow length in metres for a knockback impulse of `magnitude` (display scale, not the physical distance).
static func knock_length(magnitude: float) -> float:
	if magnitude <= 0.0:
		return 0.0
	return clampf(magnitude * KNOCK_M_PER_UNIT, KNOCK_MIN_M, KNOCK_MAX_M)


## Three world-axis crosses centred on `center`, `half` long each way: 6 points, 3 segments.
static func cross(center: Vector3, half: float) -> PackedVector3Array:
	var x := Vector3(half, 0.0, 0.0)
	var y := Vector3(0.0, half, 0.0)
	var z := Vector3(0.0, 0.0, half)
	return PackedVector3Array([center - x, center + x, center - y, center + y, center - z, center + z])


## An arrow from `from` along `vec`: shaft plus two head wings, 6 points, 3 segments. Empty for a zero vector.
static func arrow(from: Vector3, vec: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var length: float = vec.length()
	if length < 0.0001:
		return out
	var dir: Vector3 = vec / length
	var tip: Vector3 = from + vec
	var head: float = minf(KNOCK_HEAD_MAX_M, length * 0.35)
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized() * head * 0.5
	var back: Vector3 = tip - dir * head
	out.append(from)
	out.append(tip)
	out.append(tip)
	out.append(back + side)
	out.append(tip)
	out.append(back - side)
	return out


## The guard plane rectangle: centre `origin`, spanning `right` and `up` by half sizes `half_w`, `half_h`.
## 8 points, 4 segments.
static func guard_corners(origin: Vector3, right: Vector3, up: Vector3, half_w: float, half_h: float) -> PackedVector3Array:
	var a: Vector3 = origin - right * half_w - up * half_h
	var b: Vector3 = origin + right * half_w - up * half_h
	var c: Vector3 = origin + right * half_w + up * half_h
	var d: Vector3 = origin - right * half_w + up * half_h
	return PackedVector3Array([a, b, b, c, c, d, d, a])


## Tip trail: one segment per pair of consecutive samples, coloured by the later sample's speed and faded by its
## age. Returns {"segs": PackedVector3Array, "cols": PackedColorArray}.
static func trail(points: PackedVector3Array, speeds: PackedFloat32Array, ages: PackedFloat32Array) -> Dictionary:
	var segs := PackedVector3Array()
	var cols := PackedColorArray()
	var n: int = mini(points.size(), mini(speeds.size(), ages.size()))
	for i: int in range(1, n):
		var c: Color = speed_color(speeds[i])
		c.a = fade(ages[i], TRAIL_LIFE_S)
		segs.append(points[i - 1])
		segs.append(points[i])
		cols.append(c)
		cols.append(c)
	return {"segs": segs, "cols": cols}


## One colour for every point of a shape.
static func paint(segs: PackedVector3Array, col: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(segs.size())
	out.fill(col)
	return out


## Writes segments and colours into `im` as one line surface. Clears the mesh first; draws nothing when empty.
static func emit(im: ImmediateMesh, mat: Material, segs: PackedVector3Array, cols: PackedColorArray) -> void:
	im.clear_surfaces()
	if segs.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i: int in segs.size():
		im.surface_set_color(cols[i])
		im.surface_add_vertex(segs[i])
	im.surface_end()


## Text block for one fighter. `d` is Fighter.debug_frame(); `brain_state` is FighterBrain.state_name() or "".
static func format_fighter(d: Dictionary, brain_state: String) -> String:
	var side: int = int(d.get("side", 0)) + 1
	var head: String = "P%d  %s" % [side, str(d.get("state", "?"))]
	if brain_state != "":
		head += "  brain %s" % brain_state
	var target: Vector3 = d.get("hand_target", Vector3.ZERO)
	var hand: Vector3 = d.get("hand_pos", Vector3.ZERO)
	var lines: PackedStringArray = [
		head,
		"balance %.2f  stamina %.2f" % [float(d.get("balance", 0.0)), float(d.get("stamina", 0.0))],
		"consciousness %.2f  blood %.2f" % [float(d.get("consciousness", 0.0)), float(d.get("blood_frac", 0.0))],
		"tip %.1f m/s  %s  grip %s" % [float(d.get("tip_speed", 0.0)), str(d.get("weapon_id", "?")),
			str(d.get("grip", "?"))],
		"hand gap %.2f m" % (target - hand).length(),
	]
	return "\n".join(lines)


## Status line for the top of the screen.
static func format_status(slowmo: bool, frozen: bool) -> String:
	return "F1 overlay  F2 slow-mo %s  F3 freeze %s  . step" % [
		"0.25x" if slowmo else "off", "on" if frozen else "off"]


## Engine.time_scale for the slow-motion toggle.
static func time_scale_for(slowmo: bool) -> float:
	return 0.25 if slowmo else 1.0
