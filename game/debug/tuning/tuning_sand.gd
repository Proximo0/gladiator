extends "res://game/debug/tuning/tuning_blood.gd"
## Tuning rows of the "Sand" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_SAND and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_SAND: Array = [
	["sand_depth_scale", 2.2, 0.5, 6.0, 0.1, "Sand", "Visual sand: multiplier on every footprint, furrow and body press depth (the collider stays flat)."],
	["sand_deep_from", 0.03, 0.0, 0.2, 0.005, "Sand", "Requested depth (m) beyond which a press counts as a fall and gains sand_deep_gain extra."],
	["sand_deep_gain", 1.0, 0.0, 4.0, 0.1, "Sand", "Extra depth multiplier on the part of a press beyond sand_deep_from (fall craters)."],
	["sand_max_depth", 0.2, 0.05, 0.3, 0.01, "Sand", "Deepest visual hollow, m."],
	["sand_lift", 0.03, 0.0, 0.08, 0.005, "Sand", "Visual sand surface sits this far above the flat collider, so feet stand in the sand and prints reach the floor."],
	["sand_rim_gain", 1.3, 0.5, 2.5, 0.05, "Sand", "Berm height: share of the displaced sand piled on the rim (1 conserves volume)."],
	["sand_hollow_dark", 0.55, 0.0, 1.0, 0.05, "Sand", "Shader: how much darker and damper the sand in hollows reads."],
	["sand_rim_light", 0.3, 0.0, 0.8, 0.05, "Sand", "Shader: how much lighter and drier the berm crests read."],
	["sand_step_grains", 7.0, 0.0, 40.0, 1.0, "Sand", "Grains kicked up by every footstep (high quality)."],
	["sand_step_dust", 2.0, 0.0, 12.0, 1.0, "Sand", "Dust sprites per footstep (high quality)."],
	["sand_slide_grains", 1.0, 0.0, 4.0, 0.1, "Sand", "Multiplier on grains thrown by sliding feet, rolls, dodges and dragged weapons."],
	["sand_slide_dust", 1.0, 0.0, 4.0, 0.1, "Sand", "Multiplier on dust trailing sliding feet, rolls, dodges and dragged weapons."],
	["sand_fall_grains", 130.0, 0.0, 400.0, 5.0, "Sand", "Grains thrown by a hard body fall (full impact, high quality)."],
	["sand_fall_dust", 16.0, 0.0, 80.0, 1.0, "Sand", "Dust sprites thrown by a hard body fall (full impact, high quality)."],
	["sand_strike_grains", 36.0, 0.0, 200.0, 2.0, "Sand", "Grains sprayed by a weapon strike or stab into the sand (full amount, high quality)."],
	["sand_dust_life", 3.5, 0.5, 10.0, 0.1, "Sand", "Seconds fine dust lingers."],
	["sand_dust_alpha", 0.28, 0.02, 0.6, 0.01, "Sand", "Peak opacity of one dust sprite."],
	["sand_dust_size", 0.4, 0.1, 1.5, 0.05, "Sand", "Final width (m) of a footstep dust sprite; bigger events scale up."],
	["sand_contact_dark", 0.6, 0.0, 0.9, 0.05, "Sand", "Contact shadow: peak darkening of the sand under a planted foot (0 turns the foot blobs off)."],
	["sand_contact_foot_r", 0.2, 0.05, 0.4, 0.01, "Sand", "Contact shadow: radius of a planted foot's dark blob, m."],
	["sand_contact_foot_h", 0.3, 0.05, 1.0, 0.01, "Sand", "Contact shadow: height above its rest at which a lifted foot's blob has faded out, m."],
	["sand_contact_foot_rest", 0.05, 0.0, 0.15, 0.005, "Sand", "Contact shadow: foot-box centre height of a planted foot (blob at full strength), m."],
	["sand_contact_body_dark", 0.5, 0.0, 0.9, 0.05, "Sand", "Contact shadow: peak darkening under the pelvis at the sand (standing fighters get a faint wide pool)."],
	["sand_contact_body_r", 0.5, 0.1, 1.0, 0.01, "Sand", "Contact shadow: radius of the blob under the pelvis at the sand, m."],
	["sand_contact_body_h", 1.6, 0.3, 3.0, 0.05, "Sand", "Contact shadow: pelvis height at which its blob has faded out, m."],
	["sand_contact_spread", 0.8, 0.0, 3.0, 0.05, "Sand", "Contact shadow: blob radius growth per metre its part is above the sand."],
]

var sand_depth_scale: float
var sand_deep_from: float
var sand_deep_gain: float
var sand_max_depth: float
var sand_lift: float
var sand_rim_gain: float
var sand_hollow_dark: float
var sand_rim_light: float
var sand_step_grains: float
var sand_step_dust: float
var sand_slide_grains: float
var sand_slide_dust: float
var sand_fall_grains: float
var sand_fall_dust: float
var sand_strike_grains: float
var sand_dust_life: float
var sand_dust_alpha: float
var sand_dust_size: float
var sand_contact_dark: float
var sand_contact_foot_r: float
var sand_contact_foot_h: float
var sand_contact_foot_rest: float
var sand_contact_body_dark: float
var sand_contact_body_r: float
var sand_contact_body_h: float
var sand_contact_spread: float
