extends TestCase


func _hit(part: String, weapon: String, contact: String, speed: float, mass: float, armor: Array = []) -> Dictionary:
	return {
		"part": part, "weapon_id": weapon, "contact": contact, "rel_vel": Vector3(0, 0, -speed),
		"normal": Vector3(0, 0, -1), "edge_alignment": 1.0, "effective_mass": mass, "armor_ids": armor, "armor_wear": {},
	}


func _new() -> FighterHealth:
	return FighterHealth.new(Tuning.new())


func _kinds(events: Array) -> Array:
	var out: Array = []
	for e: Variant in events:
		out.append((e as Dictionary)["kind"])
	return out


func test_initial_state() -> void:
	var h := _new()
	assert_near(h.blood, 5.0)
	assert_near(h.consciousness, 1.0)
	assert_near(h.stamina, 1.0)
	assert_false(h.dead)
	assert_eq(h.severed.size(), 0)
	assert_true(h.hp("head") > 0.0)
	assert_eq(h.parts.size(), 11)


func test_sever_forearm_events_and_bleed() -> void:
	var h := _new()
	var ev: Array = h.apply(DamageModel.resolve(_hit("forearm_r", "longsword", "edge", 20.0, 1.0), Tuning.new()), "forearm_r")
	assert_eq(_kinds(ev), ["sever"])
	assert_true(h.severed.has("forearm_r"))
	assert_near(h.hp("forearm_r"), 0.0)
	assert_true(h.bleed_rate > 0.5)
	assert_false(h.dead)


func test_severed_part_ignores_further_hits() -> void:
	var h := _new()
	var res: Dictionary = DamageModel.resolve(_hit("forearm_r", "longsword", "edge", 20.0, 1.0), Tuning.new())
	h.apply(res, "forearm_r")
	var rate: float = h.bleed_rate
	assert_eq(h.apply(res, "forearm_r").size(), 0)
	assert_near(h.bleed_rate, rate)


func test_behead_kills_instantly() -> void:
	var h := _new()
	var ev: Array = h.apply(DamageModel.resolve(_hit("head", "longsword", "edge", 20.0, 1.0), Tuning.new()), "head")
	assert_eq(_kinds(ev), ["behead"])
	assert_true(h.dead)
	assert_true(h.is_severed("head"))
	assert_near(h.consciousness, 0.0)


func test_gut_event_and_slow_death_by_bleeding() -> void:
	var h := _new()
	var ev: Array = h.apply(DamageModel.resolve(_hit("torso", "spear", "point", 8.0, 2.0), Tuning.new()), "torso")
	assert_true(_kinds(ev).has("gut"))
	assert_true(h.gutted)
	assert_false(h.dead)
	var t: float = 0.0
	while not h.dead and t < 120.0:
		h.tick(1.0 / 60.0, 0.0)
		t += 1.0 / 60.0
	assert_true(h.dead)
	assert_true(t > 5.0 and t < 60.0, "died at %f" % t)


func test_bleed_drains_blood_over_time() -> void:
	var h := _new()
	h.bleed_rate = 0.2
	for i in 60:
		h.tick(1.0 / 60.0, 0.0)
	assert_near(h.blood, 5.0 - 0.2, 0.01)
	assert_true(h.bleed_rate < 0.2)


func test_death_below_blood_death() -> void:
	var h := _new()
	h.blood = 2.4
	h.tick(0.01, 0.0)
	assert_true(h.dead)


func test_blood_loss_fades_consciousness() -> void:
	var h := _new()
	h.blood = 2.8
	h.tick(1.0, 0.0)
	assert_true(h.consciousness < 0.5)
	assert_false(h.dead)


func test_minor_bleed_event() -> void:
	var h := _new()
	var r: Dictionary = DamageModel.resolve(_hit("thigh_l", "gladius", "point", 6.0, 1.0), Tuning.new())
	var ev: Array = h.apply(r, "thigh_l")
	assert_eq(_kinds(ev), ["bleed"])
	assert_true(h.hp("thigh_l") < 60.0)


