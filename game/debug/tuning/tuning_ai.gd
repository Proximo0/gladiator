extends "res://game/debug/tuning/tuning_wounds.gd"
## Tuning rows of the "AI" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_AI and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_AI: Array = [
	["ai_thrust_lead", 0.2, 0.0, 0.5, 0.01, "AI", "CPU thrust: THRUST is punched out when the point is this long from the target at the closing speed, s."],
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
	["ai_close_roll_chance", 0.02, 0.0, 0.05, 0.001, "AI", "CPU closing plan: chance per tick of a forward roll in under a longer weapon (with stamina to spare)."],
	["ai_close_rush_ticks", 40.0, 0.0, 120.0, 1.0, "AI", "CPU closing plan: how long an opening (the foe swung, had a blow parried, stumbles) keeps the way in open, ticks."],
	["ai_close_press_ticks", 240.0, 0.0, 600.0, 10.0, "AI", "CPU closing plan: once a rush gets inside, how long the short weapon keeps pressing in (no backing out), ticks."],
	["ai_close_press_frac", 0.7, 0.3, 1.0, 0.05, "AI", "CPU closing plan: while pressing, the standing distance as a share of my own reach."],
	["ai_close_point_frac", 0.55, 0.2, 1.0, 0.05, "AI", "CPU closing plan: closer than this share of the foe's reach I am inside his point (shove him, step in)."],
	["ai_close_shove_chance", 0.03, 0.0, 0.2, 0.005, "AI", "CPU closing plan: chance per tick of a shove while pressing inside the foe's point."],
	["ai_close_rest_gap", 0.1, 0.0, 0.5, 0.05, "AI", "CPU closing plan: outreached and behind on blood, a winded fighter rests only to this much past its retreat stamina (else 0.3)."],
	["ai_chase_away", 0.8, 0.0, 4.0, 0.05, "AI", "CPU chase gait: the foe backing off faster than this (m/s) is chased at a sprint."],
	["ai_chase_stamina", 0.3, 0.0, 1.0, 0.05, "AI", "CPU chase gait: only with more stamina than this."],
]

var ai_thrust_lead: float
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
var ai_close_rush_ticks: float
var ai_close_press_ticks: float
var ai_close_press_frac: float
var ai_close_point_frac: float
var ai_close_shove_chance: float
var ai_chase_away: float
var ai_chase_stamina: float
var ai_close_rest_gap: float
