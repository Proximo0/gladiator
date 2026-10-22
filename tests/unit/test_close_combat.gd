extends TestCase
## CloseCombat: press edges, gating, timers and cooldowns, the shove and kick shapes, the grab hold and the struggle.

const DT: float = 1.0 / 60.0
const P: Dictionary = {
	"shove_time": 0.45, "shove_cooldown": 0.7, "kick_time": 0.65, "kick_cooldown": 0.9, "clinch_time": 0.4,
	"clinch_max": 3.0, "clinch_cooldown": 1.5,
}


func test_edges_fire_on_press_only() -> void:
	var c := CloseCombat.new()
	assert_eq(c.edges(FighterInput.SHOVE), FighterInput.SHOVE)
	assert_eq(c.edges(FighterInput.SHOVE), 0, "held, no new press")
	assert_eq(c.edges(FighterInput.SHOVE | FighterInput.KICK), FighterInput.KICK)
	assert_eq(c.edges(0), 0)
	assert_eq(c.edges(FighterInput.SHOVE), FighterInput.SHOVE)


func test_shove_gates() -> void:
	var c := CloseCombat.new()
	assert_false(c.can_shove(false, 1.0, 0.1), "not able")
	assert_false(c.can_shove(true, 0.05, 0.1), "no stamina")
	assert_true(c.can_shove(true, 0.1, 0.1))
	c.start_shove()
	assert_false(c.can_shove(true, 1.0, 0.1), "already shoving")
	assert_false(c.can_kick(true, true, 1.0, 0.1), "no kick mid shove")


func test_kick_gates() -> void:
	var c := CloseCombat.new()
	assert_false(c.can_kick(true, false, 1.0, 0.1), "needs both legs")
	assert_true(c.can_kick(true, true, 1.0, 0.1))
	c.start_grab(false)
	assert_false(c.can_kick(true, true, 1.0, 0.1), "no kick while reaching")
	c.release(P)
	c.grab_cd = 0.0
	c.latch("head", Vector3.ZERO)
	assert_false(c.can_kick(true, true, 1.0, 0.1), "no kick while holding")


func test_shove_ends_and_cools_down() -> void:
	var c := CloseCombat.new()
	c.start_shove()
	var ended: int = -1
	for k: int in range(120):
		c.tick(DT, P)
		if not c.shoving() and ended < 0:
			ended = k
	assert_true(ended >= 25 and ended <= 28, "ends after shove_time (tick %d)" % ended)
	assert_near(c.shove_cd, 0.0, 0.0001, "cooldown has run out after 2 s")
	assert_eq(int(c.counts["shoves"]), 1)


func test_kick_cooldown_blocks_the_next() -> void:
	var c := CloseCombat.new()
	c.start_kick()
	for _k: int in range(40):
		c.tick(DT, P)
	assert_false(c.kicking())
	assert_true(c.kick_cd > 0.5)
	assert_false(c.can_kick(true, true, 1.0, 0.1), "cooling down")


func test_reach_gives_up_and_cools_down() -> void:
	var c := CloseCombat.new()
	assert_true(c.can_grab(true, true))
	assert_false(c.can_grab(true, false), "no free hand")
	c.start_grab(true)
	assert_true(c.grab_head)
	for _k: int in range(30):
		c.tick(DT, P)
	assert_false(c.reaching())
	assert_false(c.holding())
	assert_true(c.grab_cd > 1.0, "a missed grab cools down")
	assert_eq(int(c.counts["grabs"]), 1)
	assert_eq(int(c.counts["holds"]), 0)


func test_hold_lasts_at_most_clinch_max() -> void:
	var c := CloseCombat.new()
	c.start_grab(false)
	c.latch("forearm_r", Vector3(0, -0.1, 0))
	assert_true(c.holding())
	assert_false(c.reaching())
	var held: int = 0
	for _k: int in range(300):
		c.tick(DT, P)
		if c.holding():
			held += 1
	assert_true(held >= 178 and held <= 181, "held %d ticks" % held)
	assert_eq(int(c.counts["holds"]), 1)
	assert_eq(int(c.counts["breaks"]), 0)


