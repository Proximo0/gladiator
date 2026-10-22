class_name QuickMatchFlow
extends RefCounted
## The Quick Match screen's state, without nodes: searching (timer, usual wait), opponent found, the loadout confirm
## (a countdown that readies by itself, a ready note each way), when the host may start, when a connection that never
## came is given up, and why the last search ended. OnlineScreen feeds it delta, the service's answers and the
## session's notes, and draws what it says. Pure: no clock, no nodes.
##
## IDLE -> begin_search -> SEARCHING -> found -> FOUND (the card alone, FOUND_S) -> CONFIRM (countdown, ready)
## -> start -> STARTED. fail() from any phase goes back to IDLE with a plain-language reason.

enum Phase { IDLE, SEARCHING, FOUND, CONFIRM, STARTED }

const FOUND_S: float = 1.6  ## the opponent card alone before the confirm; the client connects when it ends
const CONFIRM_S: float = 10.0  ## the loadout confirm counts down this long, then this side is ready by itself
const READY_GRACE_S: float = 5.0  ## host: after its own ready, how long it waits for the other's ready note
const JOIN_TIMEOUT_S: float = 16.0  ## FOUND + CONFIRM without the other side connected: give the match up
const DEFAULT_WAIT_S: float = 30.0  ## usual wait shown before this session has searches of its own
const WAIT_SAMPLES: int = 5  ## the usual wait is the mean of this many last searches
const MIN_ESTIMATE_S: float = 10.0  ## never promise less: one lucky instant match must not read "about 0:01"

var phase: Phase = Phase.IDLE
var is_host: bool = false
var search_s: float = 0.0  ## time searched (this search)
var phase_s: float = 0.0  ## time in the current phase (FOUND and CONFIRM count together for the join timeout)
var matched_s: float = 0.0  ## time since the opponent was found
var local_ready: bool = false
var remote_ready: bool = false
var ready_sent: bool = false
var auto_ready: bool = false  ## the countdown ran out (not the player's press)
var ready_s: float = 0.0  ## time since this side was ready
var failure: Dictionary = {}  ## OnlineText.plain() of why the last search ended; {} after a cancel
var waits: Array[float] = []  ## seconds the last searches of this session took


func begin_search() -> void:
	phase = Phase.SEARCHING
	search_s = 0.0
	phase_s = 0.0
	matched_s = 0.0
	local_ready = false
	remote_ready = false
	ready_sent = false
	auto_ready = false
	ready_s = 0.0
	failure = {}


## The service matched us. Returns false (ignored) when we were not searching.
func found(host: bool) -> bool:
	if phase != Phase.SEARCHING:
		return false
	waits.append(search_s)
	if waits.size() > WAIT_SAMPLES:
		waits.pop_front()
	is_host = host
	phase = Phase.FOUND
	phase_s = 0.0
	matched_s = 0.0
	return true


## Ends the search or the match setup with `reason` (a raw NetSession / service reason).
func fail(reason: String, opponent: String = "") -> void:
	phase = Phase.IDLE
	failure = OnlineText.plain(reason, opponent)


func cancel() -> void:
	phase = Phase.IDLE
	failure = {}


## Advances the clocks. Returns true when the phase changed (FOUND -> CONFIRM: the client connects now).
func tick(delta: float) -> bool:
	phase_s += delta
	match phase:
		Phase.SEARCHING:
			search_s += delta
		Phase.FOUND:
			matched_s += delta
			if phase_s >= FOUND_S:
				phase = Phase.CONFIRM
				phase_s = 0.0
				return true
		Phase.CONFIRM:
			matched_s += delta
			if local_ready:
				ready_s += delta
			elif phase_s >= CONFIRM_S:
				local_ready = true
				auto_ready = true
	return false


## The player pressed Ready (FOUND skips straight to the confirm). Returns true when that changed anything.
func press_ready() -> bool:
	if local_ready or (phase != Phase.FOUND and phase != Phase.CONFIRM):
		return false
	local_ready = true
	if phase == Phase.FOUND:
		phase = Phase.CONFIRM
		phase_s = 0.0
	return true


func on_remote_ready() -> void:
	if phase == Phase.FOUND or phase == Phase.CONFIRM:
		remote_ready = true


## True once: this side is ready and connected, so its ready note should go out now.
func take_ready_note(remote_joined: bool) -> bool:
	if local_ready and remote_joined and not ready_sent and phase == Phase.CONFIRM:
		ready_sent = true
		return true
	return false


## Host: start the fight now? Both ready, or ours plus a grace for a note that never comes (an older build).
func can_start(remote_joined: bool) -> bool:
	return is_host and phase == Phase.CONFIRM and remote_joined and local_ready \
		and (remote_ready or ready_s >= READY_GRACE_S)


func start() -> void:
	phase = Phase.STARTED


## The other side never connected: give the match up.
func join_timed_out(remote_joined: bool) -> bool:
	return (phase == Phase.FOUND or phase == Phase.CONFIRM) and not remote_joined and matched_s >= JOIN_TIMEOUT_S


## Seconds left on the confirm countdown (whole seconds, rounded up; 0 once ready or outside the confirm).
func confirm_left() -> int:
	if local_ready:
		return 0
	if phase == Phase.FOUND:
		return int(ceilf(CONFIRM_S))
	if phase != Phase.CONFIRM:
		return 0
	return int(ceilf(maxf(CONFIRM_S - phase_s, 0.0)))


## The usual wait: this session's own searches, else the backend's hint (`hint` <= 0: none), else DEFAULT_WAIT_S.
func estimate_s(hint: float) -> float:
	if not waits.is_empty():
		var sum: float = 0.0
		for w: float in waits:
			sum += w
		return maxf(sum / float(waits.size()), MIN_ESTIMATE_S)
	return hint if hint > 0.0 else DEFAULT_WAIT_S


## A failure that is about this one opponent (not the service, not the version): search again by itself.
func should_requeue() -> bool:
	var k: String = str(failure.get("kind", ""))
	return k == OnlineText.KIND_UNREACHABLE or k == OnlineText.KIND_TIMEOUT or k == OnlineText.KIND_LEFT \
		or k == OnlineText.KIND_DROPPED or k == OnlineText.KIND_REFUSED
