class_name FighterMath
extends RefCounted
## Pure helpers for the active ragdoll: PD torques and forces, leg and arm IK, gait foot offsets, guard-plane
## mapping, yaw helpers, strength scaling and weapon contact classification. No nodes, no state.
## Conventions: Y up, fighter forward is -Z, right is +X. Limbs rest hanging along -Y.


## Rotation that takes `current` to `target`, as a world rotation vector (axis * angle, angle in 0..PI).
static func rotation_error(current: Basis, target: Basis) -> Vector3:
	var q: Quaternion = target.get_rotation_quaternion() * current.get_rotation_quaternion().inverse()
	return quat_to_rotvec(q)


## Quaternion as a rotation vector (axis * angle) along the shortest way round.
static func quat_to_rotvec(q_in: Quaternion) -> Vector3:
	var q: Quaternion = q_in.normalized()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	var s: float = sqrt(maxf(1.0 - q.w * q.w, 0.0))
	if s < 0.000001:
		return Vector3(q.x, q.y, q.z) * 2.0
	var angle: float = 2.0 * acos(clampf(q.w, -1.0, 1.0))
	return Vector3(q.x, q.y, q.z) / s * angle


## Critically damped style PD torque: inertia * (freq² * err - 2 * damping * freq * rel_ang_vel), length-capped.
static func pd_torque(err: Vector3, rel_ang_vel: Vector3, inertia: float, freq: float, damping: float, max_torque: float) -> Vector3:
	var t: Vector3 = (err * (freq * freq) - rel_ang_vel * (2.0 * damping * freq)) * inertia
	return t.limit_length(maxf(max_torque, 0.0))


## The inertia to use in an explicit PD at time step `dt` so its damping cannot overshoot: the joint's ideal
## inertia, capped where 2·damping·freq·dt·I / pair_inertia reaches `margin` (< 2 is stable, 1 is critical).
static func stable_inertia(ideal: float, pair_inertia: float, freq: float, damping: float, dt: float, margin: float) -> float:
	var rate: float = 2.0 * damping * freq * dt
	if rate <= 0.0:
		return ideal
	return minf(ideal, margin * pair_inertia / rate)


## Rotation snapped to a grid of quaternion components (`step`), so writing a pose to the physics engine and
## reading it back gives the same snapped pose again. Origin is kept as is.
static func quantize_transform(xf: Transform3D, step: float) -> Transform3D:
	var q: Quaternion = xf.basis.get_rotation_quaternion().normalized()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	q = Quaternion(snappedf(q.x, step), snappedf(q.y, step), snappedf(q.z, step), snappedf(q.w, step)).normalized()
	return Transform3D(Basis(q), xf.origin)


## Same shape as pd_torque for a point mass: mass * (freq² * err - 2 * damping * freq * vel), length-capped.
static func pd_force(err: Vector3, vel: Vector3, mass: float, freq: float, damping: float, max_force: float) -> Vector3:
	var f: Vector3 = (err * (freq * freq) - vel * (2.0 * damping * freq)) * mass
	return f.limit_length(maxf(max_force, 0.0))


## Two-link leg IK. `foot` is the ankle target relative to the hip, in the pelvis frame. Returns
## Vector3(hip_flex, hip_abduct, knee) in radians: hip_flex about +X (positive swings the leg forward),
## hip_abduct about +Z (positive swings the foot toward +X), knee about +X (negative bends the shin back).
static func leg_ik(foot: Vector3, l1: float, l2: float) -> Vector3:
	var d: float = clampf(foot.length(), 0.05, (l1 + l2) * 0.999)
	var horiz: float = sqrt(foot.x * foot.x + foot.y * foot.y)
	var abduct: float = atan2(foot.x, maxf(-foot.y, 0.001))
	var line: float = atan2(-foot.z, horiz)
	var cos_knee: float = clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0)
	var bend: float = PI - acos(cos_knee)
	var cos_a: float = clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var alpha: float = acos(cos_a)
	return Vector3(line + alpha, abduct, -bend)


