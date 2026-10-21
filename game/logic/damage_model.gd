class_name DamageModel
extends RefCounted
## Pure, deterministic hit resolution: kinetic energy 0.5*m*v^2 turned into blunt, cut and pierce damage points,
## reduced by armor, then checked for sever, gut and behead. No RNG, no nodes.
## Optional hit key: "part_hp_frac" (0..1, default 1) lets a hurt limb sever more easily.

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
