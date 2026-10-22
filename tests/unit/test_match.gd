extends TestCase
## Match's fight clock (the Node itself is built only in sims; these use a bare, never-added Match).


func _match(config: Dictionary) -> Match:
	var m := Match.new()
	m.setup(config)
	m.fight_start_tick = int(m.config["fight_start_tick"])  # what _start_match does when the match is built
	return m


func test_fight_clock_counts_from_the_start_tick() -> void:
	var m := _match({"mode": "bot_vs_bot", "seed": 3, "presentation": false, "fight_start_tick": 138})
	m.tick = 100
	assert_eq(m.fight_ticks(), 0, "before the release")
	m.tick = 138 + 600
	assert_eq(m.fight_ticks(), 600)
	m.free()


func test_offline_hold_and_release() -> void:
	var m := _match({"mode": "player_vs_cpu", "seed": 3, "presentation": false})
	m.hold_fight_clock()
	m.tick = 200
	assert_eq(m.fight_ticks(), 0, "held during the intro")
	m.start_fight_clock()
	m.tick = 260
	assert_eq(m.fight_ticks(), 60)
	assert_eq(m.fight_start_tick, 200)
	m.free()


## The time limit runs from the release: a 180 s fight after a 2.3 s intro ends at match tick 138 + 10800.
func test_time_limit_counts_from_the_release() -> void:
	var m := _match({"mode": "bot_vs_bot", "seed": 3, "presentation": false, "fight_start_tick": 138})
	var judge := MatchJudge.new(180.0)
	var frames: Array = [{"state": "standing"}, {"state": "standing"}]
	var dt: float = 1.0 / 60.0
	m.tick = 10800 + 137
	assert_true(judge.update(frames, m.fight_ticks(), dt).is_empty(), "the intro does not eat into the 180 s")
	m.tick = 10800 + 138
	assert_eq(str(judge.update(frames, m.fight_ticks(), dt).get("reason", "")), "time")
	m.free()
