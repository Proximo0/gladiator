class_name MenuState
extends RefCounted
## What the player picked in the menus, kept for the whole session: a loadout per human side, the CPU opponent's
## setup, and how to turn all of it into the dictionary Match.setup() takes. Pure: the caller passes the seed.

const PERSONALITIES: Array = [
	["random", "Random", "A different temperament every fight"],
	["duelist", "Duelist", "Patient and precise, feints and picks its moment"],
	["brute", "Brute", "Heavy swings, slow to react, hard to stop"],
	["coward", "Coward", "Keeps its distance, goes for your legs and flees"],
	["berserker", "Berserker", "Never stops coming, ignores its own wounds"],
]
const CPU_RANDOM: String = "random"
const CPU_CUSTOM: String = "custom"

var loadouts: Array = [LoadoutRules.default_loadout(), LoadoutRules.default_loadout()]
var cpu_loadout_mode: String = CPU_RANDOM  ## CPU_RANDOM or CPU_CUSTOM
var cpu_personality: String = "random"  ## "random" or a FighterBrain preset name
var cpu_seed: int = 1  ## the seed the "random" opponent preview was rolled with
var last_mode: String = "player_vs_cpu"


func set_loadout(side: int, loadout: Dictionary) -> void:
	loadouts[clampi(side, 0, 1)] = LoadoutRules.sanitize(loadout)


## The loadout the random opponent will have for `seed_value` (the same draw Match makes).
static func rolled_opponent(seed_value: int) -> Dictionary:
	var cfg: Dictionary = MatchConfig.normalize({"seed": seed_value}, seed_value)
	return (cfg["loadouts"] as Array)[1]


## The personality dict the CPU will have for `seed_value` when left on random.
static func rolled_personality(seed_value: int) -> Dictionary:
	var cfg: Dictionary = MatchConfig.normalize({"seed": seed_value}, seed_value)
	return (cfg["personalities"] as Array)[1]


## The loadout shown for the CPU side right now.
func cpu_shown_loadout() -> Dictionary:
	if cpu_loadout_mode == CPU_CUSTOM:
		return loadouts[1]
	return rolled_opponent(cpu_seed)


## Match.setup() dictionary for `mode` and `seed_value`. Player vs CPU sends the human loadout and, unless the CPU
## is custom, leaves the CPU's loadout to the seed (so what the preview rolled is what fights). Personality: a named
## preset, or left to the seed.
func to_config(mode: String, seed_value: int) -> Dictionary:
	last_mode = mode
	var cfg: Dictionary = {"mode": mode, "seed": seed_value}
	match mode:
		"local_2p":
			cfg["loadouts"] = [loadouts[0].duplicate(true), loadouts[1].duplicate(true)]
		"player_vs_cpu":
			if cpu_loadout_mode == CPU_CUSTOM:
				cfg["loadouts"] = [loadouts[0].duplicate(true), loadouts[1].duplicate(true)]
			else:
				cfg["loadouts"] = [loadouts[0].duplicate(true)]
			if cpu_personality != "random":
				cfg["personalities"] = [{}, {"preset": cpu_personality}]
	return cfg


static func personality_label(id: String) -> String:
	for p: Array in PERSONALITIES:
		if str(p[0]) == id:
			return str(p[1])
	return id
