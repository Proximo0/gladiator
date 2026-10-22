class_name KillcamPlan
extends RefCounted
## Pure maths of the instant replay of the finishing blow: which recorded moment is the killing blow, the playback
## rate around it (normal speed, a slow-motion section at the impact, a quicker tail), which camera shot runs when, and
## where each shot puts the camera. KillCam (the node) feeds it the recorded events and poses. Presentation only.

const HERO: int = 0  ## low hero angle on the winner during the build-up
const ORBIT: int = 1  ## orbit around the impact point through the slow motion
const CLOSE: int = 2  ## close on the severed head, the spilled guts or the victim

## Gore kinds that are a killing blow by themselves, best first when two land on the same tick.
const FINISH_KINDS: Array = ["behead", "gut", "run_through", "skull_crush", "sever"]
const MIN_SPAN_TICKS: int = 20
const HERO_LOW_Y: float = 0.35
const HERO_DIST0: float = 3.4
const HERO_DIST1: float = 2.6
const HERO_DOLLY_S: float = 4.0
const CHEST_Y: float = 1.15
const ORBIT_RADIUS: float = 2.1
const ORBIT_HEIGHT: float = 1.0
const ORBIT_DEG_S: float = 32.0
const CLOSE_DIST0: float = 2.3
const CLOSE_DIST1: float = 1.7
const CLOSE_RISE: float = 0.55
const CAM_MIN_Y: float = 0.25
const WALL_MARGIN: float = 0.6


## Playback parameters from Tuning (fallbacks when a field is missing).
static func params(tun: Object) -> Dictionary:
	return {
		"lead_s": _f(tun, "killcam_lead_s", 3.5), "tail_s": _f(tun, "killcam_tail_s", 1.6),
		"slow_rate": _f(tun, "killcam_slow_rate", 0.25), "slow_pre_s": _f(tun, "killcam_slow_pre_s", 0.2),
		"slow_post_s": _f(tun, "killcam_slow_post_s", 0.5), "tail_rate": _f(tun, "killcam_tail_rate", 0.6),
		"ramp_s": _f(tun, "killcam_ramp_s", 0.25),
	}


static func _f(tun: Object, field: String, fallback: float) -> float:
	var v: Variant = tun.get(field) if tun != null else null
	return float(v) if (v is float or v is int) else fallback


## The moment to replay. `events` rows are [tick, side, kind, ev, rng] (ReplayRing.events), `winner` the result's
## winner. The killing blow is the victim's last finisher gore event, else the last real hit on the victim (when the
## stored span still has it), else the victim's death. Returns {} when there is nothing to replay (a draw, no data),
## otherwise {kill_tick, victim, attacker, kind, point, part, start_tick, end_tick}.
static func pick(events: Array, winner: int, oldest: int, newest: int, lead_ticks: int, tail_ticks: int) -> Dictionary:
	if winner < 0 or winner > 1 or oldest < 0 or newest - oldest < MIN_SPAN_TICKS:
		return {}
	var victim: int = 1 - winner
	var best: Dictionary = {}
	var best_rank: int = 99
	var last_hit: Dictionary = {}
	var died: Dictionary = {}
	for e: Variant in events:
		var row: Array = e
		var t: int = int(row[0])
		var kind: String = str(row[2])
		var ev: Dictionary = row[3]
		if t < oldest or t > newest:
			continue
		if kind == "gore" and int(row[1]) == victim:
			var gk: String = str(ev.get("kind", ""))
			var rank: int = FINISH_KINDS.find(gk)
			if gk == "sever" and str(ev.get("part", "")) == "head":
				gk = "behead"
				rank = 0
			if rank >= 0 and (best.is_empty() or t > int(best["kill_tick"]) or (t == int(best["kill_tick"]) and rank < best_rank)):
				best = _moment(t, victim, gk, ev)
				best_rank = rank
		elif kind == "hit" and int(ev.get("target", row[1])) == victim and not bool(ev.get("hit_on_weapon", false)) \
				and float(ev.get("total", 0.0)) > 0.0:
			last_hit = _moment(t, victim, "hit", ev)
		elif kind == "died" and int(row[1]) == victim:
			died = _moment(t, victim, "death", ev)
	var m: Dictionary = best
	if m.is_empty():
		m = last_hit
	if m.is_empty() or (not died.is_empty() and int(m["kill_tick"]) - oldest < MIN_SPAN_TICKS):
		m = died
	if m.is_empty():
		return {}
	var k: int = int(m["kill_tick"])
	m["start_tick"] = maxi(oldest, k - lead_ticks)
	m["end_tick"] = mini(newest, k + tail_ticks)
	if int(m["end_tick"]) - int(m["start_tick"]) < MIN_SPAN_TICKS:
		return {}
	return m


static func _moment(t: int, victim: int, kind: String, ev: Dictionary) -> Dictionary:
	var p: Variant = ev.get("point", Vector3.ZERO)
	return {"kill_tick": t, "victim": victim, "attacker": 1 - victim, "kind": kind,
		"point": p if p is Vector3 else Vector3.ZERO, "part": str(ev.get("part", ""))}


