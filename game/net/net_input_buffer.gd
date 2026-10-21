class_name NetInputBuffer
extends RefCounted
## Host side of the client's input stream: a jitter buffer keyed by the client's tick. The host pops one input per
## physics tick, playing the client's ticks in order about `target` ticks behind the newest one received. A missing
## tick repeats the last input (and is skipped once newer ticks have arrived); a buffer that grew past `max_depth`
## (the client ran ahead, or a burst arrived) skips to `target`. The buffer is adaptive: it starts `target` (1) tick
## deep and grows by itself, one tick per underrun (the stall leaves the stream one tick further ahead); every
## SHRINK_WINDOW pops, if it never came within `target` ticks of empty, it drops one tick again. So a clean link
## sits at `target` and a jittery one settles at the depth its jitter needs. Pure; counters for the debug line and the tests.

const SHRINK_WINDOW: int = 90  ## pops (1.5 s) the buffer must stay deeper than `target` before it gives one tick back

var target: int = NetConfig.INPUT_BUFFER_TARGET
var max_depth: int = NetConfig.INPUT_BUFFER_MAX
var last_applied_tick: int = -1  ## client tick of the input played last (-1 before the first)
var received: int = 0
var duplicates: int = 0
var late: int = 0  ## arrived after its tick was played or skipped
var underruns: int = 0  ## pops with nothing to play (last input repeated)
var skipped: int = 0  ## ticks jumped over (lost for good, or dropped to shrink the buffer)

var _inputs: Dictionary = {}  ## client tick -> FighterInput
var _next: int = -1
var _newest: int = -1
var _last: FighterInput = FighterInput.new()
var _min_lead: int = 1 << 20  ## smallest (newest - next) seen at a pop in the current window
var _window: int = 0
var _played: Dictionary = {}  ## recently played client ticks, to tell redundant copies from late arrivals


func _init(p_target: int = NetConfig.INPUT_BUFFER_TARGET, p_max: int = NetConfig.INPUT_BUFFER_MAX) -> void:
	target = maxi(p_target, 0)
	max_depth = maxi(p_max, target + 1)


func push(tick: int, inp: FighterInput) -> void:
	if _inputs.has(tick):
		duplicates += 1
		return
	if _next >= 0 and tick < _next:
		if _played.has(tick):
			duplicates += 1  # a redundant copy of a tick already played
		else:
			late += 1
		return
	_inputs[tick] = inp
	received += 1
	_newest = maxi(_newest, tick)


## Ticks waiting to be played (from the next one to the newest).
func depth() -> int:
	return 0 if _next < 0 or _newest < _next else _newest - _next + 1


## The input for this host tick.
func pop() -> FighterInput:
	if _next < 0:
		if _newest < 0 or _inputs.size() < target + 1:
			return _last
		_next = _newest - target
	_shrink_check()
	if depth() > max_depth:
		var to: int = _newest - target
		for t: int in range(_next, to):
			if _inputs.has(t):
				_inputs.erase(t)
			skipped += 1
		_next = to
	if _inputs.has(_next):
		_last = _inputs[_next]
		_inputs.erase(_next)
		last_applied_tick = _next
		_played[_next] = true
		_played.erase(_next - 64)
		_next += 1
		return _last
	underruns += 1
	if _newest > _next:
		skipped += 1  # never coming: newer ticks are here, so move past it
		_next += 1
	return _last


## Once per SHRINK_WINDOW pops: if the lead over the next tick never fell to `target`, drop the oldest tick.
func _shrink_check() -> void:
	if _newest >= 0:
		_min_lead = mini(_min_lead, _newest - _next)
	_window += 1
	if _window < SHRINK_WINDOW:
		return
	if _min_lead > target and _inputs.has(_next):
		_inputs.erase(_next)
		_next += 1
		skipped += 1
	_window = 0
	_min_lead = 1 << 20


func last_input() -> FighterInput:
	return _last
