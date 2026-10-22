extends TestCase
## SfxGush: the fountain and gut-spill sound schedule, plus the weapon-class and footstep rules added with it.


func _run(g: SfxGush, seconds: float, blood: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var steps: int = int(seconds * 60.0)
	for i: int in range(steps):
		out.append_array(g.tick(1.0 / 60.0, blood))
	return out


func _count(evs: Array[Dictionary], key: String) -> int:
	var n: int = 0
	for e: Dictionary in evs:
		if str(e["key"]) == key:
			n += 1
	return n


func _rng() -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = 5
	return r


func test_fountain_pulses_with_the_heartbeat_and_fades() -> void:
	var g: SfxGush = SfxGush.new().setup(SfxGush.KIND_FOUNTAIN, Vector3.ZERO, 6.5, 1.6, _rng())
	var evs: Array[Dictionary] = _run(g, 7.0, 1.0)
	var n: int = _count(evs, "gore/gush_pulse")
	assert_true(n >= 4 and n <= SfxGush.MAX_PULSES, "pulse count %d" % n)
	assert_eq(_count(evs, "gore/gut_flop"), 0)
	assert_true(g.finished())
	assert_true(float(evs[0]["gain_db"]) > float(evs[evs.size() - 1]["gain_db"]), "fades")


func test_faster_heart_means_more_pulses() -> void:
	var a: SfxGush = SfxGush.new().setup(SfxGush.KIND_FOUNTAIN, Vector3.ZERO, 6.5, 1.6, _rng())
	var b: SfxGush = SfxGush.new().setup(SfxGush.KIND_FOUNTAIN, Vector3.ZERO, 6.5, 1.6, _rng())
	var full: int = _count(_run(a, 3.0, 1.0), "gore/gush_pulse")
	var hurt: int = _count(_run(b, 3.0, 0.4), "gore/gush_pulse")
	assert_true(hurt >= full, "%d vs %d" % [hurt, full])


func test_gut_spill_squelches_then_flops() -> void:
	var g: SfxGush = SfxGush.new().setup(SfxGush.KIND_GUT, Vector3.ZERO, 4.2, 1.0, _rng())
	var evs: Array[Dictionary] = _run(g, 4.5, 1.0)
	assert_eq(_count(evs, "gore/gut_squelch"), 1)
	assert_eq(_count(evs, "gore/gut_flop"), SfxGush.FLOP_TIMES.size())
	assert_true(_count(evs, "gore/gush_pulse") > 0)


func test_gush_gain_drops_as_blood_drains() -> void:
	assert_true(SfxGush.pulse_gain_db(1.0, 1.0, false) > SfxGush.pulse_gain_db(1.0, 0.1, false))
	assert_true(SfxGush.pulse_gain_db(1.0, 1.0, false) > SfxGush.pulse_gain_db(1.0, 1.0, true))
	assert_true(SfxGush.pulse_gain_db(1.0, 1.0, false) <= 0.0)


func test_weapon_class_and_whoosh_keys() -> void:
	assert_eq(SfxLogic.weapon_class("sledgehammer"), "heavy")
	assert_eq(SfxLogic.weapon_class("falchion"), "cleave")
	assert_eq(SfxLogic.weapon_class("gladius"), "")
	assert_eq(SfxLogic.whoosh_key_for(8.0, "warhammer"), "move/whoosh_heavy")
	assert_eq(SfxLogic.whoosh_key_for(9.0, "halberd"), "move/whoosh_cleave")
	assert_eq(SfxLogic.whoosh_key_for(9.0, "gladius"), "move/whoosh_mid")
	assert_eq(SfxLogic.whoosh_key_for(1.0, "mace"), "")


func test_heavy_and_cleaving_impacts_get_their_layer() -> void:
	var ev: Dictionary = {"part": "torso", "weapon_id": "sledgehammer", "contact": "blunt", "energy": 200.0,
		"total": 20.0, "blunt": 20.0, "hit_on_weapon": false, "glanced": false}
	var keys: Array[String] = []
	for l: Dictionary in SfxLogic.impact_plan(ev, "steel", "", ""):
		keys.append(str(l["key"]))
	assert_true(keys.has("impact/heavy_thump"))
	ev["weapon_id"] = "falchion"
	ev["contact"] = "edge"
	keys.clear()
	for l: Dictionary in SfxLogic.impact_plan(ev, "steel", "", ""):
		keys.append(str(l["key"]))
	assert_true(keys.has("impact/cleave_chop"))
	assert_false(keys.has("impact/heavy_thump"))


func test_footstep_plan_run_vs_walk_and_shuffle() -> void:
	assert_eq(str(SfxLogic.footstep_plan(4.0, 4.5, 0.0)["key"]), "move/footstep_run")
	assert_eq(str(SfxLogic.footstep_plan(1.5, 4.5, 0.0)["key"]), "move/footstep_sand")
	assert_true(float(SfxLogic.footstep_plan(1.5, 4.5, 1.0)["gain_db"]) < float(SfxLogic.footstep_plan(1.5, 4.5, 0.0)["gain_db"]))


func test_step_tracker_cadence() -> void:
	var st: SfxStepTracker = SfxStepTracker.new()
	var n: int = 0
	var sides: Array[int] = []
	for i: int in range(120):
		var s: int = st.update_cadence(3.0, 2.0, 1.0 / 60.0, true)
		if s != 0:
			n += 1
			sides.append(s)
	assert_true(n >= 5 and n <= 7, "steps in 2 s at 3/s: %d" % n)
	assert_true(sides[0] != sides[1])
	assert_eq(st.update_cadence(3.0, 0.0, 0.1, true), 0)


func test_low_priority_set() -> void:
	assert_true(SfxLogic.is_low_priority("move/footstep_run"))
	assert_false(SfxLogic.is_low_priority("gore/behead"))
