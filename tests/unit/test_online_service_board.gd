extends TestCase


func _board() -> ServiceBoard:
	var b := ServiceBoard.new()
	b.ensure("a", "Ann")
	b.ensure("b", "Bo")
	return b


func test_apply_updates_both_and_records() -> void:
	var b: ServiceBoard = _board()
	var r: Dictionary = b.apply("a", "b", 1.0)
	assert_eq(r["a_after"], 1020)
	assert_eq(r["b_after"], 980)
	assert_eq(b.entry("a")["wins"], 1)
	assert_eq(b.entry("b")["losses"], 1)
	assert_eq(b.entry("a")["games"], 1)


func test_repeat_pair_pays_less() -> void:
	var b: ServiceBoard = _board()
	var first: int = int(b.apply("a", "b", 1.0)["a_after"]) - 1000
	for _i: int in range(5):
		b.apply("a", "b", 1.0)
	var before: int = int(b.entry("a")["rating"])
	var last: int = int(b.apply("a", "b", 1.0)["a_after"]) - before
	assert_true(last < first)


func test_rows_sorted_and_ranked_and_skip_unplayed() -> void:
	var b: ServiceBoard = _board()
	b.ensure("c", "Cy")
	b.apply("b", "a", 1.0)
	var rows: Array = b.rows()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["id"], "b")
	assert_eq(rows[0]["rank"], 1)
	assert_eq(rows[1]["rank"], 2)


func test_leaderboard_around_me_only_when_outside_top() -> void:
	var b := ServiceBoard.new()
	for i: int in range(30):
		var e: Dictionary = b.ensure("p%02d" % i, "P%d" % i)
		e["rating"] = 2000 - i * 10
		e["games"] = 20
	var lb: Dictionary = b.leaderboard("p02", 5, 2)
	assert_eq((lb["top"] as Array).size(), 5)
	assert_true((lb["around"] as Array).is_empty())
	assert_eq(lb["me"]["rank"], 3)
	var lb2: Dictionary = b.leaderboard("p20", 5, 2)
	var around: Array = lb2["around"]
	assert_eq(around.size(), 5)
	assert_eq(around[2]["id"], "p20")
	assert_eq(lb2["total"], 30)
	assert_eq(b.leaderboard("nobody", 5, 2)["me"], {})


func test_round_trip_and_hostile_file() -> void:
	var b: ServiceBoard = _board()
	b.apply("a", "b", 1.0)
	var c := ServiceBoard.new()
	c.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(c.entry("a")["rating"], b.entry("a")["rating"])
	var d := ServiceBoard.new()
	d.from_dict({"players": {"x": {"rating": 99999999, "games": -5, "name": ""}, "y": 7}, "recent": {"x": "no"}})
	assert_eq(d.entry("x")["rating"], 9999)
	assert_eq(d.entry("x")["games"], 0)
	assert_eq(d.entry("x")["name"], "Gladiator")
	assert_false(d.players.has("y"))


func test_note_opponent_does_not_overwrite_our_own_computation() -> void:
	var b: ServiceBoard = _board()
	b.apply("a", "b", 1.0)
	b.note_opponent("b", "Bo", 1500, 0)  # they announce fewer games than we have computed: ignored
	assert_eq(b.entry("b")["rating"], 980)
	b.note_opponent("z", "Zed", 1500, 4)
	assert_eq(b.entry("z")["rating"], 1500)


func test_streaks() -> void:
	var b: ServiceBoard = _board()
	b.apply("a", "b", 1.0)
	b.apply("a", "b", 1.0)
	assert_eq(b.entry("a")["streak"], 2)
	assert_eq(b.entry("b")["streak"], -2)
	b.apply("a", "b", 0.0)
	assert_eq(b.entry("a")["streak"], -1)
	assert_eq(b.entry("b")["streak"], 1)
	b.apply("a", "b", 0.5)
	assert_eq(b.entry("a")["streak"], 0)
	assert_eq(ServiceBoard.streak_text(3), "W3")
	assert_eq(ServiceBoard.streak_text(-2), "L2")
	assert_eq(ServiceBoard.streak_text(0), "")
	var c := ServiceBoard.new()
	c.from_dict(b.to_dict())
	assert_eq(c.entry("b")["streak"], 0)
	assert_eq(b.rows()[0].has("streak"), true)


func test_pages_and_around_me() -> void:
	var b := ServiceBoard.new()
	for i: int in 50:
		var e: Dictionary = b.ensure("p%02d" % i, "P%d" % i)
		e["rating"] = 2000 - i * 10
		e["games"] = 5
	var p2: Dictionary = b.leaderboard("p45", 20, 2, 20)
	assert_eq(p2["offset"], 20)
	assert_eq((p2["top"] as Array).size(), 20)
	assert_eq(p2["top"][0]["rank"], 21)
	assert_eq(p2["me"]["rank"], 46)
	assert_eq((p2["around"] as Array).size(), 5, "me off the page: the rows around me")
	var p3: Dictionary = b.leaderboard("p45", 20, 2, 40)
	assert_eq((p3["top"] as Array).size(), 10, "the last page is short")
	assert_eq(p3["around"], [], "me on the page: nothing around")
	var edge: Dictionary = b.leaderboard("p21", 20, 2, 0)
	assert_eq((edge["around"] as Array).size(), 4, "the window never repeats rows of the page")
	assert_eq(edge["around"][0]["rank"], 21)
	var far: Dictionary = b.leaderboard("p00", 20, 2, 999)
	assert_eq(far["offset"], 49, "an offset past the end is clamped")