## Joint-target bases for leg_ik's angles: [thigh relative to pelvis, shin relative to thigh].
static func leg_bases(angles: Vector3) -> Array[Basis]:
	var thigh: Basis = Basis(Vector3(0, 0, 1), angles.y) * Basis(Vector3(1, 0, 0), angles.x)
	var shin: Basis = Basis(Vector3(1, 0, 0), angles.z)
	return [thigh, shin]


## Two-link arm IK in world space: the elbow position for a hand at `target` (clamped to reach) from `shoulder`.
## `hint` is the direction the elbow should bend toward. Returns [elbow, hand].
static func arm_ik(shoulder: Vector3, target: Vector3, l1: float, l2: float, hint: Vector3) -> Array[Vector3]:
	var to: Vector3 = target - shoulder
	var d: float = clampf(to.length(), 0.05, (l1 + l2) * 0.999)
	var u: Vector3 = to.normalized() if to.length_squared() > 0.000001 else Vector3.DOWN
	var hand: Vector3 = shoulder + u * d
	var w: Vector3 = hint - u * hint.dot(u)
	if w.length_squared() < 0.000001:
		w = Vector3.DOWN - u * Vector3.DOWN.dot(u)
		if w.length_squared() < 0.000001:
			w = Vector3.BACK
	w = w.normalized()
	var cos_a: float = clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var a: float = acos(cos_a)
	var elbow: Vector3 = shoulder + (u * cos(a) + w * sin(a)) * l1
	return [elbow, hand]


## Rotation taking a bone that rests along -Y onto `dir` (shortest arc, stable near straight up).
static func bone_basis(dir: Vector3) -> Basis:
	var d: Vector3 = dir.normalized()
	if d.dot(Vector3.DOWN) < -0.9999:
		return Basis(Vector3(1, 0, 0), PI)
	return Basis(Quaternion(Vector3.DOWN, d))


## Hand target from aim in the guard plane. `aim` is -1..1 (right, up); `thrust` 0..1 pushes the target
## forward to full reach. The frame is the guard centre `origin` with unit axes right/up/fwd. The result is
## clamped to `reach` from `shoulder` and kept at least `min_fwd` in front of `origin - fwd * guard_fwd`.
## p keys: w, h (half extents of the plane, m), fwd (guard_fwd, m), thrust (m added forward), min_fwd (m).
static func guard_target(aim: Vector2, thrust: float, origin: Vector3, right: Vector3, up: Vector3, fwd: Vector3,
		shoulder: Vector3, reach: float, p: Dictionary) -> Vector3:
	var a: Vector2 = aim.limit_length(1.41421356)
	a = Vector2(clampf(a.x, -1.0, 1.0), clampf(a.y, -1.0, 1.0))
	var t: Vector3 = origin + right * (a.x * float(p.get("w", 0.55))) + up * (a.y * float(p.get("h", 0.45)))
	t += fwd * (clampf(thrust, 0.0, 1.0) * float(p.get("thrust", 0.4)))
	var to: Vector3 = t - shoulder
	if to.length() > reach:
		t = shoulder + to.normalized() * reach
	var chest: Vector3 = origin - fwd * float(p.get("fwd", 0.4))
	var ahead: float = (t - chest).dot(fwd)
	var min_fwd: float = float(p.get("min_fwd", 0.2))
	if ahead < min_fwd:
		t += fwd * (min_fwd - ahead)
	return t


## Yaw (radians) of a forward vector: Basis(Vector3.UP, yaw) has -Z along it.
static func yaw_of(fwd: Vector3) -> float:
	return atan2(-fwd.x, -fwd.z)


## Moves angle `from` toward `to` by at most `max_step`, the short way round. Result wrapped to -PI..PI.
static func turn_toward(from: float, to: float, max_step: float) -> float:
	var diff: float = wrapf(to - from, -PI, PI)
	return wrapf(from + clampf(diff, -max_step, max_step), -PI, PI)


