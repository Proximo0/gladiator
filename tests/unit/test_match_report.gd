extends TestCase


func _ctx(extra: Dictionary = {}) -> Dictionary:
	var c: Dictionary = {"mode": "player_vs_cpu", "names": ["Crixus", "Verus"], "local_side": 0, "winner": 0,
		"reason": "behead", "hits": [7, 3], "blood_lost": [0.84, 2.61], "severs": [2, 0], "combos": [4, 2],
		"fight_s": 72.4, "rating": {}, "unlocked": ""}
	c.merge(extra, true)
	return c


func test_win_vs_cpu() -> void:
	var d: Dictionary = MatchReport.build(_ctx())
	assert_eq(d["latin"], "VICTORIA")
	assert_eq(d["english"], "You won")
	assert_eq(d["cause_latin"], "CAPVT ABSCISSVM")
	assert_eq(d["cause_english"], "Beheaded")
	assert_eq(d["names"], ["CRIXUS", "VERUS"])
	assert_eq(d["won"], [true, false])
	assert_eq(d["time"], "1:12")
	assert_false(d["has_rating"])


func test_rows_in_screen_order() -> void:
	var d: Dictionary = MatchReport.build(_ctx())
	assert_eq(d["rows"], [["Hits landed", "7", "3"], ["Blood lost", "0.8 L", "2.6 L"], ["Limbs severed", "2", "0"],
		["Longest combo", "4", "2"]])
	# Online client (side 1): its own numbers come first.
	var c: Dictionary = MatchReport.build(_ctx({"mode": "online", "local_side": 1, "winner": 0}))
	assert_eq((c["rows"] as Array)[0], ["Hits landed", "3", "7"])
	assert_eq(c["names"], ["VERUS", "CRIXUS"])
	assert_eq(c["latin"], "MORS")
	assert_eq(c["english"], "Crixus wins")
	assert_eq(c["won"], [false, true])


func test_draw_and_other_endings() -> void:
	var d: Dictionary = MatchReport.build(_ctx({"winner": -1, "reason": "time"}))
	assert_eq(d["latin"], "AEQVO MARTE")
	assert_eq(d["cause_english"], "Decided at the time limit")
	assert_eq(MatchReport.cause("blood_loss"), ["EXSANGVIS", "Bled out"])
	assert_eq(MatchReport.cause("ko"), ["SOPITVS", "Knocked out"])
	assert_eq(MatchReport.cause("mutual")[1], "Both fell")
	assert_eq(MatchReport.cause("gut"), ["VISCERA EFFVSA", "Gutted"])


func test_local_2p_names_the_winner() -> void:
	var d: Dictionary = MatchReport.build(_ctx({"mode": "local_2p", "winner": 1}))
	assert_eq(d["latin"], "VICTORIA")
	assert_eq(d["english"], "Verus wins")


func test_rating_lines() -> void:
	var d: Dictionary = MatchReport.build(_ctx({"mode": "online", "rating": {"status": "single", "before": 1000, "after": 1022, "delta": 22}}))
	assert_true(d["has_rating"])
	assert_eq(d["rating_text"], "Rating 1000 -> 1022")
	assert_eq(d["rating_delta"], 22)
	var p: Dictionary = MatchReport.build(_ctx({"mode": "online", "rating": {"status": "pending"}}))
	assert_eq(p["rating_text"], "Rating pending")
	assert_eq(p["rating_delta"], 0)
	assert_eq(MatchReport.signed(-18), "-18")
	assert_eq(MatchReport.signed(5), "+5")


func test_negative_blood_and_clock() -> void:
	var d: Dictionary = MatchReport.build(_ctx({"blood_lost": [-0.01, 0.0], "fight_s": 5.6}))
	assert_eq((d["rows"] as Array)[1], ["Blood lost", "0.0 L", "0.0 L"])
	assert_eq(d["time"], "0:06")
	assert_eq(MatchReport.clock(600.0), "10:00")


func test_plates() -> void:
	var lo: Array = [{"weapon": "gladius", "offhand": "shield_round"}, {"weapon": "fists", "offhand": ""}]
	var pers: Array = [{"preset": "duelist"}, {"preset": "coward"}]
	var cpu: Array = MatchReport.plates_for({"mode": "player_vs_cpu", "names": ["Crixus", "Verus"], "loadouts": lo,
		"personalities": pers, "local_side": 0})
	assert_eq((cpu[0] as Dictionary)["name"], "CRIXUS")
	assert_eq((cpu[0] as Dictionary)["sub"], "You")
	assert_eq((cpu[1] as Dictionary)["sub"], "CPU - Skirmisher")
	assert_eq((cpu[1] as Dictionary)["weapon"], LoadoutRules.display_name("fists"))
	assert_true(str((cpu[0] as Dictionary)["weapon"]).contains(" & "), "weapon and offhand")
	var two: Array = MatchReport.plates_for({"mode": "local_2p", "names": ["A", "B"], "loadouts": lo, "personalities": pers})
	assert_eq((two[1] as Dictionary)["sub"], "Player 2")
	var net: Array = MatchReport.plates_for({"mode": "online", "names": ["Host", "Me"], "loadouts": lo, "personalities": pers,
		"local_side": 1, "ratings": [{"rating": 1250, "games": 30}, {}]})
	assert_eq((net[0] as Dictionary)["name"], "ME")
	assert_eq((net[0] as Dictionary)["sub"], "You - Online")
	assert_eq((net[1] as Dictionary)["sub"], "Rating 1250 - %s" % Rating.tier(1250))
