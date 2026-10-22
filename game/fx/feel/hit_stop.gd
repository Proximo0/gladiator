class_name HitStop
extends Node
## Hit-stop on screen without touching physics: while HitStopLogic holds, the fighters' meshes (every visual child of
## their bodies and weapons) are drawn at a pose from a short history, `lag` seconds behind physics, then catch up.
## The bodies themselves are never moved. Every physics tick starts by putting the visual children back at their
## rest transforms (this node's physics priority runs before everything else), so game code that reads a mesh's
## transform during the tick sees the true pose; `_process` re-applies the lagged pose for drawing. Costs nothing
## while idle. Owned by FeelDirector.

const RESTORE_PRIORITY: int = -1000
const DRAW_PRIORITY: int = 1000  ## after anything that moves bodies in _process (online client smoothing)
const MAX_SAMPLES: int = 96

var logic: HitStopLogic = HitStopLogic.new()
var enabled: bool = true
var applied_frames: int = 0  ## frames drawn off physics (for sims and the perf probe)
var max_shift: float = 0.0  ## largest distance between a drawn body and its physics body, m
var last_rate: float = 1.0

var _fighters: Array = []
var _bodies: Array[Node3D] = []
var _times: PackedFloat64Array = PackedFloat64Array()
var _xfs: Array = []  ## per body: Array of Transform3D, aligned with _times
var _now: float = 0.0
var _rest: Dictionary = {}  ## instance id -> [Node3D, Transform3D rest local]
var _applied: bool = false
var _fresh_rest: bool = true  ## a physics tick restored the rest pose since the last draw


var _clock_real: RealClock = RealClock.new()

func _init() -> void:
	process_physics_priority = RESTORE_PRIORITY
	process_priority = DRAW_PRIORITY


## Tracks a fresh pair of fighters (Nodes whose RigidBody3D descendants are drawn lagged).
func bind(fighters: Array) -> void:
	clear()
	_fighters = fighters.duplicate()


## Puts everything back on physics at once and forgets the history.
func clear() -> void:
	_restore()
	_rest.clear()
	_bodies.clear()
	_xfs.clear()
	_times.resize(0)
	logic.reset()


## A resolved hit of impact `imp`. Returns the hold it started, real s (0 for none).
func on_hit(ev: Dictionary, imp: float) -> float:
	if not enabled:
		return 0.0
	var was: bool = logic.active()
	var held: float = logic.request(ev, imp, Tuning.shared())
	if held > 0.0 and not was:
		_begin()
	return held


func lag() -> float:
	return logic.lag


func _begin() -> void:
	_restore()
	_rest.clear()
	_bodies.clear()
	_xfs.clear()
	_times.resize(0)
	for f: Variant in _fighters:
		if is_instance_valid(f):
			_collect(f as Node)
	for b: Node3D in _bodies:
		_xfs.append([b.global_transform])
	_times.append(_now)


func _collect(n: Node) -> void:
	for c: Node in n.get_children():
		if c is RigidBody3D:
			_bodies.append(c as Node3D)
		elif not (c is CollisionObject3D):
			_collect(c)


func _physics_process(_delta: float) -> void:
	_restore()


func _restore() -> void:
	if not _applied:
		return
	for id: Variant in _rest:
		var e: Array = _rest[id]
		if is_instance_valid(e[0]):
			(e[0] as Node3D).transform = e[1]
	_applied = false
	_fresh_rest = true


func _process(delta: float) -> void:
	var real: float = _clock_real.step(delta, Engine.time_scale)
	_now += real
	if not logic.active():
		last_rate = 1.0
		if _applied:
			_restore()
			_rest.clear()
		return
	last_rate = logic.step(real, Tuning.shared())
	_sample()
	if not logic.active():
		_restore()
		_rest.clear()  # the next stop re-reads rest poses: game code may move these nodes between stops
		_bodies.clear()
		_xfs.clear()
		_times.resize(0)
		return
	_apply(_now - logic.lag)


func _sample() -> void:
	if _times.size() >= MAX_SAMPLES:
		_times.remove_at(0)
		for h: Variant in _xfs:
			(h as Array).remove_at(0)
	_times.append(_now)
	for i: int in _bodies.size():
		var b: Node3D = _bodies[i]
		var h: Array = _xfs[i]
		h.append(b.global_transform if is_instance_valid(b) and b.is_inside_tree() else h[h.size() - 1])


## Pose of body `i` at time `t` from its history (the oldest sample before the history starts).
func _pose(i: int, t: float) -> Transform3D:
	var h: Array = _xfs[i]
	var n: int = _times.size()
	if n == 1 or t <= _times[0]:
		return h[0]
	for k: int in range(n - 1):
		if t < _times[k + 1]:
			var span: float = maxf(_times[k + 1] - _times[k], 0.000001)
			return (h[k] as Transform3D).interpolate_with(h[k + 1] as Transform3D, (t - _times[k]) / span)
	return h[n - 1]


func _apply(t: float) -> void:
	# Drop samples older than the one just before `t`.
	var drop: int = 0
	while drop + 1 < _times.size() and _times[drop + 1] <= t:
		drop += 1
	if drop > 0:
		_times = _times.slice(drop)
		for i: int in _xfs.size():
			_xfs[i] = (_xfs[i] as Array).slice(drop)
	for i: int in _bodies.size():
		var b: Node3D = _bodies[i]
		if not is_instance_valid(b) or not b.is_inside_tree():
			continue
		var shown: Transform3D = _pose(i, t)
		var to_local: Transform3D = b.global_transform.affine_inverse() * shown
		max_shift = maxf(max_shift, shown.origin.distance_to(b.global_position))
		for c: Node in b.get_children():
			if not _drawn(c):
				continue
			var id: int = c.get_instance_id()
			var e: Variant = _rest.get(id)
			if e == null:
				e = [c, (c as Node3D).transform]
				_rest[id] = e
			elif _fresh_rest:
				(e as Array)[1] = (c as Node3D).transform  # game code may have moved it since; physics restored it
			(c as Node3D).transform = to_local * ((e as Array)[1] as Transform3D)
	_applied = true
	_fresh_rest = false
	applied_frames += 1


## Visual children only: no shapes, joints, bodies or nodes placed in world space.
static func _drawn(c: Node) -> bool:
	if not (c is Node3D) or c is CollisionShape3D or c is CollisionObject3D or c is Joint3D:
		return false
	return not (c as Node3D).top_level


func _exit_tree() -> void:
	_restore()
