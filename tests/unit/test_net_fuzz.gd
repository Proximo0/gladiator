extends TestCase
## Seeded fuzzing of every parser that reads bytes or values from the other machine (docs/net_security.md): input
## packets and the host's jitter buffer, snapshots, events, lobby messages (byte flips and wrong-typed fields),
## signed result reports and the session's packet loop. Thousands of mutated packets per case from fixed seeds. A
## case passes when no engine or script error is logged, every decoded number is finite and in range, and the
## host-side buffers stay small and fast.

const ROUNDS: int = 3000
const POP_BUDGET_USEC: int = 20000  ## one pop on a hostile stream; the unbounded skip loop took 80 ms per million ticks
const SessionTest: GDScript = preload("res://tests/unit/test_net_session_adopt.gd")


## Counts engine and script errors while installed (they still print as usual). With `allow_unmarshal`, the engine's
## own complaints about a garbled var_to_bytes body (marshalls.cpp, ustring.cpp, typed-container checks) are counted apart: bytes_to_var
## prints them and has no quiet mode, so NetSession rate-limits control messages instead (docs/net_security.md).
class NetFuzzErrorLog extends Logger:
	var count: int = 0
	var unmarshal: int = 0
	var allow_unmarshal: bool = false
	var first: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return  # e.g. JSON's "Exponent too high" on a crafted number: noise, not a failure
		if allow_unmarshal and error_type != ERROR_TYPE_SCRIPT and (file.ends_with("marshalls.cpp") or file.ends_with("ustring.cpp") or file.ends_with("container_type_validate.h")):
			unmarshal += 1
			return
		count += 1
		if first == "":
			first = "%s:%d %s: %s %s %s" % [file, line, function, code, rationale,
				script_backtraces[0].format() if not script_backtraces.is_empty() else ""]

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _log: NetFuzzErrorLog = null


func _watch(allow_unmarshal: bool = false) -> void:
	_log = NetFuzzErrorLog.new()
	_log.allow_unmarshal = allow_unmarshal
	OS.add_logger(_log)


func _done(what: String) -> void:
	OS.remove_logger(_log)
	assert_eq(_log.count, 0, "%s logged errors, first: %s" % [what, _log.first])


