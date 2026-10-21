class_name BloodMath
extends RefCounted
## Pure helpers for the blood sim: drag, heartbeat, spurt pressure, spray counts, cones. No nodes, no RNG.

const FULL_BLOOD: float = 5.0
const DEFAULT_DEATH_BLOOD: float = 2.5
## Quadratic air drag scale: deceleration per (m/s)^2 is AIR_DRAG / radius (smaller drops slow faster).
const AIR_DRAG: float = 6.0e-4
## Droplets stand for more blood than their sphere volume so pools read; tunable.
const VOLUME_BOOST: float = 12.0
const SYSTOLE: float = 0.36
const BASE_FLOW: float = 0.10

const BUDGETS: Array[int] = [400, 1500, 4000]
const MIST_BUDGETS: Array[int] = [60, 160, 320]
const RATE_MULT: Array[float] = [0.45, 1.0, 1.6]
const RAY_BUDGETS: Array[int] = [40, 120, 240]


static func budget(level: int) -> int:
	return BUDGETS[clampi(level, 0, 2)]


static func mist_budget(level: int) -> int:
	return MIST_BUDGETS[clampi(level, 0, 2)]


static func rate_mult(level: int) -> float:
	return RATE_MULT[clampi(level, 0, 2)]


static func ray_budget(level: int) -> int:
	return RAY_BUDGETS[clampi(level, 0, 2)]


## Velocity damping factor for one step (semi-implicit, always stable).
static func drag_factor(speed: float, radius: float, dt: float) -> float:
	return 1.0 / (1.0 + AIR_DRAG / maxf(radius, 0.0005) * speed * dt)


## One droplet velocity step: gravity then drag. The sim inlines exactly this.
static func step_velocity(v: Vector3, dt: float, gravity: float, radius: float) -> Vector3:
	var w: Vector3 = Vector3(v.x, v.y - gravity * dt, v.z)
	return w * drag_factor(w.length(), radius, dt)


## Fraction of usable blood left: 1 = full, 0 = at the death threshold.
static func reserve(blood: float, full: float, death: float) -> float:
	return clampf((blood - death) / maxf(full - death, 0.001), 0.0, 1.0)


## Arterial pressure 0..1 from the blood reserve (falls off fast near death).
static func pressure(reserve_frac: float) -> float:
	return pow(clampf(reserve_frac, 0.0, 1.0), 0.6)


## Heart rate in beats per minute: climbs with blood loss, collapses near death.
static func heart_rate_bpm(reserve_frac: float) -> float:
	var r: float = clampf(reserve_frac, 0.0, 1.0)
	var bpm: float = 72.0 + 78.0 * (1.0 - r)
	return bpm * (0.55 + 0.45 * smoothstep(0.0, 0.18, r))


## Heartbeat flow shape for a phase (any float, wrapped): sharp systolic surge plus a small dicrotic bump.
static func pulse(phase: float) -> float:
	var p: float = phase - floorf(phase)
	if p < SYSTOLE:
		return pow(sin(PI * p / SYSTOLE), 1.1)
	if p > 0.46 and p < 0.60:
		return 0.14 * sin(PI * (p - 0.46) / 0.14)
	return 0.0


## Relative flow 0..~1.3 of an arterial wound.
static func spurt_flow(strength: float, press: float, pulse_v: float, age: float, tau: float) -> float:
	return strength * press * exp(-age / maxf(tau, 0.01)) * (BASE_FLOW + (1.0 - BASE_FLOW) * pulse_v)


## Exit speed of a spurt droplet for a flow value.
static func spurt_speed(flow: float, v_min: float, v_max: float) -> float:
	return lerpf(v_min, v_max, clampf(flow, 0.0, 1.0))


## Unit vector inside a cone around axis. u in 0..1 sets the angle fraction, v in 0..1 the azimuth.
static func cone_dir(axis: Vector3, half_angle: float, u: float, v: float) -> Vector3:
	var a: Vector3 = axis.normalized()
	var ref: Vector3 = Vector3.UP if absf(a.y) < 0.95 else Vector3.RIGHT
	var t: Vector3 = a.cross(ref).normalized()
	var b: Vector3 = a.cross(t)
	var ang: float = half_angle * u
	var az: float = TAU * v
	return (a * cos(ang) + (t * cos(az) + b * sin(az)) * sin(ang)).normalized()


## Drop radius (m) from a 0..1 sample: many fine drops, a few fat ones.
static func drop_radius(sample: float, r_min: float, r_max: float) -> float:
	return lerpf(r_min, r_max, pow(clampf(sample, 0.0, 1.0), 2.2))


static func droplet_litres(radius: float) -> float:
	return 4.0 / 3.0 * PI * radius * radius * radius * 1000.0 * VOLUME_BOOST


static func splat_radius(litres: float) -> float:
	return 0.018 + sqrt(maxf(litres, 0.0)) * 0.22


## How much a contact type sprays relative to a clean edge cut.
static func contact_scale(contact: String) -> float:
	match contact:
		"edge":
			return 1.0
		"point":
			return 0.5
		"flat":
			return 0.18
		"blunt":
			return 0.12
	return 0.2


## Spray droplets for a hit: wound = cut + pierce + 0.3 blunt damage points.
static func spray_count(wound: float, contact: String) -> int:
	if wound <= 0.0:
		return 0
	var n: float = (8.0 + wound * 2.2) * contact_scale(contact)
	return clampi(roundi(n), 1, 150)


## Stretch length (m) of a droplet drawn along its velocity.
static func stretch_length(speed: float, radius: float, factor: float) -> float:
	return minf(radius + speed * 0.007 * factor, radius * 16.0)


## Grid key for aggregating ground splats.
static func splat_cell(x: float, z: float, cell: float) -> Vector2i:
	return Vector2i(floori(x / cell), floori(z / cell))
