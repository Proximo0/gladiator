extends "res://game/debug/tuning/tuning_movement.gd"
## Tuning rows of the "Arms" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_ARMS and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_ARMS: Array = [
	["arm_force", 900.0, 100.0, 4000.0, 25.0, "Arms", "Max force the weapon hand can apply toward its target, N."],
	["arm_freq", 22.0, 5.0, 40.0, 0.5, "Arms", "Stiffness of the hand position drive, rad/s."],
	["arm_damping", 0.3, 0.05, 1.5, 0.05, "Arms", "Damping ratio of the hand position drive."],
	["arm_drive_mass", 3.5, 0.5, 10.0, 0.1, "Arms", "Mass the hand drive gains are computed for, kg."],
	["guard_force_frac", 0.45, 0.1, 1.0, 0.05, "Arms", "Share of arm_force used when not swinging or thrusting."],
	["offhand_force_frac", 0.6, 0.1, 1.0, 0.05, "Arms", "Share of arm_force for the left hand."],
	["arm_reaction", 0.4, 0.0, 1.0, 0.05, "Arms", "Share of the hand force pushed back on the torso at the shoulder."],
	["wrist_torque", 140.0, 10.0, 400.0, 5.0, "Arms", "Max wrist torque on the weapon, N·m."],
	["wrist_freq", 16.0, 4.0, 40.0, 0.5, "Arms", "Stiffness of the weapon orientation drive, rad/s."],
	["wrist_limit", 1.2, 0.2, 2.0, 0.05, "Arms", "Wrist joint swing limit, rad."],
	["wrist_roll", 0.3, 0.0, 1.0, 0.05, "Arms", "Strength of the wrist roll drive relative to swing."],
	["wrist_reach", 0.9, 0.2, 1.6, 0.05, "Arms", "Max wrist target angle from the natural grip direction, rad."],
	["wrist_lead", 0.15, 0.0, 0.5, 0.01, "Arms", "Blade lead along hand velocity (whip), s."],
	["blade_up_guard", 0.75, 0.0, 1.0, 0.05, "Arms", "How upright the blade is held in guard."],
	["blade_up_swing", 0.25, 0.0, 1.0, 0.05, "Arms", "How upright the blade is held while swinging."],
	["blade_pivot_back", 0.45, 0.0, 1.0, 0.05, "Arms", "How far the blade points back along the swing path, wind-up."],
	["guard_width", 0.7, 0.2, 1.2, 0.05, "Arms", "Half width of the guard plane, m."],
	["guard_height", 0.5, 0.2, 1.0, 0.05, "Arms", "Half height of the guard plane, m."],
	["guard_forward", 0.42, 0.2, 0.8, 0.01, "Arms", "Guard plane distance in front of the chest, m."],
	["thrust_reach", 0.45, 0.0, 1.0, 0.05, "Arms", "Extra forward reach when thrusting, m."],
	["swing_reach", 0.35, 0.0, 1.0, 0.05, "Arms", "Extra forward reach while swinging, m."],
	["thrust_lunge", 3.0, 0.0, 4.0, 0.1, "Arms", "Extra forward body speed while THRUST is held on the run (the hips drive in behind the point), m/s."],
	["thrust_lunge_accel", 30.0, 0.0, 30.0, 0.5, "Arms", "Extra horizontal acceleration while lunging with THRUST, m/s²."],
	["thrust_lunge_torso", 1.0, 0.0, 2.0, 0.1, "Arms", "Share of the lunge acceleration that also pushes the chest, so the arm keeps up with the hips."],
	["thrust_lunge_brake", 0.4, 0.0, 1.0, 0.05, "Arms", "Seconds after a lunge that the extra acceleration also brakes the body, so it does not run on into the foe."],
	["half_sword_thrust", 1.6, 1.0, 3.0, 0.1, "Arms", "Thrust force multiplier in the half-sword grip."],
	["torso_twist", 0.7, 0.0, 1.5, 0.05, "Arms", "Torso yaw following horizontal aim, rad at full aim."],
	["guard_hand_speed", 2.5, 0.5, 10.0, 0.1, "Arms", "Max speed of the hand goal in guard, m/s."],
	["swing_hand_speed", 30.0, 5.0, 60.0, 1.0, "Arms", "Max speed of the hand goal while swinging or thrusting, m/s."],
	["offhand_hand_speed", 5.0, 0.5, 15.0, 0.5, "Arms", "Max speed of the left hand goal, m/s."],
	["reach_height", 0.5, 0.3, 0.8, 0.01, "Arms", "Pelvis height when kneeling to pick a prop off the ground (CROUCH + GRAB), m."],
	["reach_pitch", 0.55, 0.0, 1.0, 0.05, "Arms", "Forward pitch of the pelvis in the pick-up bow, rad."],
	["reach_bend", 0.65, 0.0, 0.7, 0.05, "Arms", "Torso bend over the hips in the pick-up bow, rad (joint limit 0.7)."],
	["reach_time", 0.35, 0.05, 1.0, 0.05, "Arms", "Seconds to blend into or out of the pick-up bow."],
	["reach_hold", 0.4, 0.1, 1.0, 0.05, "Arms", "Seconds a GRAB press keeps the pick-up bow wanted (covers a pulsed button)."],
	["reach_scan", 1.1, 0.3, 2.0, 0.05, "Arms", "Horizontal distance from the pelvis within which a prop starts the pick-up bow, m."],
	["reach_hand_lift", 0.05, 0.0, 0.2, 0.01, "Arms", "Height above the prop that the reaching hand aims for, m."],
	["reach_hand_speed", 3.0, 0.5, 10.0, 0.1, "Arms", "Speed of the hand goal while reaching down, m/s."],
	["reach_foot_fwd", 0.12, 0.0, 0.3, 0.01, "Arms", "How far the feet step forward under the pick-up bow, m."],
	["grab_radius", 0.6, 0.1, 1.0, 0.05, "Arms", "GRAB pickup radius from the hand, m."],
]

var arm_force: float
var arm_freq: float
var arm_damping: float
var arm_drive_mass: float
var guard_force_frac: float
var offhand_force_frac: float
var arm_reaction: float
var wrist_torque: float
var wrist_freq: float
var wrist_limit: float
var wrist_roll: float
var wrist_reach: float
var wrist_lead: float
var blade_up_guard: float
var blade_up_swing: float
var blade_pivot_back: float
var guard_width: float
var guard_height: float
var guard_forward: float
var thrust_reach: float
var swing_reach: float
var thrust_lunge: float
var thrust_lunge_accel: float
var thrust_lunge_torso: float
var thrust_lunge_brake: float
var half_sword_thrust: float
var torso_twist: float
var guard_hand_speed: float
var swing_hand_speed: float
var offhand_hand_speed: float
var reach_height: float
var reach_pitch: float
var reach_bend: float
var reach_time: float
var reach_hold: float
var reach_scan: float
var reach_hand_lift: float
var reach_hand_speed: float
var reach_foot_fwd: float
var grab_radius: float
