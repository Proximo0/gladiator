class_name NetInputBuffer
extends RefCounted
## Host side of the client's input stream: a jitter buffer keyed by the client's tick. The host pops one input per
## physics tick, playing the client's ticks in order about `target` ticks behind the newest one received. A missing
## tick repeats the last input (and is skipped once newer ticks have arrived); a buffer that grew past `max_depth`
## (the client ran ahead, or a burst arrived) skips to `target`. The buffer is adaptive: it starts `target` (1) tick
## deep and grows by itself, one tick per underrun (the stall leaves the stream one tick further ahead); every
## SHRINK_WINDOW pops, if it never came within `target` ticks of empty, it drops one tick again. So a clean link
## sits at `target` and a jittery one settles at the depth its jitter needs. A press-once button (roll, grab) on a tick
## that gets skipped or arrives late is carried onto the next tick played, so the press still happens. When nothing new
## has arrived for `stale_ticks` pops the last input stops being repeated: movement and buttons go neutral (the aim
## stays), so a client that stalls or vanishes does not keep charging and swinging on its last input. Pure; counters for the debug line and the tests.

const EDGE_BUTTONS: int = FighterInput.ROLL | FighterInput.GRAB | FighterInput.SHOVE | FighterInput.KICK | FighterInput.CLINCH  ## press-once buttons: a skipped tick must not swallow one
const SHRINK_WINDOW: int = 90  ## pops (1.5 s) the buffer must stay deeper than `target` before it gives one tick back
## Bounds against a modded client (docs/net_security.md): a tick may jump at most MAX_AHEAD past the newest one held
## (10 s; the session drops the link after 5 s of silence anyway), at most MAX_HELD ticks wait at once, and
## skipping walks the held ticks, never the gap, so a tick near 2^32 cannot stall the host in a 4-billion-step loop.
const MAX_AHEAD: int = 600
const MAX_HELD: int = 256
const PLAYED_MEMORY: int = 64  ## played ticks remembered to tell redundant copies from late arrivals

var target: int = NetConfig.INPUT_BUFFER_TARGET
var max_depth: int = NetConfig.INPUT_BUFFER_MAX
var last_applied_tick: int = -1  ## client tick of the input played last (-1 before the first)
var received: int = 0
var duplicates: int = 0
var late: int = 0  ## arrived after its tick was played or skipped
var underruns: int = 0  ## pops with nothing to play (last input repeated)
var skipped: int = 0  ## ticks jumped over (lost for good, or dropped to shrink the buffer)
var carried: int = 0  ## press-once buttons moved from a skipped or late tick onto the next one played
var stale_ticks: int = NetConfig.INPUT_STALE_TICKS  ## consecutive underruns after which the repeated input goes neutral
var stale_pops: int = 0  ## pops played neutral because the stream had gone quiet
var rejected: int = 0  ## pushes refused: too far ahead of the stream, or the buffer was full

var _inputs: Dictionary = {}  ## client tick -> FighterInput
var _next: int = -1
var _newest: int = -1
var _last: FighterInput = FighterInput.new()
var _min_lead: int = 1 << 20  ## smallest (newest - next) seen at a pop in the current window
var _window: int = 0
var _run: int = 0  ## consecutive underruns
var _carry: int = 0  ## press-once bits waiting for the next tick played
var _played: Dictionary = {}  ## recently played client ticks, to tell redundant copies from late arrivals


func _init(p_target: int = NetConfig.INPUT_BUFFER_TARGET, p_max: int = NetConfig.INPUT_BUFFER_MAX) -> void:
	target = maxi(p_target, 0)
	max_depth = maxi(p_max, target + 1)


func push(tick: int, inp: FighterInput) -> void:
	if _inputs.has(tick):
		duplicates += 1
		return
	if tick < 0 or (_newest >= 0 and tick > _newest + MAX_AHEAD) or _inputs.size() >= MAX_HELD:
		rejected += 1
		return
	if _next >= 0 and tick < _next:
		if _played.has(tick):
			duplicates += 1  # a redundant copy of a tick already played
		else:
			late += 1
			_keep_edges(inp)
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
		for t: int in _inputs.keys():
			if t < to:
				_keep_edges(_inputs[t])
				_inputs.erase(t)
		skipped += to - _next
		_next = to
	if _inputs.has(_next):
		_last = _inputs[_next]
		_inputs.erase(_next)
		last_applied_tick = _next
		_played[_next] = true
		_played.erase(_next - PLAYED_MEMORY)
		if _played.size() > PLAYED_MEMORY * 2:
			_forget_played()
		_next += 1
		_run = 0
		if _carry != 0:
			var merged: Array = _last.to_array()
			merged[4] = int(merged[4]) | _carry
			_carry = 0
			carried += 1
			return FighterInput.from_array(merged)
		return _last
	underruns += 1
	_run += 1
	if _newest > _next:
		skipped += 1  # never coming: newer ticks are here, so move past it
		_next += 1
		_run = 0
	if _run > stale_ticks:
		stale_pops += 1
		var quiet: Array = _last.to_array()
		quiet[0] = 0
		quiet[1] = 0
		quiet[4] = 0
		return FighterInput.from_array(quiet)
	return _last


## Once per SHRINK_WINDOW pops: if the lead over the next tick never fell to `target`, drop the oldest tick.
func _shrink_check() -> void:
	if _newest >= 0:
		_min_lead = mini(_min_lead, _newest - _next)
	_window += 1
	if _window < SHRINK_WINDOW:
		return
	if _min_lead > target and _inputs.has(_next):
		_keep_edges(_inputs[_next])
		_inputs.erase(_next)
		_next += 1
		skipped += 1
	_window = 0
	_min_lead = 1 << 20


## After a skip the exact-key erase above misses the ticks before the jump: drop everything older than the memory.
func _forget_played() -> void:
	for t: int in _played.keys():
		if t < _next - PLAYED_MEMORY:
			_played.erase(t)


func _keep_edges(inp: FighterInput) -> void:
	_carry |= inp.buttons & EDGE_BUTTONS


func last_input() -> FighterInput:
	return _last
