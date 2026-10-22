extends RefCounted
## Tuning rows of the "World" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_WORLD and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_WORLD: Array = [
	["gravity", 9.8, 5.0, 30.0, 0.1, "World", "Gravity, m/s². Real is 9.8."],
	["arena_radius", 11.0, 6.0, 20.0, 0.5, "World", "Radius of the arena wall, m."],
	["practice_half_gap", 1.75, 0.8, 4.0, 0.05, "World", "Practice only: each fighter's spawn distance from the centre, m (the dummy starts twice this away)."],
]

var gravity: float
var arena_radius: float
var practice_half_gap: float
