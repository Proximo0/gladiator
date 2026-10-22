extends TestCase


func _frame(side: int, state: String = "standing", tip: float = 0.0, vel: Vector3 = Vector3.ZERO, y: float = 1.0) -> Dictionary:
	return {"side": side, "state": state, "tip_speed": tip, "pelvis_vel": vel,
		"parts": {"pelvis": {"pos": Vector3(float(side), y, 0.0), "hp": 1.0, "severed": false}}}


func _at(side: int, x: float, z: float, weapon: String = "fists") -> Dictionary:
	var f: Dictionary = _frame(side)
	f["pelvis_pos"] = Vector3(x, 1.0, z)
	f["weapon_id"] = weapon
	return f


func _reach(weapon: String) -> float:
	return 0.9 + 0.9 * float(CombatData.weapon(weapon).get("length", 0.3))


func test_arena_distance_mean() -> void:
	var s := MatchStats.new()
	s.on_frames([_at(0, 0.0, 0.0), _at(1, 3.0, 4.0)], 1.0 / 60.0)  # 5 m
	s.on_frames([_at(0, 0.0, 0.0), _at(1, 0.0, 1.0)], 1.0 / 60.0)  # 1 m
	var d: Dictionary = s.to_dict()
	assert_near(s.dist_sum, 6.0)
	assert_near(float(d["mean_dist"]), 3.0)


func test_strike_share_uses_reach_with_margin() -> void:
	var r: float = 1.05 * _reach("fists")
	var s := MatchStats.new()
	s.on_frames([_at(0, 0.0, 0.0), _at(1, r * 0.99, 0.0)], 1.0 / 60.0)  # inside
	s.on_frames([_at(0, 0.0, 0.0), _at(1, r * 1.01, 0.0)], 1.0 / 60.0)  # outside
	s.on_frames([_at(0, 0.0, 0.0), _at(1, 50.0, 0.0)], 1.0 / 60.0)  # outside
	assert_eq(s.strike_ticks, 1)
	assert_near(float(s.to_dict()["strike_share"]), 1.0 / 3.0, 0.0001)


func test_strike_uses_either_fighters_weapon() -> void:
	var longest: String = ""
	var longest_len: float = -1.0
	for id: String in CombatData.weapon_ids():
		var len_: float = float(CombatData.weapon(id).get("length", 0.3))
		if len_ > longest_len:
			longest_len = len_
			longest = id
	var d: float = 1.05 * _reach(longest) * 0.99
	assert_true(d > 1.05 * _reach("fists"), "the longest weapon reaches past fists")
	var s := MatchStats.new()
	s.on_frames([_at(0, 0.0, 0.0, "fists"), _at(1, d, 0.0, longest)], 1.0 / 60.0)
	assert_eq(s.strike_ticks, 1, "one fighter's reach is enough")
	var t := MatchStats.new()
	t.on_frames([_at(0, 0.0, 0.0, "fists"), _at(1, d, 0.0, "fists")], 1.0 / 60.0)
	assert_eq(t.strike_ticks, 0)


func test_travel_is_horizontal_per_side() -> void:
	var s := MatchStats.new()
	s.on_frames([_at(0, 0.0, 0.0), _at(1, 10.0, 10.0)], 1.0 / 60.0)
	s.on_frames([_at(0, 3.0, 4.0), _at(1, 10.0, 10.0)], 1.0 / 60.0)  # side 0 steps 5 m
	s.on_frames([_at(0, 3.0, 4.0), _at(1, 10.0, 11.0)], 1.0 / 60.0)  # side 1 steps 1 m
	var d: Dictionary = s.to_dict()
	assert_near(float(d["travel0"]), 5.0)
	assert_near(float(d["travel1"]), 1.0)
	var y_only := MatchStats.new()  # a height change must not count as travel
	var high: Dictionary = _at(0, 1.0, 1.0)
	high["pelvis_pos"] = Vector3(1.0, 9.0, 1.0)
	y_only.on_frames([_at(0, 1.0, 1.0), _at(1, 20.0, 0.0)], 1.0 / 60.0)
	y_only.on_frames([high, _at(1, 20.0, 0.0)], 1.0 / 60.0)
	assert_near(float(y_only.to_dict()["travel0"]), 0.0)


func test_cells_are_floored_grid_cells_of_either_pelvis() -> void:
	var s := MatchStats.new()
	s.on_frames([_at(0, 0.2, 0.7), _at(1, -0.5, 1.5)], 1.0 / 60.0)  # (0,0), (-1,1)
	s.on_frames([_at(0, 0.9, 0.1), _at(1, -0.1, 1.9)], 1.0 / 60.0)  # (0,0) again, (-1,1) again
	s.on_frames([_at(0, 2.4, -3.2), _at(1, -0.5, 1.5)], 1.0 / 60.0)  # (2,-4) new
	assert_true(s.cells.has(Vector2i(0, 0)))
	assert_true(s.cells.has(Vector2i(-1, 1)))
	assert_true(s.cells.has(Vector2i(2, -4)))
	assert_eq(s.to_dict()["cells"], 3)


