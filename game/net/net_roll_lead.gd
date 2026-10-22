class_name NetRollLead
extends RefCounted
## Client-side cosmetic start of the client's own dodge roll. The host only starts a roll when the press reaches it,
## and the client sees that a round trip plus the interpolation delay later. On the press (when the shown fighter
## could roll: standing, enough stamina, off the predicted cooldown) this starts the roll's opening dip at once: the
## body lowers and leans toward the roll as RollLogic's dip would. When the shown snapshots start rolling it hands
## over with a time shift: the lead is the dip at the time since the press minus the dip at the time since the host's
## roll showed, which falls to zero as the shown dip completes, so the sum of the two never jumps. When the shown ack
## passes the press and no roll shows (the host refused it) the lead fades out. Visual only; nothing is sent.
## Pure: seconds from delta, no clock.

var dir: Vector2 = Vector2(0.0, -1.0)  ## roll direction in the facing frame (x right, y forward), RollLogic's rule
var drop: float = 0.0  ## drawn lowering this tick, m
var lean: float = 0.0  ## drawn lean toward `dir` this tick, rad
var pending: bool = false  ## a predicted roll is leading (pressed, the host's has not finished its dip yet)
var presses: int = 0  ## predicted roll starts
var cancels: int = 0  ## ... called off because the host did not roll
var _press_tick: int = -1
var _since_press: float = 0.0
var _host_seen: bool = false
var _since_host: float = 0.0
var _cancelled: bool = false
var _last_start: float = -1000.0  ## clock of the last predicted start, s
var _clock: float = 0.0
var _held: bool = false
var _shown_rolling: bool = false


## The press. `held`: ROLL this tick; `move`: local move input; `input_tick`: this tick's input index;
## `standing` / `stamina`: the shown fighter's. Returns true when a predicted roll starts.
func press(held: bool, move: Vector2, input_tick: int, standing: bool, stamina: float, tun: Tuning) -> bool:
	var edge: bool = held and not _held
	_held = held
	if not edge or pending or _shown_rolling or not standing or stamina < tun.roll_stamina:
		return false
	if _clock - _last_start < tun.roll_time + tun.roll_cooldown:
		return false
	dir = move.normalized() if move.length() > 0.2 else Vector2(0.0, -1.0)
	pending = true
	presses += 1
	_press_tick = input_tick
	_since_press = 0.0
	_host_seen = false
	_since_host = 0.0
	_cancelled = false
	_last_start = _clock
	return true


## One tick after the shown snapshot is known: `rolling` the shown fighter's roll bit, `ack` the input index it had
## applied, `standing` its state. Returns Vector2(drop, lean) to draw.
func step(rolling: bool, ack: int, standing: bool, delta: float, tun: Tuning) -> Vector2:
	_clock += delta
	var started: bool = rolling and not _shown_rolling
	_shown_rolling = rolling
	var want_drop: float = 0.0
	var want_lean: float = 0.0
	var tau: float = NetConfig.ROLL_LEAD_TAU_S
	if pending:
		_since_press += delta
		if started and not _cancelled:
			_host_seen = true
		if _host_seen:
			_since_host += delta
		elif not _cancelled and (not standing or (ack >= 0 and ack >= _press_tick + NetConfig.ROLL_LEAD_CONFIRM_TICKS)):
			_cancelled = true
			cancels += 1
		if not _cancelled:
			var d: Vector2 = dip_at(_since_press, tun) - (dip_at(_since_host, tun) if _host_seen else Vector2.ZERO)
			want_drop = clampf(d.x, 0.0, NetConfig.ROLL_LEAD_MAX_DROP)
			want_lean = clampf(d.y, 0.0, NetConfig.ROLL_LEAD_MAX_LEAN)
		else:
			tau = NetConfig.ROLL_LEAD_CANCEL_TAU_S
		var dip_s: float = RollLogic.DIP_END * tun.roll_time
		if (_host_seen and _since_host >= dip_s or _cancelled) and drop < 0.002 and lean < 0.003:
			pending = false
	var k: float = 1.0 - exp(-delta / tau) if tau > 0.0 else 1.0
	drop = lerpf(drop, want_drop, k)
	lean = lerpf(lean, want_lean, k)
	if not pending and want_drop == 0.0 and drop < 0.002 and lean < 0.003:
		drop = 0.0
		lean = 0.0
	return Vector2(drop, lean)


## The opening dip `t` seconds into a roll as RollLogic and the fighter shape it: pelvis lowering (stand height to the
## dip height) and lean, both on RollLogic.dip / spin up to the end of the dip.
static func dip_at(t: float, tun: Tuning) -> Vector2:
	var u: float = minf(t / maxf(tun.roll_time, 0.01), RollLogic.DIP_END)
	var depth: float = maxf(tun.stand_height - tun.roll_dip_height, 0.0)
	return Vector2(depth * RollLogic.dip(u), RollLogic.spin(u))


func active() -> bool:
	return pending or drop > 0.0 or lean > 0.0
