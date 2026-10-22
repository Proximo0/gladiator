extends TestCase

const DT: float = 1.0 / 60.0


func _frame(side: int, pos: Vector3, yaw: float) -> Dictionary:
	var parts: Dictionary = {}
	var offs: Dictionary = {
		"pelvis": 0.95, "torso": 1.3, "head": 1.65, "upper_arm_l": 1.4, "upper_arm_r": 1.4, "forearm_l": 1.2,
		"forearm_r": 1.2, "thigh_l": 0.7, "thigh_r": 0.7, "shin_l": 0.3, "shin_r": 0.3,
	}
	for n: String in offs:
		parts[n] = {"pos": Vector3(pos.x, float(offs[n]), pos.z), "hp": 50.0, "severed": false}
	return {
		"tick": 0, "side": side, "pelvis_pos": Vector3(pos.x, 0.95, pos.z), "pelvis_vel": Vector3.ZERO,
		"facing_yaw": yaw, "balance": 1.0, "stamina": 1.0, "consciousness": 1.0, "hand_target": Vector3.ZERO,
		"hand_pos": Vector3.ZERO, "tip_pos": Vector3(pos.x, 1.2, pos.z - 0.5), "tip_speed": 0.0, "weapon_id": "gladius",
		"grip": "normal", "parts": parts, "contacts": [], "state": "standing", "blood_frac": 1.0,
	}


func _brain(diff: String, extra: Dictionary = {}) -> FighterBrain:
	var p: Dictionary = {"preset": "duelist", "spawn_hold": 0, "difficulty": diff, "risk": 0.0}
	p.merge(extra, true)
	return FighterBrain.new(11, p)


## A foe at `dist` swinging hard at me for `swing_ticks` ticks; returns how many ticks passed before the brain's
## first guard (SWING and OFFHAND held together), or -1.
func _first_guard(b: FighterBrain, swing_from: int) -> int:
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0)
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -1.6), PI)
	for t in 120:
		var fast: bool = t >= swing_from
		foe["tip_speed"] = 9.0 if fast else 0.0
		foe["tip_pos"] = Vector3(0.0, 1.2, -1.6 + (float(t - swing_from) * 0.05 if fast else 0.0))
		var inp: FighterInput = b.think(me, foe, DT)
		if fast and inp.has(FighterInput.SWING) and inp.has(FighterInput.OFFHAND):
			return t - swing_from
	return -1


func test_table_is_complete_and_ordered() -> void:
	var keys: Array = AiDifficulty.params("normal").keys()
	for id: String in AiDifficulty.IDS:
		var p: Dictionary = AiDifficulty.params(id)
		for k: Variant in keys:
			assert_true(p.has(k), "%s has %s" % [id, str(k)])
		assert_eq(AiDifficulty.label(id) != id, true, "label for " + id)
	assert_true(float(AiDifficulty.params("easy")["reaction_scale"]) > float(AiDifficulty.params("normal")["reaction_scale"]))
	assert_true(float(AiDifficulty.params("hard")["reaction_scale"]) < float(AiDifficulty.params("normal")["reaction_scale"]))
	assert_true(float(AiDifficulty.params("hard")["aim_noise_scale"]) < float(AiDifficulty.params("easy")["aim_noise_scale"]))
	assert_eq(AiDifficulty.normalize("nope"), "normal")


func test_normal_is_the_identity() -> void:
	var a := FighterBrain.new(5, {"preset": "brute", "spawn_hold": 0})
	var b := FighterBrain.new(5, {"preset": "brute", "spawn_hold": 0, "difficulty": "normal"})
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0)
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -3.0), PI)
	for t in 400:
		foe["tip_speed"] = 6.0 if (t % 90) > 70 else 0.0
		var x: FighterInput = a.think(me, foe, DT)
		var y: FighterInput = b.think(me, foe, DT)
		if x.buttons != y.buttons or x.aim_x != y.aim_x or x.aim_y != y.aim_y or x.move_x != y.move_x or x.move_y != y.move_y:
			assert_true(false, "tick %d differs" % t)
			return
	assert_eq(a.difficulty(), "normal")
	assert_eq(a.personality().get("aggression"), b.personality().get("aggression"))


