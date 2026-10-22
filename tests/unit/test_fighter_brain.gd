extends TestCase

const DT: float = 1.0 / 60.0


func _frame(side: int, pos: Vector3, yaw: float, weapon: String = "gladius") -> Dictionary:
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
		"hand_pos": Vector3.ZERO, "tip_pos": Vector3(pos.x, 1.2, pos.z - 0.5), "tip_speed": 0.0, "weapon_id": weapon,
		"grip": "normal", "parts": parts, "contacts": [], "state": "standing",
	}


## Me at the origin facing -Z (yaw 0), foe `dist` metres ahead.
func _pair(dist: float, weapon: String = "gladius") -> Array:
	return [_frame(0, Vector3.ZERO, 0.0, weapon), _frame(1, Vector3(0.0, 0.0, -dist), PI, "gladius")]


func _brain(personality: Dictionary = {}) -> FighterBrain:
	var p: Dictionary = {"reaction_ms": 0.0, "aim_noise": 0.0, "spawn_hold": 0}
	p.merge(personality, true)
	return FighterBrain.new(7, p)


func test_approaches_when_far() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(7.0)
	var inp: FighterInput = null
	for i in 5:
		inp = b.think(f[0], f[1], DT)
	assert_true(inp.move_y > 500, "walks forward")
	assert_false(inp.has(FighterInput.SWING), "no swing when far")
	assert_true(inp.has(FighterInput.SPRINT), "sprints to close a long gap")


func test_winds_up_then_sweeps_through() -> void:
	var b := _brain({"preset": "berserker", "preferred_attacks": ["horizontal"], "difficulty": "normal"})
	var f: Array = _pair(1.2)
	var wind: Vector2 = Vector2.ZERO
	var end: Vector2 = Vector2.ZERO
	var saw_windup: bool = false
	var saw_strike: bool = false
	var strike_swing: bool = false
	for i in 200:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if b.state_name() == "windup":
			saw_windup = true
			wind = inp.aim()
		if b.state_name() == "strike":
			saw_strike = true
			end = inp.aim()
			strike_swing = inp.has(FighterInput.SWING)
	assert_true(saw_windup and saw_strike, "windup then strike")
	assert_true(strike_swing, "SWING held in the strike")
	assert_true(absf(wind.x - end.x) > 0.8, "hand sweeps across the target: %s to %s" % [wind, end])


func test_guards_against_fast_incoming_tip() -> void:
	var b := _brain({"preset": "duelist", "risk": 0.0})
	var f: Array = _pair(1.5)
	var foe: Dictionary = f[1]
	var inp: FighterInput = null
	for i in 10:
		foe["tip_speed"] = 8.0
		foe["tip_pos"] = Vector3(0.6, 1.7, -1.2 + 0.1 * i)
		inp = b.think(f[0], foe, DT)
	assert_eq(b.state_name(), "guard")
	assert_true(inp.aim_x > 100, "weapon goes to the right side of the incoming tip: %d" % inp.aim_x)
	assert_true(inp.aim_y > 100, "and up")
	assert_true(inp.has(FighterInput.OFFHAND), "offhand raised")


func test_thrusts_with_a_spear() -> void:
	var b := _brain({"preset": "berserker"})
	var f: Array = _pair(3.0, "spear")
	var thrust_seen: bool = false
	var early: bool = false
	for i in 300:
		# The point closes on the chest at 4 m/s while the spear drives in.
		var me: Dictionary = f[0]
		var tc: float = 1.2 - 4.0 / 60.0 * float(i % 40) if b.state_name() == "strike" else 1.2
		me["tip_pos"] = Vector3(0.0, 1.3, -3.0 + maxf(tc, 0.05))
		me["pelvis_vel"] = Vector3(0.0, 0.0, -4.0) if b.state_name() == "strike" else Vector3.ZERO
		var inp: FighterInput = b.think(me, f[1], DT)
		if b.state_name() == "strike" and inp.has(FighterInput.THRUST):
			thrust_seen = true
			early = tc > 0.8
			break
	assert_true(thrust_seen, "spear strikes use THRUST")
	assert_false(early, "THRUST waits until the point is about to arrive")
	assert_eq(str(b.plan()["kind"]), "thrust")


