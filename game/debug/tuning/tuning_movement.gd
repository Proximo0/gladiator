extends "res://game/debug/tuning/tuning_world.gd"
## Tuning rows of the "Movement" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_MOVEMENT and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_MOVEMENT: Array = [
	["move_speed", 2.5, 0.5, 8.0, 0.1, "Movement", "Walk speed on sand, m/s."],
	["sprint_speed", 4.5, 1.0, 10.0, 0.1, "Movement", "Sprint speed on sand, m/s."],
	["move_accel", 9.0, 1.0, 30.0, 0.5, "Movement", "Max horizontal acceleration while moving, m/s²."],
	["move_response", 7.0, 1.0, 20.0, 0.5, "Movement", "How fast the body velocity follows the move input, 1/s."],
	["turn_rate", 6.0, 1.0, 20.0, 0.5, "Movement", "Max turn rate toward the opponent, rad/s."],
	["hold_freq", 2.0, 0.0, 6.0, 0.1, "Movement", "Idle position hold stiffness (stops drift), rad/s."],
	["hold_slack", 0.3, 0.05, 2.0, 0.05, "Movement", "Idle position hold: a body knocked farther than this from its spot re-anchors this far from where it is (it does not walk back), m."],
]

var move_speed: float
var sprint_speed: float
var move_accel: float
var move_response: float
var turn_rate: float
var hold_freq: float
var hold_slack: float
