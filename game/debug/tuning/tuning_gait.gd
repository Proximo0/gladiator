extends "res://game/debug/tuning/tuning_balance.gd"
## Tuning rows of the "Gait" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_GAIT and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_GAIT: Array = [
	["foot_lift", 0.13, 0.0, 0.3, 0.01, "Gait", "Swing foot lift height, m."],
	["foot_load", 0.0, 0.0, 1.5, 0.05, "Gait", "Share of the pelvis support pressed into the planted feet (their grip on the sand)."],
	["foot_drive", 1.0, 0.0, 1.0, 0.05, "Gait", "Share of the drive force pushed back through the planted feet."],
	["foot_contact", 0.06, 0.0, 0.2, 0.01, "Gait", "A planted foot's ankle within this of its rest height counts as on the ground, m."],
	["leg_ff_max", 12.0, 0.0, 30.0, 0.5, "Gait", "Max leg target rate fed forward into the joint damping, rad/s."],
	["foot_force_max", 500.0, 0.0, 2000.0, 10.0, "Gait", "Max leg muscle force moving a foot to its planned point (reaction on the pelvis), N."],
	["foot_drive_mass", 6.0, 0.5, 20.0, 0.5, "Gait", "Mass the foot force's PD gains assume, kg."],
	["foot_freq", 14.0, 2.0, 30.0, 0.5, "Gait", "Stiffness of the foot force PD, rad/s."],
	["leg_height_follow", 1.0, 0.0, 1.0, 0.05, "Gait", "Share of the pelvis height error the leg IK folds or reaches for."],
	["stance_width", 0.07, 0.0, 0.25, 0.01, "Gait", "Each foot's stance spot outward of its hip, m."],
	["stance_fwd", 0.22, -0.1, 0.35, 0.01, "Gait", "Stance spots ahead of the hips (flat shins under the crouch), m."],
	["stance_stagger", 0.08, 0.0, 0.4, 0.01, "Gait", "Lead (left) foot this much ahead of the rear foot, m."],
	["walk_height_add", 0.0, 0.0, 0.1, 0.005, "Gait", "Pelvis rise from the stance crouch at sprint speed, m."],
	["cadence_base", 2.0, 0.5, 6.0, 0.05, "Gait", "Steps per second as the fighter starts moving."],
	["cadence_per_speed", 0.45, 0.0, 2.0, 0.05, "Gait", "Steps per second added per m/s."],
	["cadence_lateral", 1.0, 0.0, 4.0, 0.05, "Gait", "Extra steps per second per m/s moved sideways (a quick shuffle)."],
	["shuffle_lift", 0.7, 0.0, 1.0, 0.05, "Gait", "Foot lift share when stepping sideways (a low shuffle)."],
	["gait_reach", 0.42, 0.2, 0.7, 0.01, "Gait", "A planted foot farther than this from its hip steps at once, m."],
	["gait_span", 0.45, 0.1, 0.8, 0.01, "Gait", "How far the hip passes over a planted foot before it lifts (longer stance), m."],
	["gait_span_lat", 0.3, 0.1, 0.8, 0.01, "Gait", "The same moving sideways (the legs reach less to the side), m."],
	["stance_max", 0.4, 0.1, 1.0, 0.01, "Gait", "Longest time a foot stays down per step at a slow walk, s."],
	["swing_min", 0.18, 0.08, 0.5, 0.01, "Gait", "Shortest foot swing (the legs cannot swing faster), s."],
	["swing_max", 0.45, 0.15, 0.8, 0.01, "Gait", "Longest foot swing (a run's flight), s."],
	["gait_lead_max", 0.3, 0.0, 0.6, 0.01, "Gait", "Max landing lead ahead of the stance spot at speed, m."],
	["gait_min_gap", 0.14, 0.0, 0.4, 0.01, "Gait", "Closest the feet come sideways (they never cross), m."],
	["gait_idle_err", 0.12, 0.02, 0.4, 0.01, "Gait", "Standing, a foot this far off its stance spot steps back under, m."],
	["gait_min_speed", 0.25, 0.0, 1.0, 0.01, "Gait", "Below this speed the cadence stops (only corrective steps), m/s."],
	["gait_bob", 0.02, 0.0, 0.08, 0.005, "Gait", "Pelvis rise at mid swing over the planted leg, m."],
	["gait_sway", 0.03, 0.0, 0.1, 0.005, "Gait", "Hip shift toward the planted foot at mid swing, m."],
	["gait_hip_roll", 0.06, 0.0, 0.2, 0.01, "Gait", "Pelvis roll toward the planted leg at mid swing, rad."],
	["stance_lean", 0.08, 0.0, 0.4, 0.01, "Gait", "Torso forward lean in the fighting stance, rad."],
	["lean_per_speed", 0.025, 0.0, 0.1, 0.005, "Gait", "Extra forward lean per m/s moved forward, rad."],
	["strafe_speed_scale", 0.7, 0.3, 1.0, 0.05, "Gait", "Sideways speed as a share of the forward speed (a shuffle is slower)."],
]

var foot_lift: float
var foot_load: float
var foot_drive: float
var foot_contact: float
var leg_ff_max: float
var foot_force_max: float
var foot_drive_mass: float
var foot_freq: float
var leg_height_follow: float
var stance_width: float
var stance_fwd: float
var stance_stagger: float
var walk_height_add: float
var cadence_base: float
var cadence_per_speed: float
var cadence_lateral: float
var shuffle_lift: float
var gait_reach: float
var gait_span: float
var gait_span_lat: float
var stance_max: float
var swing_min: float
var swing_max: float
var gait_lead_max: float
var gait_min_gap: float
var gait_idle_err: float
var gait_min_speed: float
var gait_bob: float
var gait_sway: float
var gait_hip_roll: float
var stance_lean: float
var lean_per_speed: float
var strafe_speed_scale: float
