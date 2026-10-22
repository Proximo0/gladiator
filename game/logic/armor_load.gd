class_name ArmorLoad
extends RefCounted
## What worn armor costs a fighter: slower gait, stamina per step and per swing, a slower get-up and a smaller hand
## force budget. Pure and stateless: the fighter passes its worn armor ids (knocked-off pieces are gone from that
## list, so losing a helmet makes the fighter lighter at once). Armor stays out of the ragdoll's body masses, so the
## physics and the net snapshot are unchanged; only the drives read these scales.
## "Load" is worn mass over `armor_load_ref` (the iron set is about 1), capped at `armor_load_max`.

const DEFAULTS: Dictionary = {
	"armor_load_ref": 19.0,
	"armor_load_max": 1.5,
	"armor_speed_loss": 0.2,
	"armor_accel_loss": 0.25,
	"armor_step_stamina": 0.03,
	"armor_swing_stamina": 0.06,
	"armor_getup_slow": 0.6,
	"armor_arm_ref": 2.0,
	"armor_arm_force_loss": 0.15,
}
const ARM_PARTS: Dictionary = {"r": ["upper_arm_r", "forearm_r"], "l": ["upper_arm_l", "forearm_l"]}


static func _tv(t: Tuning, field: String) -> float:
	return DamageModel.tuning_value(t, field, float(DEFAULTS.get(field, 0.0)))


## Total mass of the worn pieces, kg (unknown ids weigh nothing).
static func mass(ids: Array) -> float:
	var m: float = 0.0
	for aid: Variant in ids:
		m += float(CombatData.armor(str(aid)).get("mass", 0.0))
	return m


## Mass carried on arm `h` ("r" or "l"): each piece's mass is shared evenly between the parts it covers.
static func arm_mass(ids: Array, h: String) -> float:
	var m: float = 0.0
	var arm: Array = ARM_PARTS.get(h, [])
	for aid: Variant in ids:
		var ad: Dictionary = CombatData.armor(str(aid))
		var covers: Array = ad.get("covers", [])
		if covers.is_empty():
			continue
		var on_arm: int = 0
		for pn: Variant in covers:
			if arm.has(str(pn)):
				on_arm += 1
		m += float(ad.get("mass", 0.0)) * float(on_arm) / float(covers.size())
	return m


## Worn mass as a share of the reference load: 0 naked, about 1 in the iron set.
static func load_of(m: float, t: Tuning = null) -> float:
	return clampf(m / maxf(_tv(t, "armor_load_ref"), 0.1), 0.0, _tv(t, "armor_load_max"))


## Multiplier on walk and sprint speed.
static func speed_scale(ld: float, t: Tuning = null) -> float:
	return clampf(1.0 - _tv(t, "armor_speed_loss") * ld, 0.2, 1.0)


## Multiplier on the horizontal acceleration cap (starting, stopping, changing direction).
static func accel_scale(ld: float, t: Tuning = null) -> float:
	return clampf(1.0 - _tv(t, "armor_accel_loss") * ld, 0.2, 1.0)


## Stamina paid for each step the feet take.
static func step_cost(ld: float, t: Tuning = null) -> float:
	return maxf(_tv(t, "armor_step_stamina") * ld, 0.0)


## Stamina paid for each swing or thrust started.
static func swing_cost(ld: float, t: Tuning = null) -> float:
	return maxf(_tv(t, "armor_swing_stamina") * ld, 0.0)


## Multiplier on the get-up time.
static func getup_scale(ld: float, t: Tuning = null) -> float:
	return 1.0 + maxf(_tv(t, "armor_getup_slow"), 0.0) * ld


## Multiplier on a hand's PD force cap from the armor on that arm (`arm_kg` from `arm_mass`).
static func arm_force_scale(arm_kg: float, t: Tuning = null) -> float:
	var arm_load: float = clampf(arm_kg / maxf(_tv(t, "armor_arm_ref"), 0.1), 0.0, _tv(t, "armor_load_max"))
	return clampf(1.0 - _tv(t, "armor_arm_force_loss") * arm_load, 0.3, 1.0)
