extends "res://game/debug/tuning/tuning_gait.gd"
## Tuning rows of the "Roll" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_ROLL and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_ROLL: Array = [
	["roll_time", 1.1, 0.4, 1.5, 0.05, "Roll", "Dodge roll length from tuck to stance, s."],
	["roll_speed", 4.0, 1.0, 8.0, 0.1, "Roll", "Body speed along the roll, m/s."],
	["roll_accel", 30.0, 5.0, 80.0, 1.0, "Roll", "Max horizontal acceleration while rolling, m/s²."],
	["roll_height", 0.15, 0.2, 0.8, 0.01, "Roll", "Pelvis height held through the tucked roll, m."],
	["roll_dip_height", 0.35, 0.3, 0.9, 0.01, "Roll", "Pelvis height the legs fold down to on planted feet before the tuck, m."],
	["roll_support", 0.4, 0.0, 2.0, 0.05, "Roll", "Max pelvis support while tucked, as a multiple of body weight (the sand carries the rest)."],
	["roll_pull", 2.0, 0.0, 3.0, 0.05, "Roll", "Max pull of the folding legs drawing the pelvis down to the planted feet in the dip, x body weight."],
	["roll_dip_freq", 14.0, 4.0, 30.0, 0.5, "Roll", "Stiffness of the pull drawing the pelvis down into the dip, rad/s."],
	["roll_fold_lead", 0.08, 0.0, 0.3, 0.01, "Roll", "How far below the dipping pelvis the legs fold toward, m (more lifts the feet)."],
	["roll_leg_hold", 2.0, 1.0, 5.0, 0.1, "Roll", "Leg joint stiffness and torque while tucked, as a multiple of the normal leg drive."],
	["roll_tuck_gate", 0.5, 0.0, 1.0, 0.01, "Roll", "Pelvis height below which the legs start to tuck (full 0.15 m lower); 0 tucks on time alone, m."],
	["roll_shoulder", 0.8, 0.0, 1.0, 0.05, "Roll", "Tilt of the roll's turn axis so it runs over one shoulder, rad."],
	["roll_land_lead", 0.15, 0.0, 0.6, 0.01, "Roll", "How far along the roll the opening legs plant the feet past the hips, m."],
	["roll_torque", 1500.0, 100.0, 4000.0, 10.0, "Roll", "Max torque turning the body over in a roll, N·m."],
	["roll_inertia_scale", 2.0, 0.5, 6.0, 0.1, "Roll", "Body turn gains while rolling, as a multiple of the upright controller's."],
	["roll_stamina", 0.22, 0.0, 0.6, 0.01, "Roll", "Stamina spent per roll (a roll needs this much)."],
	["roll_cooldown", 1.0, 0.0, 4.0, 0.05, "Roll", "Time after a roll ends before the next one, s."],
	["roll_guard", 0.6, 0.0, 1.0, 0.05, "Roll", "Share of a blow's effective mass while tucked (a glancing hit on a rolling body)."],
	["roll_guard_start", 0.3, 0.0, 1.0, 0.01, "Roll", "Roll progress where the tucked guard begins (0..1)."],
	["roll_guard_end", 0.72, 0.0, 1.0, 0.01, "Roll", "Roll progress where the tucked guard ends (0..1)."],
]

var roll_time: float
var roll_speed: float
var roll_accel: float
var roll_height: float
var roll_dip_height: float
var roll_support: float
var roll_pull: float
var roll_dip_freq: float
var roll_fold_lead: float
var roll_leg_hold: float
var roll_tuck_gate: float
var roll_shoulder: float
var roll_land_lead: float
var roll_torque: float
var roll_inertia_scale: float
var roll_stamina: float
var roll_cooldown: float
var roll_guard: float
var roll_guard_start: float
var roll_guard_end: float
