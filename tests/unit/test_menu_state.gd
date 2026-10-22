extends TestCase


func test_player_vs_cpu_random_sends_only_human_loadout() -> void:
	var s := MenuState.new()
	s.set_loadout(0, {"weapon": "axe"})
	var cfg: Dictionary = s.to_config("player_vs_cpu", 12)
	assert_eq((cfg["loadouts"] as Array).size(), 1)
	assert_eq(str(cfg["loadouts"][0]["weapon"]), "axe")
	assert_eq((cfg["personalities"] as Array)[0], {}, "the human side has no brain")
	var norm: Dictionary = MatchConfig.normalize(cfg, 1)
	assert_eq(norm["loadouts"][1], MenuState.rolled_opponent(12), "preview equals the fight")


func test_custom_cpu_and_personality() -> void:
	var s := MenuState.new()
	s.cpu_loadout_mode = MenuState.CPU_CUSTOM
	s.cpu_personality = "berserker"
	s.set_loadout(1, {"weapon": "spear"})
	var cfg: Dictionary = s.to_config("player_vs_cpu", 3)
	var norm: Dictionary = MatchConfig.normalize(cfg, 1)
	assert_eq(str(norm["loadouts"][1]["weapon"]), "spear")
	assert_eq(str(norm["personalities"][1]["preset"]), "berserker")
	assert_eq(str(norm["mode"]), "player_vs_cpu")


func test_local_2p_sends_both() -> void:
	var s := MenuState.new()
	s.set_loadout(0, {"weapon": "bat"})
	s.set_loadout(1, {"weapon": "club"})
	var norm: Dictionary = MatchConfig.normalize(s.to_config("local_2p", 5), 1)
	assert_eq(str(norm["loadouts"][0]["weapon"]), "bat")
	assert_eq(str(norm["loadouts"][1]["weapon"]), "club")
	assert_eq(s.last_mode, "local_2p")


func test_bot_vs_bot_is_all_random() -> void:
	var cfg: Dictionary = MenuState.new().to_config("bot_vs_bot", 9)
	assert_false(cfg.has("loadouts"))


func test_personalities_are_real_presets() -> void:
	for p: Array in MenuState.PERSONALITIES:
		if str(p[0]) != "random":
			assert_true(FighterBrain.PRESETS.has(str(p[0])))


func test_difficulty_defaults_to_normal_and_rides_in_the_personality() -> void:
	var s := MenuState.new()
	assert_eq(s.cpu_difficulty, "normal")
	var norm: Dictionary = MatchConfig.normalize(s.to_config("player_vs_cpu", 12), 1)
	assert_eq(str(norm["personalities"][1]["difficulty"]), "normal")
	assert_eq(norm["personalities"][1]["preset"], MenuState.rolled_personality(12)["preset"], "random style is the previewed one")
	s.cpu_difficulty = "hard"
	s.cpu_personality = "brute"
	var cfg: Dictionary = s.to_config("player_vs_cpu", 3)
	assert_eq(str(cfg["personalities"][1]["difficulty"]), "hard")
	assert_eq(str(cfg["personalities"][1]["preset"]), "brute")


func test_unknown_difficulty_falls_back_to_normal() -> void:
	var s := MenuState.new()
	s.cpu_difficulty = "godlike"
	assert_eq(str(s.to_config("player_vs_cpu", 1)["personalities"][1]["difficulty"]), "normal")
	assert_eq(MenuState.DIFFICULTIES.size(), 3)
