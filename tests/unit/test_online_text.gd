extends TestCase


func test_left_and_disconnected_name_the_opponent() -> void:
	var l: Dictionary = OnlineText.plain("Verus left")
	assert_eq(l["kind"], OnlineText.KIND_LEFT)
	assert_eq(l["title"], "Verus left the arena")
	var d: Dictionary = OnlineText.plain("The other player disconnected", "Cato")
	assert_eq(d["kind"], OnlineText.KIND_DROPPED)
	assert_true(str(d["title"]).contains("Cato"))
	var anon: Dictionary = OnlineText.plain("The other player left")
	assert_eq(anon["title"], "Your opponent left the arena")


func test_timeout_and_unreachable() -> void:
	assert_eq(OnlineText.plain("Connection lost", "Verus")["kind"], OnlineText.KIND_TIMEOUT)
	assert_eq(OnlineText.plain("No answer from the host")["kind"], OnlineText.KIND_UNREACHABLE)
	assert_eq(OnlineText.plain("Could not reach 10.0.0.2:7777 (Can't connect)")["kind"], OnlineText.KIND_UNREACHABLE)
	assert_true(str(OnlineText.plain("No answer from the host", "Livia")["title"]).contains("Livia"))


func test_version_mismatch_is_plain() -> void:
	var v: Dictionary = OnlineText.plain("version mismatch: different game data (host build ab12, client build cd34)", "Nero")
	assert_eq(v["kind"], OnlineText.KIND_VERSION)
	assert_false(str(v["body"]).contains("build"), "no build hashes in the player's face")
	assert_true(str(v["body"]).contains("Update"))


func test_service_failures() -> void:
	assert_eq(OnlineText.plain("Nobody else is searching on this network")["kind"], OnlineText.KIND_NO_MATCH)
	assert_eq(OnlineText.plain("Nobody to fight right now. Try again in a while.")["kind"], OnlineText.KIND_NO_MATCH)
	assert_eq(OnlineText.plain("Could not sign in: EOS sign-in failed (no answer)")["kind"], OnlineText.KIND_OFFLINE)
	assert_eq(OnlineText.plain("offline")["kind"], OnlineText.KIND_OFFLINE)
	assert_eq(OnlineText.plain("Could not open the LAN search port")["kind"], OnlineText.KIND_BLOCKED)
	assert_eq(OnlineText.plain("Host refused: full")["body"], "Reason: full.")
	var other: Dictionary = OnlineText.plain("Something odd")
	assert_eq(other["kind"], OnlineText.KIND_OTHER)
	assert_eq(other["body"], "Something odd")


func test_clock_and_wait_lines() -> void:
	assert_eq(OnlineText.clock(0.0), "0:00")
	assert_eq(OnlineText.clock(7.9), "0:07")
	assert_eq(OnlineText.clock(83.0), "1:23")
	assert_eq(OnlineText.clock(-3.0), "0:00")
	assert_eq(OnlineText.wait_line(3.0, 20.0), "Usual wait about 0:20")
	assert_true(OnlineText.wait_line(25.0, 20.0).begins_with("Longer than usual"))
	assert_eq(OnlineText.range_line(1000, 0.0), "Rivals rated 900 to 1100")
	assert_eq(OnlineText.range_line(150, 0.0), "Rivals rated %d to 250" % Rating.MIN_RATING)


func test_unrated_and_streak_lines() -> void:
	assert_true(OnlineText.unrated_line("match too short").contains("too short"))
	assert_true(OnlineText.unrated_line("reports disagree").contains("different results"))
	assert_true(OnlineText.unrated_line("friendly").begins_with("Friendly"))
	assert_eq(OnlineText.unrated_line(""), "Not rated")
	assert_eq(OnlineText.streak_line(3), "3 wins in a row")
	assert_eq(OnlineText.streak_line(-2), "2 losses in a row")
	assert_eq(OnlineText.streak_line(1), "")
