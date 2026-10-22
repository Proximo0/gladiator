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


## Outfits that ship their own cap_*.glb in assets/outfits/<id>/ (the others use the base body's caps).
const OUTFITS_WITH_CAPS: PackedStringArray = ["alien"]


## Joint -> cap asset for a severed part ("" when the part has no cap). An outfit with its own caps gives
## "outfits/<id>/cap_x", else the base "cap_x".
static func cap_for(part: String, outfit: String = "default") -> String:
	var base: String = ""
	if part == "head":
		base = "cap_neck"
	elif part.begins_with("upper_arm"):
		base = "cap_shoulder"
	elif part.begins_with("forearm"):
		base = "cap_elbow"
	elif part.begins_with("thigh"):
		base = "cap_hip"
	elif part.begins_with("shin"):
		base = "cap_knee"
	if base != "" and OUTFITS_WITH_CAPS.has(outfit):
		return "outfits/" + outfit + "/" + base
	return base
