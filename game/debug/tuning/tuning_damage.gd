extends "res://game/debug/tuning/tuning_arms.gd"
## Tuning rows of the "Damage" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_DAMAGE and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_DAMAGE: Array = [
	["damage_min_speed", 3.0, 0.0, 10.0, 0.1, "Damage", "Weapon-to-target speed below which a contact does no damage, m/s."],
	["blood_death", 2.5, 0.5, 5.0, 0.1, "Damage", "Blood volume (litres) below which a fighter dies."],
	["dmg_cut_scale", 0.25, 0.05, 1.0, 0.01, "Damage", "Cut damage points per joule of edged energy (before armor and weapon cut_factor)."],
	["dmg_pierce_scale", 0.9, 0.1, 3.0, 0.05, "Damage", "Pierce damage points per joule of point energy."],
	["dmg_blunt_scale", 0.1, 0.02, 0.5, 0.01, "Damage", "Blunt damage points per joule (before armor and weapon blunt_factor)."],
	["dmg_sever_cut", 40.0, 10.0, 120.0, 1.0, "Damage", "Cut points (after armor) that sever a forearm at full hp; other parts scale from this."],
	["dmg_gut", 30.0, 10.0, 100.0, 1.0, "Damage", "Cut or pierce points (after armor) on torso/pelvis that gut."],
	["dmg_stagger_ref", 150.0, 30.0, 600.0, 5.0, "Damage", "Blunt energy (J, after armor) that gives full stagger."],
	["dmg_knock_scale", 0.3, 0.0, 2.0, 0.05, "Damage", "Knockback impulse per N·s of hit momentum."],
	["dmg_bleed_cut", 0.004, 0.0, 0.05, 0.001, "Damage", "Bleed rate (L/s) per cut point."],
	["dmg_bleed_pierce", 0.003, 0.0, 0.05, 0.001, "Damage", "Bleed rate (L/s) per pierce point."],
	["dmg_bleed_sever", 0.4, 0.0, 2.0, 0.05, "Damage", "Extra bleed rate (L/s) from a severed limb."],
	["dmg_bleed_gut", 0.35, 0.0, 2.0, 0.05, "Damage", "Extra bleed rate (L/s) from a gutting."],
	["dmg_wear_loss", 0.6, 0.0, 1.0, 0.05, "Damage", "Fraction of an armor piece's resistance lost at full wear."],
	["dmg_glance_frac", 0.15, 0.0, 1.0, 0.01, "Damage", "A sharp hit is a glance when armor leaves less than this fraction of its cut+pierce."],
	["dmg_strap_wear", 0.7, 0.0, 1.0, 0.05, "Damage", "Fraction of an armor piece's strap strength lost at full wear."],
	["dmg_dislodge_up", 1.0, 0.0, 4.0, 0.1, "Damage", "Dislodge bonus for upward blows (doubled on the head)."],
	["dmg_dislodge_glance", 0.5, 0.0, 4.0, 0.1, "Damage", "Dislodge bonus for glancing blows."],
	["dmg_dislodge_sharp", 0.3, 0.0, 2.0, 0.05, "Damage", "How much cutting or piercing energy counts toward tearing a strap, relative to blunt."],
	["dmg_disarm_scale", 1.0, 0.1, 5.0, 0.1, "Damage", "Disarm impulse per N·s of hit momentum."],
	["dmg_disarm_forearm", 0.5, 0.0, 1.0, 0.05, "Damage", "Share of the disarm impulse that a hit on the holding forearm (not the weapon) delivers."],
	["dmg_grip_base", 18.0, 4.0, 60.0, 0.5, "Damage", "One-handed grip strength at full arm hp and stamina, N·s."],
	["dmg_grip_two_hands", 1.6, 1.0, 3.0, 0.05, "Damage", "Grip strength multiplier with two hands on the weapon."],
	["finisher_blood_frac", 0.6, 0.0, 1.0, 0.05, "Damage", "Blood fraction (0 = blood_death, 1 = full) below which a hit can be a killing blow."],
	["limp_hit_scale", 0.15, 0.0, 1.0, 0.05, "Damage", "Share of its force a blow keeps when the attacker is KO'd or dead (momentum without grip or drive)."],
	["dmg_pummel_scale", 0.8, 0.1, 1.0, 0.05, "Damage", "Ground and pound: share of the skull-crush blunt a fist head blow on a downed foe needs inside the finisher window."],
	["dmg_finisher_min_scale", 0.15, 0.1, 1.0, 0.01, "Damage", "Share of the normal sever/gut/crush force a finisher needs when blood is at blood_death."],
	["dmg_finisher_top_scale", 0.4, 0.2, 1.0, 0.01, "Damage", "Share of the normal sever/gut/crush force a finisher needs at the top edge of the finisher window."],
	["dmg_skull_crush", 20.0, 5.0, 80.0, 1.0, "Damage", "Blunt points (after armor, head multiplier included) a heavy blunt hit needs to crush the skull."],
	["dmg_disarm_weapon", 0.5, 0.1, 1.5, 0.05, "Damage", "Share of hit momentum delivered as disarm impulse when a hit lands on the held weapon."],
	["dmg_disarm_fist", 0.6, 0.1, 1.5, 0.05, "Damage", "Extra disarm multiplier when the striker is a fist."],
	["dmg_disarm_forearm_gain", 1.6, 0.5, 3.0, 0.1, "Damage", "Multiplier on the forearm disarm share, so a hard arm blow can disarm."],
	["self_hit_min_speed", 6.0, 0.0, 15.0, 0.5, "Damage", "Min speed for a fighter's own weapon to hurt them, m/s."],
	["self_hit_grace_s", 0.5, 0.0, 3.0, 0.1, "Damage", "No self hits for this long after spawn, while the weapon settles in the hand, s."],
	["finisher_consc", 0.35, 0.0, 1.0, 0.05, "Damage", "A dazed (consciousness below this) or downed fighter can be finished at any blood level."],
	["hit_debounce", 0.25, 0.05, 1.0, 0.05, "Damage", "Min time between hits by the same weapon on the same part, s."],
	["knockback_scale", 1.0, 0.0, 3.0, 0.05, "Damage", "Multiplier on hit knockback impulses."],
]

var damage_min_speed: float
var blood_death: float
var dmg_cut_scale: float
var dmg_pierce_scale: float
var dmg_blunt_scale: float
var dmg_sever_cut: float
var dmg_gut: float
var dmg_stagger_ref: float
var dmg_knock_scale: float
var dmg_bleed_cut: float
var dmg_bleed_pierce: float
var dmg_bleed_sever: float
var dmg_bleed_gut: float
var dmg_wear_loss: float
var dmg_glance_frac: float
var dmg_strap_wear: float
var dmg_dislodge_up: float
var dmg_dislodge_glance: float
var dmg_dislodge_sharp: float
var dmg_disarm_scale: float
var dmg_disarm_forearm: float
var dmg_grip_base: float
var dmg_grip_two_hands: float
var finisher_blood_frac: float
var limp_hit_scale: float
var dmg_pummel_scale: float
var dmg_finisher_min_scale: float
var dmg_finisher_top_scale: float
var dmg_skull_crush: float
var dmg_disarm_weapon: float
var dmg_disarm_fist: float
var dmg_disarm_forearm_gain: float
var self_hit_min_speed: float
var self_hit_grace_s: float
var finisher_consc: float
var hit_debounce: float
var knockback_scale: float
