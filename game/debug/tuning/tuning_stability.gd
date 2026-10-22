extends "res://game/debug/tuning/tuning_close.gd"
## Tuning rows of the "Stability" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_STABILITY and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_STABILITY: Array = [
	["pelvis_inertia", 2.0, 1.0, 5.0, 0.1, "Stability", "Pelvis inertia boost for stable PD."],
	["torso_inertia", 2.5, 1.0, 5.0, 0.1, "Stability", "Torso inertia boost for stable PD."],
	["balance_inertia", 3.0, 0.5, 8.0, 0.1, "Stability", "Inertia the upright controller gains assume, kg·m²."],
	["leg_reaction", 0.25, 0.0, 1.0, 0.05, "Stability", "Share of leg joint reaction put on the pelvis."],
	["pd_margin", 0.5, 0.1, 1.5, 0.05, "Stability", "Damping-rate margin for explicit PD (below 2 is stable)."],
]

var pelvis_inertia: float
var torso_inertia: float
var balance_inertia: float
var leg_reaction: float
var pd_margin: float