func test_struggle_breaks_free() -> void:
	var c := CloseCombat.new()
	c.latch("head", Vector3.ZERO)
	var rate: float = CloseCombat.struggle_rate(0.55, 1.0, 1.0, 1.0)
	assert_near(rate, 0.55, 0.0001)
	var ticks: int = 0
	while not c.add_struggle(rate, DT):
		ticks += 1
		assert_true(ticks < 1000)
	assert_true(ticks > 100 and ticks < 115, "about 1.8 s at full effort (%d ticks)" % ticks)
	c.release(P, true)
	assert_eq(int(c.counts["breaks"]), 1)
	assert_false(c.holding())


func test_struggle_scales_with_effort_and_strength() -> void:
	var full: float = CloseCombat.struggle_rate(1.0, 1.0, 1.0, 1.0)
	var idle: float = CloseCombat.struggle_rate(1.0, 0.0, 1.0, 1.0)
	assert_near(idle, 0.3, 0.0001, "passive resistance still counts a little")
	assert_true(full > idle)
	assert_true(CloseCombat.struggle_rate(1.0, 1.0, 1.0, 0.5) > full, "a weak holder loses the grip sooner")
	assert_near(CloseCombat.struggle_effort(-1.0, false), 1.0, 0.0001)
	assert_near(CloseCombat.struggle_effort(1.0, false), 0.0, 0.0001, "leaning in is no struggle")
	assert_near(CloseCombat.struggle_effort(0.0, true), 0.7, 0.0001)


func test_shove_shape() -> void:
	assert_near(CloseCombat.shove_extend(0.0), 0.0, 0.0001)
	assert_near(CloseCombat.shove_extend(0.5), 1.0, 0.0001)
	assert_near(CloseCombat.shove_extend(1.0), 0.0, 0.0001)
	assert_false(CloseCombat.shove_window(0.1))
	assert_true(CloseCombat.shove_window(0.5))
	assert_false(CloseCombat.shove_window(0.9))


func test_shove_numbers() -> void:
	assert_near(CloseCombat.shove_impulse(100.0, 0.5, 1.0), 50.0, 0.0001)
	assert_near(CloseCombat.shove_impulse(100.0, 1.0, 0.25), 25.0, 0.0001)
	assert_near(CloseCombat.shove_stagger(0.35, 0.55, false), 0.35, 0.0001)
	assert_true(CloseCombat.shove_stagger(0.35, 0.55, true) >= 0.85, "floors a stumbling foe (stagger_down 0.85)")


func test_kick_foot_path() -> void:
	var rest := Vector3(-0.1, 0.0, 0.1)
	assert_eq(CloseCombat.kick_foot(0.0, rest, 0.42, 0.85, 0.62), rest)
	assert_eq(CloseCombat.kick_foot(1.0, rest, 0.42, 0.85, 0.62), rest)
	var chamber: Vector3 = CloseCombat.kick_foot(CloseCombat.KICK_CHAMBER, rest, 0.42, 0.85, 0.62)
	assert_near(chamber.y, 0.42, 0.0001, "knee up")
	var out: Vector3 = CloseCombat.kick_foot(CloseCombat.KICK_EXTEND, rest, 0.42, 0.85, 0.62)
	assert_near(out.z, 0.85, 0.0001, "leg out")
	assert_near(out.y, 0.62, 0.0001)
	# The foot never goes below the sand and moves without jumps.
	var prev: Vector3 = rest
	for k: int in range(1, 101):
		var f: Vector3 = CloseCombat.kick_foot(k / 100.0, rest, 0.42, 0.85, 0.62)
		assert_true(f.y >= 0.0)
		assert_true(f.distance_to(prev) < 0.08, "step %d jumps %.3f" % [k, f.distance_to(prev)])
		prev = f
	assert_true(CloseCombat.kick_window(0.5))
	assert_false(CloseCombat.kick_window(0.1))