func test_pole_miss_is_the_offset_from_the_blade_line() -> void:
	var hand := Vector3(0.0, 1.2, -0.5)
	var tip := Vector3(0.0, 1.2, -2.4)
	assert_true(FighterBrain.pole_miss(hand, tip, Vector3(0.0, 1.2, -3.0), Vector3.RIGHT).length() < 0.0001, "on the line")
	var m: Vector2 = FighterBrain.pole_miss(hand, tip, Vector3(0.3, 1.1, -3.0), Vector3.RIGHT)
	assert_true(absf(m.x - 0.3) < 0.0001 and absf(m.y + 0.1) < 0.0001, "right and below: %s" % m)


func test_spear_servo_steers_the_blade_line_toward_the_target() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(3.0, "spear")
	# Blade levelled straight ahead but 0.3 m left of and 0.2 m below the foe's chest.
	(f[0] as Dictionary)["hand_pos"] = Vector3(-0.3, 1.1, -0.5)
	(f[0] as Dictionary)["tip_pos"] = Vector3(-0.3, 1.1, -2.4)
	var inp: FighterInput = null
	for i in 40:
		inp = b.think(f[0], f[1], DT)
	assert_true(inp.has(FighterInput.SWING), "pole stance keeps the blade level")
	assert_true(inp.aim_x > 0, "aim moves right toward the line: %d" % inp.aim_x)
	assert_true(inp.aim_y > 150, "aim moves up toward the line: %d" % inp.aim_y)


func test_spear_gives_ground_when_the_foe_is_inside_the_point() -> void:
	var b := _brain({"preset": "berserker"})
	var f: Array = _pair(1.6, "spear")
	var back: int = 0
	var thrusts: int = 0
	for i in 120:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if inp.move_y < 0:
			back += 1
		if inp.has(FighterInput.THRUST):
			thrusts += 1
	assert_true(back > 60, "backs off to make room for the point (%d ticks)" % back)
	assert_eq(thrusts, 0, "never thrusts with the point already past the foe")


func test_foe_of_a_spear_closes_in_while_guarding_out_of_reach() -> void:
	var b := _brain({"preset": "duelist", "risk": 0.0})
	var f: Array = _pair(3.0, "longsword")
	(f[1] as Dictionary)["weapon_id"] = "spear"
	(f[1] as Dictionary)["tip_speed"] = 8.0
	(f[1] as Dictionary)["tip_pos"] = Vector3(0.0, 1.3, -0.9)
	var fwd: int = 0
	for i in 30:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if b.state_name() == "guard" and inp.move_y > 0:
			fwd += 1
	assert_true(fwd > 0, "steps in past the point instead of standing in guard")


func test_goes_for_the_neck_when_foe_blood_is_low() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(1.2)
	(f[1] as Dictionary)["blood_frac"] = 0.15
	var plans: int = 0
	var necks: int = 0
	var was: String = ""
	for i in 600:
		b.think(f[0], f[1], DT)
		if b.state_name() == "windup" and was != "windup":
			plans += 1
			if str(b.plan()["part"]) == "head" and bool(b.plan()["neck"]):
				necks += 1
		was = b.state_name()
	assert_true(plans > 0, "attacks")
	assert_true(necks * 2 > plans, "the neck (below the head) is the usual finisher target: %d of %d" % [necks, plans])


func test_finishes_a_fallen_foe() -> void:
	var b := _brain({"preset": "brute"})
	var f: Array = _pair(1.2)
	(f[1] as Dictionary)["state"] = "down"
	for i in 60:
		b.think(f[0], f[1], DT)
	assert_true(bool(b.plan()["finishing"]), "plans a finisher")
	assert_eq(str(b.plan()["kind"]), "overhead")


## Runs past the spawn hold (the brain stands still for its first ticks).
func _warm(b: FighterBrain, f: Array) -> void:
	b.think(f[0], f[1], DT)


