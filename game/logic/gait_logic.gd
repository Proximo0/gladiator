class_name GaitLogic
extends RefCounted
## Foot planner for the active ragdoll's legs. A planted foot keeps its spot on the sand (its IK target is that world
## point, so it does not slide); the feet take turns stepping to a landing spot ahead of where the hip will be.
## Speed sets the cadence and the stance time: a planted foot stays down only while the hip passes over it by
## `span` (the leg's reach), so a faster fighter spends longer in the air between steps (a jog, then a run) instead of
## swinging the legs faster than the joints can follow. Sideways the feet never cross: a landing is held at least
## `min_gap` from the other foot, so a strafe becomes a lead-step and close-in shuffle. Standing still, a foot only
## steps when it has drifted off its stance spot (after a turn or a shove). No nodes, no clock: `tick` takes delta.
## World frame, Y up. `yb` is the facing basis (forward = -Z, right = +X). Feet are ground points (y = 0); a target's
## y is the swing lift above the ground.
##
## p keys (from Tuning): cadence_base, cadence_per_speed, cadence_lateral (steps/s, per m/s, extra per m/s
## sideways), span, span_lat (m the hip passes over a planted foot at speed, forward and sideways), stance_max (longest stance at a slow walk, s),
## swing_min, swing_max (s), lift (m), shuffle_lift (lift share sideways), reach (a planted foot farther than this from
## its hip steps at once, m), lead_max (max landing lead past the stance spot, m), min_gap (m), idle_err (m),
## min_speed (m/s below which the cadence stops), stance_l, stance_r (Vector3 stance spot of each foot relative to its
## hip in the facing frame).

var plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var air: Array[bool] = [false, false]  ## foot is swinging
var t: Array[float] = [0.0, 0.0]  ## time into the swing
var dur: Array[float] = [0.3, 0.3]
var from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var lift: Array[float] = [0.1, 0.1]
var step_t: float = 0.0  ## time since the last step started
var steps: int = 0  ## landings so far
var last: int = 1  ## foot that stepped last
var settled: Array[float] = [9.0, 9.0]  ## drift each foot was left with by its last corrective step standing still
var ready: bool = false


## Plants both feet at their stance spots under `hips` ([left, right] world positions).
func reset(hips: Array, yb: Basis, p: Dictionary) -> void:
	var feet: Array = []
	for i: int in range(2):
		feet.append((hips[i] as Vector3) + yb * _stance(i, p))
	replant(feet)


## Plants both feet where they are now ([left, right] world points), e.g. after a roll.
func replant(feet: Array) -> void:
	for i: int in range(2):
		plant[i] = _ground(feet[i])
		air[i] = false
		t[i] = 0.0
		settled[i] = 9.0
	step_t = 0.0
	ready = true


## Steps per second for a horizontal velocity `vel` (world) in facing frame `yb`.
static func cadence(vel: Vector3, yb: Basis, p: Dictionary) -> float:
	var lat: float = absf(vel.dot(yb.x))
	var spd: float = Vector2(vel.x, vel.z).length()
	return float(p["cadence_base"]) + float(p["cadence_per_speed"]) * spd + float(p["cadence_lateral"]) * lat


## Stance time (s) of a foot at speed `spd` with step period `period`: the hip passes over the foot by `span`, never
## longer than `stance_max`, and short enough to leave the swing at least `swing_min`.
static func stance_time(spd: float, period: float, p: Dictionary, lat: float = 0.0) -> float:
	var span: float = lerpf(float(p["span"]), float(p["span_lat"]), clampf(lat, 0.0, 1.0))
	var st: float = minf(span / maxf(spd, 0.01), float(p["stance_max"]))
	return clampf(st, 0.05, maxf(2.0 * period - float(p["swing_min"]), 0.05))


## Swing time (s): the rest of the two-step cycle after the stance, within [swing_min, swing_max].
static func swing_time(spd: float, period: float, p: Dictionary, lat: float = 0.0) -> float:
	return clampf(2.0 * period - stance_time(spd, period, p, lat), float(p["swing_min"]), float(p["swing_max"]))


## Advances the planner. `hips` = [left, right] hip world positions, `vel` = intended horizontal velocity (world).
## `active` false lets swings in progress finish but starts no new step. `feet` ([left, right] world points, optional)
## are where the feet really are: a foot plants where it actually came down, so the leg never fights the sand to
## reach a spot it fell short of.
func tick(delta: float, hips: Array, yb: Basis, vel: Vector3, p: Dictionary, active: bool = true, feet: Array = []) -> void:
	if not ready:
		reset(hips, yb, p)
	var v := Vector3(vel.x, 0.0, vel.z)
	var spd: float = v.length()
	var moving: bool = spd >= float(p["min_speed"])
	var period: float = 1.0 / maxf(cadence(v, yb, p), 0.5)
	step_t += delta
	for i: int in range(2):
		if not air[i]:
			continue
		t[i] += delta
		to[i] = _landing(i, hips, yb, v, maxf(dur[i] - t[i], 0.0), period, spd, p)
		if t[i] >= dur[i]:
			plant[i] = _ground(feet[i]) if feet.size() == 2 else to[i]
			air[i] = false
			steps += 1
			if not moving:
				settled[i] = (plant[i] - _ground((hips[i] as Vector3) + yb * _stance(i, p))).length()
	if not active:
		return
	var errs: Array[float] = [0.0, 0.0]
	for i: int in range(2):
		errs[i] = (plant[i] - _ground((hips[i] as Vector3) + yb * _stance(i, p))).length()
	var pick: int = 1 - last
	var go: bool = false
	for i: int in range(2):
		if not air[i] and _ground(plant[i] - (hips[i] as Vector3)).length() > float(p["reach"]):
			pick = i
			go = true
	if not go and moving and step_t >= period:
		go = true
	elif not go and not moving and step_t >= 0.15:
		# Standing still a foot steps back under its hip once it has drifted; a step that falls short is
		# accepted (no fidgeting) until the foot drifts a further idle_err.
		var lim: Array[float] = [0.0, 0.0]
		for i: int in range(2):
			lim[i] = maxf(float(p["idle_err"]), settled[i] + float(p["idle_err"])) if settled[i] < 9.0 else float(p["idle_err"])
		var k: int = 0 if errs[0] - lim[0] >= errs[1] - lim[1] else 1
		if errs[k] > lim[k]:
			go = true
			pick = k
	if moving:
		settled = [9.0, 9.0]
	if go and not air[pick]:
		_start(pick, hips, yb, v, spd, period, p)


