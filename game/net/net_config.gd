class_name NetConfig
extends RefCounted
## Online 1v1 constants: protocol version, port, rates, buffer depths, the byte budget and the message type ids.
## Not gameplay numbers (those stay in Tuning): these set how the wire behaves. See docs/online_brief.md.

const PROTOCOL_VERSION: int = 3  ## 3: SHOVE, KICK and CLINCH buttons (bits 512..2048 of the u16 buttons)
const DEFAULT_PORT: int = 7777
const TICK_HZ: int = 60
const SNAP_EVERY_TICKS: int = 2  ## host sends a snapshot every 2 physics ticks: 30 Hz at 60 Hz physics
const INPUT_REDUNDANCY: int = 4  ## each input packet repeats the last 4 ticks, so 3 lost packets in a row are harmless
const INPUT_BUFFER_TARGET: int = 1  ## host plays the client's inputs this many ticks behind the newest received (grows with jitter, see NetInputBuffer)
const INPUT_BUFFER_MAX: int = 10  ## above this depth the host skips ahead to the target depth
const INPUT_STALE_TICKS: int = 12  ## ticks without a new client input after which the host stops repeating the last one (200 ms)
const INTERP_MIN_DELAY: float = 2.25  ## client interpolation delay floor, ticks (one snapshot interval + a quarter tick)
const INTERP_MAX_DELAY: float = 24.0  ## ceiling, ticks (400 ms)
const INTERP_RESYNC: float = 30.0  ## render clock this far (ticks) from its target jumps instead of easing
const MAX_EXTRAPOLATE: float = 6.0  ## ticks of velocity extrapolation when snapshots stop, then hold
const EXTRAP_TAU_S: float = 0.25  ## extrapolated velocity (and spin) fades with this time constant, seconds
const BUDGET_BYTES_PER_S: int = 30000  ## per direction, packet overhead included
const PACKET_OVERHEAD: int = 42  ## IPv4 20 + UDP 8 + ENet protocol header and command (~14), per packet
const CONNECT_TIMEOUT_TICKS: int = 600  ## 10 s to reach the host
const DISCONNECT_TICKS: int = 300  ## 5 s without a packet from the other side ends the session
const THROTTLE_INTERVAL_MS: int = 5000  ## ENet packet throttle: measured over this long (ENet default)
const THROTTLE_ACCELERATION: int = 2  ## ... and how fast it recovers (ENet default); deceleration is set to 0

const MSG_HELLO: int = 1  ## client -> host, reliable: version, name, loadout
const MSG_LOBBY: int = 2  ## host -> client, reliable: host name, host loadout, accepted / reason
const MSG_START: int = 3  ## host -> client, reliable: seed, both loadouts, time limit
const MSG_INPUT: int = 4  ## client -> host, unreliable ordered: the last INPUT_REDUNDANCY FighterInputs
const MSG_SNAP: int = 5  ## host -> client, unreliable ordered: the world state of one tick
const MSG_EVENTS: int = 6  ## host -> client, reliable: hit and gore events with their ticks
const MSG_OVER: int = 7  ## host -> client, reliable: the match result
const MSG_LEAVE: int = 8  ## either way, reliable: going back to the menu
const MSG_LOADOUT: int = 9  ## client -> host, reliable: the client changed its pick in the lobby

const STATES: PackedStringArray = ["standing", "stumbling", "down", "getting_up", "ko", "dead"]


static func snapshot_hz() -> float:
	return float(TICK_HZ) / float(SNAP_EVERY_TICKS)


## Bytes per second for `payload` bytes sent `per_s` times a second, packet overhead included.
static func rate(payload: int, per_s: float) -> float:
	return float(payload + PACKET_OVERHEAD) * per_s


## Message type of a packet, or 0 when empty.
static func msg_type(bytes: PackedByteArray) -> int:
	return int(bytes[0]) if bytes.size() > 0 else 0