static func rng_for(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A mutated copy of `src`: 1-4 of byte overwrite, extreme byte, truncate, append, insert, repeat a slice; the type
## byte survives most of the time so the parser goes deep. One in ten is pure noise.
static func mutate(rng: RandomNumberGenerator, src: PackedByteArray) -> PackedByteArray:
	if rng.randf() < 0.1:
		var noise := PackedByteArray()
		noise.resize(rng.randi_range(0, 96))
		for i: int in noise.size():
			noise[i] = rng.randi_range(0, 255)
		return noise
	var b: PackedByteArray = src.duplicate()
	for _op: int in rng.randi_range(1, 4):
		var at: int = rng.randi_range(0, maxi(b.size() - 1, 0))
		match rng.randi_range(0, 5):
			0:
				if b.size() > 0:
					b[at] = rng.randi_range(0, 255)
			1:
				if b.size() > 0:
					b[at] = [0, 0x7f, 0x80, 0xff][rng.randi_range(0, 3)]
			2:
				b = b.slice(0, rng.randi_range(0, b.size()))
			3:
				for _i: int in rng.randi_range(1, 64):
					b.append(rng.randi_range(0, 255))
			4:
				var extra := PackedByteArray()
				for _i: int in rng.randi_range(1, 16):
					extra.append(rng.randi_range(0, 255))
				var head: PackedByteArray = b.slice(0, at)
				head.append_array(extra)
				head.append_array(b.slice(at))
				b = head
			5:
				if b.size() > 1:
					b.append_array(b.slice(at, mini(at + rng.randi_range(1, 32), b.size())))
	if b.size() > 0 and src.size() > 0 and rng.randf() < 0.8:
		b[0] = src[0]
	return b


## Any Variant a modded build could put in a lobby field.
static func wild_value(rng: RandomNumberGenerator) -> Variant:
	match rng.randi_range(0, 13):
		0:
			return null
		1:
			return rng.randi_range(-2147483648, 2147483647) * (1 << rng.randi_range(0, 31))
		2:
			return [NAN, INF, -INF, 1e300, -0.0, 3.5][rng.randi_range(0, 5)]
		3:
			return "x".repeat(rng.randi_range(0, 300))
		4:
			return [1, "two", {}]
		5:
			return {"weapon": "dai_katana", "armor": [1, 2], "offhand": 7}
		6:
			return {"weapon": {"a": 1}, "armor": {"head": 5, "torso": "helm_iron", 3: "x"}, "outfit": []}
		7:
			return Vector3(NAN, 1, 2)
		8:
			return PackedByteArray([1, 2, 3])
		9:
			return true
		10:
			return "laser_sword"
		11:
			return [{"weapon": "mace"}, "nope"]
		12:
			return StringName("halberd")
		_:
			return Color(1, 0, 0)


func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _check_snap(s: NetSnapshot) -> String:
	if s.fighters.size() > 2 or not is_finite(s.time_scale):
		return "header"
	for f: NetFighterSnap in s.fighters:
		if f.body_count() > NetFighterSnap.MAX_BODIES or f.prop_ids.size() > NetFighterSnap.MAX_PROPS:
			return "counts"
		for x: float in [f.blood, f.bleed_rate, f.stamina, f.consciousness, f.yaw]:
			if not is_finite(x):
				return "meter"
		if not _finite3(f.hand_target):
			return "hand"
		for i: int in f.body_count():
			var q: Quaternion = f.rot[i]
			if not (_finite3(f.pos[i]) and _finite3(f.vel[i]) and is_finite(q.x + q.y + q.z + q.w)):
				return "body %d" % i
	return ""


func _valid_snapshot(rng: RandomNumberGenerator) -> NetSnapshot:
	var s := NetSnapshot.new()
	s.tick = rng.randi_range(0, 100000)
	s.ack_input_tick = s.tick - 3
	s.time_scale = 1.0
	for side: int in 2:
		var f := NetFighterSnap.new()
		f.part_hp.resize(NetFighterSnap.PART_COUNT)
		for i: int in NetFighterSnap.PART_COUNT:
			f.part_hp[i] = rng.randf()
		for i: int in 14:
			f.pos.append(Vector3(rng.randf_range(-5, 5), rng.randf_range(0, 2), rng.randf_range(-5, 5)))
			f.rot.append(Quaternion(Vector3.UP, rng.randf_range(-PI, PI)))
			f.vel.append(Vector3(rng.randf_range(-20, 20), 0, 0))
		f.prop_ids = PackedByteArray([1 << 5])
		f.hand_target = Vector3(side, 1.2, 0.4)
		s.fighters.append(f)
	return s


func test_input_packets_fuzzed_never_error_and_stay_in_range() -> void:
	var rng: RandomNumberGenerator = rng_for(41)
	var packer := NetInputPacker.new()
	var buffer := NetInputBuffer.new()
	var worst_pop: int = 0
	var bad: int = 0
	_watch()
	for k: int in ROUNDS:
		var inp := FighterInput.from_array([rng.randi_range(-1000, 1000), rng.randi_range(-1000, 1000),
			rng.randi_range(-1000, 1000), rng.randi_range(-1000, 1000), rng.randi_range(0, 511)])
		packer.record(k, inp)
		var pkt: PackedByteArray = packer.pack() if rng.randf() < 0.3 else mutate(rng, packer.pack())
		for r: Array in NetInputPacker.unpack(pkt):
			var fi: FighterInput = r[1]
			if int(r[0]) < 0 or absi(fi.move_x) > 1000 or absi(fi.move_y) > 1000 or absi(fi.aim_x) > 1000 or absi(fi.aim_y) > 1000:
				bad += 1
			buffer.push(int(r[0]), fi)
		var t0: int = Time.get_ticks_usec()
		var out: FighterInput = buffer.pop()
		worst_pop = maxi(worst_pop, Time.get_ticks_usec() - t0)
		if absi(out.aim_x) > 1000 or absi(out.move_y) > 1000:
			bad += 1
	_done("input fuzz")
	assert_eq(bad, 0, "rows out of range")
	assert_true(worst_pop < POP_BUDGET_USEC, "slowest pop %d us" % worst_pop)
	assert_true((buffer.get("_inputs") as Dictionary).size() <= NetInputBuffer.MAX_HELD)
	assert_true((buffer.get("_played") as Dictionary).size() <= NetInputBuffer.PLAYED_MEMORY * 2 + 1)


## The host-freeze case found in review: a tick near 2^32 after a normal stream, ticks walking up by MAX_AHEAD per
## packet, and 16-row packets of scattered ticks, all against one buffer.
func test_input_buffer_survives_hostile_ticks() -> void:
	var b := NetInputBuffer.new()
	var worst: int = 0
	for t: int in 4:
		b.push(t, FighterInput.new())
	b.pop()
	b.push(4294967295, FighterInput.new())
	var t0: int = Time.get_ticks_usec()
	b.pop()
	worst = Time.get_ticks_usec() - t0
	var rng: RandomNumberGenerator = rng_for(42)
	var walk: int = 10
	for k: int in 2000:
		walk += NetInputBuffer.MAX_AHEAD
		b.push(walk, FighterInput.new())
		for _j: int in 16:
			b.push(walk - rng.randi_range(0, 5000), FighterInput.new())
		t0 = Time.get_ticks_usec()
		b.pop()
		worst = maxi(worst, Time.get_ticks_usec() - t0)
	assert_true(worst < POP_BUDGET_USEC, "slowest pop %d us" % worst)
	assert_true((b.get("_inputs") as Dictionary).size() <= NetInputBuffer.MAX_HELD, "held %d" % (b.get("_inputs") as Dictionary).size())
	assert_true((b.get("_played") as Dictionary).size() <= NetInputBuffer.PLAYED_MEMORY * 2 + 1, "played memory %d" % (b.get("_played") as Dictionary).size())
	assert_true(b.rejected > 0, "far-future ticks are refused")


func test_unpack_refuses_oversized_and_negative() -> void:
	var p := NetInputPacker.new(4)
	for t: int in 8:
		p.record(t, FighterInput.new())
	var ok: PackedByteArray = p.pack()
	assert_eq(NetInputPacker.unpack(ok).size(), 4)
	var long: PackedByteArray = ok.duplicate()
	long.append(0)
	assert_eq(NetInputPacker.unpack(long), [], "trailing bytes")
	var many := PackedByteArray([NetConfig.MSG_INPUT, 255, 0, 0, 0, 255])
	many.resize(NetInputPacker.HEADER_BYTES + 255 * NetInputPacker.ENTRY_BYTES)
	assert_eq(NetInputPacker.unpack(many), [], "255 rows")
	var neg := PackedByteArray([NetConfig.MSG_INPUT, 1, 0, 0, 0, 4])
	neg.resize(NetInputPacker.HEADER_BYTES + 4 * NetInputPacker.ENTRY_BYTES)
	assert_eq(NetInputPacker.unpack(neg), [], "rows below tick 0")


func test_snapshots_fuzzed_decode_finite_or_null() -> void:
	var rng: RandomNumberGenerator = rng_for(43)
	var good: NetSnapshot = _valid_snapshot(rng)
	var bytes: PackedByteArray = good.encode()
	var decoded: int = 0
	var bad: String = ""
	_watch()
	for _k: int in ROUNDS:
		var s: NetSnapshot = NetSnapshot.decode(mutate(rng, bytes))
		if s == null:
			continue
		decoded += 1
		var why: String = _check_snap(s)
		if why == "":
			why = _check_snap(NetSnapshot.blend(good, s, rng.randf()))
		if why == "":
			why = _check_snap(s.extrapolated(rng.randf_range(0.0, 6.0), good))
		if why != "" and bad == "":
			bad = why
	_done("snapshot fuzz")
	assert_eq(bad, "", "non-finite or out of range")
	assert_true(decoded > 100, "some mutants still decode (%d), so the deep paths ran" % decoded)


func test_events_fuzzed_decode_finite() -> void:
	var rng: RandomNumberGenerator = rng_for(44)
	var hit: Dictionary = {"attacker": 0, "target": 1, "part": "head", "weapon_id": "gladius", "contact": "edge",
		"point": Vector3(1.2, 1.7, -0.5), "normal": Vector3(0, 0, 1), "rel_vel": Vector3(8.5, -1.25, 0.0), "cut": 12.5,
		"blunt": 3.25, "total": 15.75, "finisher": "behead", "armor_ids": ["galea", "manica_r"], "sever": true,
		"knockback": Vector3(1, 0, 0), "energy": 140.0}
	var gore: Dictionary = {"kind": "behead", "part": "head", "amount": 12.5, "point": Vector3(1, 2, 3), "normal": Vector3.UP}
	var bytes: PackedByteArray = NetEvents.encode([[77, 1, "hit", hit], [78, 0, "gore", gore], [79, 1, "hit", hit]])
	var bad: String = ""
	var decoded: int = 0
	_watch()
	for _k: int in ROUNDS:
		for r: Array in NetEvents.decode(mutate(rng, bytes)):
			decoded += 1
			if int(r[0]) < 0 or not NetEvents.KINDS.has(str(r[2])):
				bad = "record header"
			var ev: Dictionary = r[3]
			for key: Variant in ev:
				var v: Variant = ev[key]
				if (v is float and not is_finite(v as float)) or (v is Vector3 and not _finite3(v as Vector3)):
					bad = "%s not finite" % str(key)
				if (key == "attacker" or key == "target") and absi(int(v)) > 1:
					bad = "side %s" % str(v)
	_done("events fuzz")
	assert_eq(bad, "")
	assert_true(decoded > 100, "deep paths ran (%d records)" % decoded)


## A hostile host's half-precision NaN in a hit reads as 0, not NaN.
func test_event_nan_half_reads_zero() -> void:
	var bytes: PackedByteArray = NetEvents.encode([[5, 1, "hit", {"total": 2.0}]])
	bytes[bytes.size() - 2] = 0x01
	bytes[bytes.size() - 1] = 0x7e  # half 0x7e01 = NaN
	var back: Array = NetEvents.decode(bytes)
	assert_eq(back.size(), 1)
	assert_eq(float((back[0][3] as Dictionary)["total"]), 0.0)


## Byte mutations of every lobby message, and structured ones: valid var_to_bytes bodies whose fields hold any type.
## Each goes through what the host and the client do with it: the checks, the loadout rules, the match config and a
## live NetSession's handler in both roles.
func test_lobby_messages_fuzzed_never_error() -> void:
	var rng: RandomNumberGenerator = rng_for(45)
	var lo: Dictionary = {"weapon": "mace", "offhand": "shield_round", "armor": {"head": "helm_iron"}, "outfit": "samurai"}
	var bases: Array = [NetLobby.hello("Cato", lo, "abc"), NetLobby.lobby("Verus", lo, true, "", "abc"),
		NetLobby.start(7, [lo, lo], 90.0, ["A", "B"]), NetLobby.loadout_msg(lo),
		NetLobby.over({"winner": 1, "reason": "ko", "ticks": 900, "seed": 7}), NetLobby.leave("left")]
	var host := NetSession.new()
	var client := NetSession.new()
	host.role = NetSession.ROLE_HOST
	client.role = NetSession.ROLE_CLIENT
	var bad: String = ""
	_watch(true)
	for k: int in ROUNDS:
		var src: PackedByteArray = bases[k % bases.size()]
		var pkt: PackedByteArray
		if rng.randf() < 0.5:
			pkt = mutate(rng, src)
		else:
			var body: Dictionary = NetLobby.decode(src)
			body.erase("_type")
			var keys: Array = body.keys()
			keys.append_array(["loadouts", "loadout", "v", "h", "accepted", "seed", "time_limit_s", "winner", "ticks"])
			for _i: int in rng.randi_range(1, 3):
				body[keys[rng.randi_range(0, keys.size() - 1)]] = wild_value(rng)
			pkt = NetLobby.encode(int(src[0]), body)
		var d: Dictionary = NetLobby.decode(pkt)
		if d.is_empty():
			continue
		NetLobby.check_hello(d, "abc")
		NetLobby.check_peer(d, "abc", true)
		var cfg: Dictionary = NetLobby.match_config(d, false)
		if not (cfg["seed"] is int) or (cfg.has("time_limit_s") and not (is_finite(float(cfg["time_limit_s"])) and float(cfg["time_limit_s"]) <= NetLobby.MAX_TIME_LIMIT_S)):
			bad = "match_config %s" % str(cfg)
		for one: Variant in cfg["loadouts"]:
			if not (one is Dictionary) or not ((one as Dictionary)["armor"] is Dictionary):
				bad = "loadout %s" % str(one)
		LoadoutRules.sanitize(NetLobby.dict_of(d.get("loadout")))
		host.remote_joined = rng.randf() < 0.5
		host._on_control(d.duplicate(true))
		client._on_control(d.duplicate(true))
		if k % 200 == 0:
			client.free()
			client = NetSession.new()
			client.role = NetSession.ROLE_CLIENT
	host.free()
	client.free()
	_done("lobby fuzz")
	assert_eq(bad, "")


func test_hello_once_per_connection() -> void:
	var host := NetSession.new()
	host.role = NetSession.ROLE_HOST
	host._on_control(NetLobby.decode(NetLobby.hello("Cato", {"weapon": "mace"}, host.content_hash())))
	assert_true(host.remote_joined)
	host._on_control(NetLobby.decode(NetLobby.hello("Imposter", {"weapon": "halberd"}, host.content_hash())))
	assert_eq(host.remote_name, "Cato", "a second hello does not rename the player")
	assert_eq(str(host.remote_loadout["weapon"]), "mace")
	host.free()


## Signed result reports read back from a lobby attribute (any string the other member wrote), then reconciled.
func test_result_reports_fuzzed_never_error() -> void:
	var rng: RandomNumberGenerator = rng_for(46)
	var rep: Dictionary = Rating.make_report("m1", "B", Rating.KIND_RESULT, "B", "ko", 3000)
	var raw: String = ServiceEos.encode_report(rep, Rating.sign_report("key", rep))
	var accepted: int = 0
	_watch()
	for k: int in ROUNDS:
		var text: String
		if k % 3 == 0:
			var body: Dictionary = {"r": rep.duplicate(), "s": Rating.sign_report("key", rep)}
			for _i: int in rng.randi_range(1, 2):
				(body["r"] as Dictionary)[["ticks", "kind", "winner", "player", "match_id"][rng.randi_range(0, 4)]] = wild_value(rng)
			text = JSON.stringify(body) if rng.randf() < 0.9 else str(body)
		else:
			text = mutate(rng, raw.to_utf8_buffer()).get_string_from_ascii()
		var back: Dictionary = ServiceEos.decode_report(text, "key" if k % 5 != 0 else "", "B", "m1")
		if not back.is_empty():
			accepted += 1
		var v: Dictionary = Rating.reconcile("A", Rating.make_report("m1", "A", Rating.KIND_RESULT, "A", "ko", 3000), "B", back, true)
		if not (v["rated"] is bool):
			accepted = -1000000
	_done("report fuzz")
	assert_true(accepted >= 0)


## A peer that floods: thousands of packets in one tick, oversized ones, every type. The session handles at most
## MAX_PACKETS_PER_TICK, logs nothing and stays open.
func test_session_flood_is_bounded() -> void:
	var pair: Array = SessionTest.make_pair()
	var hp: MultiplayerPeerExtension = pair[0]
	var cp: MultiplayerPeerExtension = pair[1]
	var host := NetSession.new()
	var client := NetSession.new()
	host.adopt_peer(hp, NetSession.ROLE_HOST)
	client.adopt_peer(cp, NetSession.ROLE_CLIENT)
	SessionTest.link_up(hp, cp)
	SessionTest.step([host, client], 10)
	assert_true(host.remote_joined, "lobby up")
	var rng: RandomNumberGenerator = rng_for(47)
	var p := NetInputPacker.new()
	p.record(0, FighterInput.new())
	var seeds: Array = [p.pack(), NetLobby.hello("X", {}, ""), NetLobby.loadout_msg({"weapon": "laser_sword"}),
		_valid_snapshot(rng).encode(), NetEvents.encode([[1, 0, "hit", {"total": 1.0}]])]
	_watch(true)
	for _k: int in 5000:
		var pkt: PackedByteArray = mutate(rng, seeds[rng.randi_range(0, seeds.size() - 1)])
		(hp.get("inbox") as Array).append([777, pkt])
	var huge := PackedByteArray()
	huge.resize(64 * 1024)
	(hp.get("inbox") as Array).append([777, huge])
	host._physics_process(1.0 / 60.0)
	_done("session flood")
	assert_true(host.is_open(), "still open")
	assert_true(host.dropped_packets >= 5001 - NetSession.MAX_PACKETS_PER_TICK, "dropped %d" % host.dropped_packets)
	host.free()
	client.free()
	hp.set("other", null)  # the fake pair points at each other: break the cycle
	cp.set("other", null)
