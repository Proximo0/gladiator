extends TestCase


func test_excitement_jumps_then_decays() -> void:
	var c: CrowdModel = CrowdModel.new()
	assert_near(c.level, CrowdModel.BASELINE)
	c.add(0.6)
	var peak: float = c.level
	assert_true(peak > 0.6)
	for i: int in range(60 * 5):
		c.tick(1.0 / 60.0, 0.0)
	assert_true(c.level < peak * 0.6, "half-life about 5 s")
	for i: int in range(60 * 60):
		c.tick(1.0 / 60.0, 0.0)
	assert_near(c.level, CrowdModel.BASELINE, 0.01)


func test_impulses_saturate_below_one() -> void:
	var c: CrowdModel = CrowdModel.new()
	for i: int in range(50):
		c.add(0.5)
	assert_true(c.level <= 1.0 and c.level > 0.99)


func test_action_raises_level() -> void:
	var c: CrowdModel = CrowdModel.new()
	for i: int in range(60 * 10):
		c.tick(1.0 / 60.0, 1.0)
	assert_true(c.level > CrowdModel.BASELINE + 0.1)


func test_hit_impulse_ordering() -> void:
	var small: float = CrowdModel.hit_impulse({"energy": 10.0})
	var big: float = CrowdModel.hit_impulse({"energy": 150.0})
	var sever: float = CrowdModel.hit_impulse({"energy": 150.0, "sever": true})
	var fin: float = CrowdModel.hit_impulse({"energy": 150.0, "finisher": "behead"})
	assert_true(small < big and big < sever and sever <= fin)
	assert_near(fin, 1.0)
	assert_true(CrowdModel.hit_impulse({"energy": 150.0, "hit_on_weapon": true}) < big)


func test_reaction_for() -> void:
	assert_eq(CrowdModel.reaction_for({"energy": 1.5}), "")
	assert_eq(CrowdModel.reaction_for({"energy": 150.0}), "cheer")
	assert_eq(CrowdModel.reaction_for({"energy": 45.0}), "gasp")
	assert_eq(CrowdModel.reaction_for({"energy": 5.0, "disarmed": true}), "gasp")
	assert_eq(CrowdModel.reaction_for({"energy": 5.0, "dislodge": true}), "cheer")
	assert_eq(CrowdModel.reaction_for({"energy": 50.0, "sever": true}), "roar")
	assert_eq(CrowdModel.reaction_for({"energy": 50.0, "gut": true}), "roar")
	assert_eq(CrowdModel.reaction_for({"energy": 50.0, "finisher": "run_through"}), "finisher")


func test_reaction_cooldown_and_tiers() -> void:
	var c: CrowdModel = CrowdModel.new()
	assert_true(c.try_reaction("cheer"))
	assert_false(c.try_reaction("cheer"), "cooling down")
	assert_false(c.try_reaction("gasp"), "lower tier blocked")
	assert_true(c.try_reaction("roar"), "higher tier breaks through")
	assert_true(c.try_reaction("finisher"))
	assert_false(c.try_reaction(""))
	for i: int in range(60 * 12):
		c.tick(1.0 / 60.0, 1.0)
	assert_true(c.try_reaction("gasp"), "cooldown expired")


func test_stall_boo() -> void:
	var c: CrowdModel = CrowdModel.new()
	var fired: int = 0
	for i: int in range(60 * 40):
		c.tick(1.0 / 60.0, 0.0)
		if c.take_stall_boo():
			fired += 1
	assert_true(fired >= 1 and fired <= 3, "boos %d" % fired)
	var busy: CrowdModel = CrowdModel.new()
	for i: int in range(60 * 40):
		busy.tick(1.0 / 60.0, 1.0)
		assert_false(busy.take_stall_boo())


func test_ambience_mix_follows_excitement() -> void:
	var calm: Vector2 = CrowdModel.ambience_gains(0.05)
	var mid: Vector2 = CrowdModel.ambience_gains(0.5)
	var hot: Vector2 = CrowdModel.ambience_gains(1.0)
	assert_true(calm.y < mid.y and mid.y < hot.y, "excited loop swells in")
	assert_true(calm.x > calm.y, "calm loop leads when quiet")
	assert_true(hot.y >= hot.x, "excited loop leads at the top")
	assert_true(hot.y <= 1.0 and calm.x <= 0.0)