func test_retreats_when_stamina_low() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(2.0)
	_warm(b, f)
	(f[0] as Dictionary)["stamina"] = 0.05
	var inp: FighterInput = null
	for i in 5:
		inp = b.think(f[0], f[1], DT)
	assert_eq(b.state_name(), "retreat")
	assert_true(inp.move_y < -300, "backs away")
	assert_false(inp.has(FighterInput.SWING))


func test_berserker_keeps_fighting_when_tired() -> void:
	var b := _brain({"preset": "berserker"})
	var f: Array = _pair(2.0)
	(f[0] as Dictionary)["stamina"] = 0.15
	for i in 5:
		b.think(f[0], f[1], DT)
	assert_true(b.state_name() != "retreat")


func test_picks_up_a_dropped_weapon() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(5.0)
	_warm(b, f)
	var me: Dictionary = f[0]
	me["weapon_id"] = "fists"
	me["props"] = [{"pos": Vector3(1.0, 0.05, -1.0), "weapon_id": "gladius"}]
	var inp: FighterInput = b.think(me, f[1], DT)
	assert_eq(b.state_name(), "weapon")
	assert_true(inp.move_x > 0, "heads toward the prop")
	me["props"] = [{"pos": Vector3(0.3, 0.05, -0.6), "weapon_id": "gladius"}]
	inp = b.think(me, f[1], DT)
	assert_true(inp.has(FighterInput.GRAB), "grabs when close")


func test_missing_props_key_is_fine() -> void:
	var b := _brain()
	var f: Array = _pair(5.0)
	b.think(f[0], f[1], DT)
	(f[0] as Dictionary)["weapon_id"] = "fists"
	b.think(f[0], f[1], DT)
	assert_true(b.state_name() != "weapon")


func test_reaction_delay_defers_guard() -> void:
	var b := FighterBrain.new(3, {"preset": "duelist", "risk": 0.0, "reaction_ms": 200.0})
	var f: Array = _pair(1.5)
	var foe: Dictionary = f[1]
	var first_guard: int = -1
	for i in 40:
		foe["tip_speed"] = 8.0 if i >= 5 else 0.0
		foe["tip_pos"] = Vector3(0.4, 1.5, -1.2 + 0.05 * i)
		b.think(f[0], foe, DT)
		if first_guard < 0 and b.state_name() == "guard":
			first_guard = i
	assert_true(first_guard >= 15, "guard comes about 12 ticks after the swing starts: %d" % first_guard)


func test_half_sword_against_heavy_armor() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(1.5, "longsword")
	var armor: Dictionary = {}
	for n: String in ["head", "torso", "pelvis", "upper_arm_l", "upper_arm_r", "forearm_l", "forearm_r", "thigh_l", "thigh_r", "shin_l", "shin_r"]:
		armor[n] = "plate"
	(f[1] as Dictionary)["armor"] = armor
	var half: bool = false
	for i in 300:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if inp.has(FighterInput.HALF_SWORD):
			half = true
	assert_true(half, "uses the half-sword grip")


func _run(seed_value: int, preset_name: String) -> Array:
	var b := FighterBrain.new(seed_value, {"preset": preset_name})
	var f: Array = _pair(1.3)
	var seq: Array = []
	for i in 400:
		(f[1] as Dictionary)["tip_speed"] = 6.0 if (i % 90) > 70 else 0.5
		(f[1] as Dictionary)["tip_pos"] = Vector3(0.3, 1.4, -1.0 - 0.01 * (i % 90))
		seq.append(b.think(f[0], f[1], DT).to_array())
	return seq


func test_same_seed_same_inputs() -> void:
	for pn: String in ["brute", "duelist", "coward", "berserker"]:
		assert_eq(_run(11, pn), _run(11, pn), pn)


func test_different_seeds_diverge() -> void:
	assert_true(_run(1, "duelist") != _run(2, "duelist"))


func test_presets_differ() -> void:
	assert_true(FighterBrain.preset("coward")["aggression"] < FighterBrain.preset("berserker")["aggression"])
	assert_true(FighterBrain.preset("berserker")["risk"] > FighterBrain.preset("duelist")["risk"])


