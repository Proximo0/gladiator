extends TestCase


func _inp(i: int) -> FighterInput:
	return FighterInput.from_array([i, -i, 1000 - i, -1000 + i, i & 0xff])


func test_pack_carries_last_ticks_newest_first_and_unpacks_oldest_first() -> void:
	var p := NetInputPacker.new(4)
	for t: int in range(10):
		p.record(t, _inp(t))
	var bytes: PackedByteArray = p.pack()
	assert_eq(bytes.size(), NetInputPacker.HEADER_BYTES + 4 * NetInputPacker.ENTRY_BYTES)
	var rows: Array = NetInputPacker.unpack(bytes)
	assert_eq(rows.size(), 4)
	assert_eq(int(rows[0][0]), 6)
	assert_eq(int(rows[3][0]), 9)
	assert_eq((rows[3][1] as FighterInput).to_array(), [9, -9, 991, -991, 9])


func test_first_packets_carry_what_exists() -> void:
	var p := NetInputPacker.new(4)
	p.record(0, _inp(0))
	var rows: Array = NetInputPacker.unpack(p.pack())
	assert_eq(rows.size(), 1)


func test_input_at_and_history_limit() -> void:
	var p := NetInputPacker.new()
	for t: int in range(300):
		p.record(t, _inp(t))
	assert_true(p.input_at(10) == null)
	assert_eq(p.input_at(299).move_x, 299)


func test_unpack_rejects_garbage() -> void:
	assert_eq(NetInputPacker.unpack(PackedByteArray([NetConfig.MSG_INPUT, 1, 0, 0, 0, 3])), [])
	assert_eq(NetInputPacker.unpack(PackedByteArray([NetConfig.MSG_SNAP])), [])


func test_rate_is_small() -> void:
	var payload: int = NetInputPacker.HEADER_BYTES + NetConfig.INPUT_REDUNDANCY * NetInputPacker.ENTRY_BYTES
	assert_true(NetConfig.rate(payload, float(NetConfig.TICK_HZ)) < 6000.0)
