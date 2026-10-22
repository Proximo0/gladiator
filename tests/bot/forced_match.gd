extends "res://game/match/match.gd"
## Balance-testing match script for tests/bot/bot.tscn (--match_script=res://tests/bot/forced_match.gd): forces the two
## loadouts from `--forced=<weapon>:<offhand>,<weapon>:<offhand>` (A is the weapon under test, B the reference) and puts A on
## side 0 for even seeds and side 1 for odd seeds, so the side bias cancels. Armor is the default loadout's on both.


func setup(p_config: Dictionary = {}) -> void:
	var spec: PackedStringArray = Flags.get_arg("forced", "").split(",")
	if spec.size() == 2:
		var cfg: Dictionary = p_config.duplicate(true)
		var sides: Array = []
		for s: String in spec:
			var p: PackedStringArray = s.split(":")
			sides.append({"weapon": p[0], "offhand": p[1] if p.size() > 1 else "", "armor": LoadoutRules.DEFAULT_ARMOR.duplicate()})
		if int(cfg.get("seed", 0)) % 2 == 1:
			sides.reverse()
		cfg["loadouts"] = sides
		p_config = cfg
	super.setup(p_config)
