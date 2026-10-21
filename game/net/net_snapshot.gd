class_name NetSnapshot
extends RefCounted
## The host's world at one tick, as the client sees it: both fighters, the newest client input tick the host has
## applied (for the client's own bookkeeping), whether the match is over and the engine time scale (slow motion on
## a knockout). Pure; encode() gives the whole MSG_SNAP packet and decode() reads one back (null if malformed).

const HEADER_BYTES: int = 12  ## type 1, tick 4, input ack 4, flags 1, time scale 1, fighter count 1

var tick: int = 0
var ack_input_tick: int = -1
var ack_older: int = -1  ## blend() only: the older snapshot's ack (what the first version of the latency meter counted)
var over: bool = false
var time_scale: float = 1.0
var fighters: Array[NetFighterSnap] = []


func encode() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetConfig.MSG_SNAP)
	buf.put_u32(tick)
	buf.put_u32(ack_input_tick + 1)  # -1 (nothing applied yet) goes out as 0
	buf.put_u8(1 if over else 0)
	buf.put_u8(NetQuant.frac_u8(time_scale))
	buf.put_u8(fighters.size())
	for f: NetFighterSnap in fighters:
		f.write(buf)
	return buf.data_array


static func decode(bytes: PackedByteArray) -> NetSnapshot:
	if bytes.size() < HEADER_BYTES or int(bytes[0]) != NetConfig.MSG_SNAP:
		return null
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(1)
	var s := NetSnapshot.new()
	s.tick = buf.get_u32()
	s.ack_input_tick = buf.get_u32() - 1
	s.over = (buf.get_u8() & 1) != 0
	s.time_scale = NetQuant.u8_frac(buf.get_u8())
	var n: int = buf.get_u8()
	if n > 2:
		return null
	for _i: int in range(n):
		var f: NetFighterSnap = NetFighterSnap.read(buf)
		if f == null:
			return null
		s.fighters.append(f)
	return s


## Interpolated snapshot between a and b at fraction t (tick blends too, as a float rounded down).
static func blend(a: NetSnapshot, b: NetSnapshot, t: float) -> NetSnapshot:
	var o := NetSnapshot.new()
	var src: NetSnapshot = b if t >= 1.0 else a
	o.tick = a.tick + floori(float(b.tick - a.tick) * t)
	o.ack_input_tick = src.ack_input_tick
	o.ack_older = a.ack_input_tick
	if a.ack_input_tick >= 0 and b.ack_input_tick >= 0:
		# The pose shows this much of the client's input stream: blend it like the bodies.
		o.ack_input_tick = a.ack_input_tick + roundi(float(b.ack_input_tick - a.ack_input_tick) * t)
	o.over = src.over
	o.time_scale = src.time_scale
	for i: int in range(mini(a.fighters.size(), b.fighters.size())):
		o.fighters.append(NetFighterSnap.blend(a.fighters[i], b.fighters[i], t))
	return o


func extrapolated(ticks: float) -> NetSnapshot:
	var o := NetSnapshot.new()
	o.tick = tick + floori(ticks)
	o.ack_input_tick = ack_input_tick
	o.over = over
	o.time_scale = time_scale
	for f: NetFighterSnap in fighters:
		o.fighters.append(f.extrapolated(ticks, float(NetConfig.TICK_HZ)))
	return o
