class_name NetCursor
extends RefCounted
## The one thing the client predicts: where its weapon hand is being steered. The host's fighter chases this point
## (Fighter._arms: FighterMath.guard_target from the aim, the torso and the facing), so drawing it from the local
## aim right away gives the hand an instant cursor while the body itself arrives one round trip plus the
## interpolation delay later. Pure: built from the interpolated torso pose and facing and the local input.

const CHEST_UP: float = 0.1
const ORIGIN_DOWN: float = 0.05
const ARM_REACH_FRAC: float = 0.97
const HALF_SWORD_AIM: float = 0.6
const SMOOTH_RATE: float = 30.0  ## 1/s, how fast the drawn cursor follows a jump in the predicted point

var point: Vector3 = Vector3.ZERO
var _have: bool = false


## The hand goal for `inp` with the torso at `torso_xf` facing `yaw`, the same maths as the fighter uses.
## `half_ok`: the held weapon allows the half-sword grip.
static func predict(inp: FighterInput, torso_xf: Transform3D, yaw: float, half_ok: bool, tun: Tuning) -> Vector3:
	var yb := Basis(Vector3.UP, yaw)
	var fwd: Vector3 = -yb.z
	var right: Vector3 = yb.x
	var up: Vector3 = Vector3.UP
	var chest: Vector3 = torso_xf.origin + up * CHEST_UP
	var origin: Vector3 = chest + fwd * tun.guard_forward - up * ORIGIN_DOWN
	var reach: float = (FighterRig.UPPER_ARM_LEN + FighterRig.FOREARM_LEN) * ARM_REACH_FRAC
	var half: bool = half_ok and inp.has(FighterInput.HALF_SWORD)
	var thrust: float = 1.0 if inp.has(FighterInput.THRUST) else (tun.swing_reach if inp.has(FighterInput.SWING) else 0.0)
	var gp: Dictionary = {"w": tun.guard_width, "h": tun.guard_height, "fwd": tun.guard_forward,
		"thrust": tun.thrust_reach * (0.6 if half else 1.0), "min_fwd": 0.2}
	var shoulder_local: Vector3 = (FighterRig.part("upper_arm_r")["pivot"] as Vector3) - (FighterRig.part("torso")["center"] as Vector3)
	var shoulder: Vector3 = torso_xf * shoulder_local
	var aim: Vector2 = inp.aim()
	if half:
		aim *= HALF_SWORD_AIM
	return FighterMath.guard_target(aim, thrust, origin, right, up, fwd, shoulder, reach, gp)


## Eases the drawn cursor toward `want` (snaps on the first call).
func follow(want: Vector3, delta: float) -> Vector3:
	if not _have:
		point = want
		_have = true
	else:
		point = point.lerp(want, clampf(SMOOTH_RATE * delta, 0.0, 1.0))
	return point
