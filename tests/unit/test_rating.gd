extends TestCase


func test_equal_players_split_k() -> void:
	var r: Dictionary = Rating.apply_match({"rating": 1000, "games": 0}, {"rating": 1000, "games": 0}, 1.0)
	assert_eq(r["a_delta"], 20)
	assert_eq(r["b_delta"], -20)


func test_expected_is_symmetric_and_ten_to_one_at_400() -> void:
	assert_near(Rating.expected(1000.0, 1000.0), 0.5)
	assert_near(Rating.expected(1400.0, 1000.0) + Rating.expected(1000.0, 1400.0), 1.0)
	assert_near(Rating.expected(1400.0, 1000.0), 10.0 / 11.0, 0.001)


func test_k_shrinks_with_games() -> void:
	assert_true(Rating.k_factor(0) > Rating.k_factor(10))
	assert_true(Rating.k_factor(10) > Rating.k_factor(40))
	assert_true(Rating.is_provisional(9))
	assert_false(Rating.is_provisional(10))


func test_upset_pays_more_than_expected_win() -> void:
	var upset: int = Rating.updated(1000, 20, 1400, 1.0) - 1000
	var easy: int = Rating.updated(1400, 20, 1000, 1.0) - 1400
	assert_true(upset > easy * 3)


func test_draw_between_unequal_moves_toward_each_other() -> void:
	var r: Dictionary = Rating.apply_match({"rating": 1200, "games": 20}, {"rating": 1000, "games": 20}, 0.5)
	assert_true(int(r["a_delta"]) < 0 and int(r["b_delta"]) > 0)


func test_rating_floor() -> void:
	assert_eq(Rating.updated(Rating.MIN_RATING, 0, 2000, 0.0), Rating.MIN_RATING)


func test_pair_weight_damps_repeats() -> void:
	assert_near(Rating.pair_weight(0), 1.0)
	assert_true(Rating.pair_weight(3) < Rating.pair_weight(2))
	assert_near(Rating.pair_weight(99), Rating.PAIR_WEIGHTS[Rating.PAIR_WEIGHTS.size() - 1])
	var full: int = Rating.updated(1000, 20, 1000, 1.0) - 1000
	var damped: int = Rating.updated(1000, 20, 1000, 1.0, Rating.pair_weight(4)) - 1000
	assert_true(damped < full)


func test_search_window_widens() -> void:
	assert_true(Rating.in_window(1000, 1090, 0.0))
	assert_false(Rating.in_window(1000, 1300, 0.0))
	assert_true(Rating.in_window(1000, 1300, 10.0))


func test_tiers() -> void:
	assert_eq(Rating.tier(900), "Tiro")
	assert_eq(Rating.tier(1000), "Gladiator")
	assert_eq(Rating.tier(1599), "Primus Palus")
	assert_eq(Rating.tier(2500), Rating.TOP_TIER)
	assert_eq(Rating.rating_text(1016, 3), "1016?")
	assert_eq(Rating.rating_text(1016, 30), "1016")


func test_signature_binds_every_field() -> void:
	var r: Dictionary = Rating.make_report("m1", "A", Rating.KIND_RESULT, "A", "ko", 3000)
	var sig: String = Rating.sign_report("key", r)
	assert_true(Rating.verify_report("key", r, sig))
	assert_false(Rating.verify_report("other", r, sig))
	var forged: Dictionary = r.duplicate()
	forged["winner"] = "B"
	assert_false(Rating.verify_report("key", forged, sig))
	assert_false(Rating.verify_report("key", r, ""))


func _res(player: String, winner: String, ticks: int = 3000) -> Dictionary:
	return Rating.make_report("m", player, Rating.KIND_RESULT, winner, "ko", ticks)


func test_agreeing_reports_are_rated() -> void:
	var v: Dictionary = Rating.reconcile("A", _res("A", "A"), "B", _res("B", "A"), false)
	assert_eq(v["status"], "agree")
	assert_true(v["rated"])
	assert_near(float(v["score_a"]), 1.0)


func test_disagreeing_reports_are_disputed_and_unrated() -> void:
	var v: Dictionary = Rating.reconcile("A", _res("A", "A"), "B", _res("B", "B"), false)
	assert_eq(v["status"], "disputed")
	assert_false(v["rated"])


func test_leaving_loses_whatever_the_other_says() -> void:
	var left: Dictionary = Rating.make_report("m", "A", Rating.KIND_LEFT, "", "left", 100)
	var v: Dictionary = Rating.reconcile("A", left, "B", _res("B", "A"), false)
	assert_eq(v["status"], "forfeit")
	assert_eq(v["winner"], "B")
	assert_near(float(v["score_a"]), 0.0)
	var v2: Dictionary = Rating.reconcile("B", {}, "A", left, true)  # B never reported
	assert_eq(v2["winner"], "B")
	assert_true(v2["rated"])


func test_both_left_is_voided() -> void:
	var l1: Dictionary = Rating.make_report("m", "A", Rating.KIND_LEFT, "", "left", 100)
	var l2: Dictionary = Rating.make_report("m", "B", Rating.KIND_LEFT, "", "left", 100)
	assert_false(Rating.reconcile("A", l1, "B", l2, false)["rated"])


func test_short_match_is_voided() -> void:
	var v: Dictionary = Rating.reconcile("A", _res("A", "A", 100), "B", _res("B", "A", 100), false)
	assert_eq(v["status"], "voided")
	assert_false(v["rated"])


func test_winner_outside_the_match_is_disputed() -> void:
	var v: Dictionary = Rating.reconcile("A", _res("A", "C"), "B", _res("B", "C"), false)
	assert_eq(v["status"], "disputed")


func test_lone_report_waits_then_counts() -> void:
	var mine: Dictionary = _res("A", "A")
	assert_eq(Rating.reconcile("A", mine, "B", {}, false)["status"], "pending")
	var v: Dictionary = Rating.reconcile("A", mine, "B", {}, true)
	assert_eq(v["status"], "single")
	assert_true(v["rated"])


func test_dropped_alone_is_never_rated_before_the_grace_period() -> void:
	var d: Dictionary = Rating.make_report("m", "A", Rating.KIND_DROPPED, "", "lost", 900)
	assert_false(Rating.reconcile("A", d, "B", {}, false)["rated"])
	assert_eq(Rating.reconcile("A", d, "B", {}, true)["winner"], "A")


func test_no_reports_at_all() -> void:
	assert_eq(Rating.reconcile("A", {}, "B", {}, false)["status"], "pending")
	assert_eq(Rating.reconcile("A", {}, "B", {}, true)["status"], "voided")
