extends TestCase
## FlightRecorder: the recording format (round trip, version, quantization) and the trace comparison. No Match needed;
## a tiny fake match with the two signals drives the recorder itself.


class FakeMatch:
	extends Node
	signal inputs_applied(tick: int, inputs: Array)
	signal match_over(result: Dictionary)
	var seed: int = 77
	var fighters: Array = []
	var fight_start_tick: int = 0


func _sample_recording() -> Dictionary:
	return {
		"version": 1, "seed": 42, "loadouts": [{"weapon": "bat", "offhand": "", "armor": {"head": "helm_iron"}},
			{"weapon": "fists", "offhand": "", "armor": {}}],
		"personalities": [{"preset": "brute", "aggression": 0.75}, {"preset": "coward"}], "tuning": {"arm_force": 500.0},
		"ticks": 3, "inputs": [[[0, 0, 0, 0, 0], [1, 2, 3, 4, 5]], [[-1000, 1000, 5, -5, 129], [0, 0, 0, 0, 0]],
			[[10, 20, 30, 40, 1], [0, 0, 0, 0, 8]]],
		"result": {"winner": 1, "reason": "behead", "ticks": 3}, "trace_every": 10,
		"trace": [[0, 123456, [980, 1330, 4000, 5, 6, 7]], [10, 99, [1, 2, 3, 4, 5, 6]]],
	}


func test_round_trip_keeps_every_input_as_an_int() -> void:
	var rec: Dictionary = _sample_recording()
	var back: Dictionary = FlightRecorder.parse(FlightRecorder.to_json(rec))
	assert_false(back.has("error"), str(back.get("error", "")))
	assert_eq(back["seed"], 42)
	assert_eq(back["ticks"], 3)
	assert_eq(back["inputs"], rec["inputs"])
	assert_eq(typeof((back["inputs"] as Array)[1][0][0]), TYPE_INT)
	assert_eq(back["loadouts"], rec["loadouts"])
	assert_eq(back["personalities"], rec["personalities"])
	assert_eq(back["tuning"], rec["tuning"])
	assert_eq((back["result"] as Dictionary)["reason"], "behead")
	assert_eq(back["trace"], rec["trace"])
	assert_eq(typeof((back["trace"] as Array)[0][1]), TYPE_INT)


func test_inputs_round_trip_through_fighter_input() -> void:
	var fi := FighterInput.new()
	fi.move_x = -250
	fi.move_y = 1000
	fi.aim_x = 7
	fi.aim_y = -1000
	fi.buttons = FighterInput.SWING | FighterInput.THRUST | FighterInput.TURN_LOCK
	assert_eq(FlightRecorder.quantize_input(fi.to_array()), fi.to_array())


func test_version_is_checked() -> void:
	var rec: Dictionary = _sample_recording()
	rec["version"] = 2
	var back: Dictionary = FlightRecorder.parse(FlightRecorder.to_json(rec))
	assert_true(back.has("error"))
	assert_true(str(back["error"]).contains("version"))
	rec["version"] = 1
	rec["ticks"] = 9
	assert_true(FlightRecorder.parse(FlightRecorder.to_json(rec)).has("error"), "ticks must match inputs")
	assert_true(FlightRecorder.parse("not json").has("error"))
	assert_true(FlightRecorder.parse("[1, 2]").has("error"))
	assert_eq(FlightRecorder.validate(_sample_recording()), "")


func test_quantization_clamps_and_rounds() -> void:
	assert_eq(FlightRecorder.quantize_input([2000, -5000, 12.6, -0.4, 5]), [1000, -1000, 13, 0, 5])
	assert_eq(FlightRecorder.quantize_input([0, 0, 0, 0, 65536 + 3]), [0, 0, 0, 0, 3], "buttons are 16 bits")
	assert_eq(FlightRecorder.quantize_input([0, 0, 0, 0, FighterInput.ROLL | FighterInput.CLINCH]), [0, 0, 0, 0, 2304], "roll and close-range bits are recorded")
	assert_eq(FlightRecorder.quantize_input([1, 2]), [1, 2, 0, 0, 0], "missing entries are 0")
	assert_eq(FlightRecorder.quantize_input([]), [0, 0, 0, 0, 0])


func test_json_safe_handles_nan_and_vectors() -> void:
	var safe: Dictionary = FlightRecorder.json_safe({"a": NAN, "b": INF, "v": Vector3(1, 2, 3), "n": 2.5,
		"p": PackedStringArray(["x", "y"])}) as Dictionary
	assert_eq(safe["a"], null)
	assert_eq(safe["b"], null)
	assert_eq(safe["v"], [1.0, 2.0, 3.0])
	assert_eq(safe["n"], 2.5)
	assert_eq(safe["p"], ["x", "y"])
	var text: String = FlightRecorder.to_json({"stats": {"max": NAN}, "ticks": 0, "inputs": [], "version": 1})
	assert_true(JSON.parse_string(text) is Dictionary, "NaN must not break the JSON")


