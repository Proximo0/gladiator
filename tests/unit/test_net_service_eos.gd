extends TestCase
## ServiceEos without the plugin: the availability check (falls back here, where no EOSG binaries exist) and the
## pure matchmaking, report and leaderboard helpers the EOS calls feed.

const BUILD: String = "abcdef0123456789ff"


func _cand(owner: String, rating: int, slots: int = 1, build: String = BUILD, key: String = "k") -> Dictionary:
	var attrs: Array = [{"key": "build", "value": build}, {"key": "rating", "value": rating}, {"key": "games", "value": 3},
		{"key": "name", "value": "P" + owner}, {"key": "key", "value": key}, {"key": "ver", "value": NetConfig.PROTOCOL_VERSION}]
	return ServiceEos.summarize("lobby_" + owner, owner, slots, 2 - slots, attrs)


func test_unavailable_without_the_plugin() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	assert_false(ServiceEos.available(tree), "no EOSG binaries in this environment")
	var missing: PackedStringArray = ServiceEos.missing_parts(tree)
	assert_true(missing.size() >= 3, ", ".join(missing))
	var cfg: EosConfig = EosConfig.parse("[eos]\nproduct_id=a1\nsandbox_id=b2\ndeployment_id=c3\nclient_id=d4\nclient_secret=e5\n")
	assert_true(ServiceEos.unavailable_reason(tree, "eos", false, cfg).begins_with("EOS plugin not installed"))
	assert_eq(ServiceEos.unavailable_reason(tree, "auto", true, cfg), "scripted run")
	assert_eq(ServiceEos.unavailable_reason(tree, "local", false, cfg), "--online-service=local")
	assert_true(ServiceEos.create_for(tree, "auto", "", true) == null, "MenuFlow falls back to ServiceLocal")


func test_profile_names_and_paths() -> void:
	assert_eq(ServiceEos.clean_profile(" Second Player!/..\\2 "), "secondplayer2")
	assert_eq(ServiceEos.clean_profile("p2-test_x"), "p2-test_x")
	assert_eq(ServiceEos.clean_profile("x".repeat(40)).length(), 24)
	assert_eq(ServiceEos.cache_dir_for(""), "user://eosg-cache")
	assert_eq(ServiceEos.cache_dir_for("p2"), "user://eosg-cache-p2")
	assert_eq(ServiceEos.store_path_for(""), "user://eos_profile.json")
	assert_eq(ServiceEos.store_path_for("p2"), "user://eos_profile_p2.json")


func test_bucket_and_socket() -> void:
	assert_eq(ServiceEos.bucket_for(BUILD), "sb_quick:abcdef0123456789")
	assert_eq(ServiceEos.bucket_for(""), "sb_quick:dev")
	var s: String = ServiceEos.socket_name("0f3a-9b_7c:" + "d".repeat(40))
	assert_eq(s.left(9), "sb0f3a9b7")
	assert_true(s.length() <= ServiceEos.MAX_SOCKET, "at most 32")
	for ch: String in s:
		assert_true(ch.is_valid_identifier() or ch.is_valid_int(), "alphanumeric only: %s" % s)
	assert_eq(ServiceEos.socket_name("abc"), ServiceEos.socket_name("abc"), "both members derive the same socket")


func test_summarize_reads_attributes() -> void:
	var c: Dictionary = _cand("u1", 1234)
	assert_eq(c["owner"], "u1")
	assert_eq(c["rating"], 1234)
	assert_eq(c["games"], 3)
	assert_eq(c["name"], "Pu1")
	assert_eq(c["build"], BUILD)
	var bare: Dictionary = ServiceEos.summarize("l", "o", 1, 1, [])
	assert_eq(bare["rating"], Rating.START_RATING)
	assert_eq(bare["key"], "")


func test_pick_lobby_rules() -> void:
	var cands: Array = [_cand("me", 1000), _cand("far", 1400), _cand("full", 1000, 0), _cand("old", 1000, 1, "other"),
		_cand("nokey", 1000, 1, BUILD, ""), _cand("b", 1060), _cand("a", 940)]
	# "a" and "b" are both 60 away: the smaller owner id wins the tie; never mine, full, other build or keyless.
	assert_eq(ServiceEos.pick_lobby(cands, "me", 1000, BUILD, 0.0), 6)
	assert_eq(ServiceEos.pick_lobby([_cand("far", 1400)], "me", 1000, BUILD, 0.0), -1, "outside the start window")
	var secs: float = float(400 - Rating.WINDOW_START) / float(Rating.WINDOW_PER_S)
	assert_eq(ServiceEos.pick_lobby([_cand("far", 1400)], "me", 1000, BUILD, secs), 0, "the window widens")
	assert_eq(ServiceEos.pick_lobby([], "me", 1000, BUILD, 99.0), -1)


