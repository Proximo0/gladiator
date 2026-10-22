extends "res://game/debug/tuning/tuning_roll.gd"
## Tuning rows of the "Close" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_CLOSE and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_CLOSE: Array = [
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
]

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
var clinch_break_min_speed: float
var clinch_twist: float