func test_compare_finds_the_first_difference() -> void:
	var a: Dictionary = _sample_recording()
	var b: Dictionary = _sample_recording()
	var same: Dictionary = FlightRecorder.compare(a, b)
	assert_near(float(same["divergence"]), 0.0)
	assert_eq(same["first_tick"], -1)
	assert_true(bool(same["hash_match"]))
	assert_eq(same["samples"], 2)
	(b["trace"] as Array)[1] = [10, 99, [1, 2, 3, 4, 5, 6 + 40]]  # 40 mm off
	var diff: Dictionary = FlightRecorder.compare(a, b)
	assert_near(float(diff["divergence"]), 0.04, 0.0001)
	assert_eq(diff["first_tick"], 10)
	(b["trace"] as Array)[0] = [0, 5, [980, 1330, 4000, 5, 6, 7]]
	var hashed: Dictionary = FlightRecorder.compare(a, b)
	assert_false(bool(hashed["hash_match"]))
	assert_eq(hashed["first_tick"], 0)


func test_recorder_collects_inputs_and_result() -> void:
	var m := FakeMatch.new()
	var r := FlightRecorder.new()
	r.attach(m)
	m.inputs_applied.emit(0, [[1, 2, 3, 4, 5], [0, 0, 0, 0, 0]])
	m.inputs_applied.emit(1, [[1500, 0, 0, 0, 1], [9, 9, 9, 9, 9]])
	m.match_over.emit({"winner": 0, "reason": "time", "ticks": 2, "seed": 99, "loadouts": [{"weapon": "club"}, {"weapon": "bat"}],
		"personalities": [{"preset": "duelist"}, {"preset": "brute"}], "stats": {"hits": 1, "max": NAN}})
	var rec: Dictionary = r.recording()
	assert_eq(rec["version"], 1)
	assert_eq(rec["ticks"], 2)
	assert_eq(rec["seed"], 99)
	assert_eq((rec["inputs"] as Array)[1][0], [1000, 0, 0, 0, 1], "inputs are quantized when recorded")
	assert_eq((rec["loadouts"] as Array)[0], {"weapon": "club"})
	assert_eq((rec["result"] as Dictionary)["reason"], "time")
	assert_false(FlightRecorder.parse(FlightRecorder.to_json(rec)).has("error"))
	m.inputs_applied.emit(0, [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]])  # a looping match starts over at tick 0
	assert_eq(r.recording()["ticks"], 1)
	r.free()
	m.free()


func test_save_and_load_file() -> void:
	var m := FakeMatch.new()
	var r := FlightRecorder.new()
	r.attach(m)
	m.inputs_applied.emit(0, [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]])
	var path: String = "user://recorder_test_%d.json" % hash(str(Time.get_ticks_usec()))
	assert_eq(r.save(path), path)
	var back: Dictionary = FlightRecorder.load_file(path)
	assert_false(back.has("error"), str(back.get("error", "")))
	assert_eq((back["inputs"] as Array)[0][1], [6, 7, 8, 9, 10])
	DirAccess.remove_absolute(path)
	assert_true(FlightRecorder.load_file("user://does_not_exist.json").has("error"))
	var empty := FlightRecorder.new()
	assert_eq(empty.save(), "", "nothing recorded, nothing written")
	empty.free()
	r.free()
	m.free()


## The intro skip moves fight_start_tick after the header (tick 0) was taken: the recording keeps the latest value.
func test_fight_start_tick_set_after_the_header_is_kept() -> void:
	var m := FakeMatch.new()
	var r := FlightRecorder.new()
	r.attach(m)
	m.inputs_applied.emit(0, [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]])
	m.inputs_applied.emit(1, [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]])
	assert_eq(r.recording()["fight_start_tick"], 0, "held: no release yet")
	m.fight_start_tick = 2  # start_fight_clock between ticks 1 and 2
	m.inputs_applied.emit(2, [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]])
	assert_eq(r.recording()["fight_start_tick"], 2)
	m.match_over.emit({"winner": -1, "reason": "time", "ticks": 3, "fight_ticks": 1})
	var back: Dictionary = FlightRecorder.parse(FlightRecorder.to_json(r.recording()))
	assert_eq(back["fight_start_tick"], 2)
	assert_eq(typeof(back["fight_start_tick"]), TYPE_INT)
	assert_eq(FlightRecorder.replay_config(back, false)["fight_start_tick"], 2)
	r.free()
	m.free()


func test_older_file_without_fight_start_tick_replays_from_zero() -> void:
	var rec: Dictionary = _sample_recording()
	assert_false(rec.has("fight_start_tick"))
	var back: Dictionary = FlightRecorder.parse(FlightRecorder.to_json(rec))
	assert_eq(back["fight_start_tick"], 0)
	var cfg: Dictionary = FlightRecorder.replay_config(back, false, 9.0)
	assert_eq(cfg["fight_start_tick"], 0)
	assert_near(float(cfg["time_limit_s"]), 9.0)
	assert_eq(cfg["seed"], 42)
	assert_false(bool(cfg["loop"]))
