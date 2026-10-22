extends TestCase

const DT: float = 1.0 / 60.0


## Presses ROLL at input tick 0 and runs `ticks`: the host's roll shows at `show_at` (-1 never), acks trail by `lag`.
func _run(lead: NetRollLead, ticks: int, lag: int, show_at: int, out: Array) -> void:
	var tun: Tuning = Tuning.new()
	for t: int in range(ticks):
		lead.press(t < 3, Vector2(1.0, 0.0), t, true, 1.0, tun)
		var rolling: bool = show_at >= 0 and t >= show_at and t < show_at + int(tun.roll_time * 60.0)
		var v: Vector2 = lead.step(rolling, t - lag, true, DT, tun)
		out.append(v)


func test_press_dips_at_once() -> void:
	var lead := NetRollLead.new()
	var out: Array = []
	_run(lead, 4, 14, -1, out)
	assert_eq(lead.presses, 1)
	assert_true((out[3] as Vector2).x > 0.005, "dropping by tick 3: %s" % str(out[3]))
	assert_true((out[3] as Vector2).y > 0.0)
	assert_eq(lead.dir, Vector2(1.0, 0.0))


func test_hands_over_smoothly_and_ends_at_zero() -> void:
	var lead := NetRollLead.new()
	var out: Array = []
	_run(lead, 120, 14, 16, out)
	var worst: float = 0.0
	for i: int in range(1, out.size()):
		worst = maxf(worst, absf((out[i] as Vector2).x - (out[i - 1] as Vector2).x))
	assert_true(worst < 0.03, "largest one-tick drop change %.3f" % worst)
	assert_eq(out[out.size() - 1], Vector2.ZERO)
	assert_false(lead.active())
	assert_eq(lead.cancels, 0)


func test_lead_stays_within_limits() -> void:
	var lead := NetRollLead.new()
	var out: Array = []
	_run(lead, 60, 40, -1, out)
	for v: Vector2 in out:
		assert_true(v.x <= NetConfig.ROLL_LEAD_MAX_DROP + 0.0001 and v.y <= NetConfig.ROLL_LEAD_MAX_LEAN + 0.0001)


func test_refused_roll_fades_out() -> void:
	var lead := NetRollLead.new()
	var out: Array = []
	_run(lead, 90, 14, -1, out)
	assert_eq(lead.cancels, 1)
	var peak: float = 0.0
	for v: Vector2 in out:
		peak = maxf(peak, v.x)
	assert_true(peak > 0.02)
	assert_eq(out[out.size() - 1], Vector2.ZERO)


func test_no_lead_without_stamina_or_while_down_or_in_cooldown() -> void:
	var tun: Tuning = Tuning.new()
	var lead := NetRollLead.new()
	assert_false(lead.press(true, Vector2.ZERO, 0, true, tun.roll_stamina * 0.5, tun))
	lead.press(false, Vector2.ZERO, 1, true, 1.0, tun)
	assert_false(lead.press(true, Vector2.ZERO, 2, false, 1.0, tun))
	lead.press(false, Vector2.ZERO, 3, true, 1.0, tun)
	assert_true(lead.press(true, Vector2.ZERO, 4, true, 1.0, tun))
	assert_eq(lead.dir, Vector2(0.0, -1.0), "no direction rolls backward")
	for t: int in range(5, 90):
		lead.step(t > 20 and t < 86, t - 14, true, DT, tun)
	lead.press(false, Vector2.ZERO, 90, true, 1.0, tun)
	assert_false(lead.press(true, Vector2.ZERO, 91, true, 1.0, tun), "inside roll time + cooldown")


func test_holding_roll_starts_once() -> void:
	var lead := NetRollLead.new()
	var out: Array = []
	_run(lead, 3, 14, -1, out)
	assert_eq(lead.presses, 1)


func test_dip_model_matches_roll_logic_ends() -> void:
	var tun: Tuning = Tuning.new()
	assert_eq(NetRollLead.dip_at(0.0, tun), Vector2.ZERO)
	var full: Vector2 = NetRollLead.dip_at(tun.roll_time, tun)
	assert_near(full.x, tun.stand_height - tun.roll_dip_height, 0.0001)
	assert_near(full.y, RollLogic.LEAN_IN, 0.0001)