func test_blunt_hit_no_gore_event() -> void:
	var h := _new()
	var ev: Array = h.apply(DamageModel.resolve(_hit("torso", "club", "blunt", 10.0, 2.0), Tuning.new()), "torso")
	assert_eq(ev.size(), 0)
	assert_true(h.hp("torso") < 120.0)
	assert_near(h.bleed_rate, 0.0)


func test_consciousness_recovers() -> void:
	var h := _new()
	h.consciousness = 0.3
	for i in 600:
		h.tick(1.0 / 60.0, 0.0)
	assert_true(h.consciousness > 0.5)


func test_stamina_drains_and_recovers() -> void:
	var h := _new()
	for i in 120:
		h.tick(1.0 / 60.0, 1.0)
	assert_true(h.stamina < 0.6)
	var low: float = h.stamina
	for i in 120:
		h.tick(1.0 / 60.0, 0.0)
	assert_true(h.stamina > low)
	for i in 6000:
		h.tick(1.0 / 60.0, 1.0)
	assert_true(h.stamina >= 0.0)


func test_dead_ignores_hits_and_ticks() -> void:
	var h := _new()
	h.dead = true
	var blood: float = h.blood
	h.bleed_rate = 1.0
	h.tick(1.0, 0.0)
	assert_near(h.blood, blood)
	assert_eq(h.apply({"total": 10.0, "bleed": 1.0}, "torso").size(), 0)


func test_torso_destroyed_kills() -> void:
	var h := _new()
	h.apply({"total": 500.0}, "torso")
	assert_true(h.dead)


func test_snapshot_round_trip() -> void:
	var h := _new()
	h.apply(DamageModel.resolve(_hit("forearm_l", "axe", "edge", 18.0, 1.8), Tuning.new()), "forearm_l")
	h.apply(DamageModel.resolve(_hit("head", "bat", "blunt", 20.0, 1.0), Tuning.new()), "head")
	h.tick(0.5, 0.5)
	var g := _new()
	g.from_dict(h.to_dict())
	assert_eq(g.to_dict(), h.to_dict())
	for i in 30:
		h.tick(1.0 / 60.0, 0.2)
		g.tick(1.0 / 60.0, 0.2)
	assert_eq(g.to_dict(), h.to_dict())


func test_blood_frac() -> void:
	var h := _new()
	assert_near(h.blood_frac(), 1.0)
	h.blood = 2.5
	assert_near(h.blood_frac(), 0.0)
	h.blood = 3.75
	assert_near(h.blood_frac(), 0.5)


func _finish(part: String, weapon: String, contact: String, speed: float, mass: float) -> Array:
	var h := _new()
	h.blood = 2.6
	var hit: Dictionary = _hit(part, weapon, contact, speed, mass)
	hit["blood_frac"] = h.blood_frac()
	var ev: Array = h.apply(DamageModel.resolve(hit, Tuning.new()), part)
	assert_true(h.dead)
	return ev


func test_finisher_events_kill() -> void:
	assert_eq(_kinds(_finish("torso", "spear", "point", 6.0, 2.0)), ["run_through"])
	assert_eq(_kinds(_finish("torso", "axe", "edge", 8.0, 1.8)), ["gut"])
	assert_eq(_kinds(_finish("head", "longsword", "edge", 12.0, 1.0)), ["behead"])
	assert_eq(_kinds(_finish("head", "club", "blunt", 10.0, 1.6)), ["skull_crush"])


func test_same_hit_at_full_blood_no_finisher() -> void:
	var h := _new()
	var hit: Dictionary = _hit("head", "club", "blunt", 10.0, 1.6)
	hit["blood_frac"] = h.blood_frac()
	h.apply(DamageModel.resolve(hit, Tuning.new()), "head")
	assert_false(h.dead)


func test_hp_total_frac() -> void:
	var h := _new()
	assert_near(h.hp_total_frac(), 1.0)
	h.parts["torso"] = 0.0
	assert_true(h.hp_total_frac() < 1.0 and h.hp_total_frac() > 0.8)
