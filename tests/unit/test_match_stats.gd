extends TestCase


func _frame(side: int, state: String = "standing", tip: float = 0.0, vel: Vector3 = Vector3.ZERO, y: float = 1.0) -> Dictionary:
	return {"side": side, "state": state, "tip_speed": tip, "pelvis_vel": vel,
		"parts": {"pelvis": {"pos": Vector3(float(side), y, 0.0), "hp": 1.0, "severed": false}}}


func test_hit_counts_and_kinds() -> void:
	var s := MatchStats.new()
	s.on_hit({"attacker": 0, "target": 1, "contact": "edge", "total": 10.0})
	s.on_hit({"attacker": 1, "target": 0, "contact": "blunt", "disarmed": true, "dislodge": true})
	s.on_hit({"attacker": 1, "target": 1, "contact": "flat"})
	s.on_hit({"attacker": 0, "target": 1, "contact": "edge", "hit_on_weapon": true})
	var d: Dictionary = s.to_dict()
	assert_eq(d["hits"], 3)
	assert_eq(d["hits_by_side"], [1, 2])
	assert_eq(d["self_hits"], 1)
	assert_eq(d["disarms"], 1)
	assert_eq(d["armor_dislodged"], 1)
	assert_eq(d["parries"], 1)
	assert_eq((d["contact_kinds"] as Dictionary)["edge"], 1)
	assert_eq((d["contact_kinds"] as Dictionary)["blunt"], 1)
	assert_eq((d["contact_kinds"] as Dictionary)["flat"], 1)


func test_finisher_and_severs() -> void:
	var s := MatchStats.new()
	s.on_gore({"kind": "sever", "part": "forearm_r"})
	s.on_gore({"kind": "bleed", "part": "torso"})
	assert_eq(s.to_dict()["severs"], 1)
	assert_eq(s.to_dict()["finisher"], "")
	s.on_hit({"attacker": 0, "target": 1, "contact": "point", "finisher": "run_through"})
	assert_eq(s.to_dict()["finisher"], "run_through")
	var t := MatchStats.new()
	t.on_gore({"kind": "behead", "part": "head"})
	assert_eq(t.to_dict()["finisher"], "behead")
	assert_eq(t.to_dict()["severs"], 1)


func test_swing_speed_stats() -> void:
	var s := MatchStats.new()
	s.on_frames([_frame(0, "standing", 6.0), _frame(1, "standing", 0.5)], 1.0 / 60.0)
	s.on_frames([_frame(0, "standing", 10.0), _frame(1, "standing", 0.5)], 1.0 / 60.0)
	var d: Dictionary = s.to_dict()
	assert_near(float(d["max_tip_speed"]), 10.0)
	assert_near(float(d["mean_tip_speed"]), 8.0)
	assert_eq(d["ticks"], 2)


func test_knockdown_and_time_down() -> void:
	var s := MatchStats.new()
	var dt: float = 0.5
	s.on_frames([_frame(0), _frame(1)], dt)
	s.on_frames([_frame(0, "down"), _frame(1)], dt)
	s.on_frames([_frame(0, "down"), _frame(1)], dt)
	s.on_frames([_frame(0, "getting_up"), _frame(1)], dt)
	s.on_frames([_frame(0), _frame(1, "ko")], dt)
	var d: Dictionary = s.to_dict()
	assert_eq(d["knockdowns"], 1, "ko is not a knockdown, a second down tick is not a new one")
	assert_near(float(d["time_down_s"]), 2.0)


func test_stuck_needs_both_still_past_grace() -> void:
	var s := MatchStats.new()
	var dt: float = 0.5
	for i: int in 6:
		s.on_frames([_frame(0), _frame(1)], dt)  # 3 s still: inside the grace
	assert_near(float(s.to_dict()["stuck_s"]), 0.0)
	for i: int in 4:
		s.on_frames([_frame(0), _frame(1)], dt)
	assert_near(float(s.to_dict()["stuck_s"]), 2.0)
	s.on_frames([_frame(0, "standing", 0.0, Vector3(1, 0, 0)), _frame(1)], dt)
	s.on_frames([_frame(0), _frame(1)], dt)
	assert_near(float(s.to_dict()["stuck_s"]), 2.0, 0.0001, "movement resets the run")
	var t := MatchStats.new()
	for i: int in 20:
		t.on_frames([_frame(0, "standing", 5.0), _frame(1)], dt)
	assert_near(float(t.to_dict()["stuck_s"]), 0.0, 0.0001, "a swinging fighter is not stuck")


func test_explosions() -> void:
	var s := MatchStats.new()
	var dt: float = 1.0 / 60.0
	s.on_frames([_frame(0), _frame(1)], dt)
	s.on_frames([_frame(0), _frame(1)], dt)
	assert_eq(s.to_dict()["explosions"], 0)
	s.on_frames([_frame(0, "standing", 0.0, Vector3.ZERO, 3.0), _frame(1)], dt)  # 2 m in one tick = 120 m/s
	assert_eq(s.to_dict()["explosions"], 1)
	var n := MatchStats.new()
	n.on_frames([_frame(0, "standing", 0.0, Vector3.ZERO, NAN), _frame(1)], dt)
	assert_eq(n.to_dict()["explosions"], 1, "NaN position")
	var f := MatchStats.new()
	f.on_frames([_frame(0, "standing", 0.0, Vector3(0, -50, 0)), _frame(1)], dt)
	assert_eq(f.to_dict()["explosions"], 1, "pelvis speed over 40")
	var g := MatchStats.new()
	g.on_frames([_frame(0, "standing", 0.0, Vector3.ZERO, -9.0), _frame(1)], dt)
	assert_eq(g.to_dict()["explosions"], 1, "fell through the floor")


func test_to_dict_has_contract_keys() -> void:
	var d: Dictionary = MatchStats.new().to_dict()
	for k: String in ["hits", "hits_by_side", "contact_kinds", "max_tip_speed", "mean_tip_speed", "severs", "finisher",
			"disarms", "armor_dislodged", "self_hits", "knockdowns", "time_down_s", "stuck_s", "explosions",
			"wall_time_s", "blood_left"]:
		assert_true(d.has(k), k)
