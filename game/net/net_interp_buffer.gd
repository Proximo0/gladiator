class_name NetInterpBuffer
extends RefCounted
## Client side of the snapshot stream: keeps recent snapshots and a render clock in host ticks that runs a little
## behind the host, so there is (almost) always a snapshot on each side of it to blend between. The delay adapts:
## one snapshot interval plus the measured arrival jitter, clamped to INTERP_MIN_DELAY..INTERP_MAX_DELAY.
## The clock eases toward its target at up to +-10% speed and jumps when it is INTERP_RESYNC ticks off. When the
## stream stops it extrapolates by velocity for up to MAX_EXTRAPOLATE ticks, then holds. Hit and gore events wait
## here too and come out when the render clock reaches their tick, in step with the bodies.
## Pure: the caller passes its own tick count; nothing reads the clock.

const CAPACITY: int = 32
const MAX_EVENTS: int = 512  ## queued hit and gore events kept at most (the oldest go first)
const OFFSET_EASE: float = 0.02  ## per snapshot, host-minus-local tick offset rising (packets came early)
const OFFSET_FALL: float = 0.3  ## ... and falling (a packet came late)
const JITTER_EASE: float = 0.1
const RATE_GAIN: float = 0.05  ## clock speed change per tick of error
const RATE_LIMIT: float = 0.1
const STALE_RESTART: int = 4  ## snapshots in a row that arrive behind the render clock before it starts over
const JITTER_MARGIN: float = 1.0  ## delay = one snapshot interval + BASE_MARGIN + this many mean arrival deviations (the offset already sits at the late edge)
const BASE_MARGIN: float = 0.25

var interval: float = float(NetConfig.SNAP_EVERY_TICKS)
var render_tick: float = -1.0
var delay: float = NetConfig.INTERP_MIN_DELAY
var jitter: float = 0.0  ## mean absolute deviation of arrival offsets, ticks
var received: int = 0
var dropped_old: int = 0  ## arrived older than one already held (out of order) or already rendered past
var extrapolated_ticks: int = 0  ## advance() calls that found the clock past the newest snapshot
var held_ticks: int = 0  ## ... and past the extrapolation limit too
var resyncs: int = 0

var _snaps: Array[NetSnapshot] = []
var _events: Array = []  ## [[tick, side, kind, ev], ...] in arrival order
var _offset: float = 0.0
var _have_offset: bool = false
var _started: bool = false
var _stale_run: int = 0


func _init(p_interval: float = float(NetConfig.SNAP_EVERY_TICKS)) -> void:
	interval = maxf(p_interval, 1.0)
	delay = maxf(NetConfig.INTERP_MIN_DELAY, interval + BASE_MARGIN)


func newest_tick() -> int:
	return _snaps[_snaps.size() - 1].tick if not _snaps.is_empty() else -1


func size() -> int:
	return _snaps.size()


## The oldest snapshot held at or after `tick`, or null.
func first_at_or_after(tick: int) -> NetSnapshot:
	for s: NetSnapshot in _snaps:
		if s.tick >= tick:
			return s
	return null


func push(s: NetSnapshot, local_tick: int) -> void:
	if s == null:
		return
	if not _snaps.is_empty() and s.tick <= newest_tick():
		dropped_old += 1
		return
	if _started and float(s.tick) < render_tick - interval:
		# Behind the clock. A packet or two is just late; a run of them means the clock ran ahead of the stream (the
		# host paused, or the offset was wrong), so start the clock over from the stream.
		dropped_old += 1
		_stale_run += 1
		if _stale_run < STALE_RESTART:
			return
		resyncs += 1
		_snaps.clear()
		_have_offset = false
		_started = false
	_stale_run = 0
	received += 1
	_snaps.append(s)
	while _snaps.size() > CAPACITY:
		_snaps.pop_front()
	var off: float = float(s.tick - local_tick)
	if not _have_offset:
		_offset = off
		_have_offset = true
	else:
		# Late packets pull the offset down fast and early ones lift it slowly, so it tracks the late edge of the
		# stream; the jitter around it sets how far behind the clock runs.
		jitter = lerpf(jitter, absf(off - _offset), JITTER_EASE)
		_offset = lerpf(_offset, off, OFFSET_FALL if off < _offset else OFFSET_EASE)
	delay = clampf(interval + BASE_MARGIN + JITTER_MARGIN * jitter, maxf(NetConfig.INTERP_MIN_DELAY, interval + BASE_MARGIN), NetConfig.INTERP_MAX_DELAY)


func push_event(tick: int, side: int, kind: String, ev: Dictionary) -> void:
	_events.append([tick, side, kind, ev])
	if _events.size() > MAX_EVENTS:
		_events.pop_front()  # a host stamping events far in the future must not grow the queue for ever


## Where the render clock wants to be at `local_tick`.
func target_tick(local_tick: int) -> float:
	return float(local_tick) + _offset - delay


## Moves the render clock on by one local tick. Returns false until there is something to show.
func advance(local_tick: int) -> bool:
	if _snaps.is_empty():
		return false
	var want: float = target_tick(local_tick)
	if not _started:
		render_tick = want
		_started = true
	else:
		var err: float = want - render_tick
		if absf(err) > NetConfig.INTERP_RESYNC:
			render_tick = maxf(want, render_tick)
			resyncs += 1
		else:
			render_tick += 1.0 + clampf(err * RATE_GAIN, -RATE_LIMIT, RATE_LIMIT)
	var past: float = render_tick - float(newest_tick())
	if past > 0.0:
		extrapolated_ticks += 1
		if past > NetConfig.MAX_EXTRAPOLATE:
			held_ticks += 1
	# Keep one snapshot at or before the clock; older ones are done.
	while _snaps.size() > 2 and float(_snaps[1].tick) <= render_tick:
		_snaps.pop_front()
	return true


## The state at the render clock: a blend of the two snapshots around it, the oldest one when the clock is before
## everything held, or the newest moved on by velocity (up to MAX_EXTRAPOLATE ticks) when it is past them all.
func sample() -> NetSnapshot:
	if _snaps.is_empty():
		return null
	var r: float = render_tick
	var first: NetSnapshot = _snaps[0]
	if r <= float(first.tick):
		return first
	for i: int in range(_snaps.size() - 1):
		var a: NetSnapshot = _snaps[i]
		var b: NetSnapshot = _snaps[i + 1]
		if r >= float(a.tick) and r < float(b.tick):
			return NetSnapshot.blend(a, b, (r - float(a.tick)) / float(b.tick - a.tick))
	var last: NetSnapshot = _snaps[_snaps.size() - 1]
	return last.extrapolated(minf(r - float(last.tick), NetConfig.MAX_EXTRAPOLATE), _snaps[_snaps.size() - 2] if _snaps.size() > 1 else null)


## Events whose tick the render clock has reached, oldest first: [[tick, side, kind, ev], ...].
func take_due_events() -> Array:
	var due: Array = []
	var keep: Array = []
	for e: Array in _events:
		if float(int(e[0])) <= render_tick:
			due.append(e)
		else:
			keep.append(e)
	_events = keep
	return due


## Every waiting event, due or not (the match ended and the stream stops).
func take_all_events() -> Array:
	var all: Array = _events
	_events = []
	return all
