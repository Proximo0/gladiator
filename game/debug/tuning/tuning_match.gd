extends "res://game/debug/tuning/tuning_health.gd"
## Tuning rows of the "Match" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_MATCH and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_MATCH: Array = [
	["match_pause_s", 4.0, 1.0, 15.0, 0.5, "Match", "Pause after a match before the next bot match starts, s."],
	["match_slowmo_scale", 0.4, 0.1, 1.0, 0.05, "Match", "Time scale during the finisher slow motion."],
	["match_slowmo_s", 1.0, 0.0, 5.0, 0.1, "Match", "Length of the finisher slow motion, game seconds."],
	["intro_s", 2.3, 0.0, 8.0, 0.1, "Match", "Pre-fight intro: name plates up and fighters held before FIGHT!, s (0 = no intro)."],
	["intro_fight_s", 0.8, 0.2, 3.0, 0.1, "Match", "FIGHT! stinger on screen (the fighters are free from its first frame), s."],
	["combo_gap_s", 1.5, 0.3, 5.0, 0.1, "Match", "Results' longest combo: most time between one fighter's blows with no blow back, s."],
	["combo_merge_s", 0.15, 0.0, 0.5, 0.01, "Match", "Results: contacts closer than this to the last blow are the same swing, s."],
]

var match_pause_s: float
var match_slowmo_scale: float
var match_slowmo_s: float
var intro_s: float
var intro_fight_s: float
var combo_gap_s: float
var combo_merge_s: float
