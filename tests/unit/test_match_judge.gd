extends TestCase


func _fr(state: String, blood: float = 5.0) -> Dictionary:
	return {"state": state, "blood": blood}


func test_going_on() -> void:
	var j := MatchJudge.new(10.0)
	assert_true(j.update([_fr("standing"), _fr("down")], 5, 0.1).is_empty())


func test_death_gives_winner_and_cause() -> void:
	var j := MatchJudge.new(10.0)
	assert_eq(j.update([_fr("standing"), _fr("dead")], 5, 0.1), {"winner": 0, "reason": "blood_loss"})
	var k := MatchJudge.new(10.0)
	k.note_cause(0, "behead")
	k.note_cause(0, "gut")
	assert_eq(k.update([_fr("dead"), _fr("standing")], 5, 0.1), {"winner": 1, "reason": "behead"})
	var m := MatchJudge.new(10.0)
	assert_eq(m.update([_fr("dead"), _fr("dead")], 5, 0.1)["winner"], -1)


func test_ko_needs_hold_time() -> void:
	var j := MatchJudge.new(100.0, 0.95)
	for i: int in 9:
		assert_true(j.update([_fr("standing"), _fr("ko")], i, 0.1).is_empty())
	assert_eq(j.update([_fr("standing"), _fr("ko")], 10, 0.1), {"winner": 0, "reason": "ko"})
	var k := MatchJudge.new(100.0, 0.95)
	for i: int in 8:
		k.update([_fr("ko"), _fr("standing")], i, 0.1)
	assert_true(k.update([_fr("down"), _fr("standing")], 8, 0.1).is_empty(), "waking up resets the timer")
	assert_true(k.update([_fr("ko"), _fr("standing")], 9, 0.1).is_empty())


func test_both_ko_is_no_result() -> void:
	var j := MatchJudge.new(100.0, 0.5)
	for i: int in 20:
		assert_true(j.update([_fr("ko"), _fr("ko")], i, 0.1).is_empty())


func test_time_limit() -> void:
	var j := MatchJudge.new(10.0)
	assert_true(j.update([_fr("standing"), _fr("standing")], 99, 0.1).is_empty())
	assert_eq(j.update([_fr("standing", 4.0), _fr("standing", 3.0)], 100, 0.1), {"winner": 0, "reason": "time"})
	assert_eq(j.update([_fr("standing", 3.0), _fr("standing", 4.0)], 100, 0.1), {"winner": 1, "reason": "time"})
	assert_eq(j.update([_fr("standing", 4.0), _fr("standing", 4.1)], 100, 0.1), {"winner": -1, "reason": "time"})


func test_banners() -> void:
	for k: String in ["run_through", "gut", "behead", "skull_crush"]:
		assert_true(MatchJudge.finisher_banner(k).contains(" / "), k)
	assert_eq(MatchJudge.finisher_banner("sever"), "")
	assert_eq(MatchJudge.result_banner({"winner": 1}, ["A", "B"]), "VICTOR / B")
	assert_true(MatchJudge.result_banner({"winner": -1}, ["A", "B"]).contains("/"))
