extends TestCase

const DT: float = 1.0 / 60.0


func _run(lead: NetHandLead, raw: Vector3, from_tick: int, ticks: int, ack_lag: int, fast: bool = true) -> Vector3:
	var tun: Tuning = Tuning.new()
	var off: Vector3 = Vector3.ZERO
	for i: int in range(ticks):
		var t: int = from_tick + i
		off = lead.step(raw, Vector3.ZERO, Vector3(0.0, 1.3, -0.4), t, t - ack_lag, fast, true, DT, tun)
	return off


func test_still_aim_has_no_lead() -> void:
	var lead := NetHandLead.new()
	var off: Vector3 = _run(lead, Vector3(0.0, 1.3, -0.4), 0, 60, 10)
	assert_true(off.length() < 0.001, "lead %s" % str(off))


func test_aim_step_leads_at_once_and_fades_once_acked() -> void:
	var lead := NetHandLead.new()
	_run(lead, Vector3(0.0, 1.3, -0.4), 0, 30, 12)
	var first: Vector3 = _run(lead, Vector3(0.4, 1.3, -0.4), 30, 1, 12)
	assert_true(first.x > 0.005, "moves on the first tick: %s" % str(first))
	var mid: Vector3 = _run(lead, Vector3(0.4, 1.3, -0.4), 31, 10, 12)
	assert_true(mid.x > 0.2 and mid.x <= 0.4 + 0.001, "most of the step before the ack: %s" % str(mid))
	var late: Vector3 = _run(lead, Vector3(0.4, 1.3, -0.4), 41, 60, 12)
	assert_true(late.length() < 0.01, "the shown arm has it once acked: %s" % str(late))


func test_lead_moves_no_faster_than_the_modelled_arm() -> void:
	var lead := NetHandLead.new()
	_run(lead, Vector3(0.0, 1.3, -0.4), 0, 20, 12)
	var prev: Vector3 = lead.offset
	var prev_arm: Vector3 = lead.arm
	var worst: float = 0.0
	var arm_worst: float = 0.0
	for i: int in range(80):
		var raw: Vector3 = Vector3(0.5, 1.0, -0.3) if i < 40 else Vector3(-0.5, 1.5, -0.4)
		var off: Vector3 = _run(lead, raw, 20 + i, 1, 12)
		worst = maxf(worst, off.distance_to(prev))
		arm_worst = maxf(arm_worst, lead.arm.distance_to(prev_arm))
		prev = off
		prev_arm = lead.arm
	assert_true(worst <= arm_worst + 0.05, "largest one-tick lead change %.3f, arm %.3f" % [worst, arm_worst])


func test_handover_never_pulls_the_hand_back_faster_than_the_release() -> void:
	var lead := NetHandLead.new()
	var tun: Tuning = Tuning.new()
	_run(lead, Vector3(0.0, 1.3, -0.4), 0, 20, 12)
	_run(lead, Vector3(0.5, 1.3, -0.4), 20, 12, 12)
	var before: float = lead.offset.length()
	# The ack jumps far ahead (the host shows the whole move) while the shown hand has not moved yet.
	var off: Vector3 = lead.step(Vector3(0.5, 1.3, -0.4), Vector3.ZERO, Vector3.ZERO, 32, 31, true, true, DT, tun, Vector3.ZERO)
	var most: float = before * (1.0 - exp(-DT / NetConfig.HAND_LEAD_RELEASE_S)) + 0.02
	assert_true(before - off.length() <= most, "lead %.3f -> %.3f" % [before, off.length()])


func test_clamped_to_max() -> void:
	var lead := NetHandLead.new()
	_run(lead, Vector3(0.0, 1.3, -0.4), 0, 5, 200)
	var off: Vector3 = _run(lead, Vector3(5.0, 1.3, -0.4), 5, 90, 200)
	assert_true(off.length() <= NetConfig.HAND_LEAD_MAX + 0.001)


func test_inactive_fades_and_forgets() -> void:
	var lead := NetHandLead.new()
	var tun: Tuning = Tuning.new()
	_run(lead, Vector3(0.0, 1.3, -0.4), 0, 10, 12)
	_run(lead, Vector3(0.5, 1.3, -0.4), 10, 6, 12)
	var off: Vector3 = Vector3.ONE
	for i: int in range(30):
		off = lead.step(Vector3(0.5, 1.3, -0.4), Vector3.ZERO, Vector3.ZERO, 16 + i, 4 + i, true, false, DT, tun)
	assert_true(off.length() < 0.01)


func test_guard_goal_moves_at_guard_speed() -> void:
	var lead := NetHandLead.new()
	var tun: Tuning = Tuning.new()
	_run(lead, Vector3(0.0, 1.3, -0.4), 0, 5, 3, false)
	_run(lead, Vector3(1.0, 1.3, -0.4), 5, 6, 3, false)
	assert_near(lead.goal.x, 6.0 * DT * tun.guard_hand_speed, 0.002)


func test_two_bone_reaches_and_keeps_lengths() -> void:
	var s := Vector3(0.23, 1.53, 0.0)
	var e := Vector3(0.23, 1.25, 0.0)
	var h := Vector3(0.23, 0.94, 0.0) + Vector3(0.0, 0.0, -0.05)
	var want := Vector3(0.4, 1.2, -0.3)
	var r: Array = NetHandLead.two_bone(s, e, h, want)
	var q1: Quaternion = r[0]
	var e2: Vector3 = r[1]
	var q2: Quaternion = r[2]
	assert_near(s.distance_to(e2), s.distance_to(e), 0.001)
	assert_true((s + Basis(q1) * (e - s)).distance_to(e2) < 0.001)
	var h2: Vector3 = e2 + Basis(q2) * (Basis(q1) * (h - e))
	assert_true(h2.distance_to(want) < 0.002, "hand at %s" % str(h2))
	assert_near(e2.distance_to(h2), e.distance_to(h), 0.001)


func test_two_bone_stops_at_full_stretch() -> void:
	var s := Vector3.ZERO
	var e := Vector3(0.0, -0.28, -0.02)
	var h := Vector3(0.0, -0.58, 0.0)
	var r: Array = NetHandLead.two_bone(s, e, h, Vector3(0.0, -3.0, 0.0))
	var h2: Vector3 = (r[1] as Vector3) + Basis(r[2] as Quaternion) * (Basis(r[0] as Quaternion) * (h - e))
	assert_true(h2.length() <= s.distance_to(e) + e.distance_to(h) + 0.001)
	assert_true(h2.y < -0.55)


func test_arc_turns_one_direction_onto_another() -> void:
	var q: Quaternion = NetHandLead.arc(Vector3(1, 0, 0), Vector3(0, 2, 0))
	assert_true((Basis(q) * Vector3(1, 0, 0)).distance_to(Vector3(0, 1, 0)) < 0.0001)
	var back: Quaternion = NetHandLead.arc(Vector3(1, 0, 0), Vector3(-1, 0, 0))
	assert_true((Basis(back) * Vector3(1, 0, 0)).distance_to(Vector3(-1, 0, 0)) < 0.0001)
	assert_eq(NetHandLead.arc(Vector3.ZERO, Vector3.UP), Quaternion.IDENTITY)