static func ease01(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Playback rate (game seconds per real second) at `off` game seconds from the killing blow.
static func rate_at(off: float, p: Dictionary) -> float:
	var slow: float = float(p["slow_rate"])
	var pre: float = float(p["slow_pre_s"])
	var post: float = float(p["slow_post_s"])
	var ramp: float = maxf(float(p["ramp_s"]), 0.001)
	if off < -pre - ramp:
		return 1.0
	if off < -pre:
		return lerpf(1.0, slow, ease01((off + pre + ramp) / ramp))
	if off <= post:
		return slow
	return lerpf(slow, float(p["tail_rate"]), ease01((off - post) / ramp))


## Which shot runs at `off` game seconds from the killing blow.
static func shot_at(off: float, p: Dictionary) -> int:
	if off < -float(p["slow_pre_s"]) - float(p["ramp_s"]):
		return HERO
	if off < float(p["slow_post_s"]):
		return ORBIT
	return CLOSE


## Real seconds the replay of [from_off, to_off] (game seconds from the blow) takes.
static func real_duration(from_off: float, to_off: float, p: Dictionary, step: float = 1.0 / 240.0) -> float:
	var t: float = from_off
	var real: float = 0.0
	while t < to_off:
		var r: float = maxf(rate_at(t, p), 0.01)
		real += step / r
		t += step
	return real


## Keeps a camera inside the wall and above the sand.
static func clamp_cam(pos: Vector3, arena_r: float) -> Vector3:
	var p: Vector3 = FinaleShot.inside_wall(pos, arena_r, WALL_MARGIN)
	return Vector3(p.x, maxf(p.y, CAM_MIN_Y), p.z)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## +1 or -1: the side of the fight line the hero camera sits on (the one with more room inside the wall).
static func hero_side(attacker: Vector3, victim: Vector3, arena_r: float) -> float:
	var best: float = 1.0
	var best_room: float = -INF
	for s: float in [1.0, -1.0]:
		var p: Vector3 = _hero_raw(attacker, victim, s, HERO_DIST0)
		var room: float = arena_r - Vector2(p.x, p.z).length() if arena_r > 0.0 else 0.0
		if room > best_room:
			best_room = room
			best = s
	return best


static func _hero_raw(attacker: Vector3, victim: Vector3, side: float, dist: float) -> Vector3:
	var fwd: Vector3 = _flat(victim - attacker)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var lat: Vector3 = fwd.cross(Vector3.UP).normalized() * side
	var dir: Vector3 = (fwd * 0.55 + lat * 0.85).normalized()
	return _flat(attacker) + dir * dist + Vector3(0.0, HERO_LOW_Y, 0.0)


## [camera position, look point]: low and in front of the winner, looking up past him at the victim; dollies in.
static func hero_view(attacker: Vector3, victim: Vector3, side: float, t_real: float, arena_r: float) -> Array:
	var dist: float = lerpf(HERO_DIST0, HERO_DIST1, ease01(t_real / HERO_DOLLY_S))
	var pos: Vector3 = clamp_cam(_hero_raw(attacker, victim, side, dist), arena_r)
	pos.y = maxf(HERO_LOW_Y, CAM_MIN_Y)
	var a: Vector3 = Vector3(attacker.x, CHEST_Y, attacker.z)
	var v: Vector3 = Vector3(victim.x, CHEST_Y, victim.z)
	return [pos, a.lerp(v, 0.35)]


## Ground angle (radians, atan2(z, x)) of `from` seen from `center`.
static func angle_of(center: Vector3, from: Vector3) -> float:
	var d: Vector3 = _flat(from - center)
	return atan2(d.z, d.x) if d.length() > 0.001 else 0.0


## [camera position, look point]: circling the impact point at bullet-time pace (real seconds).
static func orbit_view(center: Vector3, a0: float, t_real: float, arena_r: float) -> Array:
	var a: float = a0 + deg_to_rad(ORBIT_DEG_S) * t_real
	var look: Vector3 = Vector3(center.x, clampf(center.y, 0.4, 1.6), center.z)
	var pos: Vector3 = Vector3(center.x + cos(a) * ORBIT_RADIUS, look.y + ORBIT_HEIGHT * 0.45, center.z + sin(a) * ORBIT_RADIUS)
	return [clamp_cam(pos, arena_r), look]


## [camera position, look point]: close on `target` (head, guts or victim) from the ground direction `from_dir`.
static func close_view(target: Vector3, from_dir: Vector3, t_real: float, arena_r: float) -> Array:
	var d: Vector3 = _flat(from_dir)
	d = d.normalized() if d.length() > 0.01 else Vector3.BACK
	var dist: float = lerpf(CLOSE_DIST0, CLOSE_DIST1, ease01(t_real / 2.0))
	var pos: Vector3 = target + d * dist + Vector3(0.0, CLOSE_RISE, 0.0)
	return [clamp_cam(pos, arena_r), target]
