class_name AiDifficulty
extends RefCounted
## CPU difficulty: a table of human-like handicaps the FighterBrain applies on top of its personality. Nothing here
## touches physics or reads hidden state: a harder CPU reacts sooner, aims truer, guards more often, hits the vitals,
## notices a beaten foe, uses the sand better and rests when tired; an easier one does the opposite.
## "normal" is the identity: the brain behaves exactly as it did before difficulties existed (docs/ai_difficulty.md).
## Pure data, no Node. Ids: easy, normal, hard.

const IDS: PackedStringArray = ["easy", "normal", "hard"]
const DEFAULT_ID: String = "normal"

## Shown in the menu: [id, label, note].
const LIST: Array = [
	["easy", "Easy", "Slow hands, wild aim, forgets to guard. A fair start."],
	["normal", "Normal", "A sound fighter."],
	["hard", "Hard", "Quick hands, true aim, guards well and goes for the kill."],
]

## Keys:
##   reaction_scale, reaction_min_ms  delay before it sees the foe's moves (personality reaction_ms x scale, floored)
##   aim_noise_scale, aim_err         the personality's aim noise x scale; aim_err adds a flat aim miss (aim units)
##   aim_slew                         max aim travel per tick (the hand's speed; 9 = uncapped)
##   aggr_add, wait_scale, p_scale    commit rate: aggression shift, pause between attacks x, attack chance x
##   recover_scale                    recovery after a swing x
##   guard_miss, guard_boost, guard_slew  chance the guard reflex is skipped, lift of the reflex toward 1, guard hand speed x
##   finish_seek                      chance per second-ish that a beaten foe is noticed as finishable (1 = always)
##   opp_seek                         chance an opening (foe just whiffed) is noticed
##   footwork                         0..1 use of the sand: venue leaning and pinning the foe against the wall
##   swing_scale                      strike length x (longer = a slower, weaker blow)
##   target_skill                     how much it weighs the foe's armor and wounds when picking where to hit (1 = as before)
##   riposte                          shift of the chance to answer a guarded blow with a counter-attack
##   punish                           extra chance to strike at once when the foe has just whiffed
##   threat_speed                     foe tip speed (m/s) from which it reads a blow as coming (lower = earlier)
##   hand_return                      how fast the hand comes back to guard after a blow x
##   core_bias                        weight of head, torso and pelvis against limbs when picking where to hit
##   stamina_mgmt                     retreat_stamina x (rests earlier when above 1, fights on empty when below)
##   thrust_skill                     chance a sword or pole-arm thrust is a committed one (point set, body drive)
##   close_plan                       0 = a shorter weapon walks up as usual; above 0 it plans its way inside
##   armor_read                       0..1 use of the foe's armor (ArmorRead): plate-gap thrusts, helmet targeting, kiting
const TABLE: Dictionary = {
	"easy": {
		"reaction_scale": 3.0, "reaction_min_ms": 450.0, "aim_noise_scale": 2.5, "aim_err": 0.4, "aim_slew": 0.022,
		"aggr_add": 0.1, "wait_scale": 0.9, "p_scale": 1.0, "recover_scale": 1.3,
		"guard_miss": 0.6, "guard_boost": 0.0, "guard_slew": 0.5, "finish_seek": 0.3, "opp_seek": 0.3,
		"footwork": 0.0, "stamina_mgmt": 0.5, "swing_scale": 1.3, "target_skill": 0.2, "riposte": -0.2, "punish": 0.0,
		"threat_speed": 5.5, "hand_return": 0.6, "core_bias": 0.6, "thrust_skill": 0.3, "close_plan": 0.0, "armor_read": 0.15,
	},
	"normal": {
		"reaction_scale": 1.0, "reaction_min_ms": 0.0, "aim_noise_scale": 1.0, "aim_err": 0.0, "aim_slew": 9.0,
		"aggr_add": 0.0, "wait_scale": 1.0, "p_scale": 1.0, "recover_scale": 1.0,
		"guard_miss": 0.0, "guard_boost": 0.0, "guard_slew": 1.0, "finish_seek": 1.0, "opp_seek": 1.0,
		"footwork": 0.5, "stamina_mgmt": 1.0, "swing_scale": 1.0, "target_skill": 1.0, "riposte": 0.0, "punish": 0.3, "hand_return": 1.0, "core_bias": 1.0, "threat_speed": 4.0,
		"thrust_skill": 1.0, "close_plan": 1.0, "armor_read": 0.6,
	},
	"hard": {
		"reaction_scale": 0.5, "reaction_min_ms": 70.0, "aim_noise_scale": 0.45, "aim_err": 0.0, "aim_slew": 9.0,
		"aggr_add": 0.0, "wait_scale": 0.8, "p_scale": 1.1, "recover_scale": 0.85,
		"guard_miss": 0.0, "guard_boost": 0.6, "guard_slew": 1.4, "finish_seek": 1.0, "opp_seek": 1.0,
		"footwork": 1.0, "stamina_mgmt": 1.25, "swing_scale": 0.8, "target_skill": 1.6, "riposte": 0.3, "punish": 0.8,
		"hand_return": 1.0, "core_bias": 2.4, "threat_speed": 3.8, "thrust_skill": 1.0, "close_plan": 1.0, "armor_read": 1.0,
	},
}


static func normalize(id: String) -> String:
	return id if TABLE.has(id) else DEFAULT_ID


static func params(id: String) -> Dictionary:
	return (TABLE[normalize(id)] as Dictionary).duplicate()


static func label(id: String) -> String:
	for e: Array in LIST:
		if str(e[0]) == id:
			return str(e[1])
	return id


static func note(id: String) -> String:
	for e: Array in LIST:
		if str(e[0]) == id:
			return str(e[2])
	return ""
