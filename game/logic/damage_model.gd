class_name DamageModel
extends RefCounted
## Pure, deterministic hit resolution: kinetic energy 0.5*m*v^2 turned into blunt, cut and pierce damage points,
## reduced by armor, then checked for sever, gut and behead. No RNG, no nodes.
## Optional hit keys: "blood_frac" (0..1, default 1; 0 = at blood_death, 1 = full, see FighterHealth.blood_frac()), "part_hp_frac" (0..1, default 1) lets a hurt limb sever more easily;
## "hit_on_weapon" (bool) means the contact was on the defender's held weapon or shield: no body damage, only
## disarm_impulse. Armor def "strap" is the blunt-equivalent energy (J) that tears a fresh piece off.

const DEFAULTS: Dictionary = {
	"damage_min_speed": 3.0,
	"dmg_cut_scale": 0.25,
	"dmg_pierce_scale": 0.9,
	"dmg_blunt_scale": 0.1,
	"dmg_sever_cut": 40.0,
	"dmg_gut": 30.0,
	"dmg_stagger_ref": 150.0,
	"dmg_knock_scale": 0.3,
	"dmg_bleed_cut": 0.004,
	"dmg_bleed_pierce": 0.003,
	"dmg_bleed_sever": 0.4,
	"dmg_bleed_gut": 0.35,
	"dmg_wear_loss": 0.6,
	"dmg_glance_frac": 0.15,
	"dmg_strap_wear": 0.7,
	"dmg_dislodge_up": 1.0,
	"dmg_dislodge_glance": 0.5,
	"dmg_dislodge_sharp": 0.3,
	"dmg_disarm_scale": 1.0,
	"dmg_disarm_forearm": 0.5,
	"dmg_grip_base": 18.0,
	"dmg_grip_two_hands": 1.6,
	"finisher_blood_frac": 0.6,
	"dmg_finisher_min_scale": 0.25,
	"dmg_skull_crush": 20.0,
	"dmg_finisher_top_scale": 0.5,
}


## Reads a Tuning field, falling back to `default_value` when Tuning lacks it (or `t` is null: shared Tuning).
static func tuning_value(t: Tuning, field: String, default_value: float) -> float:
	var src: Tuning = t if t != null else Tuning.shared()
	var v: Variant = src.get(field)
	if v is float or v is int:
		return float(v)
	return default_value


static func _tv(t: Tuning, field: String) -> float:
	return tuning_value(t, field, float(DEFAULTS.get(field, 0.0)))


static func empty_result() -> Dictionary:
	return {
		"energy": 0.0, "blunt": 0.0, "cut": 0.0, "pierce": 0.0, "total": 0.0, "bleed": 0.0,
		"sever": false, "gut": false, "behead": false, "knockback": Vector3.ZERO, "stagger": 0.0,
		"armor_wear": {}, "glanced": false,
		"finisher": "", "dislodge": false, "dislodged_id": "", "disarm_impulse": 0.0,
	}