## 0..1 balance from tilt angle (0 = upright): 1 - tilt / fall_tilt, clamped.
static func balance_from_tilt(tilt: float, fall_tilt: float) -> float:
	return clampf(1.0 - tilt / maxf(fall_tilt, 0.001), 0.0, 1.0)


## Overall drive strength 0..1 from stamina and consciousness. `floor_frac` is the strength left at 0 stamina.
static func strength(stamina: float, consciousness: float, floor_frac: float) -> float:
	var s: float = lerpf(floor_frac, 1.0, clampf(stamina, 0.0, 1.0))
	return s * clampf(consciousness, 0.0, 1.0)


## Per-limb strength factor from hp fraction: `floor_frac` at 0 hp, 1 at full hp.
static func limb_factor(hp_frac: float, floor_frac: float) -> float:
	return lerpf(floor_frac, 1.0, clampf(hp_frac, 0.0, 1.0))


## Gait: foot offset relative to its hip in the facing frame (x right, y up, z back) for a leg at `phase`
## (radians, 0..TAU; 0..PI is the swing). `dir` is the local move direction (x right, y forward), `amp` the
## half stride (m), `lift` the swing height (m).
static func foot_offset(phase: float, dir: Vector2, amp: float, lift: float) -> Vector3:
	var along: float = -cos(phase) * amp
	var up: float = maxf(sin(phase), 0.0) * lift * clampf(amp / 0.1, 0.0, 1.0)
	return Vector3(dir.x * along, up, -dir.y * along)


## Half stride for a speed (m/s): grows with speed, capped.
## Continuous in speed (it ramps in from 0 below 0.3 m/s) so the feet never jump when the fighter starts moving.
static func stride_amp(speed: float, base: float, per_speed: float, cap: float) -> float:
	var s: float = maxf(speed, 0.0)
	return minf(base * clampf(s / 0.3, 0.0, 1.0) + per_speed * s, cap)


## Effective mass (kg) of a weapon hit `r` m from the weapon's centre of mass, plus the share of the arm behind it.
static func effective_mass(mass: float, inertia_com: float, r: float, arm_mass: float) -> float:
	var m: float = maxf(mass, 0.01)
	var i: float = maxf(inertia_com, 0.0001)
	return m / (1.0 + m * r * r / i) + maxf(arm_mass, 0.0)


## Contact type and edge alignment for a hit at `s` (m along the weapon's +Y from the grip) with the relative
## velocity in weapon space (x edge, y along the blade, z flat). Returns {"contact", "edge_alignment"}.
static func classify_contact(def: Dictionary, s: float, rel_local: Vector3) -> Dictionary:
	var shape: String = str(def.get("shape", "club"))
	var length: float = float(def.get("length", 0.5))
	var tip: float = length - float(def.get("grip_offset", 0.0))
	var edge_len: float = float(def.get("edge_len", 0.0))
	var speed: float = rel_local.length()
	var dir: Vector3 = rel_local / speed if speed > 0.0001 else Vector3.ZERO
	var align: float = absf(dir.x)
	var out: Dictionary = {"contact": "blunt", "edge_alignment": align}
	if shape == "shield" or shape == "fist":
		return out
	var point_zone: float = maxf(0.08, edge_len * 0.25) if shape == "spear" else 0.08
	if bool(def.get("point", false)) and s > tip - point_zone and dir.y > 0.6:
		out["contact"] = "point"
		return out
	if shape == "rake" and s > tip - 0.15:
		out["contact"] = "point" if dir.y > 0.3 or absf(dir.z) > 0.6 else "blunt"
		return out
	if edge_len > 0.0 and s > tip - edge_len - 0.02:
		if align >= 0.45:
			out["contact"] = "edge"
		elif shape == "sword":
			out["contact"] = "flat"
	return out
