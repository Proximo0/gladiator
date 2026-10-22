class_name NetInputPacker
extends RefCounted
## Client side of the input stream: remembers the FighterInput of each local tick and packs the newest few into one
## MSG_INPUT packet (newest first), so any one packet that arrives carries the ticks lost before it. unpack() is the
## host side. Wire: type u8, newest tick u32, count u8, then count x (move_x, move_y, aim_x, aim_y as int16, buttons
## u16, FighterInput bits up to CLINCH 2048) = 6 + 10 x count bytes.

const HEADER_BYTES: int = 6
const ENTRY_BYTES: int = 10
const HISTORY: int = 128
const MAX_ROWS: int = 16  ## unpack refuses more rows than this (a packet carries INPUT_REDUNDANCY = 4; the u8 count could say 255)

var redundancy: int = NetConfig.INPUT_REDUNDANCY
var _history: Dictionary = {}  ## tick -> [5 ints]
var newest_tick: int = -1


func _init(p_redundancy: int = NetConfig.INPUT_REDUNDANCY) -> void:
	redundancy = maxi(p_redundancy, 1)


func record(tick: int, inp: FighterInput) -> void:
	_history[tick] = inp.to_array()
	newest_tick = maxi(newest_tick, tick)
	_history.erase(tick - HISTORY)


## The input recorded for `tick`, or null.
func input_at(tick: int) -> FighterInput:
	if not _history.has(tick):
		return null
	return FighterInput.from_array(_history[tick])


func pack() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetConfig.MSG_INPUT)
	buf.put_u32(maxi(newest_tick, 0))
	var rows: Array = []
	for k: int in range(redundancy):
		var t: int = newest_tick - k
		if t < 0 or not _history.has(t):
			break
		rows.append(_history[t])
	buf.put_u8(rows.size())
	for r: Array in rows:
		for i: int in range(4):
			buf.put_16(int(r[i]))
		buf.put_u16(int(r[4]) & 0xffff)
	return buf.data_array


## [[tick, FighterInput], ...] oldest first; [] when malformed. Axes come back clamped by FighterInput.from_array.
static func unpack(bytes: PackedByteArray) -> Array:
	if bytes.size() < HEADER_BYTES or int(bytes[0]) != NetConfig.MSG_INPUT:
		return []
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(1)
	var newest: int = buf.get_u32()
	var n: int = buf.get_u8()
	# Exact size, a sane row count and no tick below 0: anything else is a modded or broken sender.
	if n < 1 or n > MAX_ROWS or bytes.size() != HEADER_BYTES + n * ENTRY_BYTES or newest < n - 1:
		return []
	var out: Array = []
	for k: int in range(n):
		var a: Array = [buf.get_16(), buf.get_16(), buf.get_16(), buf.get_16(), buf.get_u16()]
		out.push_front([newest - k, FighterInput.from_array(a)])
	return out