func test_nan_pelvis_skips_arena_sums() -> void:
	var s := MatchStats.new()
	s.on_frames([_at(0, 0.0, 0.0), _at(1, 2.0, 0.0)], 1.0 / 60.0)
	s.on_frames([_at(0, NAN, 0.0), _at(1, 2.0, 0.0)], 1.0 / 60.0)
	var d: Dictionary = s.to_dict()
	assert_near(float(d["mean_dist"]), 2.0)
	assert_near(float(d["travel0"]), 0.0)
	assert_eq(d["cells"], 2)


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


func _blow(att: int, part: String = "torso") -> Dictionary:
	return {"attacker": att, "target": 1 - att, "part": part, "contact": "edge", "total": 10.0}


func test_one_swing_touching_two_parts_is_one_blow() -> void:
	var s := MatchStats.new()
	s.on_hit(_blow(0), 1.0)
	s.on_hit(_blow(0, "forearm_l"), 1.05)  # the same swing, inside combo_merge_s
	s.on_hit(_blow(0), 2.0)
	assert_eq(s.hits_by_side, [3, 0], "contacts")
	assert_eq(s.blows_by_side, [2, 0], "blows")
	assert_eq(s.longest_combo, [2, 0])


func test_combo_runs_until_a_reply_or_a_gap() -> void:
	var s := MatchStats.new()
	for i: int in 4:
		s.on_hit(_blow(0), 1.0 + 0.8 * float(i))  # 4 blows, 0.8 s apart
	s.on_hit(_blow(1), 4.5)  # a reply breaks it
	s.on_hit(_blow(0), 4.9)
	s.on_hit(_blow(0), 9.0)  # past combo_gap_s: a new run
	assert_eq(s.blows_by_side, [6, 1])
	assert_eq(s.longest_combo, [4, 1])


func test_parries_and_self_hits_are_not_blows() -> void:
	var s := MatchStats.new()
	s.on_hit({"attacker": 0, "target": 1, "hit_on_weapon": true}, 1.0)
	s.on_hit({"attacker": 1, "target": 1, "contact": "flat"}, 2.0)
	assert_eq(s.blows_by_side, [0, 0])
	assert_eq(s.longest_combo, [0, 0])


## "Hits landed" and "Longest combo" read the same blows: a side's combo never exceeds its blows, and a burst of
## contacts inside the merge window adds one to each.
func test_hits_landed_and_longest_combo_agree() -> void:
	var s := MatchStats.new()
	for i: int in 3:
		var t: float = 1.0 + 0.5 * float(i)
		s.on_hit(_blow(0), t)
		s.on_hit(_blow(0, "upper_arm_l"), t + 0.02)
		s.on_hit(_blow(0, "head"), t + 0.04)
	assert_eq(s.hits_by_side[0], 9)
	assert_eq(s.blows_by_side[0], 3)
	assert_eq(s.longest_combo[0], 3)
	var d: Dictionary = s.to_dict()
	assert_eq(d["blows_by_side"], [3, 0])
	assert_eq(d["longest_combo"], [3, 0])


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
	var p := MatchStats.new()
	p.on_gore({"kind": "pummel", "part": "head"})
	assert_eq(p.to_dict()["finisher"], "pummel")
	assert_eq(p.to_dict()["severs"], 0)


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
			"disarms", "arm_drops", "rearms", "rearms_after_disarm", "stamina0_max_s", "getup_fails", "armor_dislodged", "self_hits", "knockdowns", "blows_by_side", "longest_combo", "time_down_s", "stuck_s", "explosions",
			"wall_time_s", "blood_left", "mean_dist", "strike_share", "travel0", "travel1", "cells"]:
		assert_true(d.has(k), k)


func test_weapon_log_arm_drops_and_rearms() -> void:
	var s := MatchStats.new()
	var a: Dictionary = _frame(0)
	var b: Dictionary = _frame(1)
	a["weapon_log"] = {"disarms": 1, "arm_drops": 1, "rearms": 0}
	b["weapon_log"] = {"disarms": 0, "arm_drops": 0, "rearms": 1}
	s.on_frames([a, b], 1.0 / 60.0)
	a["weapon_log"] = {"disarms": 1, "arm_drops": 1, "rearms": 2, "rearms_after_disarm": 1}
	s.on_frames([a, b], 1.0 / 60.0)
	var d: Dictionary = s.to_dict()
	assert_eq(d["arm_drops"], 1, "latest cumulative log, not a sum over ticks")
	assert_eq(d["rearms"], 3)
	assert_eq(d["rearms_after_disarm"], 1)
	assert_eq(d["disarms"], 0, "disarms come from hit events only")


func test_stamina_zero_run_and_getup_fails() -> void:
	var s := MatchStats.new()
	var dt: float = 0.5
	var a: Dictionary = _frame(0, "getting_up")
	a["stamina"] = 0.0
	for i: int in range(4):
		s.on_frames([a, _frame(1)], dt)
	a["stamina"] = 0.3
	s.on_frames([a, _frame(1)], dt)
	a["stamina"] = 0.0
	s.on_frames([a, _frame(1)], dt)
	assert_near(float(s.to_dict()["stamina0_max_s"]), 2.0)
	a["state"] = "down"
	s.on_frames([a, _frame(1)], dt)
	assert_eq(s.to_dict()["getup_fails"], 1)
