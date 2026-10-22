class_name NetLobby
extends RefCounted
## Lobby and match-control messages (all reliable, rare): HELLO, LOADOUT, LOBBY, START, OVER, LEAVE. Body is a
## Dictionary in var_to_bytes form after the type byte (no objects allowed when decoding). Pure: build, parse and
## check messages, and turn a START into the Match.setup() dictionary each side uses.

const MAX_NAME: int = 24
const MAX_BYTES: int = 4096
const CONTENT_HASH_CHARS: int = 16
const MAX_TIME_LIMIT_S: float = 3600.0  ## a START asking for a longer fight is capped here


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
			NetConfig.MSG_LOADOUT, NetConfig.MSG_NOTE].has(t):
		return {}
	var v: Variant = bytes_to_var(bytes.slice(1))
	if not (v is Dictionary) or (v as Dictionary).is_typed():
		return {}  # ours are plain dictionaries; a typed one (garbled or crafted) would refuse the "_type" key
	var d: Dictionary = (v as Dictionary).duplicate(true)
	d["_type"] = t
	return d


## Typed reads of a decoded message: the other side may be a modded build, so a field can hold any Variant.
## `v` when it is a Dictionary, else {}.
static func dict_of(v: Variant) -> Dictionary:
	return v as Dictionary if v is Dictionary else {}


## `v` as an int when it is a finite number, else `fallback`.
static func int_of(v: Variant, fallback: int) -> int:
	if v is int:
		return v as int
	if v is float and is_finite(v as float) and absf(v as float) < 9.0e18:
		return int(v as float)
	return fallback


## `v` when it is a finite number, else `fallback`.
static func float_of(v: Variant, fallback: float) -> float:
	if v is int:
		return float(v as int)
	if v is float and is_finite(v as float):
		return v as float
	return fallback


static func clean_name(n: String) -> String:
	var s: String = n.strip_edges().left(MAX_NAME)
	return s if s != "" else "Gladiator"


## Short hex digest of the game content both sides must share: the data JSON files (`json_texts`, any order; parsed and
## re-written with sorted keys so line endings and spacing do not matter) and the Tuning values. Different digest =
## different weapons, armor or numbers = the host's picture of the fight would not match what the client builds.
static func content_hash(json_texts: Array, tuning: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for t: Variant in json_texts:
		var parsed: Variant = JSON.parse_string(str(t))
		parts.append(JSON.stringify(parsed, "", true) if parsed != null else str(t).strip_edges())
	parts.sort()
	var keys: Array = tuning.keys()
	keys.sort()
	var tp: PackedStringArray = PackedStringArray()
	for k: Variant in keys:
		tp.append("%s=%.5f" % [str(k), float(tuning[k])])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("\n".join(parts) + "\n#tuning\n" + "\n".join(tp)).to_utf8_buffer())
	return ctx.finish().hex_encode().left(CONTENT_HASH_CHARS)


static func hello(player_name: String, loadout: Dictionary, content: String = "") -> PackedByteArray:
	return encode(NetConfig.MSG_HELLO, {"v": NetConfig.PROTOCOL_VERSION, "h": content, "name": clean_name(player_name),
		"loadout": LoadoutRules.sanitize(loadout)})


static func loadout_msg(loadout: Dictionary) -> PackedByteArray:
	return encode(NetConfig.MSG_LOADOUT, {"loadout": LoadoutRules.sanitize(loadout)})


## The host's answer to a HELLO: accepted, or refused with a reason.
static func lobby(host_name: String, host_loadout: Dictionary, accepted: bool, reason: String = "", content: String = "") -> PackedByteArray:
	return encode(NetConfig.MSG_LOBBY, {"v": NetConfig.PROTOCOL_VERSION, "h": content, "name": clean_name(host_name),
		"loadout": LoadoutRules.sanitize(host_loadout), "accepted": accepted, "reason": reason})


## "" when a HELLO is acceptable, else why not. `own_hash` is this build's content_hash ("" skips that check).
static func check_hello(d: Dictionary, own_hash: String = "") -> String:
	if int_of(d.get("_type"), 0) != NetConfig.MSG_HELLO:
		return "not a hello"
	return check_peer(d, own_hash, false)


## "" when the other side's HELLO or LOBBY (`d`) has our protocol version and content digest, else a "version mismatch"
## line naming the difference. `from_host`: d came from the host (so "yours" is the client).
static func check_peer(d: Dictionary, own_hash: String, from_host: bool) -> String:
	var theirs: int = int_of(d.get("v"), -1)
	if theirs != NetConfig.PROTOCOL_VERSION:
		return "version mismatch: different protocol (%s %d, %s %d)" % [
			"host" if from_host else "client", theirs, "client" if from_host else "host", NetConfig.PROTOCOL_VERSION]
	if own_hash != "" and str(d.get("h", "")) != own_hash:
		return "version mismatch: different game data (%s build %s, %s build %s)" % [
			"host" if from_host else "client", str(d.get("h", "")).left(8) if str(d.get("h", "")) != "" else "unknown",
			"client" if from_host else "host", own_hash.left(8)]
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
	var lo: Array = start_msg.get("loadouts") as Array if start_msg.get("loadouts") is Array else []
	var cfg: Dictionary = {"mode": "player_vs_cpu", "seed": int_of(start_msg.get("seed"), 1), "presentation": presentation,
		"loop": false,
		"loadouts": [LoadoutRules.sanitize(dict_of(lo[0] if lo.size() > 0 else {})), LoadoutRules.sanitize(dict_of(lo[1] if lo.size() > 1 else {}))]}
	var limit: float = float_of(start_msg.get("time_limit_s"), 0.0)
	if limit > 0.0:
		cfg["time_limit_s"] = minf(limit, MAX_TIME_LIMIT_S)
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
