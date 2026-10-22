class_name FighterHealth
extends RefCounted
## Per-part hp, blood, bleeding, consciousness and stamina for one fighter. Pure and deterministic.

const DEFAULTS: Dictionary = {
	"blood_death": 2.5,
	"blood_faint": 3.5,
	"health_head_ko": 0.03,
	"health_stagger_ko": 0.05,
	"health_clot": 0.02,
	"health_consc_recover": 0.03,
	"health_stamina_recover": 0.2,
	"health_stamina_drain": 0.3,
}
const START_BLOOD: float = 5.0

var parts: Dictionary = {}
var blood: float = START_BLOOD
var bleed_rate: float = 0.0
var consciousness: float = 1.0
var stamina: float = 1.0
var severed: PackedStringArray = PackedStringArray()
var dead: bool = false
var gutted: bool = false
var tuning: Tuning = null


func _init(t: Tuning = null) -> void:
	tuning = t
	for p: String in CombatData.part_names():
		parts[p] = float(CombatData.part_info(p).get("hp", 50.0))


func _tv(field: String) -> float:
	return DamageModel.tuning_value(tuning, field, float(DEFAULTS.get(field, 0.0)))


func hp(part: String) -> float:
	return float(parts.get(part, 0.0))


## Fraction of a part's full hp left (1 for unknown parts).
func hp_frac(part: String) -> float:
	var full: float = float(CombatData.part_info(part).get("hp", 0.0))
	return clampf(hp(part) / full, 0.0, 1.0) if full > 0.0 else 1.0


## Fraction of the fighter's whole hp pool left (all parts), for deciding a timed-out fight on damage taken.
func hp_total_frac() -> float:
	var left: float = 0.0
	var full: float = 0.0
	for p: Variant in parts:
		left += hp(str(p))
		full += float(CombatData.part_info(str(p)).get("hp", 0.0))
	return clampf(left / full, 0.0, 1.0) if full > 0.0 else 1.0


## Blood left above the death line: 1 = full, 0 = at blood_death. Feed this to DamageModel as "blood_frac".
func blood_frac() -> float:
	var death: float = _tv("blood_death")
	return clampf((blood - death) / maxf(START_BLOOD - death, 0.001), 0.0, 1.0)


func is_severed(part: String) -> bool:
	return severed.has(part)


func knocked_out() -> bool:
	return not dead and consciousness < 0.2


## Applies a DamageModel result to `part`. Returns gore events {kind, part, amount}.
func apply(result: Dictionary, part: String) -> Array:
	var events: Array = []
	if dead or not parts.has(part) or severed.has(part):
		return events
	var total: float = float(result.get("total", 0.0))
	if total <= 0.0 and not bool(result.get("sever", false)):
		return events
	parts[part] = maxf(hp(part) - total, 0.0)
	bleed_rate += float(result.get("bleed", 0.0))
	var drain: float = float(result.get("stagger", 0.0)) * _tv("health_stagger_ko")
	if part == "head":
		drain += float(result.get("blunt", 0.0)) * _tv("health_head_ko")
	consciousness = clampf(consciousness - drain, 0.0, 1.0)

	var cut: float = float(result.get("cut", 0.0))
	var pierce: float = float(result.get("pierce", 0.0))
	var bleed: float = float(result.get("bleed", 0.0))
	var big: bool = false
	if bool(result.get("sever", false)) and float(CombatData.part_info(part).get("sever", 0.0)) > 0.0:
		severed.append(part)
		parts[part] = 0.0
		big = true
		if part == "head" or bool(result.get("behead", false)):
			dead = true
			events.append({"kind": "behead", "part": part, "amount": cut})
		else:
			events.append({"kind": "sever", "part": part, "amount": cut})
	if bool(result.get("gut", false)) and (part == "torso" or part == "pelvis"):
		gutted = true
		big = true
		events.append({"kind": "gut", "part": part, "amount": maxf(cut, pierce)})
	if not big and bleed > 0.0:
		events.append({"kind": "bleed", "part": part, "amount": bleed})
	var fin: String = str(result.get("finisher", ""))
	if fin != "":
		dead = true
		if fin == "behead" and not severed.has(part):
			severed.append(part)
			parts[part] = 0.0
		if fin == "gut":
			gutted = true
		events = [{"kind": fin, "part": part, "amount": maxf(maxf(cut, pierce), float(result.get("blunt", 0.0)))}]
	if hp("head") <= 0.0 or hp("torso") <= 0.0:
		dead = true
	_check_death()
	return events


func _check_death() -> void:
	if blood < _tv("blood_death"):
		dead = true
	if dead:
		consciousness = 0.0


## Advances bleeding, clotting, stamina and consciousness. `exertion` is 0..1 (how hard the fighter is working).
func tick(delta: float, exertion: float) -> void:
	if dead:
		return
	blood = maxf(blood - bleed_rate * delta, 0.0)
	bleed_rate = maxf(bleed_rate * (1.0 - clampf(_tv("health_clot") * delta, 0.0, 1.0)) - 0.0, 0.0)
	if bleed_rate < 0.0005:
		bleed_rate = 0.0
	var ex: float = clampf(exertion, 0.0, 1.0)
	stamina = clampf(stamina + (_tv("health_stamina_recover") * (1.0 - ex) - _tv("health_stamina_drain") * ex) * delta, 0.0, 1.0)
	# Blood loss caps consciousness: fully awake above blood_faint, out cold at blood_death.
	var death: float = _tv("blood_death")
	var faint: float = maxf(_tv("blood_faint"), death + 0.01)
	var cap: float = clampf((blood - death) / (faint - death), 0.0, 1.0)
	consciousness = minf(clampf(consciousness + _tv("health_consc_recover") * delta, 0.0, 1.0), cap)
	_check_death()


func to_dict() -> Dictionary:
	return {
		"parts": parts.duplicate(), "blood": blood, "bleed_rate": bleed_rate, "consciousness": consciousness,
		"stamina": stamina, "severed": Array(severed), "dead": dead, "gutted": gutted,
	}


func from_dict(d: Dictionary) -> void:
	var p: Dictionary = d.get("parts", {})
	for k: Variant in p:
		parts[str(k)] = float(p[k])
	blood = float(d.get("blood", START_BLOOD))
	bleed_rate = float(d.get("bleed_rate", 0.0))
	consciousness = float(d.get("consciousness", 1.0))
	stamina = float(d.get("stamina", 1.0))
	severed = PackedStringArray()
	for s: Variant in d.get("severed", []):
		severed.append(str(s))
	dead = bool(d.get("dead", false))
	gutted = bool(d.get("gutted", false))