static func resolve(hit: Dictionary, tuning: Tuning) -> Dictionary:
	var out: Dictionary = empty_result()
	var wear_in: Dictionary = hit.get("armor_wear", {})
	out["armor_wear"] = wear_in.duplicate()
	var rel_vel: Vector3 = hit.get("rel_vel", Vector3.ZERO)
	var speed: float = rel_vel.length()
	var mass: float = maxf(float(hit.get("effective_mass", 0.0)), 0.0)
	var energy: float = 0.5 * mass * speed * speed
	out["energy"] = energy
	var wdef: Dictionary = CombatData.weapon(str(hit.get("weapon_id", "")))
	if wdef.is_empty() or speed < _tv(tuning, "damage_min_speed") or energy <= 0.0:
		return out

	var part: String = str(hit.get("part", ""))
	var closing: float = speed
	var blunt_f: float = float(wdef.get("blunt_factor", 0.0))
	var momentum: float = mass * closing * _tv(tuning, "dmg_disarm_scale")
	if bool(hit.get("hit_on_weapon", false)):
		out["disarm_impulse"] = momentum * (0.3 + 0.7 * blunt_f)
		return out
	if part.begins_with("forearm"):
		out["disarm_impulse"] = momentum * _tv(tuning, "dmg_disarm_forearm") * (0.3 + 0.7 * blunt_f)
	var pinfo: Dictionary = CombatData.part_info(part)
	var contact: String = str(hit.get("contact", "blunt"))
	var align: float = clampf(float(hit.get("edge_alignment", 1.0)), 0.0, 1.0)
	var blunt_raw: float = energy * float(wdef.get("blunt_factor", 0.0)) * _tv(tuning, "dmg_blunt_scale")
	var cut_raw: float = 0.0
	var pierce_raw: float = 0.0
	if contact == "edge" and float(wdef.get("edge_len", 0.0)) > 0.0:
		cut_raw = energy * float(wdef.get("cut_factor", 0.0)) * align * _tv(tuning, "dmg_cut_scale")
	elif contact == "point" and bool(wdef.get("point", false)):
		pierce_raw = energy * float(wdef.get("pierce_factor", 0.0)) * _tv(tuning, "dmg_pierce_scale")

	# Armor: resistances of stacked pieces multiply the damage that gets through; wear weakens them.
	var wear_loss: float = _tv(tuning, "dmg_wear_loss")
	var pass_cut: float = 1.0
	var pass_pierce: float = 1.0
	var pass_blunt: float = 1.0
	var pieces: Array[String] = []
	for aid: Variant in hit.get("armor_ids", []):
		var adef: Dictionary = CombatData.armor(str(aid))
		if adef.is_empty():
			continue
		pieces.append(str(aid))
		var w: float = clampf(float(wear_in.get(str(aid), 0.0)), 0.0, 1.0)
		var k: float = 1.0 - wear_loss * w
		pass_cut *= 1.0 - clampf(float(adef.get("cut_resist", 0.0)) * k, 0.0, 1.0)
		pass_pierce *= 1.0 - clampf(float(adef.get("pierce_resist", 0.0)) * k, 0.0, 1.0)
		pass_blunt *= 1.0 - clampf(float(adef.get("blunt_resist", 0.0)) * k, 0.0, 1.0)
	var cut: float = cut_raw * pass_cut
	var pierce: float = pierce_raw * pass_pierce
	var blunt_mult: float = float(pinfo.get("blunt_mult", 1.0))
	var blunt: float = blunt_raw * pass_blunt * blunt_mult
	out["cut"] = cut
	out["pierce"] = pierce
	out["blunt"] = blunt
	out["total"] = cut + pierce + blunt

	var raw_sharp: float = cut_raw + pierce_raw
	out["glanced"] = raw_sharp > 0.0 and cut + pierce < raw_sharp * _tv(tuning, "dmg_glance_frac")

	# Wear: damage soaked by the armor wears every covering piece in proportion to its durability.
	if not pieces.is_empty():
		var absorbed: float = (cut_raw - cut) + (pierce_raw - pierce) + (blunt_raw * blunt_mult - blunt)
		var share: float = absorbed / float(pieces.size())
		var wear_out: Dictionary = out["armor_wear"]
		for aid: String in pieces:
			var dur: float = maxf(float(CombatData.armor(aid).get("durability", 100.0)), 1.0)
			wear_out[aid] = clampf(float(wear_out.get(aid, 0.0)) + share / dur, 0.0, 1.0)

	# Dislodge: the weakest strap among the covering pieces gives way to a strong, upward or glancing blow.
	var wear_after: Dictionary = out["armor_wear"]
	var dir_n: Vector3 = (hit.get("normal", Vector3.ZERO) as Vector3)
	var vdir: Vector3 = rel_vel.normalized()
	var up: float = maxf(vdir.y, 0.0) * (2.0 if part == "head" else 1.0)
	var glance: float = 0.0
	if dir_n.length_squared() > 0.0001:
		glance = 1.0 - absf(vdir.dot(dir_n.normalized()))
	var dir_mult: float = 1.0 + _tv(tuning, "dmg_dislodge_up") * up + _tv(tuning, "dmg_dislodge_glance") * glance
	var sharp_f: float = maxf(float(wdef.get("cut_factor", 0.0)) if cut_raw > 0.0 else 0.0, float(wdef.get("pierce_factor", 0.0)) if pierce_raw > 0.0 else 0.0)
	var hit_energy: float = energy * maxf(blunt_f, sharp_f * _tv(tuning, "dmg_dislodge_sharp")) * dir_mult
	var weakest: float = INF
	for aid: String in pieces:
		var strap: float = float(CombatData.armor(aid).get("strap", 0.0))
		var left: float = strap * (1.0 - _tv(tuning, "dmg_strap_wear") * float(wear_after.get(aid, 0.0)))
		if left < weakest:
			weakest = left
			out["dislodged_id"] = aid
	if pieces.is_empty() or hit_energy < weakest:
		out["dislodged_id"] = ""
	else:
		out["dislodge"] = true

	# Sever / behead: an edged hit on a severable part with enough cut left, easier on a hurt part.
	var sev_mult: float = float(pinfo.get("sever", 0.0))
	var frac: float = clampf(float(hit.get("part_hp_frac", 1.0)), 0.0, 1.0)
	var sever: bool = false
	if sev_mult > 0.0 and cut > 0.0:
		var need: float = _tv(tuning, "dmg_sever_cut") * sev_mult * (0.5 + 0.5 * frac)
		sever = cut >= need
	out["sever"] = sever
	out["behead"] = sever and part == "head"
	out["gut"] = (part == "torso" or part == "pelvis") and maxf(cut, pierce) >= _tv(tuning, "dmg_gut")

	# Finishing blows: below finisher_blood_frac a good enough hit kills, needing less force the lower the blood.
	var bfrac: float = clampf(float(hit.get("blood_frac", 1.0)), 0.0, 1.0)
	var fin_top: float = maxf(_tv(tuning, "finisher_blood_frac"), 0.001)
	if bfrac < fin_top:
		var s: float = lerpf(_tv(tuning, "dmg_finisher_min_scale"), _tv(tuning, "dmg_finisher_top_scale"), bfrac / fin_top)
		var fin: String = ""
		var gut_need: float = _tv(tuning, "dmg_gut") * s
		var is_torso: bool = part == "torso" or part == "pelvis"
		if part == "head" and cut > 0.0 and sev_mult > 0.0 and cut >= _tv(tuning, "dmg_sever_cut") * sev_mult * (0.5 + 0.5 * frac) * s:
			fin = "behead"
		elif part == "head" and (contact == "blunt" or contact == "flat") and str(wdef.get("shape", "")) != "fist" \
				and blunt_f >= 0.5 and blunt >= _tv(tuning, "dmg_skull_crush") * s:
			fin = "skull_crush"
		elif is_torso and contact == "point" and pierce >= gut_need:
			fin = "run_through"
		elif is_torso and contact == "edge" and cut >= gut_need:
			fin = "gut"
		out["finisher"] = fin
		if fin == "behead":
			sever = true
			out["sever"] = true
			out["behead"] = true
		if fin == "gut":
			out["gut"] = true

	var bleed: float = cut * _tv(tuning, "dmg_bleed_cut") + pierce * _tv(tuning, "dmg_bleed_pierce")
	if sever:
		bleed += _tv(tuning, "dmg_bleed_sever")
	if bool(out["gut"]):
		bleed += _tv(tuning, "dmg_bleed_gut")
	out["bleed"] = bleed

	# Knockback along the surface normal (into the target), momentum scaled, blunt weapons shove more.
	var dir: Vector3 = (hit.get("normal", Vector3.ZERO) as Vector3)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else rel_vel.normalized()
	var push: float = mass * speed * _tv(tuning, "dmg_knock_scale") * (0.3 + 0.7 * float(wdef.get("blunt_factor", 0.0)))
	out["knockback"] = dir * push * pass_blunt

	var stagger_energy: float = energy * float(wdef.get("blunt_factor", 0.0)) * pass_blunt * blunt_mult
	out["stagger"] = clampf(stagger_energy / maxf(_tv(tuning, "dmg_stagger_ref"), 0.001), 0.0, 1.0)
	return out


## True when the hand keeps its weapon against a disarm impulse (N·s). Weaker with a hurt arm or low stamina,
## stronger with two hands on the weapon.
static func grip_holds(disarm_impulse: float, arm_hp_frac: float, stamina: float, two_hands: bool, tuning: Tuning) -> bool:
	var strength: float = _tv(tuning, "dmg_grip_base")
	strength *= 0.4 + 0.6 * clampf(arm_hp_frac, 0.0, 1.0)
	strength *= 0.5 + 0.5 * clampf(stamina, 0.0, 1.0)
	if two_hands:
		strength *= _tv(tuning, "dmg_grip_two_hands")
	return disarm_impulse <= strength