func test_holds_still_while_spawn_settles() -> void:
	var b := _brain({"preset": "berserker", "spawn_hold": 24})
	var f: Array = _pair(5.0)
	var inp: FighterInput = b.think(f[0], f[1], DT)
	assert_eq(inp.move_y, 0, "no lunge on the first tick")
	assert_false(inp.has(FighterInput.SWING))


func test_cowardly_pair_still_closes_and_swings() -> void:
	# range_frac 1.3 holds outside striking range; after commit_ticks the coward steps in and attacks.
	var b := _brain({"preset": "coward"})
	var f: Array = _pair(2.4)
	var swung: bool = false
	for i in 900:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if inp.has(FighterInput.SWING) and b.state_name() == "windup":
			swung = true
			break
	assert_true(swung, "a coward eventually commits to an attack")


func _finish_plan(weapon: String, armor: Dictionary, seed_value: int) -> Dictionary:
	var b := FighterBrain.new(seed_value, {"preset": "duelist", "reaction_ms": 0.0, "aim_noise": 0.0, "spawn_hold": 0})
	var f: Array = _pair(3.0 if weapon == "spear" else 1.0, weapon)  # a spear thrusts from its own range only
	(f[1] as Dictionary)["blood_frac"] = 0.1
	(f[1] as Dictionary)["armor"] = armor
	for i in 400:
		b.think(f[0], f[1], DT)
		if not b.plan().is_empty() and bool(b.plan().get("finishing", false)):
			return b.plan()
	return {}


func test_spear_finisher_is_a_thrust_to_the_torso() -> void:
	var p: Dictionary = _finish_plan("spear", {}, 3)
	assert_false(p.is_empty(), "plans a finisher")
	assert_eq(str(p["kind"]), "thrust")
	assert_eq(str(p["part"]), "torso")


func test_blunt_finisher_is_overhead_to_the_head() -> void:
	var p: Dictionary = _finish_plan("club", {}, 3)
	assert_false(p.is_empty(), "plans a finisher")
	assert_eq(str(p["kind"]), "overhead")
	assert_eq(str(p["part"]), "head")


func test_sword_finisher_is_a_behead_gut_or_run_through() -> void:
	var kinds: Dictionary = {}
	for sd in 12:
		var p: Dictionary = _finish_plan("gladius", {}, sd)
		if p.is_empty():
			continue
		kinds["%s/%s" % [p["kind"], p["part"]]] = true
		assert_true(["head", "torso", "pelvis"].has(str(p["part"])), "a killing target")
	assert_true(kinds.size() >= 2, "varies between killing blows")


func test_aim_never_sweeps_to_the_offhand_side() -> void:
	var b := _brain({"preset": "berserker"})
	var f: Array = _pair(1.2)
	for i in 300:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		assert_true(inp.aim_x >= int(FighterBrain.AIM_LEFT_LIMIT * 1000.0) - 1, "aim x stays right of the limit")


func test_duelist_sometimes_aims_at_the_weapon_forearm() -> void:
	var hit: int = 0
	for sd in 30:
		var b := FighterBrain.new(sd, {"preset": "duelist", "reaction_ms": 0.0, "spawn_hold": 0})
		var f: Array = _pair(1.0)
		for i in 200:
			b.think(f[0], f[1], DT)
			if str(b.plan().get("part", "")) == "forearm_r":
				hit += 1
				break
	assert_true(hit > 0, "disarm attempts happen")


func test_dazed_foe_is_finished_at_full_blood() -> void:
	var b := _brain({"preset": "berserker"})
	var f: Array = _pair(1.2, "club")
	(f[1] as Dictionary)["consciousness"] = 0.1
	(f[1] as Dictionary)["blood_frac"] = 1.0
	for i in 60:
		b.think(f[0], f[1], DT)
	assert_true(bool(b.plan().get("finishing", false)), "a dazed foe is pressed with a killing blow")


func test_conscious_foe_at_full_blood_is_not_finished() -> void:
	var b := _brain({"preset": "berserker"})
	var f: Array = _pair(1.2, "club")
	(f[1] as Dictionary)["blood_frac"] = 1.0
	for i in 60:
		b.think(f[0], f[1], DT)
	assert_false(bool(b.plan().get("finishing", false)), "no finisher on a healthy foe")


