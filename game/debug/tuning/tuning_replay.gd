extends "res://game/debug/tuning/tuning_match.gd"
## Tuning rows of the "Replay" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_REPLAY and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_REPLAY: Array = [
	["killcam_on", 1.0, 0.0, 1.0, 1.0, "Replay", "1 = instant replay of the finishing blow before the result panel, 0 = off."],
	["killcam_buffer_s", 8.0, 5.0, 20.0, 0.5, "Replay", "Seconds of shown fight kept for the replay (ring buffer)."],
	["killcam_lead_s", 3.5, 1.0, 6.0, 0.1, "Replay", "Game seconds replayed before the killing blow."],
	["killcam_tail_s", 1.6, 0.3, 3.0, 0.1, "Replay", "Game seconds replayed after the killing blow."],
	["killcam_slow_rate", 0.25, 0.05, 1.0, 0.05, "Replay", "Playback speed of the slow motion at the impact."],
	["killcam_slow_pre_s", 0.2, 0.0, 1.0, 0.05, "Replay", "Game seconds of slow motion before the impact."],
	["killcam_slow_post_s", 0.5, 0.1, 2.0, 0.05, "Replay", "Game seconds of slow motion after the impact."],
	["killcam_tail_rate", 0.6, 0.1, 1.0, 0.05, "Replay", "Playback speed after the slow motion."],
	["killcam_ramp_s", 0.25, 0.05, 1.0, 0.05, "Replay", "Game seconds the speed takes to ease in and out of slow motion."],
]

var killcam_on: float
var killcam_buffer_s: float
var killcam_lead_s: float
var killcam_tail_s: float
var killcam_slow_rate: float
var killcam_slow_pre_s: float
var killcam_slow_post_s: float
var killcam_tail_rate: float
var killcam_ramp_s: float
