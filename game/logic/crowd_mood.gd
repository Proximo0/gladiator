class_name CrowdMood
extends RefCounted
## Crowd excitement as the stands show it (pure). A target level (from SfxDirector's crowd excitement) plus short
## reaction pulses; the shown level rises fast and falls slowly so the stands erupt on a hit and sit down gradually.

const RISE_RATE: float = 2.5
const FALL_RATE: float = 0.3
const PULSE_DECAY: float = 0.45
const PULSES: Dictionary = {"gasp": 0.2, "boo": 0.1, "cheer": 0.5, "roar": 0.8, "finisher": 1.0}
const CHEER_THRESHOLD_MIN: float = 0.18
const CHEER_THRESHOLD_MAX: float = 0.92
const STAND_CALM: PackedStringArray = ["stand_idle", "stand_idle", "stand_point", "stand_thumbs"]
const STAND_CALM_F: PackedStringArray = ["stand_idle_f"]
const STAND_CHEER: PackedStringArray = ["stand_cheer_one_arm", "stand_cheer_both_arms", "stand_fist_pump"]
const STAND_CHEER_F: PackedStringArray = ["stand_cheer_f"]
const SEATED: PackedStringArray = ["sit_idle", "sit_idle", "sit_lean"]
const NOBLE: String = "noble_sit"
const ALL_VARIANTS: PackedStringArray = [
	"stand_idle", "stand_point", "stand_thumbs", "stand_idle_f", "stand_cheer_one_arm", "stand_cheer_both_arms",
	"stand_fist_pump", "stand_cheer_f", "sit_idle", "sit_lean", "noble_sit",
]

var target: float = 0.0
var pulse: float = 0.0
var level: float = 0.0


func set_target(x: float) -> void:
	target = clampf(x, 0.0, 1.0)


## A crowd reaction ("gasp", "cheer", "roar", "finisher", "boo") kicks the shown level up for a moment.
func react(kind: String) -> void:
	pulse = maxf(pulse, float(PULSES.get(kind, 0.0)))


func tick(delta: float) -> void:
	var goal: float = maxf(target, pulse)
	if goal > level:
		level = minf(goal, level + RISE_RATE * delta)
	else:
		level = maxf(goal, level - FALL_RATE * delta)
	pulse = maxf(0.0, pulse - PULSE_DECAY * delta)


## Whether the cheering twin of a seat is shown at excitement `e` (the calm twin is shown exactly when this is false).
static func cheering(e: float, threshold: float) -> bool:
	return e >= threshold + 0.0001


## Variant names for one spectator: [calm, cheer]; cheer is "" when the spectator never stands up to cheer.
static func pick_variants(seated: bool, female: bool, r: float) -> PackedStringArray:
	if seated:
		return PackedStringArray([SEATED[mini(int(r * float(SEATED.size())), SEATED.size() - 1)], ""])
	if female:
		return PackedStringArray([STAND_CALM_F[0], STAND_CHEER_F[0]])
	var i: int = mini(int(r * float(STAND_CALM.size())), STAND_CALM.size() - 1)
	var j: int = mini(int(fposmod(r * 97.0, 1.0) * float(STAND_CHEER.size())), STAND_CHEER.size() - 1)
	return PackedStringArray([STAND_CALM[i], STAND_CHEER[j]])


## Per-spectator look and timing all derive from one small integer seed (it rides in INSTANCE_CUSTOM.w, exact even in
## half floats); crowd.gdshader uses the same golden-ratio style sequences. Cheer threshold: the excitement at which
## the cheering twin replaces the calm twin (before the shader adds a small back-row bias).

const SEED_COUNT: int = 2048
const THRESHOLD_STEP: float = 0.41421356


static func threshold_for(seed_value: int) -> float:
	return lerpf(CHEER_THRESHOLD_MIN, CHEER_THRESHOLD_MAX, fposmod(float(seed_value) * THRESHOLD_STEP, 1.0))
