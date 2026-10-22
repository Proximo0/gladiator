extends "res://game/debug/tuning/tuning_damage.gd"
## Tuning rows of the "Fighter" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_FIGHTER and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_FIGHTER: Array = [
	["stand_height", 0.87, 0.7, 1.1, 0.01, "Fighter", "Pelvis height held in the standing fighting crouch, m."],
	["crouch_height", 0.74, 0.5, 0.95, 0.01, "Fighter", "Pelvis height held when crouching, m."],
	["support_freq", 9.0, 2.0, 20.0, 0.5, "Fighter", "Stiffness of the pelvis height support, rad/s."],
	["support_max", 2.2, 0.5, 4.0, 0.1, "Fighter", "Max support force as a multiple of body weight."],
	["balance_freq", 9.0, 2.0, 20.0, 0.5, "Fighter", "Stiffness of the upright and yaw controller, rad/s."],
	["balance_torque", 450.0, 50.0, 2000.0, 10.0, "Fighter", "Max upright torque on the pelvis, N·m."],
	["torso_assist", 0.35, 0.0, 1.0, 0.05, "Fighter", "Share of the upright torque also put on the torso."],
	["joint_strength", 1.0, 0.0, 3.0, 0.05, "Fighter", "Multiplier on every joint's PD torque cap."],
	["joint_damping", 1.0, 0.2, 2.0, 0.05, "Fighter", "Damping ratio of joint PD drives."],
	["stamina_floor", 0.45, 0.0, 1.0, 0.05, "Fighter", "Strength left at zero stamina."],
	["limb_floor", 0.25, 0.0, 1.0, 0.05, "Fighter", "Limb drive left at zero limb hp."],
	["weapon_drop_hp", 0.15, 0.0, 0.5, 0.01, "Fighter", "Arm hp fraction below which the weapon is dropped."],
]

var stand_height: float
var crouch_height: float
var support_freq: float
var support_max: float
var balance_freq: float
var balance_torque: float
var torso_assist: float
var joint_strength: float
var joint_damping: float
var stamina_floor: float
var limb_floor: float
var weapon_drop_hp: float