func _start(i: int, hips: Array, yb: Basis, v: Vector3, spd: float, period: float, p: Dictionary) -> void:
	air[i] = true
	t[i] = 0.0
	last = i
	step_t = 0.0
	var lat: float = absf(v.dot(yb.x)) / spd if spd > 0.05 else 0.0
	dur[i] = swing_time(spd, period, p, lat) if spd >= float(p["min_speed"]) else float(p["swing_min"]) * 1.4
	from[i] = plant[i]
	to[i] = _landing(i, hips, yb, v, dur[i], period, spd, p)
	var dist: float = (to[i] - from[i]).length()
	lift[i] = float(p["lift"]) * lerpf(1.0, float(p["shuffle_lift"]), lat) * clampf(dist / 0.3, 0.4, 1.0)


## Where foot `i` should land if it touches down in `rest` seconds: the stance spot under the hip then, plus a lead
## of half the coming stance at the current velocity, kept within reach and off the other foot's side.
func _landing(i: int, hips: Array, yb: Basis, v: Vector3, rest: float, period: float, spd: float, p: Dictionary) -> Vector3:
	var hip_then: Vector3 = (hips[i] as Vector3) + v * rest
	var lat: float = absf(v.dot(yb.x)) / spd if spd > 0.05 else 0.0
	var lead: Vector3 = (v * (stance_time(spd, period, p, lat) * 0.5)).limit_length(float(p["lead_max"]))
	var off: Vector3 = yb * _stance(i, p) + lead
	off.y = 0.0
	var pos: Vector3 = _ground(hip_then + off.limit_length(float(p["reach"])))
	var other: Vector3 = target(1 - i) if air[1 - i] else plant[1 - i]
	var side: float = (pos - _ground(other)).dot(yb.x)
	var gap: float = float(p["min_gap"])
	if i == 0 and side > -gap:
		pos -= yb.x * (side + gap)
	elif i == 1 and side < gap:
		pos += yb.x * (gap - side)
	return pos


## Swing progress 0..1 of foot `i` (0 when planted).
func swing_u(i: int) -> float:
	return clampf(t[i] / maxf(dur[i], 0.001), 0.0, 1.0) if air[i] else 0.0


## World target for foot `i`: its plant, or the swing arc (y = lift above the ground).
func target(i: int) -> Vector3:
	if not air[i]:
		return plant[i]
	var u: float = swing_u(i)
	var s: float = u * u * (3.0 - 2.0 * u)
	var out: Vector3 = from[i].lerp(to[i], s)
	out.y = lift[i] * sin(PI * u)
	return out


## True when foot `i` is on the ground.
func planted(i: int) -> bool:
	return not air[i]


## Hip sway -1..1 toward the planted foot while the other swings (negative = left), 0 with both feet alike.
func sway() -> float:
	return sin(PI * swing_u(0)) - sin(PI * swing_u(1))


## Rate of change of sway() (1/s), for a velocity feed-forward.
func sway_rate() -> float:
	var r: float = 0.0
	for i: int in range(2):
		if air[i]:
			r += (1.0 if i == 0 else -1.0) * PI * cos(PI * swing_u(i)) / maxf(dur[i], 0.001)
	return r


## Vertical bob 0..1: highest while a foot passes under the body at mid swing, 0 at a landing.
func bob() -> float:
	return maxf(sin(PI * swing_u(0)), sin(PI * swing_u(1)))


func to_array() -> Array:
	return [plant.duplicate(), air.duplicate(), t.duplicate(), dur.duplicate(), from.duplicate(), to.duplicate(),
		lift.duplicate(), step_t, steps, last, ready, settled.duplicate()]


func from_array(a: Array) -> void:
	if a.size() < 11:
		ready = false
		return
	plant.assign(a[0])
	air.assign(a[1])
	t.assign(a[2])
	dur.assign(a[3])
	from.assign(a[4])
	to.assign(a[5])
	lift.assign(a[6])
	step_t = float(a[7])
	steps = int(a[8])
	last = int(a[9])
	ready = bool(a[10])
	if a.size() > 11:
		settled.assign(a[11])


static func _stance(i: int, p: Dictionary) -> Vector3:
	return p["stance_l"] if i == 0 else p["stance_r"]


static func _ground(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
