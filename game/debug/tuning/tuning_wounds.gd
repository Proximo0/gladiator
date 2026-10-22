extends "res://game/debug/tuning/tuning_sand.gd"
## Tuning rows of the "Wounds" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_WOUNDS and a matching `var` below. Row format: [field, default, min, max, step, group, doc].
## (The older wound rows, wound_core_scale .. wound_stump_sev, live in the Blood group.)

const ROWS_WOUNDS: Array = [
	["wound_smear_lobe", 0.26, 0.0, 0.5, 0.01, "Wounds", "Wound marks: how far a blood smear's outline bulges in and out (a few soft lobes; high values read as a star)."],
	["wound_smear_drops", 0.35, 0.0, 1.0, 0.05, "Wounds", "Wound marks: share of a smear's edge cells that hold a satellite drop (0 = a clean blot)."],
	["wound_ring_band", 0.06, 0.01, 0.2, 0.005, "Wounds", "Sever ring: height of the wet blood band round a stump and the cut end of a severed part, m."],
	["wound_ring_glow", 1.4, 0.0, 4.0, 0.05, "Wounds", "Sever ring: emission of the band's fresh wet blood, so a stump reads at fight-camera distance."],
	["wound_ring_glow_s", 12.0, 0.0, 60.0, 0.5, "Wounds", "Sever ring: seconds the band's glow takes to fade (a stump keeps bleeding longer than a cut)."],
]

var wound_smear_lobe: float
var wound_smear_drops: float
var wound_ring_band: float
var wound_ring_glow: float
var wound_ring_glow_s: float