func test_should_yield_is_one_sided() -> void:
	assert_true(ServiceEos.should_yield("b", "a"), "the larger id joins the smaller one's lobby")
	assert_false(ServiceEos.should_yield("a", "b"), "the smaller id keeps hosting")
	assert_false(ServiceEos.should_yield("a", ""))


func test_profile_from_stats() -> void:
	var fresh: Dictionary = ServiceEos.profile_from_stats({})
	assert_eq(fresh, {"rating": Rating.START_RATING, "games": 0, "wins": 0, "losses": 0})
	var p: Dictionary = ServiceEos.profile_from_stats({"sb_rating": 1188, "sb_games": 12, "sb_wins": 8, "sb_losses": 4})
	assert_eq(p["rating"], 1188)
	assert_eq(p["games"], 12)
	assert_eq(ServiceEos.profile_from_stats({"sb_rating": 0})["rating"], Rating.START_RATING, "unset Latest stat")


func test_stats_for_result() -> void:
	assert_eq(ServiceEos.stats_for_result(1020, 1.0), [{"stat_name": "sb_rating", "ingest_amount": 1020},
		{"stat_name": "sb_games", "ingest_amount": 1}, {"stat_name": "sb_wins", "ingest_amount": 1}])
	assert_eq(ServiceEos.stats_for_result(980, 0.0)[2], {"stat_name": "sb_losses", "ingest_amount": 1})
	assert_eq(ServiceEos.stats_for_result(1000, 0.5).size(), 2, "a draw moves no counter")


func test_report_round_trip_and_rejections() -> void:
	var key: String = "0123abcd"
	var rep: Dictionary = Rating.make_report("m1", "opp", Rating.KIND_RESULT, "opp", "ko", 2400)
	var raw: String = ServiceEos.encode_report(rep, Rating.sign_report(key, rep))
	var back: Dictionary = ServiceEos.decode_report(raw, key, "opp", "m1")
	assert_eq(back.get("winner", ""), "opp")
	assert_eq(back.get("ticks", 0), 2400)
	assert_true(ServiceEos.decode_report(raw, "wrongkey", "opp", "m1").is_empty(), "bad signature")
	assert_true(ServiceEos.decode_report(raw, key, "someone", "m1").is_empty(), "another player's report")
	assert_true(ServiceEos.decode_report(raw, key, "opp", "m2").is_empty(), "another match")
	assert_true(ServiceEos.decode_report("{not json", key, "opp", "m1").is_empty())
	assert_true(ServiceEos.decode_report("[1,2]", key, "opp", "m1").is_empty())
	var v: Dictionary = Rating.reconcile("me", Rating.make_report("m1", "me", Rating.KIND_RESULT, "opp", "ko", 2400), "opp", back, true)
	assert_eq(v["status"], "agree", "a decoded report reconciles like the original")


func test_leaderboard_view() -> void:
	var records: Array = []
	for i: int in 30:
		records.append({"user_id": "u%02d" % i, "rank": i + 1, "score": 1600 - i * 10, "user_display_name": "Name%d" % i})
	records[3]["user_display_name"] = ""
	records.shuffle()  # EOS order is not trusted: rank sorts
	var extra: Dictionary = {"u00": {"games": 50, "wins": 40, "losses": 10}}
	var mine: Dictionary = {"name": "Me", "games": 4, "wins": 3, "losses": 1}
	var d: Dictionary = ServiceEos.leaderboard_view(records, extra, "u20", mine, 5, 2)
	assert_eq((d["top"] as Array).size(), 5)
	assert_eq(d["top"][0]["id"], "u00")
	assert_eq(d["top"][0]["games"], 50)
	assert_false(d["top"][0]["provisional"])
	assert_eq(d["top"][0]["tier"], Rating.tier(1600))
	assert_eq(d["top"][3]["name"], ServiceEos.fallback_name("u03"), "no display name")
	assert_eq(d["me"]["name"], "Me", "my own row uses my profile")
	assert_eq(d["me"]["rank"], 21)
	assert_eq(d["me"]["wins"], 3)
	var around: Array = d["around"]
	assert_eq(around.size(), 5)
	assert_eq(around[0]["rank"], 19)
	assert_eq(d["total"], 30)
	var inside: Dictionary = ServiceEos.leaderboard_view(records, {}, "u01", {}, 5, 2)
	assert_true((inside["around"] as Array).is_empty(), "in the top list: no window")
	var absent: Dictionary = ServiceEos.leaderboard_view(records, {}, "nobody", {}, 5, 2)
	assert_true((absent["me"] as Dictionary).is_empty())
	var ids: PackedStringArray = ServiceEos.ids_to_detail(records, "u20", 5, 2)
	assert_eq(ids.size(), 9, "5 top rows and 4 neighbours, without me: %s" % ", ".join(ids))
	assert_false(ids.has("u20"))
