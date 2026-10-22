class_name ReplayRing
extends RefCounted
## Ring buffer of the last few seconds of a fight as it was shown: one frame per physics tick holding every tracked
## body's pose (position + rotation quaternion, 7 floats per body), plus the tick-stamped hit and gore events of the
## same span. Presentation only: it is what the instant replay (KillCam) plays back kinematically, so it never feeds
## the simulation. Ticks are consecutive; a gap (or a tick going back) starts the buffer over.
## A body that did not exist yet, or was gone, on a tick has a NaN x (see `has_pose`).

const STRIDE: int = 7

var capacity: int = 600
var events: Array = []  ## [tick, side, kind ("hit"|"gore"), event Dictionary, blood rng state], oldest first

var _frames: Array[PackedFloat32Array] = []
var _ticks: PackedInt32Array = PackedInt32Array()
var _head: int = 0  ## next slot to write
var _count: int = 0
var _newest: int = -1


func _init(p_capacity: int = 600) -> void:
	capacity = maxi(p_capacity, 2)


func clear() -> void:
	_frames.clear()
	_ticks = PackedInt32Array()
	_head = 0
	_count = 0
	_newest = -1
	events.clear()


func size() -> int:
	return _count


func newest_tick() -> int:
	return _newest if _count > 0 else -1


func oldest_tick() -> int:
	return _newest - _count + 1 if _count > 0 else -1


## Stores the frame of `tick`. A tick that does not follow the newest one clears the buffer first.
func push(tick: int, frame: PackedFloat32Array) -> void:
	if _count > 0 and tick != _newest + 1:
		clear()
	if _frames.size() < capacity:
		_frames.append(frame)
		_ticks.append(tick)
	else:
		_frames[_head] = frame
		_ticks[_head] = tick
	_head = (_head + 1) % capacity
	_count = mini(_count + 1, capacity)
	_newest = tick
	var oldest: int = oldest_tick()
	var drop: int = 0
	while drop < events.size() and int((events[drop] as Array)[0]) < oldest:
		drop += 1
	if drop > 0:
		events = events.slice(drop)


func has_tick(tick: int) -> bool:
	return _count > 0 and tick >= oldest_tick() and tick <= _newest


## The frame of `tick` (clamped into the stored span); empty when nothing is stored.
func frame(tick: int) -> PackedFloat32Array:
	if _count == 0:
		return PackedFloat32Array()
	var t: int = clampi(tick, oldest_tick(), _newest)
	var newest_slot: int = (_head - 1 + capacity) % capacity
	var slot: int = (newest_slot - (_newest - t) + capacity * 2) % capacity
	return _frames[slot]


func push_event(tick: int, side: int, kind: String, ev: Dictionary, rng_state: int) -> void:
	events.append([tick, side, kind, ev, rng_state])


## Events with a <= tick <= b, oldest first.
func events_in(a: int, b: int) -> Array:
	var out: Array = []
	for e: Variant in events:
		var t: int = int((e as Array)[0])
		if t >= a and t <= b:
			out.append(e)
	return out


## Bytes held by the pose frames (the float payload; Godot's per-array header is about 40 bytes more each).
func frame_bytes() -> int:
	var n: int = 0
	for f: PackedFloat32Array in _frames:
		n += f.size() * 4
	return n


## Pose interpolated between the frames around fractional tick `pos`; Transform3D() with `ok` false when absent.
func sample(pos: float, i: int) -> Dictionary:
	var a: int = floori(pos)
	var fa: PackedFloat32Array = frame(a)
	var fb: PackedFloat32Array = frame(a + 1)
	return blend(fa, fb, i, clampf(pos - float(a), 0.0, 1.0))


# ---------------------------------------------------------------- pure helpers (static)

## Writes body `i`'s pose into `frame` (growing it, gaps filled as absent).
static func write_pose(frame: PackedFloat32Array, i: int, xf: Transform3D) -> void:
	_grow(frame, i)
	var q: Quaternion = xf.basis.get_rotation_quaternion()
	var o: int = i * STRIDE
	frame[o] = xf.origin.x
	frame[o + 1] = xf.origin.y
	frame[o + 2] = xf.origin.z
	frame[o + 3] = q.x
	frame[o + 4] = q.y
	frame[o + 5] = q.z
	frame[o + 6] = q.w


## Marks body `i` absent in `frame`.
static func write_absent(frame: PackedFloat32Array, i: int) -> void:
	_grow(frame, i)
	frame[i * STRIDE] = NAN


static func _grow(frame: PackedFloat32Array, i: int) -> void:
	var need: int = (i + 1) * STRIDE
	if frame.size() < need:
		var old: int = frame.size()
		frame.resize(need)
		for k: int in range(old, need, STRIDE):
			frame[k] = NAN


static func has_pose(frame: PackedFloat32Array, i: int) -> bool:
	return i >= 0 and (i + 1) * STRIDE <= frame.size() and is_finite(frame[i * STRIDE])


static func pose(frame: PackedFloat32Array, i: int) -> Transform3D:
	var o: int = i * STRIDE
	var q := Quaternion(frame[o + 3], frame[o + 4], frame[o + 5], frame[o + 6])
	if q.length_squared() < 0.0001:
		q = Quaternion.IDENTITY
	return Transform3D(Basis(q.normalized()), Vector3(frame[o], frame[o + 1], frame[o + 2]))


## {ok, xf}: body `i` between two frames at `t` (0..1): positions lerp, rotations slerp; one side absent uses the other.
static func blend(fa: PackedFloat32Array, fb: PackedFloat32Array, i: int, t: float) -> Dictionary:
	var ha: bool = has_pose(fa, i)
	var hb: bool = has_pose(fb, i)
	if not ha and not hb:
		return {"ok": false, "xf": Transform3D()}
	if not hb or t <= 0.0:
		return {"ok": ha, "xf": pose(fa, i) if ha else pose(fb, i)}
	if not ha or t >= 1.0:
		return {"ok": true, "xf": pose(fb, i)}
	var a: Transform3D = pose(fa, i)
	var b: Transform3D = pose(fb, i)
	var q: Quaternion = a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)
	return {"ok": true, "xf": Transform3D(Basis(q), a.origin.lerp(b.origin, t))}
