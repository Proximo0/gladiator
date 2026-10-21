class_name NetFighterSnap
extends RefCounted
## One fighter's networked state at one tick: health, state, what is cut off or knocked off, facing, the weapon hand
## target and every rigid body (11 parts, then the fighter's weapons in creation order: fists, main, off hand).
## Pure data plus its wire format and interpolation. The layout is in docs/online_brief.md.

const PART_COUNT: int = 11
const META_BYTES: int = 31  ## everything before the bodies, the body count byte included
const BODY_BYTES: int = 16  ## pos 6 + rotation 4 + linear velocity 6
const BLOOD_SCALE: float = 10000.0  ## litres to uint16 (0.1 ml, up to 6.5 l)
const MAX_BODIES: int = 32

var state: int = 0  ## index into NetConfig.STATES
var dead: bool = false
var gutted: bool = false
var blood: float = 5.0
var bleed_rate: float = 0.0
var stamina: float = 1.0
var consciousness: float = 1.0
var severed_mask: int = 0  ## bit i = FighterRig.PARTS[i] is cut off
var armor_mask: int = 0  ## bit i = the i-th armor piece of the loadout is still worn
var part_hp: PackedFloat32Array = PackedFloat32Array()  ## hp fraction per part, FighterRig order
var yaw: float = 0.0
var hand_target: Vector3 = Vector3.ZERO
var pos: PackedVector3Array = PackedVector3Array()
var rot: Array[Quaternion] = []
var vel: PackedVector3Array = PackedVector3Array()


func body_count() -> int:
	return pos.size()


func byte_size() -> int:
	return META_BYTES + BODY_BYTES * body_count()


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u8(clampi(state, 0, 255))
	buf.put_u8((1 if dead else 0) | (2 if gutted else 0))
	buf.put_u16(NetQuant.to_u16(blood, BLOOD_SCALE))
	buf.put_u16(NetQuant.to_u16(bleed_rate, BLOOD_SCALE))
	buf.put_u8(NetQuant.frac_u8(stamina))
	buf.put_u8(NetQuant.frac_u8(consciousness))
	buf.put_u16(severed_mask & 0xffff)
	buf.put_u8(armor_mask & 0xff)
	for i: int in range(PART_COUNT):
		buf.put_u8(NetQuant.frac_u8(part_hp[i] if i < part_hp.size() else 1.0))
	buf.put_u16(NetQuant.yaw_u16(yaw))
	NetQuant.put_vec_i16(buf, hand_target, NetQuant.POS_SCALE)
	var n: int = mini(body_count(), MAX_BODIES)
	buf.put_u8(n)
	for i: int in range(n):
		NetQuant.put_vec_i16(buf, pos[i], NetQuant.POS_SCALE)
		buf.put_u32(NetQuant.quat_u32(rot[i] if i < rot.size() else Quaternion.IDENTITY))
		NetQuant.put_vec_i16(buf, vel[i] if i < vel.size() else Vector3.ZERO, NetQuant.VEL_SCALE)


## Reads one fighter, or null when the buffer is short or the body count is out of range.
static func read(buf: StreamPeerBuffer) -> NetFighterSnap:
	if buf.get_available_bytes() < META_BYTES:
		return null
	var f := NetFighterSnap.new()
	f.state = buf.get_u8()
	var flags: int = buf.get_u8()
	f.dead = (flags & 1) != 0
	f.gutted = (flags & 2) != 0
	f.blood = float(buf.get_u16()) / BLOOD_SCALE
	f.bleed_rate = float(buf.get_u16()) / BLOOD_SCALE
	f.stamina = NetQuant.u8_frac(buf.get_u8())
	f.consciousness = NetQuant.u8_frac(buf.get_u8())
	f.severed_mask = buf.get_u16()
	f.armor_mask = buf.get_u8()
	f.part_hp.resize(PART_COUNT)
	for i: int in range(PART_COUNT):
		f.part_hp[i] = NetQuant.u8_frac(buf.get_u8())
	f.yaw = NetQuant.u16_yaw(buf.get_u16())
	f.hand_target = NetQuant.get_vec_i16(buf, NetQuant.POS_SCALE)
	var n: int = buf.get_u8()
	if n > MAX_BODIES or buf.get_available_bytes() < n * BODY_BYTES:
		return null
	f.pos.resize(n)
	f.vel.resize(n)
	for i: int in range(n):
		f.pos[i] = NetQuant.get_vec_i16(buf, NetQuant.POS_SCALE)
		f.rot.append(NetQuant.u32_quat(buf.get_u32()))
		f.vel[i] = NetQuant.get_vec_i16(buf, NetQuant.VEL_SCALE)
	return f


## Between a (t = 0) and b (t = 1): bodies, hand target, facing and the meters blend; discrete fields (state, masks,
## flags) come from a until t reaches 1. Bodies only blend when both have the same count (else a's are kept).
static func blend(a: NetFighterSnap, b: NetFighterSnap, t: float) -> NetFighterSnap:
	var take_b: bool = t >= 1.0
	var o := NetFighterSnap.new()
	var src: NetFighterSnap = b if take_b else a
	o.state = src.state
	o.dead = src.dead
	o.gutted = src.gutted
	o.severed_mask = src.severed_mask
	o.armor_mask = src.armor_mask
	o.blood = lerpf(a.blood, b.blood, t)
	o.bleed_rate = lerpf(a.bleed_rate, b.bleed_rate, t)
	o.stamina = lerpf(a.stamina, b.stamina, t)
	o.consciousness = lerpf(a.consciousness, b.consciousness, t)
	o.part_hp = src.part_hp.duplicate()
	o.yaw = lerp_angle(a.yaw, b.yaw, t)
	o.hand_target = a.hand_target.lerp(b.hand_target, t)
	if a.body_count() != b.body_count():
		var keep: NetFighterSnap = src
		o.pos = keep.pos.duplicate()
		o.rot = keep.rot.duplicate()
		o.vel = keep.vel.duplicate()
		return o
	var n: int = a.body_count()
	o.pos.resize(n)
	o.vel.resize(n)
	for i: int in range(n):
		o.pos[i] = a.pos[i].lerp(b.pos[i], t)
		o.rot.append(a.rot[i].slerp(b.rot[i], t))
		o.vel[i] = a.vel[i].lerp(b.vel[i], t)
	return o


## A copy moved on by `ticks` of each body's velocity (rotations held): the bridge when snapshots stop coming.
func extrapolated(ticks: float, tick_hz: float) -> NetFighterSnap:
	var o: NetFighterSnap = NetFighterSnap.blend(self, self, 0.0)
	var dt: float = ticks / tick_hz
	for i: int in range(o.pos.size()):
		o.pos[i] = o.pos[i] + o.vel[i] * dt
	o.hand_target = hand_target
	return o
