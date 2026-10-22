class_name Tuning
extends RefCounted
## Template for live-tunable gameplay numbers (pattern from the skate project's PhysicsTuning).
## Game code reads `Tuning.shared().<field>` every tick instead of hard-coding numbers, so a tuning panel,
## replays, sims and presets can change the feel without touching code.
## Add a row to FIELDS and a matching `var` below; nothing else is needed.
## Presets are JSON dictionaries of {field: value}; unknown keys are ignored.

signal changed(field: String, value: float)

## [field, default, min, max, step, group, doc]. The order here is the order a tuning panel shows.
const FIELDS: Array = [
	["gravity", 9.8, 5.0, 30.0, 0.1, "World", "Gravity, m/s². Real is 9.8."],
	["arena_radius", 11.0, 6.0, 20.0, 0.5, "World", "Radius of the arena wall, m."],
	["move_speed", 2.5, 0.5, 8.0, 0.1, "Movement", "Walk speed on sand, m/s."],
	["sprint_speed", 4.5, 1.0, 10.0, 0.1, "Movement", "Sprint speed on sand, m/s."],
	["arm_force", 900.0, 100.0, 4000.0, 25.0, "Arms", "Max force the weapon hand can apply toward its target, N."],
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
	["stand_height", 0.87, 0.7, 1.1, 0.01, "Fighter", "Pelvis height held in the standing fighting crouch, m."],
	["crouch_height", 0.74, 0.5, 0.95, 0.01, "Fighter", "Pelvis height held when crouching, m."],
	["support_freq", 9.0, 2.0, 20.0, 0.5, "Fighter", "Stiffness of the pelvis height support, rad/s."],
	["support_max", 2.2, 0.5, 4.0, 0.1, "Fighter", "Max support force as a multiple of body weight."],
	["balance_freq", 9.0, 2.0, 20.0, 0.5, "Fighter", "Stiffness of the upright and yaw controller, rad/s."],
	["balance_torque", 450.0, 50.0, 2000.0, 10.0, "Fighter", "Max upright torque on the pelvis, N·m."],
	["torso_assist", 0.35, 0.0, 1.0, 0.05, "Fighter", "Share of the upright torque also put on the torso."],
	["move_accel", 9.0, 1.0, 30.0, 0.5, "Movement", "Max horizontal acceleration while moving, m/s²."],
	["move_response", 7.0, 1.0, 20.0, 0.5, "Movement", "How fast the body velocity follows the move input, 1/s."],
	["turn_rate", 6.0, 1.0, 20.0, 0.5, "Movement", "Max turn rate toward the opponent, rad/s."],
	["joint_strength", 1.0, 0.0, 3.0, 0.05, "Fighter", "Multiplier on every joint's PD torque cap."],
	["joint_damping", 1.0, 0.2, 2.0, 0.05, "Fighter", "Damping ratio of joint PD drives."],
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
	["half_sword_thrust", 1.6, 1.0, 3.0, 0.1, "Arms", "Thrust force multiplier in the half-sword grip."],
	["torso_twist", 0.7, 0.0, 1.5, 0.05, "Arms", "Torso yaw following horizontal aim, rad at full aim."],
	["stumble_tilt", 0.35, 0.1, 1.0, 0.01, "Balance", "Tilt where standing turns to stumbling, rad."],
	["fall_tilt", 1.0, 0.4, 1.5, 0.05, "Balance", "Tilt where the fighter goes down, rad."],
	["stagger_down", 0.85, 0.2, 1.5, 0.05, "Balance", "Stagger level that knocks the fighter down."],
	["stagger_recover", 0.8, 0.1, 3.0, 0.05, "Balance", "Stagger recovered per second."],
	["down_time", 1.5, 0.2, 5.0, 0.1, "Balance", "Time spent down before getting up, s."],
	["getup_time", 1.4, 0.3, 4.0, 0.1, "Balance", "Duration of getting up, s."],
	["down_strength", 0.3, 0.0, 1.0, 0.05, "Balance", "Joint strength while down."],
	["limp_strength", 0.04, 0.0, 0.3, 0.01, "Balance", "Joint strength when KO or dead."],
	["stamina_floor", 0.45, 0.0, 1.0, 0.05, "Fighter", "Strength left at zero stamina."],
	["limb_floor", 0.25, 0.0, 1.0, 0.05, "Fighter", "Limb drive left at zero limb hp."],
	["weapon_drop_hp", 0.15, 0.0, 0.5, 0.01, "Fighter", "Arm hp fraction below which the weapon is dropped."],
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
	["shove_time", 0.45, 0.2, 1.0, 0.01, "Close", "Shove length from push to drawn back, s."],
	["shove_stamina", 0.12, 0.0, 0.5, 0.01, "Close", "Stamina spent per shove (a shove needs this much)."],
	["shove_cooldown", 0.7, 0.0, 3.0, 0.05, "Close", "Time after a shove before the next one, s."],
	["shove_reach", 0.62, 0.3, 0.9, 0.01, "Close", "How far ahead of the chest the shoving hand drives at full extension, m."],
	["shove_force_frac", 1.1, 0.2, 2.0, 0.05, "Close", "Shoving hand force cap as a share of arm_force."],
	["shove_contact", 0.3, 0.1, 0.6, 0.01, "Close", "Hand (or shoulder) distance from the foe's torso or pelvis centre that counts as a landed shove, m."],
	["shove_impulse", 110.0, 0.0, 400.0, 5.0, "Close", "Push a landed shove gives the foe at full strength, N·s (split torso and pelvis)."],
	["shove_stagger", 0.35, 0.0, 1.0, 0.01, "Close", "Stagger a landed shove adds (stumbling above 0.25)."],
	["shove_stagger_off", 0.55, 0.0, 1.0, 0.01, "Close", "Extra stagger when the foe is already off balance: this floors a stumbling foe."],
	["shove_recoil", 0.3, 0.0, 1.0, 0.05, "Close", "Share of the shove impulse pushed back on the shover."],
	["shove_lunge", 1.2, 0.0, 3.0, 0.1, "Close", "Forward body drive while pushing, m/s."],
	["kick_time", 0.65, 0.3, 1.2, 0.01, "Close", "Front kick length from lifting the knee to the foot down again, s."],
	["kick_stamina", 0.18, 0.0, 0.5, 0.01, "Close", "Stamina spent per kick (a kick needs this much)."],
	["kick_cooldown", 0.9, 0.0, 3.0, 0.05, "Close", "Time after a kick before the next one, s."],
	["kick_reach", 0.85, 0.3, 1.0, 0.01, "Close", "How far ahead of the hip the kicking foot drives, m."],
	["kick_height", 0.62, 0.2, 1.0, 0.01, "Close", "Height of the kicking foot at full extension, m."],
	["kick_chamber", 0.42, 0.1, 0.7, 0.01, "Close", "Height the foot comes up to under the knee before the kick drives out, m."],
	["kick_lunge", 1.4, 0.0, 3.0, 0.1, "Close", "Forward hip drive while the kicking leg extends, m/s."],
	["kick_force", 1400.0, 200.0, 4000.0, 10.0, "Close", "Max leg muscle force driving the kicking foot, N (reaction on the pelvis)."],
	["kick_mass", 4.5, 1.0, 20.0, 0.5, "Close", "Effective mass behind a landed kick in the damage model, kg."],
	["kick_push", 80.0, 0.0, 300.0, 5.0, "Close", "Push a landed kick gives the foe on top of the contact, N·s."],
	["kick_miss_stagger", 0.3, 0.0, 1.0, 0.01, "Close", "Stagger a kick that meets nothing leaves the kicker with (over-extended on one leg)."],
	["kick_stagger_take", 1.6, 1.0, 3.0, 0.05, "Close", "Multiplier on stagger taken while kicking (standing on one leg)."],
	["kick_lean_back", 0.35, 0.0, 0.8, 0.01, "Close", "How far the kicker leans the upper body back while the leg is out (counterweight), rad."],
	["clinch_time", 0.4, 0.1, 1.0, 0.01, "Close", "How long the free hand reaches for the foe's weapon arm or head before it gives up, s."],
	["clinch_latch", 0.16, 0.05, 0.4, 0.01, "Close", "Hand distance from the grabbed point that closes the grip, m."],
	["clinch_slack", 0.03, 0.0, 0.15, 0.005, "Close", "How far the held point may move from the holding hand before the grip's joint pulls, m."],
	["clinch_pull", 0.3, 0.1, 0.6, 0.01, "Close", "How far ahead of the chest the holding hand draws the held part, m."],
	["clinch_break_dist", 0.3, 0.1, 0.8, 0.01, "Close", "The grip slips when the held point is pulled this far from the hand, m."],
	["clinch_max", 3.0, 0.5, 8.0, 0.1, "Close", "Longest a hold lasts, s."],
	["clinch_stamina", 0.1, 0.0, 0.5, 0.01, "Close", "Stamina per second a hold costs the holder."],
	["clinch_cooldown", 1.5, 0.0, 5.0, 0.05, "Close", "Time after a hold or a missed grab before the next grab, s."],
	["clinch_pin", 0.35, 0.0, 1.0, 0.05, "Close", "Share of its force a held weapon arm keeps (it cannot swing freely)."],
	["clinch_head_balance", 0.5, 0.0, 1.0, 0.05, "Close", "Share of its upright torque a fighter held by the head keeps."],
	["clinch_struggle", 0.55, 0.0, 3.0, 0.05, "Close", "Break-free progress per second at full effort against an equal holder (1 = free)."],
	["clinch_pull_side", 0.3, 0.0, 0.5, 0.01, "Close", "How far across to the holder's free side a held weapon arm is hauled, m."],
	["clinch_pull_down", 0.2, 0.0, 0.5, 0.01, "Close", "How far below the chest a held weapon arm is hauled, m."],
	["clinch_head_down", 0.3, 0.0, 0.6, 0.01, "Close", "How far below the chest a held head is pulled, m."],
	["clinch_pull_step", 0.22, 0.02, 0.4, 0.01, "Close", "How far ahead of the held point the holding hand leads it each tick, m."],
	["clinch_pull_force_frac", 0.9, 0.2, 2.0, 0.05, "Close", "Holding hand force cap as a share of arm_force (the pull)."],
	["clinch_break_min_speed", 3.0, 0.0, 10.0, 0.1, "Close", "Speed the striking body itself needs for a staggering blow on the holding arm to break the hold, m/s."],
	["clinch_twist", 0.35, 0.0, 0.8, 0.01, "Close", "Torso turn toward the free side while holding, putting the body into the pull, rad."],
	["pelvis_inertia", 2.0, 1.0, 5.0, 0.1, "Stability", "Pelvis inertia boost for stable PD."],
	["torso_inertia", 2.5, 1.0, 5.0, 0.1, "Stability", "Torso inertia boost for stable PD."],
	["balance_inertia", 3.0, 0.5, 8.0, 0.1, "Stability", "Inertia the upright controller gains assume, kg·m²."],
	["leg_reaction", 0.25, 0.0, 1.0, 0.05, "Stability", "Share of leg joint reaction put on the pelvis."],
	["pd_margin", 0.5, 0.1, 1.5, 0.05, "Stability", "Damping-rate margin for explicit PD (below 2 is stable)."],
	["dmg_disarm_weapon", 0.5, 0.1, 1.5, 0.05, "Damage", "Share of hit momentum delivered as disarm impulse when a hit lands on the held weapon."],
	["dmg_disarm_fist", 0.6, 0.1, 1.5, 0.05, "Damage", "Extra disarm multiplier when the striker is a fist."],
	["dmg_disarm_forearm_gain", 1.6, 0.5, 3.0, 0.1, "Damage", "Multiplier on the forearm disarm share, so a hard arm blow can disarm."],
	["self_hit_min_speed", 6.0, 0.0, 15.0, 0.5, "Damage", "Min speed for a fighter's own weapon to hurt them, m/s."],
	["self_hit_grace_s", 0.5, 0.0, 3.0, 0.1, "Damage", "No self hits for this long after spawn, while the weapon settles in the hand, s."],
	["finisher_consc", 0.35, 0.0, 1.0, 0.05, "Damage", "A dazed (consciousness below this) or downed fighter can be finished at any blood level."],
	["hold_freq", 2.0, 0.0, 6.0, 0.1, "Movement", "Idle position hold stiffness (stops drift), rad/s."],
	["guard_hand_speed", 2.5, 0.5, 10.0, 0.1, "Arms", "Max speed of the hand goal in guard, m/s."],
	["swing_hand_speed", 30.0, 5.0, 60.0, 1.0, "Arms", "Max speed of the hand goal while swinging or thrusting, m/s."],
	["offhand_hand_speed", 5.0, 0.5, 15.0, 0.5, "Arms", "Max speed of the left hand goal, m/s."],
	["hit_debounce", 0.25, 0.05, 1.0, 0.05, "Damage", "Min time between hits by the same weapon on the same part, s."],
	["arm_exertion", 0.7, 0.0, 1.0, 0.05, "Health", "Stamina cost of arm force, as a share of the fresh arm's cap (force used x strength)."],
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
	["knockback_scale", 1.0, 0.0, 3.0, 0.05, "Damage", "Multiplier on hit knockback impulses."],
	["match_pause_s", 4.0, 1.0, 15.0, 0.5, "Match", "Pause after a match before the next bot match starts, s."],
	["match_slowmo_scale", 0.4, 0.1, 1.0, 0.05, "Match", "Time scale during the finisher slow motion."],
	["match_slowmo_s", 1.0, 0.0, 5.0, 0.1, "Match", "Length of the finisher slow motion, game seconds."],
	["intro_s", 2.3, 0.0, 8.0, 0.1, "Match", "Pre-fight intro: name plates up and fighters held before FIGHT!, s (0 = no intro)."],
	["intro_fight_s", 0.8, 0.2, 3.0, 0.1, "Match", "FIGHT! stinger on screen (the fighters are free from its first frame), s."],
	["combo_gap_s", 1.5, 0.3, 5.0, 0.1, "Match", "Results' longest combo: most time between one fighter's blows with no blow back, s."],
	["combo_merge_s", 0.15, 0.0, 0.5, 0.01, "Match", "Results: contacts closer than this to the last blow are the same swing, s."],
	["killcam_on", 1.0, 0.0, 1.0, 1.0, "Replay", "1 = instant replay of the finishing blow before the result panel, 0 = off."],
	["killcam_buffer_s", 8.0, 5.0, 20.0, 0.5, "Replay", "Seconds of shown fight kept for the replay (ring buffer)."],
	["killcam_lead_s", 3.5, 1.0, 6.0, 0.1, "Replay", "Game seconds replayed before the killing blow."],
	["killcam_tail_s", 1.6, 0.3, 3.0, 0.1, "Replay", "Game seconds replayed after the killing blow."],
	["killcam_slow_rate", 0.25, 0.05, 1.0, 0.05, "Replay", "Playback speed of the slow motion at the impact."],
	["killcam_slow_pre_s", 0.2, 0.0, 1.0, 0.05, "Replay", "Game seconds of slow motion before the impact."],
	["killcam_slow_post_s", 0.5, 0.1, 2.0, 0.05, "Replay", "Game seconds of slow motion after the impact."],
	["killcam_tail_rate", 0.6, 0.1, 1.0, 0.05, "Replay", "Playback speed after the slow motion."],
	["killcam_ramp_s", 0.25, 0.05, 1.0, 0.05, "Replay", "Game seconds the speed takes to ease in and out of slow motion."],
	["feel_shake_scale", 1.0, 0.0, 2.0, 0.05, "Feel", "Master scale of camera kick, shake and zoom punch. 0 turns them all off (reduced motion forces 0)."],
	["feel_impact_energy_ref", 90.0, 10.0, 400.0, 5.0, "Feel", "Hit energy (J) at which the impact reads about 63 percent."],
	["feel_impact_total_ref", 25.0, 5.0, 100.0, 1.0, "Feel", "Damage points at which the impact reads about 63 percent."],
	["feel_shake_min", 0.15, 0.0, 0.8, 0.01, "Feel", "Impact below which a hit does no camera kick or shake."],
	["feel_kick_m", 0.14, 0.0, 0.6, 0.01, "Feel", "Camera kick distance at full impact, m (toward the blow)."],
	["feel_kick_freq", 16.0, 6.0, 40.0, 0.5, "Feel", "Spring stiffness of the camera kick, rad/s."],
	["feel_shake_m", 0.035, 0.0, 0.2, 0.005, "Feel", "High-frequency shake amplitude at full impact, m."],
	["feel_shake_roll_deg", 1.6, 0.0, 6.0, 0.1, "Feel", "Camera roll shake at full impact, degrees."],
	["feel_shake_decay", 7.0, 1.0, 20.0, 0.5, "Feel", "How fast shake dies away, 1/s."],
	["feel_zoom_deg", 7.0, 0.0, 20.0, 0.5, "Feel", "Field-of-view punch-in on a finisher, degrees."],
	["feel_zoom_hit_deg", 1.2, 0.0, 6.0, 0.1, "Feel", "Field-of-view punch-in on a full-impact ordinary hit, degrees."],
	["feel_zoom_decay", 5.0, 1.0, 20.0, 0.5, "Feel", "How fast the zoom punch relaxes, 1/s."],
	["feel_flash_s", 0.08, 0.0, 0.4, 0.01, "Feel", "Hit-flash length on the struck part, s (real time)."],
	["feel_flash_min", 0.08, 0.0, 0.8, 0.01, "Feel", "Impact below which a hit does not flash."],
	["feel_spark_max", 26.0, 0.0, 80.0, 1.0, "Feel", "Sparks per metal-on-metal hit at full impact."],
	["feel_spark_min", 0.1, 0.0, 0.8, 0.01, "Feel", "Impact below which metal hits make no sparks."],
	["feel_rumble_scale", 1.0, 0.0, 1.0, 0.05, "Feel", "Gamepad rumble and phone vibration strength (the options toggle also gates it)."],
	["feel_rumble_s", 0.3, 0.0, 1.0, 0.02, "Feel", "Rumble length at full impact, s."],
	["feel_rumble_min", 0.2, 0.0, 0.8, 0.01, "Feel", "Impact below which a hit does not rumble."],
	["feel_hitstop_min", 0.2, 0.0, 0.9, 0.01, "Feel", "Impact below which a hit has no hit-stop (presentation only; physics never pauses)."],
	["feel_hitstop_light_s", 0.035, 0.0, 0.2, 0.005, "Feel", "Hit-stop of a hit just over the floor, real s."],
	["feel_hitstop_heavy_s", 0.095, 0.0, 0.3, 0.005, "Feel", "Hit-stop of a full-impact hit, real s."],
	["feel_hitstop_sever_s", 0.12, 0.0, 0.3, 0.005, "Feel", "Least hit-stop of a blow that severs or guts, real s."],
	["feel_hitstop_finisher_s", 0.16, 0.0, 0.4, 0.005, "Feel", "Hit-stop of a finisher (behead, gut, run through, skull crush), real s."],
	["feel_hitstop_clash_mult", 0.7, 0.0, 1.5, 0.05, "Feel", "Hit-stop share for weapon on weapon (a crisp clang, not a stall)."],
	["feel_hitstop_rate", 0.06, 0.0, 0.5, 0.01, "Feel", "Presentation speed while a hit-stop holds (0 = frozen)."],
	["feel_hitstop_catchup", 1.6, 0.3, 6.0, 0.1, "Feel", "Extra presentation speed while it catches back up to physics after a hold (1.6 = 2.6x)."],
	["feel_hitstop_lag_max", 0.15, 0.02, 0.4, 0.01, "Feel", "Most the shown pose may trail physics, s: the hard cap against stacked stalls."],
	["feel_hitstop_budget_s", 0.3, 0.05, 1.5, 0.01, "Feel", "Hit-stop debt at which further stops shrink to nothing (a flurry does not stall)."],
	["feel_hitstop_budget_tau", 0.8, 0.1, 4.0, 0.05, "Feel", "Time constant over which hit-stop debt drains, s."],
	["feel_punch_min", 0.45, 0.0, 1.0, 0.01, "Feel", "Impact below which a hit does no screen punch (radial blur, colour split, flash)."],
	["feel_punch_s", 0.16, 0.02, 0.6, 0.01, "Feel", "Length of a screen punch, real s."],
	["feel_punch_blur", 0.045, 0.0, 0.15, 0.005, "Feel", "Radial blur reach of a full screen punch (share of the distance to the impact point)."],
	["feel_punch_chroma", 0.006, 0.0, 0.03, 0.001, "Feel", "Colour split of a full screen punch (share of the distance to the impact point)."],
	["feel_punch_flash", 0.22, 0.0, 0.8, 0.01, "Feel", "Screen flash alpha of a full screen punch."],
	["feel_cine_scale", 0.2, 0.05, 1.0, 0.01, "Feel", "Time scale of the finisher slow motion on a behead, gut or run through."],
	["feel_cine_hold_s", 0.9, 0.0, 3.0, 0.05, "Feel", "How long that slow motion holds, real s."],
	["feel_cine_ramp_s", 0.7, 0.05, 3.0, 0.05, "Feel", "Ease back to full speed after the hold, real s (the crowd roars as it starts)."],
	["feel_cine_lpf_hz", 900.0, 200.0, 8000.0, 50.0, "Feel", "Low-pass cutoff on crowd and effects during the finisher slow motion, Hz."],
	["feel_cine_bass_db", -2.0, -30.0, 6.0, 0.5, "Feel", "Gain of the finisher bass hit, dB."],
	["feel_bass_min", 0.6, 0.0, 1.0, 0.01, "Feel", "Impact above which an ordinary heavy hit gets a short sub-bass thump."],
	["aim_trail_s", 0.3, 0.05, 1.0, 0.05, "Feel", "Length of the player's own weapon-tip trail (aim aid), s."],
	["aim_alpha", 0.8, 0.1, 1.0, 0.05, "Feel", "Opacity of the aim aid (tip marker, trail, hand reticle)."],
	["aim_lost_delay_s", 0.4, 0.0, 3.0, 0.1, "Feel", "Disarmed for this long before the weapon-lost prompt shows, s."],
	["practice_half_gap", 1.75, 0.8, 4.0, 0.05, "World", "Practice only: each fighter's spawn distance from the centre, m (the dummy starts twice this away)."],
	["feel_frame_pull_max", 5.0, 0.0, 12.0, 0.5, "Feel", "Most the follow camera pulls back to keep both fighters on screen, m."],
	["feel_frame_margin", 0.82, 0.4, 1.0, 0.01, "Feel", "Share of the half field of view both fighters must stay inside."],
	["feel_close_shoulder", 1.1, 0.0, 2.5, 0.05, "Feel", "Extra sideways shift of the follow camera at melee range, so the opponent is not hidden behind your back, m."],
	["feel_close_height", 0.7, 0.0, 2.0, 0.05, "Feel", "Extra height of the follow camera at melee range, m."],
	["feel_close_near", 1.7, 0.5, 4.0, 0.1, "Feel", "Fighter separation at or under which the full close-range camera shift applies, m."],
	["feel_finale_hold_s", 3.0, 0.5, 8.0, 0.1, "Feel", "How long the finisher / death camera holds its framing, s."],
	["feel_finale_ease_s", 0.6, 0.1, 2.0, 0.05, "Feel", "Ease-in of the finisher camera, s."],
	["feel_finale_release_s", 1.5, 0.2, 4.0, 0.1, "Feel", "Ease-out back to the normal camera after the hold, s."],
	["feel_finale_dist", 3.6, 1.5, 7.0, 0.1, "Feel", "Distance of the finisher camera from the held point, m."],
	["feel_finale_height", 1.1, 0.3, 3.0, 0.1, "Feel", "Height of the finisher camera above the held point, m."],
	["feel_finale_look_y", 0.8, 0.3, 1.5, 0.05, "Feel", "Height of the held finisher look point, m."],
	["feel_finale_head_bias0", 0.2, 0.0, 1.0, 0.05, "Feel", "Share of the beheading look point on the severed head at first (the rest stays on the body's fountain)."],
	["feel_finale_head_bias1", 0.65, 0.0, 1.0, 0.05, "Feel", "Share of the beheading look point on the head once it has rolled."],
	["feel_finale_head_s", 2.0, 0.2, 5.0, 0.1, "Feel", "Seconds over which the beheading shot shifts from the fountain to the head, s."],
	["feel_finale_head_reach", 5.0, 1.5, 10.0, 0.1, "Feel", "Furthest the beheading shot follows the head from the body, m."],
	["feel_finale_dist_max", 7.5, 3.0, 12.0, 0.1, "Feel", "Most the finisher camera backs off to keep body and head in frame, m."],
	["feel_finale_high", 3.2, 1.5, 6.0, 0.1, "Feel", "Camera height of the high 3/4 finisher fallback when no side-on angle fits inside the wall, m."],
	["feel_prime_ticks", 1.0, 0.0, 10.0, 1.0, "Feel", "Physics ticks the camera waits after a restart before it primes, so ragdolls settle."],
	["feel_close_far", 3.6, 1.0, 8.0, 0.1, "Feel", "Fighter separation at or over which the close-range camera shift is gone, m."],
	["blood_faint", 3.5, 2.6, 5.0, 0.1, "Health", "Blood (L) below which consciousness is capped; zero at blood_death."],
	["health_head_ko", 0.04, 0.0, 0.2, 0.005, "Health", "Consciousness lost per blunt point on the head (0.04: a solid club blow dazes into the finisher window, only a huge one knocks out)."],
	["health_stagger_ko", 0.05, 0.0, 0.5, 0.01, "Health", "Consciousness lost per unit of stagger on any part."],
	["health_clot", 0.02, 0.0, 0.5, 0.005, "Health", "Bleed rate decay per second (clotting)."],
	["health_concuss_gain", 0.12, 0.0, 0.3, 0.005, "Health", "Concussion added per blunt point on the head (a fist blow is about 2-3 points)."],
	["health_concuss_hit_max", 0.25, 0.0, 1.0, 0.05, "Health", "Most concussion one head blow adds, so a club does not stun in one hit."],
	["health_concuss_decay", 0.004, 0.0, 0.2, 0.005, "Health", "Concussion fading per second (slow: a long brawl accumulates)."],
	["health_concuss_cap", 0.8, 0.0, 1.0, 0.05, "Health", "Consciousness ceiling falls by this much at full concussion (weak limbs while stunned)."],
	["health_concuss_stun", 0.3, 0.0, 1.0, 0.05, "Health", "Concussion at which a fighter counts as stunned."],
	["health_concuss_amp", 3.0, 0.0, 6.0, 0.1, "Health", "Head consciousness loss is multiplied by 1 + this x concussion (a stunned head knocks out easily)."],
	["health_nose_bleed", 0.0006, 0.0, 0.01, 0.0001, "Health", "Bleed rate (L/s) per blunt point on the head: bloody nose and mouth."],
	["health_consc_recover", 0.03, 0.0, 0.5, 0.005, "Health", "Consciousness recovery per second."],
	["health_stamina_recover", 0.2, 0.0, 1.0, 0.01, "Health", "Stamina recovered per second at rest."],
	["health_stamina_drain", 0.3, 0.0, 1.0, 0.01, "Health", "Stamina drained per second at full exertion."],
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
	["fountain_streams", 5.0, 1.0, 8.0, 1.0, "Blood", "Beheading fountain: jets from the neck at normal quality (low quality uses half, high a quarter more)."],
	["fountain_dur", 6.5, 1.0, 15.0, 0.1, "Blood", "Beheading fountain: seconds until the jets stop."],
	["fountain_hold", 1.6, 0.0, 8.0, 0.1, "Blood", "Beheading fountain: seconds at full strength before it tapers off."],
	["fountain_bpm", 150.0, 40.0, 240.0, 5.0, "Blood", "Beheading fountain: heartbeat pulses per minute."],
	["fountain_pulse_floor", 0.14, 0.0, 1.0, 0.02, "Blood", "Beheading fountain: share of the flow that stays between heartbeats."],
	["fountain_rate", 1300.0, 50.0, 2000.0, 10.0, "Blood", "Beheading fountain: droplets per second per jet at full flow and normal quality."],
	["fountain_v_min", 3.2, 1.0, 12.0, 0.1, "Blood", "Beheading fountain: droplet exit speed between beats, m/s."],
	["fountain_v_max", 7.5, 3.0, 20.0, 0.1, "Blood", "Beheading fountain: droplet exit speed at the top of a beat, m/s."],
	["fountain_up_bias", 0.6, 0.0, 1.0, 0.05, "Blood", "Beheading fountain: how far the jets turn from the neck axis toward straight up (0 = along the neck, 1 = vertical)."],
	["fountain_fan", 0.5, 0.0, 1.0, 0.02, "Blood", "Beheading fountain: radians the jets lean away from the main axis."],
	["fountain_wobble", 0.22, 0.0, 1.0, 0.02, "Blood", "Beheading fountain: radians of swaying added to each jet."],
	["fountain_swirl", 0.9, 0.0, 4.0, 0.1, "Blood", "Beheading fountain: radians per second the jets circle around the axis."],
	["fountain_drop_scale", 3.2, 0.5, 3.0, 0.05, "Blood", "Beheading fountain: droplet size multiplier (cartoon fat drops)."],
	["fountain_gush", 1.4, 0.0, 4.0, 0.1, "Blood", "Beheading fountain: extra flow in the first moments."],
	["fountain_emit_cap", 250.0, 20.0, 400.0, 5.0, "Blood", "Beheading fountain: most droplets all jets may emit in one frame."],
	["fountain_mist", 2.0, 0.0, 6.0, 1.0, "Blood", "Beheading fountain: mist puffs per jet per heartbeat."],
	["fountain_pool", 0.9, 0.0, 4.0, 0.05, "Blood", "Beheading fountain: presentation litres per second poured onto the sand under the body."],
	["fountain_head_share", 0.35, 0.0, 1.0, 0.05, "Blood", "Beheading fountain: strength of the trail from the severed head, as a share of one neck jet."],
	["fountain_size_var", 1.0, 0.0, 2.0, 0.05, "Blood", "Beheading fountain: per-drop size and speed variance (0 = every drop alike)."],
	["fountain_gout", 0.05, 0.0, 0.3, 0.01, "Blood", "Beheading fountain: chance that a drop is a big fast gout."],
	["fountain_drift", 1.0, 0.0, 3.0, 0.1, "Blood", "Beheading fountain: spray drift and wobble of the jets and the scatter of single drops."],
	["fountain_fine_mist", 14.0, 0.0, 60.0, 1.0, "Blood", "Beheading fountain: fine mist puffs per second per jet at full flow."],
	["fountain_headroom", 0.35, 0.05, 1.0, 0.05, "Blood", "Beheading fountain: the jets taper off as free droplet slots drop below this share of the pool."],
	["gore_spawn_frames", 3.0, 1.0, 6.0, 1.0, "Blood", "Gore moments: frames a burst or ground splash of droplets is spread over (same total, smoother frame time)."],
	["gut_ropes", 4.0, 0.0, 8.0, 1.0, "Blood", "Gut spill: intestine strings that slide out of a gutting or run-through at normal quality."],
	["gut_segs", 9.0, 4.0, 14.0, 1.0, "Blood", "Gut spill: points per intestine string at normal quality (low uses a third fewer)."],
	["gut_seg_len", 0.15, 0.03, 0.4, 0.005, "Blood", "Gut spill: length of one intestine link when fully paid out, m."],
	["gut_radius", 0.038, 0.01, 0.12, 0.002, "Blood", "Gut spill: thickness (radius) of the intestine sausage, m."],
	["gut_pay_time", 0.9, 0.1, 3.0, 0.05, "Blood", "Gut spill: seconds for a string to slide fully out of the wound."],
	["gut_eject", 3.4, 0.0, 8.0, 0.1, "Blood", "Gut spill: speed the guts are flung out of the wound, m/s."],
	["gut_push", 12.0, 0.0, 30.0, 0.5, "Blood", "Gut spill: acceleration that shoves the guts out while they pay out, m/s^2."],
	["gut_sway", 4.0, 0.0, 12.0, 0.5, "Blood", "Gut spill: sideways acceleration that fans neighbouring strings apart while they hang, m/s^2."],
	["gut_damp", 0.99, 0.9, 1.0, 0.005, "Blood", "Gut spill: air damping per 60th of a second on the strings and chunks."],
	["gut_friction", 0.8, 0.3, 1.0, 0.01, "Blood", "Gut spill: sideways grip on the sand per 60th of a second (lower = stops sooner)."],
	["gut_sleep_speed", 0.06, 0.01, 0.5, 0.01, "Blood", "Gut spill: a string slower than this, m/s, counts as calm."],
	["gut_sleep_time", 0.6, 0.1, 3.0, 0.1, "Blood", "Gut spill: seconds of calm before a string freezes on the sand."],
	["gut_bounce", 0.3, 0.0, 0.8, 0.05, "Blood", "Gut spill: how much an organ chunk bounces off the sand."],
	["gut_blobs", 4.0, 0.0, 10.0, 1.0, "Blood", "Gut spill: organ chunks flung out per spill at normal quality."],
	["gut_blob_radius", 0.06, 0.02, 0.15, 0.005, "Blood", "Gut spill: organ chunk size (radius), m."],
	["gut_max_ropes", 14.0, 1.0, 40.0, 1.0, "Blood", "Gut spill: most intestine strings alive at normal quality (low is half, high is double)."],
	["gut_max_blobs", 28.0, 0.0, 80.0, 1.0, "Blood", "Gut spill: most organ chunks alive at normal quality (low is half, high is double)."],
	["gut_smear", 0.12, 0.0, 0.6, 0.01, "Blood", "Gut spill: presentation litres smeared on the sand where a string or chunk first lands."],
	["gut_drip", 16.0, 0.0, 60.0, 1.0, "Blood", "Gut spill: droplets per second dripping off each hanging string tip."],
	["gut_drip_time", 5.0, 0.0, 20.0, 0.5, "Blood", "Gut spill: seconds the strings keep dripping."],
	["gut_streams", 3.0, 1.0, 8.0, 1.0, "Blood", "Gut spill: blood jets from the wound at normal quality (low uses half, high a quarter more)."],
	["gut_dur", 4.2, 1.0, 15.0, 0.1, "Blood", "Gut spill: seconds until the gush stops."],
	["gut_hold", 1.0, 0.0, 8.0, 0.1, "Blood", "Gut spill: seconds at full strength before the gush tapers."],
	["gut_rate", 1100.0, 50.0, 2000.0, 10.0, "Blood", "Gut spill: droplets per second per jet at full flow and normal quality."],
	["gut_v_scale", 0.7, 0.2, 2.0, 0.05, "Blood", "Gut spill: exit speed of the gush as a share of the beheading fountain's."],
	["gut_up_bias", 0.12, 0.0, 1.0, 0.05, "Blood", "Gut spill: how far the gush turns from the wound normal toward straight up."],
	["gut_pool", 2.2, 0.0, 6.0, 0.05, "Blood", "Gut spill: presentation litres per second poured onto the sand under the wound."],
	["gut_exit_depth", 0.3, 0.1, 0.6, 0.02, "Blood", "Run-through: how far behind the entry wound the exit wound is, m."],
	["gut_exit_streams", 3.0, 0.0, 8.0, 1.0, "Blood", "Run-through: jets from the exit wound at normal quality."],
	["gut_exit_v_scale", 1.3, 0.2, 3.0, 0.05, "Blood", "Run-through: exit-wound gush speed relative to the entry gush."],
	["gut_cluster_size", 0.13, 0.0, 0.4, 0.01, "Blood", "Gut spill: half width of the tangle of guts bulging out of the wound, m."],
	["gut_organ_points", 40.0, 0.0, 200.0, 1.0, "Blood", "Gut spill: cut or pierce points of a gutting at which whole organs fall out (a run-through always)."],
	["gut_organs", 2.0, 0.0, 2.0, 1.0, "Blood", "Gut spill: organs (liver, stomach) that fall out of a big gut wound at normal quality."],
	["gut_max_organs", 6.0, 0.0, 20.0, 1.0, "Blood", "Gut spill: most organs on the sand at normal quality (low is half, high is double)."],
	["gut_organ_eject", 1.5, 0.0, 6.0, 0.1, "Blood", "Gut spill: speed an organ slides out of the wound, m/s."],
	["gut_organ_friction", 0.92, 0.5, 1.0, 0.01, "Blood", "Gut spill: an organ's grip on the sand per 60th of a second (higher slides further)."],
	["gut_organ_smear_step", 0.12, 0.03, 1.0, 0.01, "Blood", "Gut spill: an organ sliding on the sand leaves a smear every this many metres."],
	["wound_core_scale", 1.6, 1.0, 3.0, 0.05, "Blood", "Wound marks: width multiplier on a gash's open slit and a puncture's hole, so fresh cuts read at fight-camera distance."],
	["wound_rim_glow", 0.9, 0.0, 3.0, 0.05, "Blood", "Wound marks: emission of a fresh gash's or puncture's wet rim (0 = none)."],
	["wound_rim_glow_s", 4.0, 0.0, 20.0, 0.5, "Blood", "Wound marks: seconds the rim glow takes to fade as the wound dries."],
	["wound_drop_rate", 12.0, 0.0, 60.0, 1.0, "Blood", "Body stains: blood drops landing on one fighter that leave a smear, per second (the rest merge or are lost)."],
	["wound_drop_size", 6.0, 2.0, 14.0, 0.5, "Blood", "Body stains: radius of a landed drop's smear per metre of drop radius."],
	["wound_soak_min", 2.0, 0.0, 20.0, 0.5, "Blood", "Body stains: blood points (cut + pierce + 0.3 blunt) of a bleeding hit with no gash or hole that soak a smear in."],
	["wound_stump_sev", 1.0, 0.0, 1.0, 0.05, "Blood", "Body stains: strength of the blood collar on both sides of a severed limb or neck (0 = none)."],
	["sand_depth_scale", 2.2, 0.5, 6.0, 0.1, "Sand", "Visual sand: multiplier on every footprint, furrow and body press depth (the collider stays flat)."],
	["sand_deep_from", 0.03, 0.0, 0.2, 0.005, "Sand", "Requested depth (m) beyond which a press counts as a fall and gains sand_deep_gain extra."],
	["sand_deep_gain", 1.0, 0.0, 4.0, 0.1, "Sand", "Extra depth multiplier on the part of a press beyond sand_deep_from (fall craters)."],
	["sand_max_depth", 0.2, 0.05, 0.3, 0.01, "Sand", "Deepest visual hollow, m."],
	["sand_lift", 0.03, 0.0, 0.08, 0.005, "Sand", "Visual sand surface sits this far above the flat collider, so feet stand in the sand and prints reach the floor."],
	["sand_rim_gain", 1.3, 0.5, 2.5, 0.05, "Sand", "Berm height: share of the displaced sand piled on the rim (1 conserves volume)."],
	["sand_hollow_dark", 0.55, 0.0, 1.0, 0.05, "Sand", "Shader: how much darker and damper the sand in hollows reads."],
	["sand_rim_light", 0.3, 0.0, 0.8, 0.05, "Sand", "Shader: how much lighter and drier the berm crests read."],
	["sand_step_grains", 7.0, 0.0, 40.0, 1.0, "Sand", "Grains kicked up by every footstep (high quality)."],
	["sand_step_dust", 2.0, 0.0, 12.0, 1.0, "Sand", "Dust sprites per footstep (high quality)."],
	["sand_slide_grains", 1.0, 0.0, 4.0, 0.1, "Sand", "Multiplier on grains thrown by sliding feet, rolls, dodges and dragged weapons."],
	["sand_slide_dust", 1.0, 0.0, 4.0, 0.1, "Sand", "Multiplier on dust trailing sliding feet, rolls, dodges and dragged weapons."],
	["sand_fall_grains", 130.0, 0.0, 400.0, 5.0, "Sand", "Grains thrown by a hard body fall (full impact, high quality)."],
	["sand_fall_dust", 16.0, 0.0, 80.0, 1.0, "Sand", "Dust sprites thrown by a hard body fall (full impact, high quality)."],
	["sand_strike_grains", 36.0, 0.0, 200.0, 2.0, "Sand", "Grains sprayed by a weapon strike or stab into the sand (full amount, high quality)."],
	["sand_dust_life", 3.5, 0.5, 10.0, 0.1, "Sand", "Seconds fine dust lingers."],
	["sand_dust_alpha", 0.28, 0.02, 0.6, 0.01, "Sand", "Peak opacity of one dust sprite."],
	["sand_dust_size", 0.4, 0.1, 1.5, 0.05, "Sand", "Final width (m) of a footstep dust sprite; bigger events scale up."],
]

