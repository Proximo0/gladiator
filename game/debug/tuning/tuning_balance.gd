extends "res://game/debug/tuning/tuning_fighter.gd"
## Tuning rows of the "Balance" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_BALANCE and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_BALANCE: Array = [
	["stumble_tilt", 0.35, 0.1, 1.0, 0.01, "Balance", "Tilt where standing turns to stumbling, rad."],
	["fall_tilt", 1.0, 0.4, 1.5, 0.05, "Balance", "Tilt where the fighter goes down, rad."],
	["stagger_down", 0.85, 0.2, 1.5, 0.05, "Balance", "Stagger level that knocks the fighter down."],
	["stagger_recover", 0.8, 0.1, 3.0, 0.05, "Balance", "Stagger recovered per second."],
	["down_time", 1.5, 0.2, 5.0, 0.1, "Balance", "Time spent down before getting up, s."],
	["getup_time", 1.4, 0.3, 4.0, 0.1, "Balance", "Duration of getting up, s."],
	["down_strength", 0.3, 0.0, 1.0, 0.05, "Balance", "Joint strength while down."],
	["limp_strength", 0.04, 0.0, 0.3, 0.01, "Balance", "Joint strength when KO or dead."],
]

var stumble_tilt: float
var fall_tilt: float
var stagger_down: float
var stagger_recover: float
var down_time: float
var getup_time: float
var down_strength: float
var limp_strength: float