func _disarmed_pair(forearm_hp: float, prop_y: float) -> Array:
	var f: Array = _pair(3.0, "gladius")
	var b := _brain({"preset": "duelist"})
	b.think(f[0], f[1], DT)  # remembers the main weapon
	(f[0] as Dictionary)["weapon_id"] = "fists"
	((f[0] as Dictionary)["parts"] as Dictionary)["forearm_r"]["hp"] = forearm_hp
	(f[0] as Dictionary)["props"] = [{"pos": Vector3(1.0, prop_y, 1.0), "weapon_id": "gladius"}]
	for i in 3:
		b.think(f[0], f[1], DT)
	return [b, f]


func test_disarmed_fighter_goes_for_a_prop() -> void:
	var r: Array = _disarmed_pair(40.0, 0.02)
	assert_eq((r[0] as FighterBrain).state_name(), "weapon")


func test_disarmed_fighter_under_attack_still_goes_for_a_prop() -> void:
	var f: Array = _pair(1.2, "gladius")
	var b := _brain({"preset": "duelist"})
	b.think(f[0], f[1], DT)  # remembers the main weapon
	(f[0] as Dictionary)["weapon_id"] = "fists"
	(f[0] as Dictionary)["props"] = [{"pos": Vector3(1.0, 0.02, 1.0), "weapon_id": "gladius"}]
	# The foe's blade comes at the torso fast: a threat that would normally raise a guard.
	(f[1] as Dictionary)["tip_speed"] = 9.0
	for i in 6:
		(f[1] as Dictionary)["tip_pos"] = Vector3(0.0, 1.3, -1.0 + 0.1 * i)
		b.think(f[0], f[1], DT)
	assert_eq(b.state_name(), "weapon", "a bare-fist guard is no use: pick the weapon up")


func test_crippled_weapon_arm_does_not_chase_props() -> void:
	var r: Array = _disarmed_pair(1.0, 0.02)
	assert_true((r[0] as FighterBrain).state_name() != "weapon", "it would drop the weapon again at once")


func test_ground_prop_pickup_crouches_and_reaches_down() -> void:
	var r: Array = _disarmed_pair(40.0, 0.02)
	var b: FighterBrain = r[0]
	var f: Array = r[1]
	# Stand on the spot GRAB_REACH behind the prop (the body faces -Z).
	for k in ["pelvis_pos"]:
		(f[0] as Dictionary)[k] = Vector3(1.0, 0.95, 1.0 + FighterBrain.GRAB_REACH)
	for n: String in ((f[0] as Dictionary)["parts"] as Dictionary):
		(((f[0] as Dictionary)["parts"] as Dictionary)[n] as Dictionary)["pos"].x = 1.0
		(((f[0] as Dictionary)["parts"] as Dictionary)[n] as Dictionary)["pos"].z = 1.0 + FighterBrain.GRAB_REACH
	var inp: FighterInput = null
	for i in 12:
		inp = b.think(f[0], f[1], DT)
	assert_true(inp.has(FighterInput.CROUCH), "crouches")
	assert_eq(inp.aim_y, -1000, "hand straight down")


func test_stalemate_builds_desperation_and_decisive_damage_resets_it() -> void:
	var b := _brain({"preset": "coward"})
	var f: Array = _pair(4.0)
	for i in FighterBrain.STALE_START + FighterBrain.STALE_RAMP + 10:
		b.think(f[0], f[1], DT)
	assert_true(b._desperation() > 0.99, "fully desperate after a long stalemate")
	((f[1] as Dictionary)["parts"] as Dictionary)["torso"]["hp"] = 10.0
	b.think(f[0], f[1], DT)
	assert_true(b._desperation() < 0.01, "core damage resets the clock")


func test_exhausted_fighter_stops_resting_when_resting_fails() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(1.5, "club")
	(f[0] as Dictionary)["stamina"] = 0.0
	for i in 40:
		b.think(f[0], f[1], DT)
	assert_eq(b.state_name(), "retreat", "tired at first")
	for i in FighterBrain.REST_FAIL_TICKS + 40:
		b.think(f[0], f[1], DT)
	assert_true(b.state_name() != "retreat", "fights on once resting is hopeless")