static var _shared: Tuning = null

var gravity: float
var arena_radius: float
var move_speed: float
var sprint_speed: float
var arm_force: float
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
var stand_height: float
var crouch_height: float
var support_freq: float
var support_max: float
var balance_freq: float
var balance_torque: float
var torso_assist: float
var move_accel: float
var move_response: float
var turn_rate: float
var joint_strength: float
var joint_damping: float
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
var half_sword_thrust: float
var torso_twist: float
var stumble_tilt: float
var fall_tilt: float
var stagger_down: float
var stagger_recover: float
var down_time: float
var getup_time: float
var down_strength: float
var limp_strength: float
var stamina_floor: float
var limb_floor: float
var weapon_drop_hp: float
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
var shove_time: float
var shove_stamina: float
var shove_cooldown: float
var shove_reach: float
var shove_force_frac: float
var shove_contact: float
var shove_impulse: float
var shove_stagger: float
var shove_stagger_off: float
var shove_recoil: float
var shove_lunge: float
var kick_time: float
var kick_stamina: float
var kick_cooldown: float
var kick_reach: float
var kick_height: float
var kick_chamber: float
var kick_lunge: float
var kick_force: float
var kick_mass: float
var kick_push: float
var kick_miss_stagger: float
var kick_stagger_take: float
var kick_lean_back: float
var clinch_time: float
var clinch_latch: float
var clinch_slack: float
var clinch_pull: float
var clinch_break_dist: float
var clinch_max: float
var clinch_stamina: float
var clinch_cooldown: float
var clinch_pin: float
var clinch_head_balance: float
var clinch_struggle: float
var clinch_pull_side: float
var clinch_pull_down: float
var clinch_head_down: float
var clinch_pull_step: float
var clinch_pull_force_frac: float
var clinch_twist: float
var clinch_break_min_speed: float
var pelvis_inertia: float
var torso_inertia: float
var balance_inertia: float
var leg_reaction: float
var pd_margin: float
var self_hit_min_speed: float
var dmg_disarm_weapon: float
var dmg_disarm_fist: float
var dmg_disarm_forearm_gain: float
var self_hit_grace_s: float
var finisher_consc: float
var hold_freq: float
var guard_hand_speed: float
var swing_hand_speed: float
var offhand_hand_speed: float
var hit_debounce: float
var grab_radius: float
var arm_exertion: float
var reach_height: float
var reach_pitch: float
var reach_bend: float
var reach_time: float
var reach_hold: float
var reach_scan: float
var reach_hand_lift: float
var reach_hand_speed: float
var reach_foot_fwd: float
var knockback_scale: float
var match_pause_s: float
var match_slowmo_scale: float
var match_slowmo_s: float
var intro_s: float
var intro_fight_s: float
var combo_gap_s: float
var combo_merge_s: float
var killcam_on: float
var killcam_buffer_s: float
var killcam_lead_s: float
var killcam_tail_s: float
var killcam_slow_rate: float
var killcam_slow_pre_s: float
var killcam_slow_post_s: float
var killcam_tail_rate: float
var killcam_ramp_s: float
var feel_shake_scale: float
var feel_impact_energy_ref: float
var feel_impact_total_ref: float
var feel_shake_min: float
var feel_kick_m: float
var feel_kick_freq: float
var feel_shake_m: float
var feel_shake_roll_deg: float
var feel_shake_decay: float
var feel_zoom_deg: float
var feel_zoom_hit_deg: float
var feel_zoom_decay: float
var feel_flash_s: float
var sand_depth_scale: float
var sand_deep_from: float
var sand_deep_gain: float
var sand_max_depth: float
var sand_lift: float
var sand_rim_gain: float
var sand_hollow_dark: float
var sand_rim_light: float
var sand_step_grains: float
var sand_step_dust: float
var sand_slide_grains: float
var sand_slide_dust: float
var sand_fall_grains: float
var sand_fall_dust: float
var sand_strike_grains: float
var sand_dust_life: float
var sand_dust_alpha: float
var sand_dust_size: float
var feel_flash_min: float
var feel_spark_max: float
var feel_spark_min: float
var feel_rumble_scale: float
var feel_rumble_s: float
var feel_rumble_min: float
var feel_hitstop_min: float
var feel_hitstop_light_s: float
var feel_hitstop_heavy_s: float
var feel_hitstop_sever_s: float
var feel_hitstop_finisher_s: float
var feel_hitstop_clash_mult: float
var feel_hitstop_rate: float
var feel_hitstop_catchup: float
var feel_hitstop_lag_max: float
var feel_hitstop_budget_s: float
var feel_hitstop_budget_tau: float
var feel_punch_min: float
var feel_punch_s: float
var feel_punch_blur: float
var feel_punch_chroma: float
var feel_punch_flash: float
var feel_cine_scale: float
var feel_cine_hold_s: float
var feel_cine_ramp_s: float
var feel_cine_lpf_hz: float
var feel_cine_bass_db: float
var feel_bass_min: float
var aim_trail_s: float
var aim_alpha: float
var aim_lost_delay_s: float
var practice_half_gap: float
var feel_frame_pull_max: float
var feel_frame_margin: float
var feel_close_shoulder: float
var feel_close_height: float
var feel_close_near: float
var feel_close_far: float
var feel_finale_hold_s: float
var feel_finale_ease_s: float
var feel_finale_release_s: float
var feel_finale_dist: float
var feel_finale_height: float
var feel_finale_look_y: float
var feel_finale_head_bias0: float
var feel_finale_head_bias1: float
var feel_finale_head_s: float
var feel_finale_head_reach: float
var feel_finale_dist_max: float
var feel_finale_high: float
var feel_prime_ticks: float
var blood_faint: float
var health_head_ko: float
var health_stagger_ko: float
var health_clot: float
var health_consc_recover: float
var health_concuss_gain: float
var health_concuss_hit_max: float
var health_concuss_decay: float
var health_concuss_cap: float
var health_concuss_stun: float
var health_concuss_amp: float
var health_nose_bleed: float
var health_stamina_recover: float
var health_stamina_drain: float
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
var fountain_streams: float
var fountain_dur: float
var fountain_hold: float
var fountain_bpm: float
var fountain_pulse_floor: float
var fountain_rate: float
var fountain_v_min: float
var fountain_v_max: float
var fountain_up_bias: float
var fountain_fan: float
var fountain_wobble: float
var fountain_swirl: float
var fountain_drop_scale: float
var fountain_gush: float
var fountain_emit_cap: float
var fountain_mist: float
var fountain_pool: float
var fountain_head_share: float
var fountain_headroom: float
var fountain_size_var: float
var fountain_gout: float
var fountain_drift: float
var fountain_fine_mist: float
var gore_spawn_frames: float
var gut_ropes: float
var gut_segs: float
var gut_seg_len: float
var gut_radius: float
var gut_pay_time: float
var gut_eject: float
var gut_push: float
var gut_sway: float
var gut_damp: float
var gut_friction: float
var gut_sleep_speed: float
var gut_sleep_time: float
var gut_bounce: float
var gut_blobs: float
var gut_blob_radius: float
var gut_max_ropes: float
var gut_max_blobs: float
var gut_smear: float
var gut_drip: float
var gut_drip_time: float
var gut_streams: float
var gut_dur: float
var gut_hold: float
var gut_rate: float
var gut_v_scale: float
var gut_up_bias: float
var gut_pool: float
var gut_exit_depth: float
var gut_exit_streams: float
var gut_exit_v_scale: float
var gut_cluster_size: float
var gut_organ_points: float
var gut_organs: float
var gut_max_organs: float
var gut_organ_eject: float
var gut_organ_friction: float
var gut_organ_smear_step: float
var wound_core_scale: float
var wound_rim_glow: float
var wound_rim_glow_s: float
var wound_drop_rate: float
var wound_drop_size: float
var wound_soak_min: float
var wound_stump_sev: float


