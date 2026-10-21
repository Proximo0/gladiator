extends TestCase


static func make_fighter(bodies: int, base: float) -> NetFighterSnap:
	var f := NetFighterSnap.new()
	f.state = 2
	f.dead = false
	f.gutted = true
	f.blood = 4.321
	f.bleed_rate = 0.0125
	f.stamina = 0.5
	f.consciousness = 0.75
	f.severed_mask = 0b100
	f.armor_mask = 0b11
	f.part_hp.resize(NetFighterSnap.PART_COUNT)
	for i: int in range(NetFighterSnap.PART_COUNT):
		f.part_hp[i] = float(i) / 10.0
	f.yaw = -2.5
	f.hand_target = Vector3(base, 1.3, -0.4)
	for i: int in range(bodies):
		f.pos.append(Vector3(base + 0.1 * i, 1.0, -2.0))
		f.rot.append(Quaternion(Vector3.UP, 0.1 * i))
		f.vel.append(Vector3(0.5 * i, 0.0, -1.0))
	return f


static func make_snap(tick: int, base: float) -> NetSnapshot:
	var s := NetSnapshot.new()
	s.tick = tick
	s.ack_input_tick = tick - 7
	s.time_scale = 0.4
	s.fighters = [make_fighter(15, base), make_fighter(13, -base)]
	return s


func test_round_trip() -> void:
	var s: NetSnapshot = make_snap(1234, 2.0)
	var bytes: PackedByteArray = s.encode()
	var back: NetSnapshot = NetSnapshot.decode(bytes)
	assert_true(back != null)
	assert_eq(back.tick, 1234)
	assert_eq(back.ack_input_tick, 1227)
	assert_near(back.time_scale, 0.4, 0.003)
	assert_eq(back.fighters.size(), 2)
	var f: NetFighterSnap = back.fighters[0]
	assert_eq(f.state, 2)
	assert_true(f.gutted and not f.dead)
	assert_near(f.blood, 4.321, 0.0001)
	assert_near(f.bleed_rate, 0.0125, 0.0001)
	assert_eq(f.severed_mask, 4)
	assert_eq(f.armor_mask, 3)
	assert_near(f.part_hp[5], 0.5, 0.003)
	assert_near(f.yaw, -2.5, 0.0002)
	assert_eq(f.body_count(), 15)
	assert_true((f.pos[3] - Vector3(2.3, 1.0, -2.0)).length() < 0.001)
	assert_true(f.rot[3].angle_to(Quaternion(Vector3.UP, 0.3)) < 0.003)
	assert_true((f.vel[3] - Vector3(1.5, 0.0, -1.0)).length() < 0.01)
	assert_eq(back.fighters[1].body_count(), 13)


func test_no_ack_round_trips() -> void:
	var s := NetSnapshot.new()
	s.ack_input_tick = -1
	assert_eq(NetSnapshot.decode(s.encode()).ack_input_tick, -1)


func test_size_matches_layout_and_budget() -> void:
	var s: NetSnapshot = make_snap(1, 0.0)
	var bytes: PackedByteArray = s.encode()
	var want: int = NetSnapshot.HEADER_BYTES + 2 * NetFighterSnap.META_BYTES + 28 * NetFighterSnap.BODY_BYTES
	assert_eq(bytes.size(), want)
	# Worst case: 2 fighters with 15 bodies each (fists, weapon and off hand) at 30 Hz stays under 2/3 of the budget.
	var worst: int = NetSnapshot.HEADER_BYTES + 2 * (NetFighterSnap.META_BYTES + 15 * NetFighterSnap.BODY_BYTES)
	assert_true(NetConfig.rate(worst, NetConfig.snapshot_hz()) < NetConfig.BUDGET_BYTES_PER_S * 0.67,
		"%f B/s" % NetConfig.rate(worst, NetConfig.snapshot_hz()))


func test_decode_rejects_garbage() -> void:
	assert_true(NetSnapshot.decode(PackedByteArray()) == null)
	assert_true(NetSnapshot.decode(PackedByteArray([NetConfig.MSG_INPUT, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == null)
	var bytes: PackedByteArray = make_snap(5, 1.0).encode()
	assert_true(NetSnapshot.decode(bytes.slice(0, bytes.size() - 3)) == null, "truncated")


func test_blend_midpoint() -> void:
	var a: NetSnapshot = make_snap(10, 0.0)
	var b: NetSnapshot = make_snap(12, 1.0)
	b.fighters[0].severed_mask = 0b1100
	var m: NetSnapshot = NetSnapshot.blend(a, b, 0.5)
	assert_eq(m.tick, 11)
	assert_near(m.fighters[0].pos[0].x, 0.5, 0.0001)
	assert_eq(m.fighters[0].severed_mask, 0b100, "discrete fields from the older side until t = 1")
	assert_eq(NetSnapshot.blend(a, b, 1.0).fighters[0].severed_mask, 0b1100)


func test_blend_keeps_bodies_when_counts_differ() -> void:
	var a: NetSnapshot = make_snap(10, 0.0)
	var b: NetSnapshot = make_snap(12, 1.0)
	b.fighters[0].pos.resize(14)
	var m: NetSnapshot = NetSnapshot.blend(a, b, 0.5)
	assert_eq(m.fighters[0].body_count(), 15)


func test_extrapolate_moves_by_velocity() -> void:
	var s: NetSnapshot = make_snap(10, 0.0)
	var e: NetSnapshot = s.extrapolated(6.0)
	assert_eq(e.tick, 16)
	assert_near(e.fighters[0].pos[0].z, -2.0 - 1.0 * 0.1, 0.0001)
