extends "res://game/debug/tuning/tuning_stability.gd"
## Tuning rows of the "Health" group: one link of the chain that `Tuning` (game/debug/tuning.gd) extends, so each
## group's rows and vars live in their own file and branches that tune different systems never touch the same file.
## Add a field: a row in ROWS_HEALTH and a matching `var` below. Row format: [field, default, min, max, step, group, doc].

const ROWS_HEALTH: Array = [
	["arm_exertion", 0.7, 0.0, 1.0, 0.05, "Health", "Stamina cost of arm force, as a share of the fresh arm's cap (force used x strength)."],
	["blood_faint", 3.5, 2.6, 5.0, 0.1, "Health", "Blood (L) below which consciousness is capped; zero at blood_death."],
	["health_head_ko", 0.04, 0.0, 0.2, 0.005, "Health", "Consciousness lost per blunt point on the head (0.04: a solid club blow dazes into the finisher window, only a huge one knocks out)."],
	["health_stagger_ko", 0.05, 0.0, 0.5, 0.01, "Health", "Consciousness lost per unit of stagger on any part."],
	["health_clot", 0.02, 0.0, 0.5, 0.005, "Health", "Bleed rate decay per second (clotting)."],
	["health_concuss_gain", 0.12, 0.0, 0.3, 0.005, "Health", "Concussion added per blunt point on the head (a fist blow is about 2-3 points)."],
	["health_concuss_hit_max", 0.25, 0.0, 1.0, 0.05, "Health", "Most concussion one head blow adds, so a club does not stun in one hit."],
	["health_concuss_decay", 0.004, 0.0, 0.2, 0.005, "Health", "Concussion fading per second (slow: a long brawl accumulates)."],
	["health_concuss_cap", 0.8, 0.0, 1.0, 0.05, "Health", "Consciousness ceiling falls by this much at full concussion (weak limbs while stunned)."],
	["health_concuss_stun", 0.3, 0.0, 1.0, 0.05, "Health", "Concussion at which a fighter counts as stunned."],
	["health_concuss_amp", 3.0, 0.0, 6.0, 0.1, "Health", "Head consciousness loss is multiplied by 1 + this x concussion (a stunned head knocks out easily)."],
	["health_nose_bleed", 0.0006, 0.0, 0.01, 0.0001, "Health", "Bleed rate (L/s) per blunt point on the head: bloody nose and mouth."],
	["health_consc_recover", 0.03, 0.0, 0.5, 0.005, "Health", "Consciousness recovery per second."],
	["health_stamina_recover", 0.2, 0.0, 1.0, 0.01, "Health", "Stamina recovered per second at rest."],
	["health_stamina_drain", 0.3, 0.0, 1.0, 0.01, "Health", "Stamina drained per second at full exertion."],
]

var arm_exertion: float
var blood_faint: float
var health_head_ko: float
var health_stagger_ko: float
var health_clot: float
var health_concuss_gain: float
var health_concuss_hit_max: float
var health_concuss_decay: float
var health_concuss_cap: float
var health_concuss_stun: float
var health_concuss_amp: float
var health_nose_bleed: float
var health_consc_recover: float
var health_stamina_recover: float
var health_stamina_drain: float
