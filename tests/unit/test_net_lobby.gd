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
	assert_eq(int(cfg["fight_start_tick"]), 0, "no intro: the fight clock starts at tick 0")


func test_start_carries_the_fight_tick() -> void:
	var d: Dictionary = NetLobby.decode(NetLobby.start(7, [{}, {}], 180.0, ["A", "B"], 138))
	assert_eq(int(NetLobby.match_config(d, false)["fight_start_tick"]), 138)
	var huge: Dictionary = NetLobby.decode(NetLobby.start(7, [{}, {}], 180.0, ["A", "B"], 1 << 30))
	assert_eq(int(NetLobby.match_config(huge, false)["fight_start_tick"]), NetLobby.MAX_FIGHT_TICK, "capped")
	var neg: Dictionary = NetLobby.decode(NetLobby.encode(NetConfig.MSG_START, {"seed": 1, "fight_tick": -50}))
	assert_eq(int(NetLobby.match_config(neg, false)["fight_start_tick"]), 0, "never negative")


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


func test_content_hash_ignores_formatting_and_order_but_not_values() -> void:
	var a: String = NetLobby.content_hash(['{"a": 1, "b": [1, 2]}', '{"x": 0.5}'], {"k": 1.0, "j": 2.0})
	assert_eq(a.length(), NetLobby.CONTENT_HASH_CHARS)
	assert_eq(NetLobby.content_hash(['{"x":0.5}\r\n', '{\n\t"b": [1,2], "a": 1}'], {"j": 2.0, "k": 1.0}), a, "spacing, key order, file order")
	assert_true(NetLobby.content_hash(['{"a": 1, "b": [1, 3]}', '{"x": 0.5}'], {"k": 1.0, "j": 2.0}) != a, "data value")
	assert_true(NetLobby.content_hash(['{"a": 1, "b": [1, 2]}', '{"x": 0.5}'], {"k": 1.0, "j": 2.5}) != a, "tuning value")
	assert_true(NetLobby.content_hash(['{"a": 1, "b": [1, 2]}'], {"k": 1.0, "j": 2.0}) != a, "missing file")


func test_content_mismatch_refused_with_clear_message_on_both_sides() -> void:
	var mine: String = "aaaaaaaaaaaaaaaa"
	var theirs: String = "bbbbbbbbbbbbbbbb"
	var d: Dictionary = NetLobby.decode(NetLobby.hello("x", {"weapon": "spear"}, theirs))
	assert_eq(NetLobby.check_hello(d, theirs), "")
	var why: String = NetLobby.check_hello(d, mine)
	assert_true(why.begins_with("version mismatch"), why)
	assert_true(why.contains("bbbbbbbb") and why.contains("aaaaaaaa"), why)
	# The host's refusal reaches the client as the same text.
	var l: Dictionary = NetLobby.decode(NetLobby.lobby("h", {}, false, why, mine))
	assert_false(bool(l["accepted"]))
	assert_eq(str(l["reason"]), why)
	# A host that accepted but runs other data is caught by the client too.
	var accepted: Dictionary = NetLobby.decode(NetLobby.lobby("h", {}, true, "", theirs))
	assert_true(NetLobby.check_peer(accepted, mine, true).begins_with("version mismatch: different game data"))
	assert_eq(NetLobby.check_peer(accepted, theirs, true), "")


func test_hello_without_a_hash_is_refused_when_checking() -> void:
	var d: Dictionary = NetLobby.decode(NetLobby.hello("x", {}))
	assert_true(NetLobby.check_hello(d, "aaaaaaaaaaaaaaaa").begins_with("version mismatch"))
	assert_eq(NetLobby.check_hello(d), "", "no own hash: only the protocol version is checked")
