extends TestCase


func test_severs_go_to_the_other_side_and_finisher_is_kept() -> void:
	var t := FightTally.new()
	t.on_gore({"kind": "sever", "part": "forearm_l"}, 1)
	t.on_gore({"kind": "behead"}, 1)
	t.on_gore({"kind": "gut"}, 0)
	t.on_gore({"kind": "sever"}, 0)
	assert_eq(t.severs, [2, 1] as Array[int])
	t.on_hit({"attacker": 0, "target": 1, "finisher": "behead"})
	t.on_hit({"attacker": 1, "target": 0, "finisher": "gut"})
	assert_eq(t.finisher, "behead")


func test_parried_finisher_is_ignored() -> void:
	var t := FightTally.new()
	t.on_hit({"attacker": 0, "target": 1, "finisher": "gut", "hit_on_weapon": true})
	assert_eq(t.finisher, "")
