extends "res://game/debug/tuning/tuning_feel.gd"
## Tuning rows of the "Armor" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_ARMOR and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_ARMOR: Array = [
	["armor_load_ref", 19.0, 5.0, 40.0, 0.5, "Armor", "Worn armor mass (kg) that counts as a full load (the iron set is 19.3 kg)."],
	["armor_load_max", 1.5, 1.0, 3.0, 0.1, "Armor", "Cap on the armor load (worn mass / armor_load_ref)."],
	["armor_speed_loss", 0.2, 0.0, 0.6, 0.01, "Armor", "Share of walk and sprint speed lost at a full armor load."],
	["armor_accel_loss", 0.25, 0.0, 0.6, 0.01, "Armor", "Share of the walking acceleration cap (starts, stops, turns) lost at a full armor load."],
	["armor_step_stamina", 0.03, 0.0, 0.1, 0.001, "Armor", "Stamina per step at a full armor load."],
	["armor_swing_stamina", 0.06, 0.0, 0.3, 0.005, "Armor", "Stamina per swing or thrust started at a full armor load."],
	["armor_getup_slow", 0.6, 0.0, 2.0, 0.05, "Armor", "Get-up time grows by this share at a full armor load."],
	["armor_arm_ref", 2.0, 0.5, 6.0, 0.1, "Armor", "Armor mass on one arm (kg) that counts as a full arm load."],
	["armor_arm_force_loss", 0.15, 0.0, 0.5, 0.01, "Armor", "Share of a hand's force cap lost at a full arm load."],
	["armor_gap_len", 0.07, 0.0, 0.15, 0.005, "Armor", "Plate gaps: band at each limb end (joints) and the top of the torso (neck, armpits), m."],
	["armor_gap_pass", 0.8, 0.0, 1.0, 0.05, "Armor", "Share of plate cut and pierce resistance that a hit in a gap (or a helmet's face opening) skips."],
]

var armor_load_ref: float
var armor_load_max: float
var armor_speed_loss: float
var armor_accel_loss: float
var armor_step_stamina: float
var armor_swing_stamina: float
var armor_getup_slow: float
var armor_arm_ref: float
var armor_arm_force_loss: float
var armor_gap_len: float
var armor_gap_pass: float
