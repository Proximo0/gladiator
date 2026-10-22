class_name ArmorRead
extends RefCounted
## The CPU's read of the foe's armor, from what a player can see: which parts wear plate, where its gaps are (neck,
## face opening, elbows, knees: ArmorGaps), how heavy each fighter is (ArmorLoad), and so whether the lighter one
## should kite until the heavy one has run out of breath. Pure: the brain passes the debug-frame "armor"
## ({part: armor id}) and "parts" ({part: {"pos"}}) dictionaries.

## Gaps a point can aim for: [part whose armor must be plate, weight].
const GAPS: Dictionary = {
	"neck": ["torso", 1.4], "face": ["head", 1.0], "elbow_r": ["forearm_r", 0.6], "elbow_l": ["forearm_l", 0.25],
	"knee_l": ["shin_l", 0.3], "knee_r": ["shin_r", 0.3],
}
## The two parts whose joint a limb gap sits at (aimed at their midpoint).
const JOINTS: Dictionary = {
	"elbow_r": ["upper_arm_r", "forearm_r"], "elbow_l": ["upper_arm_l", "forearm_l"],
	"knee_l": ["thigh_l", "shin_l"], "knee_r": ["thigh_r", "shin_r"],
}
const FACE_DROP: float = 0.015  ## the face opening is centred a little below the head's centre (ArmorGaps.FACE_Y)
## A lighter fighter kites while the foe carries at least this much more armor load (about 8 kg at the 19 kg ref).
const KITE_LOAD_GAP: float = 0.4
const KITE_FOE_STAMINA: float = 0.45  ## and the foe still has this much stamina: below it, go in
const KITE_MIN_STAMINA: float = 0.3  ## the kiter needs breath of its own to run
const HELM_BLUNT_BIAS: float = 1.8  ## blunt weapons hit a plate helmet more: the blow carries through it
const HELM_EDGE_SCALE: float = 0.45  ## edged swings at a plate helmet glance: aim them elsewhere


static func kind_on(armor: Dictionary, part: String) -> String:
	var aid: String = str(armor.get(part, ""))
	if aid == "":
		return ""
	return str(CombatData.armor(aid).get("kind", aid))


static func plate_on(armor: Dictionary, part: String) -> bool:
	return kind_on(armor, part) == "plate"


## Distinct armor ids in a {part: id} map.
static func worn_ids(armor: Dictionary) -> Array:
	var out: Array = []
	for v: Variant in armor.values():
		var aid: String = str(v)
		if aid != "" and not out.has(aid):
			out.append(aid)
	return out


## Armor load (ArmorLoad.load_of) of a fighter wearing `armor`.
static func load_of(armor: Dictionary) -> float:
	return ArmorLoad.load_of(ArmorLoad.mass(worn_ids(armor)))


## {gap: weight} for the gaps that matter: only plate leaves a gap worth aiming for (anything else is cut through).
static func open_gaps(armor: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for g: Variant in GAPS:
		var e: Array = GAPS[g]
		if plate_on(armor, str(e[0])):
			out[g] = float(e[1])
	return out


## The part a gap belongs to, for severed checks and hp reads.
static func gap_part(gap: String) -> String:
	return str((GAPS.get(gap, ["torso", 0.0]) as Array)[0])


## World point to aim a thrust at for `gap`, from the foe's part positions (`fallback` when they are missing).
static func gap_point(gap: String, parts: Dictionary, fallback: Vector3) -> Vector3:
	var head: Vector3 = _pos(parts, "head", fallback + Vector3(0.0, 0.5, 0.0))
	var torso: Vector3 = _pos(parts, "torso", fallback)
	match gap:
		"neck":
			var up: Vector3 = head - torso
			if up.length() < 0.05:
				up = Vector3.UP * 0.4
			return torso + up.normalized() * (ArmorGaps.TORSO_HALF - _tv("armor_gap_len") * 0.5)
		"face":
			return head - Vector3(0.0, FACE_DROP, 0.0)
	if JOINTS.has(gap):
		var j: Array = JOINTS[gap]
		return (_pos(parts, str(j[0]), torso) + _pos(parts, str(j[1]), torso)) * 0.5
	return torso


## Head targeting factor from the helmet: up for a blunt weapon on plate, down for an edged swing on plate.
static func head_scale(armor: Dictionary, blunt: bool, edged: bool) -> float:
	if not plate_on(armor, "head"):
		return 1.0
	if blunt:
		return HELM_BLUNT_BIAS
	return HELM_EDGE_SCALE if edged else 1.0


## Whether a fighter with armor load `my_load` should keep away from one with `foe_load` for now.
static func should_kite(my_load: float, foe_load: float, my_stamina: float, foe_stamina: float) -> bool:
	return foe_load - my_load >= KITE_LOAD_GAP and foe_stamina > KITE_FOE_STAMINA and my_stamina > KITE_MIN_STAMINA


static func _pos(parts: Dictionary, part: String, fallback: Vector3) -> Vector3:
	var pd: Variant = parts.get(part, {})
	if pd is Dictionary and (pd as Dictionary).has("pos"):
		return (pd as Dictionary)["pos"]
	return fallback


static func _tv(field: String) -> float:
	return DamageModel.tuning_value(null, field, float(ArmorGaps.DEFAULTS.get(field, 0.0)))
