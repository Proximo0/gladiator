extends TestCase

const GAP: float = 1.5
const MERGE: float = 0.15


func _hit(att: int, extra: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {"attacker": att, "target": 1 - att, "part": "torso", "total": 10.0}
	ev.merge(extra, true)
	return ev


func test_counts_blows_per_side() -> void:
	var t := FightTally.new()
	t.on_hit(_hit(0), 1.0, GAP, MERGE)
	t.on_hit(_hit(1), 3.0, GAP, MERGE)
	t.on_hit(_hit(0), 6.0, GAP, MERGE)
	assert_eq(t.hits, [2, 1] as Array[int])


func test_parries_and_self_hits_do_not_count() -> void:
	var t := FightTally.new()
	t.on_hit(_hit(0, {"hit_on_weapon": true}), 1.0, GAP, MERGE)
	t.on_hit({"attacker": 1, "target": 1}, 2.0, GAP, MERGE)
	assert_eq(t.hits, [0, 0] as Array[int])
	assert_eq(t.longest_combo, [0, 0] as Array[int])


func test_combo_runs_until_a_reply_or_a_gap() -> void:
	var t := FightTally.new()
	for i: int in 4:
		t.on_hit(_hit(0), 1.0 + 0.8 * float(i), GAP, MERGE)  # 4 blows, 0.8 s apart
	t.on_hit(_hit(1), 4.5, GAP, MERGE)  # reply breaks it
	t.on_hit(_hit(0), 4.9, GAP, MERGE)
	t.on_hit(_hit(0), 9.0, GAP, MERGE)  # too late: a new run
	assert_eq(t.longest_combo, [4, 1] as Array[int])


func test_one_swing_touching_two_parts_is_one_blow() -> void:
	var t := FightTally.new()
	t.on_hit(_hit(0), 1.0, GAP, MERGE)
	t.on_hit(_hit(0, {"part": "forearm_l"}), 1.05, GAP, MERGE)
	t.on_hit(_hit(0), 2.0, GAP, MERGE)
	assert_eq(t.hits[0], 2)
	assert_eq(t.longest_combo[0], 2)


func test_severs_go_to_the_other_side_and_finisher_is_kept() -> void:
	var t := FightTally.new()
	t.on_gore({"kind": "sever", "part": "forearm_l"}, 1)
	t.on_gore({"kind": "behead"}, 1)
	t.on_gore({"kind": "gut"}, 0)
	t.on_gore({"kind": "sever"}, 0)
	assert_eq(t.severs, [2, 1] as Array[int])
	t.on_hit(_hit(0, {"finisher": "behead"}), 5.0, GAP, MERGE)
	assert_eq(t.finisher, "behead")
