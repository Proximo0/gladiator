class_name NetLinkSim
extends RefCounted
## A fake bad network for tests and the --net-lag dev flag: delays each packet by a base latency plus seeded jitter
## (ticks) and drops a share of the unreliable ones. Reliable packets are delayed but never dropped and stay in
## order, like ENet's reliable channel; unreliable ones can reorder, and NetSession drops the stale ones. Pure.

var latency_ticks: int = 0
var jitter_ticks: int = 0
var loss: float = 0.0
var dropped: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _queue: Array = []  ## [[due_tick, serial, bytes], ...]
var _serial: int = 0
var _last_reliable_due: int = -1


func _init(p_latency: int = 0, p_jitter: int = 0, p_loss: float = 0.0, seed_value: int = 1) -> void:
	latency_ticks = maxi(p_latency, 0)
	jitter_ticks = maxi(p_jitter, 0)
	loss = clampf(p_loss, 0.0, 1.0)
	_rng.seed = seed_value


func active() -> bool:
	return latency_ticks > 0 or jitter_ticks > 0 or loss > 0.0


func send(tick: int, bytes: PackedByteArray, reliable: bool) -> void:
	if not reliable and loss > 0.0 and _rng.randf() < loss:
		dropped += 1
		return
	var due: int = tick + latency_ticks + (_rng.randi_range(0, jitter_ticks) if jitter_ticks > 0 else 0)
	if reliable:
		due = maxi(due, _last_reliable_due)
		_last_reliable_due = due
	_queue.append([due, _serial, bytes])
	_serial += 1


## Packets due by `tick`, in due order (send order on ties).
func receive(tick: int) -> Array[PackedByteArray]:
	var due: Array = []
	var keep: Array = []
	for e: Array in _queue:
		if int(e[0]) <= tick:
			due.append(e)
		else:
			keep.append(e)
	_queue = keep
	due.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	var out: Array[PackedByteArray] = []
	for e: Array in due:
		out.append(e[2] as PackedByteArray)
	return out


func pending() -> int:
	return _queue.size()
