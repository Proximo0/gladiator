class_name ArmorGaps
extends RefCounted
## Where plate leaves gaps (Half Sword style): a cut or thrust that lands near a limb's joints (elbow, knee,
## shoulder, hip), in the neck and armpit band at the top of the torso, or in the face opening of a helmet finds
## the gap and loses most of the plate's cut and pierce resistance; the plate face still glances. Blunt force and
## mail and leather are unaffected. Pure: the fighter passes the hit point in the struck part's own frame.

const DEFAULTS: Dictionary = {
	"armor_gap_len": 0.05,
	"armor_gap_pass": 0.8,
}
## Limb half lengths along the part's Y axis (FighterRig capsule heights / 2).
const LIMB_HALF: Dictionary = {
	"upper_arm_l": 0.15, "upper_arm_r": 0.15, "forearm_l": 0.17, "forearm_r": 0.17,
	"thigh_l": 0.22, "thigh_r": 0.22, "shin_l": 0.21, "shin_r": 0.21,
}
const TORSO_HALF: float = 0.24
## Face opening on the head (part frame, forward is -Z): from the chin to the brow, in front of this depth.
const FACE_Y: Vector2 = Vector2(-0.07, 0.04)
const FACE_Z: float = -0.05


static func _tv(t: Tuning, field: String) -> float:
	return DamageModel.tuning_value(t, field, float(DEFAULTS.get(field, 0.0)))


## True when `local_p` (in part `part`'s frame) lies in a plate gap.
static func in_gap(part: String, local_p: Vector3, t: Tuning = null) -> bool:
	var gap: float = maxf(_tv(t, "armor_gap_len"), 0.0)
	if gap <= 0.0:
		return false
	if LIMB_HALF.has(part):
		return absf(local_p.y) >= float(LIMB_HALF[part]) - gap
	if part == "torso":
		return local_p.y >= TORSO_HALF - gap
	if part == "head":
		return local_p.z <= FACE_Z and local_p.y >= FACE_Y.x and local_p.y <= FACE_Y.y
	return false


## Share of a plate piece's cut and pierce resistance that a hit at `local_p` bypasses (0 off the gaps).
static func bypass(part: String, local_p: Vector3, t: Tuning = null) -> float:
	return clampf(_tv(t, "armor_gap_pass"), 0.0, 1.0) if in_gap(part, local_p, t) else 0.0
