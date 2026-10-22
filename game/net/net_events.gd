class_name NetEvents
extends RefCounted
## Hit and gore events on the wire (MSG_EVENTS, reliable). Each record: tick u32, emitting fighter u8, kind u8
## (0 hit, 1 gore), a u32 mask of which KEYS are present, then the present values in KEYS order. Booleans live in
## the mask alone; zero numbers, empty strings and false flags are left out. Keys not in the table are dropped:
## the client only needs what blood, sound, sand and the announcer read. About 30-45 bytes per hit.

const T_BOOL: int = 0
const T_HALF: int = 1
const T_STR: int = 2
const T_POS: int = 3
const T_DIR: int = 4
const T_VEL: int = 5
const T_SIDE: int = 6
const T_STRS: int = 7

const KEYS: Array = [
	["attacker", T_SIDE], ["target", T_SIDE], ["part", T_STR], ["weapon_id", T_STR], ["contact", T_STR],
	["point", T_POS], ["normal", T_DIR], ["rel_vel", T_VEL], ["cut", T_HALF], ["pierce", T_HALF], ["blunt", T_HALF],
	["total", T_HALF], ["bleed", T_HALF], ["energy", T_HALF], ["stagger", T_HALF], ["glanced", T_BOOL],
	["hit_on_weapon", T_BOOL], ["disarmed", T_BOOL], ["arm_drop", T_BOOL], ["sever", T_BOOL], ["behead", T_BOOL],
	["gut", T_BOOL], ["finisher", T_STR], ["armor_ids", T_STRS], ["kind", T_STR], ["amount", T_HALF],
	["dislodge", T_BOOL], ["edge_alignment", T_HALF], ["knockback", T_VEL],
]
const KINDS: PackedStringArray = ["hit", "gore"]
const MAX_PER_PACKET: int = 32
## Largest events packet: the EOS P2P relay drops anything over 1164 bytes, even reliable packets.
const MAX_BYTES: int = 1100


## Splits `records` into encoded packets of at most MAX_PER_PACKET records and MAX_BYTES bytes each.
static func encode_chunks(records: Array) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var rest: Array = records.duplicate()
	while not rest.is_empty():
		var n: int = mini(rest.size(), MAX_PER_PACKET)
		var pkt: PackedByteArray = encode(rest.slice(0, n))
		while pkt.size() > MAX_BYTES and n > 1:
			n = n / 2
			pkt = encode(rest.slice(0, n))
		out.append(pkt)
		rest = rest.slice(n)
	return out


## One packet for `records` ([[tick, side, kind, ev], ...]); at most MAX_PER_PACKET are written.
static func encode(records: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetConfig.MSG_EVENTS)
	var n: int = mini(records.size(), MAX_PER_PACKET)
	buf.put_u8(n)
	for i: int in range(n):
		var r: Array = records[i]
		buf.put_u32(int(r[0]))
		buf.put_u8(int(r[1]))
		buf.put_u8(maxi(KINDS.find(str(r[2])), 0))
		_write_event(buf, r[3] as Dictionary)
	return buf.data_array


static func _present(v: Variant, kind: int) -> bool:
	match kind:
		T_BOOL:
			return bool(v)
		T_HALF:
			return (v is float or v is int) and float(v) != 0.0
		T_STR:
			return str(v) != ""
		T_POS, T_DIR, T_VEL:
			return v is Vector3 and (v as Vector3) != Vector3.ZERO
		T_SIDE:
			return v is int or v is float
		T_STRS:
			return v is Array and not (v as Array).is_empty()
	return false


static func _write_event(buf: StreamPeerBuffer, ev: Dictionary) -> void:
	var mask: int = 0
	for k: int in range(KEYS.size()):
		var key: Array = KEYS[k]
		if ev.has(key[0]) and _present(ev[key[0]], int(key[1])):
			mask |= 1 << k
	buf.put_u32(mask)
	for k: int in range(KEYS.size()):
		if (mask & (1 << k)) == 0:
			continue
		var key: Array = KEYS[k]
		var v: Variant = ev[key[0]]
		match int(key[1]):
			T_HALF:
				buf.put_half(float(v))
			T_STR:
				NetQuant.put_str(buf, str(v))
			T_POS:
				NetQuant.put_vec_i16(buf, v as Vector3, NetQuant.POS_SCALE)
			T_DIR:
				NetQuant.put_dir(buf, v as Vector3)
			T_VEL:
				NetQuant.put_vec_i16(buf, v as Vector3, NetQuant.VEL_SCALE)
			T_SIDE:
				buf.put_u8(clampi(int(v) + 1, 0, 255))
			T_STRS:
				var arr: Array = v
				buf.put_u8(mini(arr.size(), 8))
				for i: int in range(mini(arr.size(), 8)):
					NetQuant.put_str(buf, str(arr[i]))


## [[tick, side, kind, ev], ...], or [] when the packet is malformed.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.size() < 2 or int(bytes[0]) != NetConfig.MSG_EVENTS:
		return []
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(1)
	var n: int = buf.get_u8()
	var out: Array = []
	for _i: int in range(n):
		if buf.get_available_bytes() < 10:
			return []
		var tick: int = buf.get_u32()
		var side: int = buf.get_u8()
		var kind: int = buf.get_u8()
		var mask: int = buf.get_u32()
		var ev: Dictionary = {}
		for k: int in range(KEYS.size()):
			if (mask & (1 << k)) == 0:
				continue
			var key: Array = KEYS[k]
			match int(key[1]):
				T_BOOL:
					ev[key[0]] = true
				T_HALF:
					ev[key[0]] = buf.get_half()
				T_STR:
					ev[key[0]] = NetQuant.get_str(buf)
				T_POS:
					ev[key[0]] = NetQuant.get_vec_i16(buf, NetQuant.POS_SCALE)
				T_DIR:
					ev[key[0]] = NetQuant.get_dir(buf)
				T_VEL:
					ev[key[0]] = NetQuant.get_vec_i16(buf, NetQuant.VEL_SCALE)
				T_SIDE:
					ev[key[0]] = buf.get_u8() - 1
				T_STRS:
					var arr: Array = []
					for _j: int in range(buf.get_u8()):
						arr.append(NetQuant.get_str(buf))
					ev[key[0]] = arr
		if buf.get_position() > bytes.size():
			return []
		out.append([tick, side, KINDS[clampi(kind, 0, KINDS.size() - 1)], ev])
	return out