func test_reaction_delay_by_difficulty() -> void:
	var easy := _brain("easy", {"reaction_ms": 200.0})
	var norm := _brain("normal", {"reaction_ms": 200.0})
	var hard := _brain("hard", {"reaction_ms": 200.0})
	var e: int = _first_guard(easy, 20)
	var n: int = _first_guard(norm, 20)
	var h: int = _first_guard(hard, 20)
	assert_true(n >= 0 and h >= 0, "normal and hard guard")
	assert_true(h < n, "hard guards sooner (%d vs %d)" % [h, n])
	assert_true(e == -1 or e > n, "easy is slower or misses it (%d vs %d)" % [e, n])


func test_hard_guards_more_often_than_easy() -> void:
	var easy_guards: int = 0
	var hard_guards: int = 0
	for s in 40:
		var e := FighterBrain.new(s, {"preset": "brute", "spawn_hold": 0, "difficulty": "easy", "reaction_ms": 0.0, "risk": 0.0})
		var h := FighterBrain.new(s, {"preset": "brute", "spawn_hold": 0, "difficulty": "hard", "reaction_ms": 0.0, "risk": 0.0})
		if _first_guard(e, 20) >= 0:
			easy_guards += 1
		if _first_guard(h, 20) >= 0:
			hard_guards += 1
	assert_true(hard_guards > easy_guards, "hard %d easy %d" % [hard_guards, easy_guards])


func test_easy_hand_is_slower() -> void:
	var easy := _brain("easy", {"aim_noise": 0.0, "preset": "berserker"})
	var norm := _brain("hard", {"aim_noise": 0.0, "preset": "berserker"})
	var me: Dictionary = _frame(0, Vector3.ZERO, 0.0)
	var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -1.2), PI)
	var worst_e: float = 0.0
	var worst_n: float = 0.0
	var le := Vector2(0.0, 0.15)
	var ln := Vector2(0.0, 0.15)
	for t in 300:
		var ie: FighterInput = easy.think(me, foe, DT)
		var inn: FighterInput = norm.think(me, foe, DT)
		var ce := Vector2(ie.aim_x, ie.aim_y) / 1000.0
		var cn := Vector2(inn.aim_x, inn.aim_y) / 1000.0
		if t > 2:
			worst_e = maxf(worst_e, ce.distance_to(le))
			worst_n = maxf(worst_n, cn.distance_to(ln))
		le = ce
		ln = cn
	assert_true(worst_e <= float(AiDifficulty.params("easy")["aim_slew"]) + 0.002, "easy aim step %f" % worst_e)
	assert_true(worst_n > worst_e, "hard moves faster (%f vs %f)" % [worst_n, worst_e])


func test_easy_misses_a_finisher_hard_does_not() -> void:
	var hard_saw: int = 0
	var easy_saw: int = 0
	for s in 20:
		for diff: String in ["easy", "hard"]:
			var b := FighterBrain.new(s, {"preset": "duelist", "spawn_hold": 0, "difficulty": diff, "reaction_ms": 0.0})
			var me: Dictionary = _frame(0, Vector3.ZERO, 0.0)
			var foe: Dictionary = _frame(1, Vector3(0.0, 0.0, -1.0), PI)
			foe["state"] = "down"
			var saw: bool = false
			for t in 30:
				b.think(me, foe, DT)
				if b.state_name() == "finish" or (b.plan().get("finishing", false) as bool):
					saw = true
			if saw:
				if diff == "hard":
					hard_saw += 1
				else:
					easy_saw += 1
	assert_eq(hard_saw, 20, "hard always goes for the downed foe")
	assert_true(easy_saw < 20, "easy sometimes dithers (%d)" % easy_saw)


func test_difficulty_scales_personality_knobs() -> void:
	var h: Dictionary = _brain("hard").personality()
	var n: Dictionary = _brain("normal").personality()
	var e: Dictionary = _brain("easy").personality()
	assert_true(float(e["aggression"]) > float(n["aggression"]), "easy is reckless")
	assert_true(float(h["retreat_stamina"]) > float(n["retreat_stamina"]), "hard rests earlier")
	assert_true(float(e["retreat_stamina"]) < float(n["retreat_stamina"]), "easy fights on tired")
