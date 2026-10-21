class_name NetLobby
extends RefCounted
## Lobby and match-control messages (all reliable, rare): HELLO, LOADOUT, LOBBY, START, OVER, LEAVE. Body is a
## Dictionary in var_to_bytes form after the type byte (no objects allowed when decoding). Pure: build, parse and
## check messages, and turn a START into the Match.setup() dictionary each side uses.

const MAX_NAME: int = 24
const MAX_BYTES: int = 4096


static func encode(msg_type: int, body: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([msg_type])
	out.append_array(var_to_bytes(body))
	return out


## {} when the packet is not a lobby message or does not parse.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2 or bytes.size() > MAX_BYTES:
		return {}
	var t: int = int(bytes[0])
	if not [NetConfig.MSG_HELLO, NetConfig.MSG_LOBBY, NetConfig.MSG_START, NetConfig.MSG_OVER, NetConfig.MSG_LEAVE,
			NetConfig.MSG_LOADOUT].has(t):
		return {}
	var v: Variant = bytes_to_var(bytes.slice(1))
	if not (v is Dictionary):
		return {}
	var d: Dictionary = (v as Dictionary).duplicate(true)
	d["_type"] = t
	return d


static func clean_name(n: String) -> String:
	var s: String = n.strip_edges().left(MAX_NAME)
	return s if s != "" else "Gladiator"


static func hello(player_name: String, loadout: Dictionary) -> PackedByteArray:
	return encode(NetConfig.MSG_HELLO, {"v": NetConfig.PROTOCOL_VERSION, "name": clean_name(player_name),
		"loadout": LoadoutRules.sanitize(loadout)})


static func loadout_msg(loadout: Dictionary) -> PackedByteArray:
	return encode(NetConfig.MSG_LOADOUT, {"loadout": LoadoutRules.sanitize(loadout)})


## The host's answer to a HELLO: accepted, or refused with a reason.
static func lobby(host_name: String, host_loadout: Dictionary, accepted: bool, reason: String = "") -> PackedByteArray:
	return encode(NetConfig.MSG_LOBBY, {"v": NetConfig.PROTOCOL_VERSION, "name": clean_name(host_name),
		"loadout": LoadoutRules.sanitize(host_loadout), "accepted": accepted, "reason": reason})


## "" when a HELLO is acceptable, else why not.
static func check_hello(d: Dictionary) -> String:
	if int(d.get("_type", 0)) != NetConfig.MSG_HELLO:
		return "not a hello"
	if int(d.get("v", -1)) != NetConfig.PROTOCOL_VERSION:
		return "version mismatch (host %d, client %d)" % [NetConfig.PROTOCOL_VERSION, int(d.get("v", -1))]
	return ""


## START: the seed and both loadouts (host is side 0, client side 1), the time limit and the names.
static func start(seed_value: int, loadouts: Array, time_limit_s: float, names: Array) -> PackedByteArray:
	return encode(NetConfig.MSG_START, {"seed": seed_value,
		"loadouts": [LoadoutRules.sanitize(loadouts[0]), LoadoutRules.sanitize(loadouts[1])],
		"time_limit_s": time_limit_s, "names": [clean_name(str(names[0])), clean_name(str(names[1]))]})


## The Match.setup() dictionary for a START, on either side. Mode player_vs_cpu gives the host its InputReader on
## side 0 and a brain slot on side 1 (NetSession swaps in a NetRemoteBrain); the client uses the same build and
## then switches the simulation off.
static func match_config(start_msg: Dictionary, presentation: bool) -> Dictionary:
	var lo: Array = start_msg.get("loadouts", [])
	var cfg: Dictionary = {"mode": "player_vs_cpu", "seed": int(start_msg.get("seed", 1)), "presentation": presentation,
		"loop": false,
		"loadouts": [LoadoutRules.sanitize(lo[0] if lo.size() > 0 else {}), LoadoutRules.sanitize(lo[1] if lo.size() > 1 else {})]}
	if start_msg.has("time_limit_s") and float(start_msg["time_limit_s"]) > 0.0:
		cfg["time_limit_s"] = float(start_msg["time_limit_s"])
	return cfg


## Match result without the bulky stats (the client only shows who won and how).
static func over(result: Dictionary) -> PackedByteArray:
	return encode(NetConfig.MSG_OVER, {"winner": int(result.get("winner", -1)), "reason": str(result.get("reason", "")),
		"ticks": int(result.get("ticks", 0)), "seed": int(result.get("seed", 0))})


static func leave(reason: String) -> PackedByteArray:
	return encode(NetConfig.MSG_LEAVE, {"reason": reason})


## "host:port" or "host" (default port) to [host, port]; [] when it does not parse.
static func parse_address(text: String) -> Array:
	var s: String = text.strip_edges()
	if s == "":
		return []
	var host: String = s
	var port: int = NetConfig.DEFAULT_PORT
	if s.count(":") == 1:
		var parts: PackedStringArray = s.split(":")
		host = parts[0]
		if not parts[1].is_valid_int():
			return []
		port = parts[1].to_int()
	elif s.begins_with("["):  # [ipv6]:port
		var close: int = s.find("]")
		if close < 0:
			return []
		host = s.substr(1, close - 1)
		var rest: String = s.substr(close + 1)
		if rest.begins_with(":"):
			if not rest.substr(1).is_valid_int():
				return []
			port = rest.substr(1).to_int()
	if host == "" or port < 1 or port > 65535:
		return []
	return [host, port]