## Ticks (of `n`, foe fixed at `dist`) the brain spends in a footwork phase between engagement bursts.
func _footwork_ticks(personality: Dictionary, dist: float, n: int, seed_value: int = 7) -> int:
	var p: Dictionary = {"reaction_ms": 0.0, "aim_noise": 0.0, "spawn_hold": 0}
	p.merge(personality, true)
	var b := FighterBrain.new(seed_value, p)
	var f: Array = _pair(dist)
	var c: int = 0
	for i in n:
		b.think(f[0], f[1], DT)
		if b._phase == 1:
			c += 1
	return c


func test_fights_come_in_bursts_with_footwork_between() -> void:
	var c: int = _footwork_ticks({"preset": "duelist"}, 1.4, 540)  # before the stalemate clock presses
	assert_true(c > 80, "a duelist spends part of 9 s in footwork: %d ticks" % c)
	assert_true(c < 440, "but not all of it: %d ticks" % c)


func test_coward_breaks_off_more_than_berserker() -> void:
	var cow: int = _footwork_ticks({"preset": "coward"}, 1.4, 3000)
	var ber: int = _footwork_ticks({"preset": "berserker"}, 1.4, 3000)
	assert_true(cow > ber * 2, "coward %d vs berserker %d footwork ticks" % [cow, ber])


func test_footwork_walks_around_the_foe_instead_of_standing_in_range() -> void:
	var b := _brain({"preset": "coward"})
	var f: Array = _pair(1.4)
	var moved_back: bool = false
	var sideways: bool = false
	for i in 1500:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if b._phase == 1 and b.state_name() == "approach" and not inp.has(FighterInput.SWING):
			moved_back = moved_back or inp.move_y < -100
			sideways = sideways or absi(inp.move_x) > 200
	assert_true(moved_back and sideways, "steps back and strafes (back %s, side %s)" % [moved_back, sideways])


func test_repositioning_goals_stay_inside_the_arena() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(4.0)
	b.think(f[0], f[1], DT)
	for i in 40:
		var g: Vector3 = b._pick_spot()
		assert_true(Vector2(g.x, g.z).length() <= FighterBrain.GOAL_RADIUS_MAX + 0.01, "goal %s inside" % g)


func test_stalemate_ends_the_footwork_and_presses() -> void:
	var b := _brain({"preset": "coward"})
	var f: Array = _pair(3.0)
	for i in 400:
		b.think(f[0], f[1], DT)
	b._stale_ticks = FighterBrain.STALE_START + FighterBrain.STALE_RAMP
	var phase_one: int = 0
	for i in 300:
		b._stale_ticks = FighterBrain.STALE_START + FighterBrain.STALE_RAMP
		b.think(f[0], f[1], DT)
		if i > 5 and b._phase == 1:
			phase_one += 1
	assert_eq(phase_one, 0, "a desperate brain stops circling")


func test_footwork_is_deterministic() -> void:
	assert_eq(_footwork_ticks({"preset": "duelist"}, 1.4, 1200, 11), _footwork_ticks({"preset": "duelist"}, 1.4, 1200, 11))


func test_heavy_short_weapons_do_not_swing_low_on_the_weapon_side() -> void:
	assert_eq(FighterBrain.heavy_low_limit(0.75, false), FighterBrain.AIM_LOW_LIMIT, "swords keep the normal floor")
	assert_eq(FighterBrain.heavy_low_limit(0.0, true), FighterBrain.AIM_LOW_LIMIT, "leg attacks in front stay")
	assert_eq(FighterBrain.heavy_low_limit(0.75, true), FighterBrain.HEAVY_LOW_LIMIT, "axe low right is capped")
	for w: String in ["axe", "club"]:
		var b := _brain({"preset": "berserker", "preferred_attacks": ["low"]})
		var f: Array = _pair(1.0, w)
		for i in 400:
			var inp: FighterInput = b.think(f[0], f[1], DT)
			var lim: float = FighterBrain.heavy_low_limit(float(inp.aim_x) / 1000.0, true)
			assert_true(float(inp.aim_y) / 1000.0 >= lim - 0.002 or inp.aim_y == -1000, "%s aim %d,%d" % [w, inp.aim_x, inp.aim_y])