func _init() -> void:
	reset()


## The tuning the game uses unless it is given its own. A tuning panel edits this one.
static func shared() -> Tuning:
	if _shared == null:
		_shared = Tuning.new()
	return _shared


static func field_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in FIELDS:
		out.append(f[0])
	return out


static func field_info(field: String) -> Dictionary:
	for f: Array in FIELDS:
		if f[0] == field:
			return {"name": f[0], "default": f[1], "min": f[2], "max": f[3], "step": f[4], "group": f[5], "doc": f[6]}
	return {}


func reset() -> void:
	for f: Array in FIELDS:
		set(f[0], float(f[1]))


## Sets one field, clamped to its range. Returns false for an unknown field.
func set_value(field: String, value: float) -> bool:
	var info: Dictionary = field_info(field)
	if info.is_empty():
		return false
	var v: float = clampf(value, float(info["min"]), float(info["max"]))
	set(field, v)
	changed.emit(field, v)
	return true


func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		d[f[0]] = get(f[0])
	return d


## Applies known keys from `d` (others are ignored). Returns the number of fields applied.
func apply_dict(d: Dictionary) -> int:
	var n: int = 0
	for key: Variant in d:
		if set_value(str(key), float(d[key])):
			n += 1
	return n


## Only the fields that differ from the defaults: what a preset needs to store.
func diff_from_defaults() -> Dictionary:
	var d: Dictionary = {}
	for f: Array in FIELDS:
		if not is_equal_approx(float(get(f[0])), float(f[1])):
			d[f[0]] = get(f[0])
	return d


func copy_from(other: Tuning) -> void:
	apply_dict(other.to_dict())


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t", false))
	return OK


## Loads a preset file over the current values. Returns false if the file is missing or not a JSON object.
func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	apply_dict(parsed)
	return true
