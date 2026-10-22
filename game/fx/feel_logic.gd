class_name FeelLogic
extends RefCounted
## Pure maths for combat feel: how hard a resolved hit reads (0..1), and what the camera, flash, sparks and rumble do
## with that. Small taps stay subtle because every effect scales from `impact` and has a floor under which it is off.
## No nodes, no clock, no random. Unit-tested in test_feel_logic.gd.

const FINISHER_IMPACT: float = 0.9  ## a killing blow reads at least this hard
const WEAPON_HIT_ENERGY_MULT: float = 0.8  ## steel on steel is loud but does not rock the camera as much as flesh
const FLASH_MIN_STRENGTH: float = 0.35
const RUMBLE_DEALER_MULT: float = 0.55  ## the one who lands the blow feels less than the one who takes it
const VIBRATE_MAX_MS: int = 220
const SPARK_ARMOR_KINDS: PackedStringArray = ["plate", "mail"]


## 0..1 hardness of a hit from its energy (J) and damage points; saturating, so a tap is near 0 and a full swing near 1.
static func impact(ev: Dictionary, tun: Tuning) -> float:
	var energy: float = float(ev.get("energy", 0.0))
	if bool(ev.get("hit_on_weapon", false)):
		energy *= WEAPON_HIT_ENERGY_MULT
	var by_energy: float = 1.0 - exp(-maxf(energy, 0.0) / maxf(tun.feel_impact_energy_ref, 1.0))
	var by_total: float = 1.0 - exp(-maxf(float(ev.get("total", 0.0)), 0.0) / maxf(tun.feel_impact_total_ref, 1.0))
	var v: float = maxf(by_energy, by_total)
	if str(ev.get("finisher", "")) != "" and not bool(ev.get("hit_on_weapon", false)):
		v = maxf(v, FINISHER_IMPACT)
	return clampf(v, 0.0, 1.0)


static func is_finisher(ev: Dictionary) -> bool:
	return str(ev.get("finisher", "")) != "" and not bool(ev.get("hit_on_weapon", false))


## World direction the blow travelled (weapon relative to the target); falls back to into the surface.
static func blow_dir(ev: Dictionary) -> Vector3:
	var rel: Vector3 = ev.get("rel_vel", Vector3.ZERO)
	if rel.length() > 0.01:
		return rel.normalized()
	var n: Vector3 = ev.get("normal", Vector3.ZERO)
	if n.length() > 0.01:
		return -n.normalized()
	return Vector3.ZERO


## Strength 0..1 for the camera effects: 0 under `feel_shake_min`, then ramps up to 1 at full impact.
static func camera_strength(imp: float, tun: Tuning) -> float:
	if imp < tun.feel_shake_min:
		return 0.0
	var span: float = maxf(1.0 - tun.feel_shake_min, 0.001)
	return clampf((imp - tun.feel_shake_min) / span, 0.0, 1.0)


## Strength 0..1 of the flash on the struck part (0 for a tap).
static func flash_strength(imp: float, tun: Tuning) -> float:
	if imp < tun.feel_flash_min or tun.feel_flash_s <= 0.0:
		return 0.0
	return lerpf(FLASH_MIN_STRENGTH, 1.0, clampf(imp, 0.0, 1.0))


## Do these two materials strike sparks? Steel (or iron) against steel, aluminium or worn plate / mail.
static func strikes_sparks(ev: Dictionary, atk_mat: String, other_mat: String, armor_kind: String) -> bool:
	if atk_mat == "energy":
		# A laser blade arcs off metal and hard armor, never off cloth or wood.
		if bool(ev.get("hit_on_weapon", false)):
			return other_mat == "steel" or other_mat == "aluminium" or other_mat == "energy"
		return SPARK_ARMOR_KINDS.has(armor_kind)
	if other_mat == "energy" and bool(ev.get("hit_on_weapon", false)):
		return atk_mat == "steel" or atk_mat == "aluminium"
	if atk_mat != "steel":
		# An aluminium bat on a steel blade sparks as well; a bat on plate does not (dull thud).
		return bool(ev.get("hit_on_weapon", false)) and atk_mat == "aluminium" and other_mat == "steel"
	if bool(ev.get("hit_on_weapon", false)):
		return other_mat == "steel" or other_mat == "aluminium"
	if bool(ev.get("glanced", false)) and SPARK_ARMOR_KINDS.has(armor_kind):
		return true
	return SPARK_ARMOR_KINDS.has(armor_kind)


## How many sparks; 0 when the pair does not spark or the hit is a tap.
static func spark_count(ev: Dictionary, atk_mat: String, other_mat: String, armor_kind: String, imp: float,
		tun: Tuning) -> int:
	if imp < tun.feel_spark_min or not strikes_sparks(ev, atk_mat, other_mat, armor_kind):
		return 0
	return maxi(1, roundi(tun.feel_spark_max * imp))


## Rumble for one pad: {"weak", "strong", "dur"} (zeros when below the floor or switched off). `taken` is true for the
## fighter who was hit, false for the one who landed it.
static func rumble(imp: float, taken: bool, tun: Tuning, scale: float) -> Dictionary:
	var none: Dictionary = {"weak": 0.0, "strong": 0.0, "dur": 0.0}
	if scale <= 0.0 or imp < tun.feel_rumble_min or tun.feel_rumble_s <= 0.0:
		return none
	var mult: float = 1.0 if taken else RUMBLE_DEALER_MULT
	var k: float = clampf(imp * mult * scale, 0.0, 1.0)
	return {
		"weak": clampf(k * 0.6 + 0.1, 0.0, 1.0),
		"strong": clampf(k, 0.0, 1.0),
		"dur": tun.feel_rumble_s * clampf(0.35 + 0.65 * imp, 0.0, 1.0),
	}


## Phone vibration for the same hit: {"ms", "amp"} (amp 0..1; ms 0 for none).
static func vibrate(imp: float, taken: bool, tun: Tuning, scale: float) -> Dictionary:
	var r: Dictionary = rumble(imp, taken, tun, scale)
	if float(r["dur"]) <= 0.0:
		return {"ms": 0, "amp": 0.0}
	return {"ms": mini(int(float(r["dur"]) * 600.0), VIBRATE_MAX_MS), "amp": float(r["strong"])}


## Gamepad device for a fighter side, or -1. Two or more pads: pad i is side i. One pad: it belongs to the human side
## (`player_side`). No pads: -1.
static func pad_for_side(side: int, player_side: int, pads: Array[int]) -> int:
	if pads.is_empty() or side < 0:
		return -1
	if pads.size() >= 2:
		return pads[side] if side < pads.size() else -1
	return pads[0] if side == player_side else -1
