class_name NetBandwidth
extends RefCounted
## Bytes and packets per direction over a sliding window of ticks, packet overhead included, plus totals.
## Pure: the caller says which tick it is.

var window_ticks: int = NetConfig.TICK_HZ
var total_bytes: int = 0
var total_packets: int = 0
var peak_per_s: float = 0.0

var _buckets: Dictionary = {}  ## tick -> bytes


func _init(p_window: int = NetConfig.TICK_HZ) -> void:
	window_ticks = maxi(p_window, 1)


func add(tick: int, payload: int) -> void:
	var b: int = payload + NetConfig.PACKET_OVERHEAD
	_buckets[tick] = int(_buckets.get(tick, 0)) + b
	total_bytes += b
	total_packets += 1


## Bytes per second over the window ending at `tick`; also tracks the peak.
func per_second(tick: int) -> float:
	var sum: int = 0
	for t: Variant in _buckets.keys():
		if int(t) <= tick - window_ticks:
			_buckets.erase(t)
		elif int(t) <= tick:
			sum += int(_buckets[t])
	var r: float = float(sum) * float(NetConfig.TICK_HZ) / float(window_ticks)
	peak_per_s = maxf(peak_per_s, r)
	return r


## Average bytes per second over `ticks` ticks.
func average(ticks: int) -> float:
	return float(total_bytes) * float(NetConfig.TICK_HZ) / float(maxi(ticks, 1))
