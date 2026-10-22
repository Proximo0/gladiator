extends TestCase
## NetResultCheck: the client flags a host result its own snapshots contradict, and only then.


func _snap(tick: int, dead0: bool, dead1: bool, blood0: float = 4.0, blood1: float = 4.0) -> NetSnapshot:
	var s := NetSnapshot.new()
	s.tick = tick
	for side: int in 2:
		var f := NetFighterSnap.new()
		f.dead = dead0 if side == 0 else dead1
		f.state = NetConfig.STATES.find("dead") if f.dead else 0
		f.blood = blood0 if side == 0 else blood1
		s.fighters.append(f)
	return s


func _res(winner: int, reason: String, ticks: int) -> Dictionary:
	return {"winner": winner, "reason": reason, "ticks": ticks}


func test_honest_results_pass() -> void:
	assert_eq(NetResultCheck.check(_res(0, "behead", 900), _snap(902, false, true), 180.0), "")
	assert_eq(NetResultCheck.check(_res(1, "blood_loss", 900), _snap(900, true, false), 180.0), "")
	assert_eq(NetResultCheck.check(_res(0, "ko", 900), _snap(900, false, false), 180.0), "", "a KO leaves both alive")
	assert_eq(NetResultCheck.check(_res(-1, "mutual", 900), _snap(900, true, true), 180.0), "")
	assert_eq(NetResultCheck.check(_res(1, "time", 10800), _snap(10800, false, false, 3.9, 4.2), 180.0), "")
	assert_eq(NetResultCheck.check(_res(-1, "time", 10800), _snap(10800, false, false, 3.0, 4.2), 180.0), "", "a draw is never flagged")


func test_forged_results_are_flagged() -> void:
	assert_true(NetResultCheck.check(_res(0, "behead", 900), _snap(902, false, false), 180.0) != "", "nobody was beheaded")
	assert_true(NetResultCheck.check(_res(0, "ko", 900), _snap(902, true, false), 180.0) != "", "the winner is dead")
	assert_true(NetResultCheck.check(_res(-1, "mutual", 900), _snap(900, true, false), 180.0) != "")
	assert_true(NetResultCheck.check(_res(0, "time", 3000), _snap(3000, false, false), 180.0) != "", "before the limit")
	assert_true(NetResultCheck.check(_res(0, "time", 10800), _snap(10800, false, false, 3.0, 4.2), 180.0) != "", "against the blood lead")


func test_unverified_when_snapshots_stop_short() -> void:
	assert_eq(NetResultCheck.check(_res(0, "behead", 900), _snap(880, false, false), 180.0), "")
	assert_eq(NetResultCheck.check(_res(0, "behead", 900), null, 180.0), "")
