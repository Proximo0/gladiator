extends TestCase


func test_hello_round_trip_and_check() -> void:
	var d: Dictionary = NetLobby.decode(NetLobby.hello("  Spartacus  ", {"weapon": "spear"}))
	assert_eq(int(d["_type"]), NetConfig.MSG_HELLO)
	assert_eq(d["name"], "Spartacus")
	assert_eq(str((d["loadout"] as Dictionary)["weapon"]), "spear")
	assert_eq(NetLobby.check_hello(d), "")


func test_version_mismatch_refused() -> void:
	var d: Dictionary = NetLobby.decode(NetLobby.encode(NetConfig.MSG_HELLO, {"v": 999, "name": "x"}))
	assert_true(NetLobby.check_hello(d).begins_with("version mismatch"))


func test_start_to_match_config() -> void:
	var d: Dictionary = NetLobby.decode(NetLobby.start(4242, [{"weapon": "gladius"}, {"weapon": "spear"}], 90.0, ["A", "B"]))
	var cfg: Dictionary = NetLobby.match_config(d, false)
	assert_eq(cfg["mode"], "player_vs_cpu")
	assert_eq(int(cfg["seed"]), 4242)
	assert_eq(str((cfg["loadouts"][1] as Dictionary)["weapon"]), "spear")
	assert_near(float(cfg["time_limit_s"]), 90.0)
	assert_false(bool(cfg["presentation"]))


func test_decode_rejects_unknown_and_objects() -> void:
	assert_eq(NetLobby.decode(PackedByteArray([NetConfig.MSG_SNAP, 1, 2])), {})
	assert_eq(NetLobby.decode(PackedByteArray([NetConfig.MSG_HELLO, 0, 0, 0, 0])), {})
	assert_eq(NetLobby.decode(NetLobby.encode(NetConfig.MSG_LEAVE, {}))["_type"], NetConfig.MSG_LEAVE)


func test_parse_address() -> void:
	assert_eq(NetLobby.parse_address("192.168.1.5"), ["192.168.1.5", NetConfig.DEFAULT_PORT])
	assert_eq(NetLobby.parse_address(" 10.0.0.2:9000 "), ["10.0.0.2", 9000])
	assert_eq(NetLobby.parse_address("[::1]:7778"), ["::1", 7778])
	assert_eq(NetLobby.parse_address("host:notaport"), [])
	assert_eq(NetLobby.parse_address("host:70000"), [])
	assert_eq(NetLobby.parse_address(""), [])


func test_over_drops_stats() -> void:
	var d: Dictionary = NetLobby.decode(NetLobby.over({"winner": 1, "reason": "ko", "ticks": 900, "stats": {"hits": 3}}))
	assert_eq(int(d["winner"]), 1)
	assert_eq(d["reason"], "ko")
	assert_false(d.has("stats"))