func test_kick_snaps_out_and_rechambers() -> void:
	var rest := Vector3(-0.1, 0.0, 0.1)
	var chamber: Vector3 = CloseCombat.kick_foot(CloseCombat.KICK_CHAMBER, rest, 0.42, 0.85, 0.62)
	var back: Vector3 = CloseCombat.kick_foot(CloseCombat.KICK_RECHAMBER, rest, 0.42, 0.85, 0.62)
	assert_true(back.distance_to(chamber) < 0.001, "the foot comes back under the knee before it goes down")
	# The snap out is faster than the chamber: the most the foot target moves in 1% of the kick.
	var chamber_step: float = 0.0
	var snap_step: float = 0.0
	for k: int in range(1, 100):
		var a: Vector3 = CloseCombat.kick_foot((k - 1) / 100.0, rest, 0.42, 0.85, 0.62)
		var b: Vector3 = CloseCombat.kick_foot(k / 100.0, rest, 0.42, 0.85, 0.62)
		if k <= 30:
			chamber_step = maxf(chamber_step, a.distance_to(b))
		elif k <= 45:
			snap_step = maxf(snap_step, a.distance_to(b))
	assert_true(snap_step > chamber_step * 2.0, "snap %.3f vs chamber %.3f" % [snap_step, chamber_step])


func test_kick_lean_back() -> void:
	assert_near(CloseCombat.kick_lean(0.0), 0.0, 0.0001)
	assert_near(CloseCombat.kick_lean(0.05), 0.0, 0.0001, "not before the knee comes up")
	assert_near(CloseCombat.kick_lean(CloseCombat.KICK_EXTEND), 1.0, 0.0001, "full while the leg is out")
	assert_near(CloseCombat.kick_lean(0.95), 0.0, 0.0001, "upright again as the foot lands")
	assert_near(CloseCombat.kick_lean(1.0), 0.0, 0.0001)


func test_hold_pull_hauls_the_arm_across_and_down() -> void:
	var chest := Vector3(0.0, 1.3, 0.0)
	var fwd := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	var arm: Vector3 = CloseCombat.hold_pull_goal(false, chest, fwd, right, Vector3.UP, 0.3, 0.22, 0.2, 0.3)
	assert_true(arm.x < -0.2, "across to the free (left) side")
	assert_true(arm.y < chest.y - 0.15, "down")
	assert_near(arm.z, -0.3, 0.0001, "in front of the chest")
	var head: Vector3 = CloseCombat.hold_pull_goal(true, chest, fwd, right, Vector3.UP, 0.3, 0.22, 0.2, 0.3)
	assert_near(head.x, 0.0, 0.0001, "a head is pulled straight down")
	assert_near(head.y, 1.0, 0.0001)
	var held := Vector3(0.5, 1.4, -0.6)
	var t: Vector3 = CloseCombat.hold_pull_target(held, arm, 0.16)
	assert_near(t.distance_to(held), 0.16, 0.0001, "leads the held point by at most one step")
	assert_true(t.distance_to(arm) < held.distance_to(arm), "toward the goal")
	assert_eq(CloseCombat.hold_pull_target(arm, arm, 0.16), arm)


func test_hold_slips() -> void:
	assert_false(CloseCombat.hold_slips(0.2, 0.3))
	assert_true(CloseCombat.hold_slips(0.31, 0.3))


func test_round_trip() -> void:
	var c := CloseCombat.new()
	c.edges(FighterInput.KICK)
	c.start_kick()
	c.tick(DT, P)
	c.latch("forearm_r", Vector3(0.1, 0.2, 0.3))
	c.add_struggle(0.5, 0.5)
	var d := CloseCombat.new()
	d.from_array(c.to_array())
	assert_eq(d.to_array(), c.to_array())
	assert_eq(d.edges(FighterInput.KICK), 0, "held button state survives")
	d.from_array([])
	assert_false(d.kicking())
	assert_false(d.holding())


func test_only_a_moving_striker_breaks_a_hold() -> void:
	assert_false(CloseCombat.blow_breaks_hold(0.4, 3.0), "the holder ran into a still fist")
	assert_true(CloseCombat.blow_breaks_hold(5.0, 3.0))
