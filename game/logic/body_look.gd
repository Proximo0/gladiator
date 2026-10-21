class_name BodyLook
extends RefCounted
## Pure picks for a fighter's body art: skin tone and head variant from the match seed and the side, plus the cloth
## colour per side. Deterministic, no RNG; visuals only (never feeds physics).

const SKIN_TONES: Array[Color] = [
	Color(0.89, 0.72, 0.60),
	Color(0.80, 0.60, 0.46),
	Color(0.68, 0.48, 0.34),
	Color(0.55, 0.37, 0.26),
	Color(0.40, 0.26, 0.18),
	Color(0.29, 0.18, 0.12),
]
const CLOTH_RED: Color = Color(0.62, 0.16, 0.12)
const CLOTH_BLUE: Color = Color(0.16, 0.26, 0.55)


static func _mix(seed_value: int) -> int:
	var h: int = (seed_value * 2654435761 + 40503) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


## Index into SKIN_TONES. The two sides never share a tone.
static func skin_index(match_seed: int, side: int) -> int:
	var h: int = _mix(match_seed)
	var first: int = h % SKIN_TONES.size()
	if side == 0:
		return first
	return (first + 1 + int((h >> 8) % (SKIN_TONES.size() - 1))) % SKIN_TONES.size()


static func skin_color(match_seed: int, side: int) -> Color:
	return SKIN_TONES[skin_index(match_seed, side)]


## True when the fighter wears the bearded head.
static func bearded(match_seed: int, side: int) -> bool:
	return ((_mix(match_seed + side * 7919 + 1) >> 5) & 1) == 1


static func cloth_color(side: int) -> Color:
	return CLOTH_RED if side == 0 else CLOTH_BLUE


## Joint -> cap asset for a severed part ("" when the part has no cap).
static func cap_for(part: String) -> String:
	if part == "head":
		return "cap_neck"
	if part.begins_with("upper_arm"):
		return "cap_shoulder"
	if part.begins_with("forearm"):
		return "cap_elbow"
	if part.begins_with("thigh"):
		return "cap_hip"
	if part.begins_with("shin"):
		return "cap_knee"
	return ""
