extends TestCase


func _stub() -> ServiceStub:
	var s := ServiceStub.new()
	s.login("Hero")
	return s


func _signed(s: ServiceStub, mid: String, kind: String, winner: String, ticks: int = 3000) -> Array:
	var r: Dictionary = Rating.make_report(mid, str(s.profile["id"]), kind, winner, "ko", ticks)
	return [r, Rating.sign_report(s.key_for(mid), r)]


func test_login_failure_and_profile() -> void:
	var s := ServiceStub.new()
	s.fail_login_with = "offline"
	var why: Array = [""]
	s.login_failed.connect(func(r: String) -> void: why[0] = r)
	s.login("x")
	assert_eq(why[0], "offline")
	assert_false(s.is_logged_in())
	var ok: ServiceStub = _stub()
	assert_true(ok.is_logged_in())
	assert_eq(ok.my_rating()["rating"], Rating.START_RATING)
	assert_true(ok.my_rating()["provisional"])
	ok.free()
	s.free()


func test_quick_match_hands_over_a_ready_to_use_match() -> void:
	var s: ServiceStub = _stub()
	var got: Array = []
	s.matched.connect(func(i: Dictionary) -> void: got.append(i))
	s.quick_match({})
	assert_eq(got.size(), 1)
	var info: Dictionary = got[0]
	assert_eq(info["role"], OnlineService.ROLE_HOST)
	assert_eq(info["opponent"]["name"], "Verus")
	assert_true(info["port"] > 0)
	assert_false(s.is_searching())
	s.free()


func test_cancel_stops_a_pending_search() -> void:
	var s: ServiceStub = _stub()
	s.auto_match = false
	var got: Array = []
	s.matched.connect(func(i: Dictionary) -> void: got.append(i))
	s.quick_match({})
	assert_true(s.is_searching())
	s.cancel()
	s.fulfil()
	assert_true(got.is_empty())
	s.free()


func test_both_agree_updates_ratings() -> void:
	var s: ServiceStub = _stub()
	s.quick_match({})
	var mid: String = "stub-match-1"
	var me: String = str(s.profile["id"])
	var a: Array = _signed(s, mid, Rating.KIND_RESULT, me)
	s.report_result(mid, a[0], a[1])
	assert_true(s.summaries.is_empty(), "waits for the other report")
	s.opponent_report(mid, Rating.make_report(mid, "", Rating.KIND_RESULT, me, "ko", 3000))
	assert_eq(s.summaries.size(), 1)
	assert_eq(s.summaries[0]["status"], "agree")
	assert_true(int(s.summaries[0]["delta"]) > 0)
	assert_true(int(s.my_rating()["rating"]) > Rating.START_RATING)
	assert_eq(s.my_rating()["games"], 1)
	s.free()


func test_disagreement_changes_nothing() -> void:
	var s: ServiceStub = _stub()
	s.quick_match({})
	var me: String = str(s.profile["id"])
	var a: Array = _signed(s, "stub-match-1", Rating.KIND_RESULT, me)
	s.report_result("stub-match-1", a[0], a[1])
	s.opponent_report("stub-match-1", Rating.make_report("", "", Rating.KIND_RESULT, str(s.opponent["id"]), "ko", 3000))
	assert_eq(s.summaries[0]["status"], "disputed")
	assert_eq(s.my_rating()["rating"], Rating.START_RATING)
	assert_eq(s.my_rating()["games"], 0)
	s.free()


func test_leaving_loses_even_without_the_other_report() -> void:
	var s: ServiceStub = _stub()
	s.quick_match({})
	var a: Array = _signed(s, "stub-match-1", Rating.KIND_LEFT, "", 200)
	s.report_result("stub-match-1", a[0], a[1])
	assert_eq(s.summaries[0]["status"], "forfeit")
	assert_true(int(s.summaries[0]["delta"]) < 0)
	s.free()


func test_forged_signature_is_voided_and_duplicates_ignored() -> void:
	var s: ServiceStub = _stub()
	s.quick_match({})
	var r: Dictionary = Rating.make_report("stub-match-1", str(s.profile["id"]), Rating.KIND_RESULT, str(s.profile["id"]), "ko", 3000)
	s.report_result("stub-match-1", r, "deadbeef")
	assert_eq(s.summaries[0]["status"], "voided")
	var a: Array = _signed(s, "stub-match-1", Rating.KIND_RESULT, str(s.profile["id"]))
	s.report_result("stub-match-1", a[0], a[1])
	s.timeout_match("stub-match-1")
	s.timeout_match("stub-match-1")
	assert_eq(s.summaries.size(), 2, "settles once")
	s.free()


func test_leaderboard_view() -> void:
	var s: ServiceStub = _stub()
	for i: int in range(6):
		s.add_fake_player("f%d" % i, "Fake%d" % i, 1500 - i * 50, 20, 10)
	var got: Array = []
	s.leaderboard_ready.connect(func(d: Dictionary) -> void: got.append(d))
	s.request_leaderboard(3, 1)
	assert_eq((got[0]["top"] as Array).size(), 3)
	assert_eq(got[0]["me"], {}, "no rated game yet")
	s.free()


func test_local_never_writes_in_scripted_runs() -> void:
	var path: String = "user://test_online_local_%d.json" % OS.get_process_id()
	var s := ServiceLocal.new()
	s.store_path = path
	s.device_id = "aaaa"
	s.login("Writer")
	s.board.apply("aaaa", "bbbb", 1.0)
	assert_false(FileAccess.file_exists(path), "scripted runs never write player data")
	s.free()


func test_local_ids_and_match_ids_are_deterministic() -> void:
	var a := ServiceLocal.new()
	a.entropy = 5
	a.login("A")
	var b := ServiceLocal.new()
	b.entropy = 5
	b.login("B")
	assert_eq(a.device_id, b.device_id)
	assert_eq(a.device_id.length(), 16)
	assert_eq(ServiceLocal._match_id("h", "c", 1), ServiceLocal._match_id("h", "c", 1))
	assert_true(ServiceLocal._match_id("h", "c", 1) != ServiceLocal._match_id("h", "c", 2))
	a.free()
	b.free()
