extends TestCase


func _sample() -> FighterInput:
	var f := FighterInput.new()
	f.move_x = -350
	f.move_y = 1000
	f.aim_x = 12
	f.aim_y = -999
	f.buttons = FighterInput.SWING | FighterInput.SPRINT
	return f


func test_defaults_are_zero() -> void:
	var f := FighterInput.new()
	assert_eq(f.to_array(), [0, 0, 0, 0, 0])


func test_round_trip_is_exact() -> void:
	var f := _sample()
	var back: FighterInput = FighterInput.from_array(f.to_array())
	assert_eq(back.to_array(), [-350, 1000, 12, -999, 17])
	assert_eq(back.move_x, -350)
	assert_eq(back.aim_y, -999)
	assert_eq(back.buttons, 17)


func test_to_array_order() -> void:
	var f := _sample()
	assert_eq(f.to_array(), [-350, 1000, 12, -999, 17], "order is move_x, move_y, aim_x, aim_y, buttons")


func test_from_array_clamps_axes() -> void:
	var f: FighterInput = FighterInput.from_array([5000, -5000, 1200, -1200, 0])
	assert_eq(f.move_x, 1000)
	assert_eq(f.move_y, -1000)
	assert_eq(f.aim_x, 1000)
	assert_eq(f.aim_y, -1000)


func test_from_array_short_fills_zero() -> void:
	var f: FighterInput = FighterInput.from_array([7])
	assert_eq(f.to_array(), [7, 0, 0, 0, 0])


func test_from_array_accepts_floats_as_ints() -> void:
	var f: FighterInput = FighterInput.from_array([500.0, -250.0, 0.0, 0.0, 8.0])
	assert_eq(f.to_array(), [500, -250, 0, 0, 8])
	assert_eq(typeof(f.move_x), TYPE_INT)


func test_clamp_axis() -> void:
	assert_eq(FighterInput.clamp_axis(1001), 1000)
	assert_eq(FighterInput.clamp_axis(-1001), -1000)
	assert_eq(FighterInput.clamp_axis(-1000), -1000)
	assert_eq(FighterInput.clamp_axis(0), 0)


func test_move_and_aim_scale_to_unit_range() -> void:
	var f := FighterInput.new()
	f.move_x = 500
	f.move_y = -1000
	f.aim_x = 250
	f.aim_y = 1000
	assert_near(f.move().x, 0.5)
	assert_near(f.move().y, -1.0)
	assert_near(f.aim().x, 0.25)
	assert_near(f.aim().y, 1.0)


func test_bits_are_distinct_powers_of_two() -> void:
	var bits: Array = [
		FighterInput.SWING, FighterInput.OFFHAND, FighterInput.HALF_SWORD, FighterInput.THRUST,
		FighterInput.SPRINT, FighterInput.CROUCH, FighterInput.GRAB, FighterInput.TURN_LOCK,
	]
	assert_eq(bits, [1, 2, 4, 8, 16, 32, 64, 128])


func test_has_reports_each_bit() -> void:
	var f := _sample()
	assert_true(f.has(FighterInput.SWING))
	assert_true(f.has(FighterInput.SPRINT))
	assert_false(f.has(FighterInput.OFFHAND))
	assert_false(f.has(FighterInput.TURN_LOCK))


func test_has_zero_mask_is_false() -> void:
	assert_false(_sample().has(0))
