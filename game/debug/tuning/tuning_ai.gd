extends "res://game/debug/tuning/tuning_wounds.gd"
## Tuning rows of the "AI" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_AI and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_AI: Array = [
	["ai_thrust_lead", 0.2, 0.0, 0.5, 0.01, "AI", "CPU thrust: THRUST is punched out when the point is this long from the target at the closing speed, s."],
	["ai_spear_thrust_lead", 0.5, 0.0, 1.0, 0.01, "AI", "CPU spear: THRUST (and the hip lunge) starts when the point is this long from the target at the closing speed, s."],
	["ai_thrust_near", 0.45, 0.0, 1.0, 0.01, "AI", "CPU thrust: THRUST goes at the latest when the point is this close to the target, m."],
	["ai_thrust_hit_d", 0.1, 0.0, 0.5, 0.01, "AI", "CPU thrust: the drive ends when the point is this close to the target (it arrived), m."],
	["ai_thrust_past_d", 0.25, 0.05, 1.0, 0.01, "AI", "CPU thrust: the drive ends when the point is this much farther than its closest (it went past), m."],
	["ai_spear_drive_max", 4.3, 2.5, 5.0, 0.05, "AI", "CPU spear: a drive starts only inside this distance (pelvis to pelvis), m."],
	["ai_spear_hold_min", 3.6, 2.5, 5.0, 0.05, "AI", "CPU spear: near end of the standing band the point is held at (room for a run-up), m."],
	["ai_spear_hold_max", 4.0, 2.5, 5.0, 0.05, "AI", "CPU spear: far end of the standing band, m."],
	["ai_spear_set_ticks", 30.0, 2.0, 90.0, 1.0, "AI", "CPU spear: longest set (the point brought onto the chest before the drive), ticks."],
	["ai_spear_drive_ticks", 40.0, 10.0, 90.0, 1.0, "AI", "CPU spear: longest drive (the run-in that carries the point), ticks."],
	["ai_stop_thrust_closing", 1.2, 0.0, 5.0, 0.1, "AI", "CPU spear: a foe stepping in faster than this is met with a thrust at once (a stop thrust), m/s."],
	["ai_sword_set_ticks", 14.0, 2.0, 40.0, 1.0, "AI", "CPU sword thrust: longest set (the point brought onto the target before the drive), ticks."],
	["ai_sword_drive_ticks", 36.0, 6.0, 60.0, 1.0, "AI", "CPU sword thrust: longest drive (the step in), ticks."],
	["ai_square_cos", 0.8, 0.0, 1.0, 0.01, "AI", "CPU sword thrust: the foe counts as square-on when his facing is within this cosine of the line to me."],
	["ai_square_thrust_mult", 2.5, 1.0, 8.0, 0.1, "AI", "CPU sword thrust: thrust weight multiplier against a square-on foe."],
	["ai_close_margin", 0.25, 0.0, 2.0, 0.05, "AI", "CPU closing plan: the foe's reach must beat mine by this much before a short weapon plans its way in, m."],
	["ai_close_band", 0.5, 0.0, 2.0, 0.05, "AI", "CPU closing plan: distance past the foe's reach that still counts as at his range, m."],
	["ai_close_wait_gap", 0.35, 0.0, 1.5, 0.05, "AI", "CPU closing plan: how far outside the longer weapon's reach a shorter one stands off while it waits, m."],
	["ai_bait_cycle", 150.0, 30.0, 400.0, 5.0, "AI", "CPU reach plan: length of one bait cycle of an outreached fighter waiting outside the longer blade, ticks."],
	["ai_bait_in_start", 90.0, 0.0, 400.0, 5.0, "AI", "CPU reach plan: tick of the cycle at which the bait steps inside the foe's reach."],
	["ai_bait_in_len", 35.0, 0.0, 200.0, 5.0, "AI", "CPU reach plan: ticks the bait stays inside the foe's reach before falling back out."],
	["ai_bait_depth", 0.25, 0.0, 0.8, 0.05, "AI", "CPU reach plan: how far inside the foe's reach the bait steps, m."],
	["ai_reach_low_mult", 3.0, 1.0, 8.0, 0.1, "AI", "CPU reach plan: weight multiplier of the low cut for a fighter outreached by the foe's blade (the legs sit under a high guard)."],
	["ai_holder_min_length", 1.2, 0.5, 2.0, 0.05, "AI", "CPU reach plan: a two-handed sword at least this long (data length) counts as the long blade that over-commits."],
	["ai_overcommit_chance", 0.1, 0.0, 1.0, 0.05, "AI", "CPU reach plan: chance that a swing of the long blade is an over-commit (a lunge and a long recovery)."],
	["ai_overcommit_recover", 1.8, 1.0, 4.0, 0.1, "AI", "CPU reach plan: recovery time multiplier after an over-commit."],
	["ai_holder_wait_mult", 4.0, 1.0, 4.0, 0.1, "AI", "CPU reach plan: the long two-handed blade waits this many times longer between attacks (it holds the reach instead of pressing)."],
	["ai_close_roll_chance", 0.02, 0.0, 0.05, 0.001, "AI", "CPU closing plan: chance per tick of a forward roll in under a longer weapon (with stamina to spare)."],
]

var ai_thrust_lead: float
var ai_spear_thrust_lead: float
var ai_thrust_near: float
var ai_thrust_hit_d: float
var ai_thrust_past_d: float
var ai_spear_drive_max: float
var ai_spear_hold_min: float
var ai_spear_hold_max: float
var ai_spear_set_ticks: float
var ai_spear_drive_ticks: float
var ai_stop_thrust_closing: float
var ai_sword_set_ticks: float
var ai_sword_drive_ticks: float
var ai_square_cos: float
var ai_square_thrust_mult: float
var ai_close_margin: float
var ai_close_band: float
var ai_close_wait_gap: float
var ai_close_roll_chance: float
var ai_holder_wait_mult: float
var ai_bait_cycle: float
var ai_bait_in_start: float
var ai_bait_in_len: float
var ai_bait_depth: float
var ai_reach_low_mult: float
var ai_holder_min_length: float
var ai_overcommit_chance: float
var ai_overcommit_recover: float