## A foe blade sweeping in fast at close range, over and over (tip closes on my torso every tick of a 20-tick cycle).
func _threat_rolls(stamina: float) -> Array:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(1.6)
	f[0]["stamina"] = stamina
	var ticks: Array[int] = []
	for i in 1200:
		var k: int = i % 20
		f[1]["tip_pos"] = Vector3(0.0, 1.3, -1.2 + 0.05 * k)
		f[1]["tip_speed"] = 14.0
		var inp: FighterInput = b.think(f[0], f[1], DT)
		if inp.has(FighterInput.ROLL):
			ticks.append(i)
			assert_true(inp.move_y < 0, "rolls back, away from the foe")
	return ticks


func test_rolls_now_and_then_to_escape_a_fast_blow() -> void:
	var ticks: Array = _threat_rolls(1.0)
	assert_true(ticks.size() >= 1, "rolled at least once in 20 s of threats")
	for j: int in range(1, ticks.size()):
		assert_true(int(ticks[j]) - int(ticks[j - 1]) >= 240, "cooldown between rolls")


func test_does_not_roll_when_tired() -> void:
	assert_eq(_threat_rolls(0.3).size(), 0)


## Close-range moves over 60 s at `dist` m: ticks of each press (the brain presses a move for one tick).
func _close_presses(dist: float, foe_state: String = "standing", stamina: float = 1.0) -> Dictionary:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(dist)
	f[0]["stamina"] = stamina
	f[1]["state"] = foe_state
	var out: Dictionary = {"shove": [], "kick": [], "clinch": []}
	for i in 3600:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		for k: String in out:
			var bit: int = {"shove": FighterInput.SHOVE, "kick": FighterInput.KICK, "clinch": FighterInput.CLINCH}[k]
			if inp.has(bit):
				(out[k] as Array).append(i)
	return out


func test_shoves_and_grabs_sparingly_at_close_range() -> void:
	var p: Dictionary = _close_presses(0.9)
	var n: int = (p["shove"] as Array).size()
	# 0.9 m is inside the shove and grab ranges, closer than a kick needs.
	assert_true(n >= 1 and n <= 12, "a few shoves a minute, got %d" % n)
	assert_eq((p["kick"] as Array).size(), 0, "too close to kick")
	assert_true((p["clinch"] as Array).size() >= 1, "grabs now and then (held for a while)")
	var all: Array = (p["shove"] as Array).duplicate()
	all.sort()
	for j: int in range(1, all.size()):
		assert_true(int(all[j]) - int(all[j - 1]) >= 300, "cooldown between close moves")


func test_kicks_at_kick_range() -> void:
	var p: Dictionary = _close_presses(1.28)
	assert_true((p["kick"] as Array).size() >= 1, "kicks now and then")
	assert_eq((p["shove"] as Array).size(), 0, "out of shove range")


func test_shoves_a_stumbling_foe_more() -> void:
	var calm: int = (_close_presses(0.9)["shove"] as Array).size()
	var off: int = (_close_presses(0.9, "stumbling")["shove"] as Array).size()
	assert_true(off > calm, "stumbling %d vs standing %d" % [off, calm])


func test_no_close_moves_when_tired_or_far() -> void:
	var tired: Dictionary = _close_presses(0.9, "standing", 0.2)
	var far: Dictionary = _close_presses(3.0)
	for d: Dictionary in [tired, far]:
		for k: String in d:
			assert_eq((d[k] as Array).size(), 0, k)


func test_held_fighter_pulls_back_and_shoves() -> void:
	var b := _brain({"preset": "duelist"})
	var f: Array = _pair(0.9)
	f[0]["close"] = {"held": "forearm_r"}
	var shoves: int = 0
	for i in 120:
		var inp: FighterInput = b.think(f[0], f[1], DT)
		assert_true(inp.move_y < 0, "pulls away")
		if inp.has(FighterInput.SHOVE):
			shoves += 1
	assert_true(shoves >= 1)
