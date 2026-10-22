class_name NetSession
extends Node
## One online 1v1 connection over ENet (direct IP and port, default 7777). The host listens for one client; the
## client joins by address. Owns the peer, polls it every physics tick (before Match runs), counts bytes both ways,
## runs the lobby (HELLO / LOBBY / LOADOUT / START) and routes match traffic to the NetHostDriver or NetClientDriver
## hung on the current Match. The host is side 0 and simulates both fighters; the client is side 1 and only
## renders. See docs/online_brief.md.
## Relay play (EOS P2P and other backends): adopt_peer() takes a ready MultiplayerPeer instead of host()/join(). Only
## the packet API is used then; the ENet extras (flush, round trip time, throttle) are skipped, and unreliable traffic
## goes out TRANSFER_MODE_UNRELIABLE because relay peers have no "unreliable ordered" (EOSG turns it into reliable,
## which would queue every snapshot behind a lost one). Inputs and snapshots carry ticks and tolerate reordering.
## Dev flags: --net-lag=<ms one way> --net-jitter=<ms> --net-loss=<0..1> fake a bad link on what this side sends.

signal status_changed(text: String)
signal lobby_changed  ## the other side joined, left or changed its loadout
signal match_requested(start: Dictionary)  ## build the match now (both sides; host: after start_match())
signal match_result(result: Dictionary)  ## client: the host's result arrived
signal closed(reason: String)  ## the connection is gone (left, refused, timed out, failed)
signal note_received(note: Dictionary)  ## the other side sent a NOTE (ready, rematch: OnlineScreen's handshakes)

const ROLE_HOST: String = "host"
const ROLE_CLIENT: String = "client"
const HOST_PEER: int = 1
const DATA_DIR: String = "res://data/"
const RELAY_MAX_PACKET: int = 1164  ## EOS P2P: 1170 bytes per packet minus EOSG's 6-byte header
const RELAY_CLOSE_DELAY_S: float = 0.3  ## a relay peer sends on the SDK tick: give a LEAVE time to go out before closing
## Flood guard (docs/net_security.md): per physics tick at most this many packets from the other side are handled
## (legit traffic is 1-3; a 1 s hitch delivers about 30-60), the rest are drained and dropped.
const MAX_PACKETS_PER_TICK: int = 64
const MAX_PACKET_BYTES: int = 4096  ## nothing legit is larger (a worst-case snapshot is ~1.1 KB, lobby messages cap at 4 KB)
## Lobby and control messages are rare (a handful per match); past this many per second they are dropped unread, which
## also caps the engine errors bytes_to_var prints for a garbled body.
const MAX_CONTROL_PER_S: int = 20

var role: String = ""
var local_name: String = "Gladiator"
var local_loadout: Dictionary = {}
var remote_name: String = ""
var remote_loadout: Dictionary = {}
var remote_joined: bool = false  ## host: a client said hello; client: the host accepted us
var local_tick: int = 0
var bw_out: NetBandwidth = NetBandwidth.new()
var bw_in: NetBandwidth = NetBandwidth.new()
var max_sent: Dictionary = {}  ## message type -> largest payload sent (bytes), for the soak and the relay budget
var link: NetLinkSim = NetLinkSim.new()
var host_driver: NetHostDriver = null
var client_driver: NetClientDriver = null
var input_blocked: bool = false:  ## the Esc menu is open over the match: this side sends and plays neutral input (MenuFlow sets it)
	set(v):
		input_blocked = v
		if host_driver != null and is_instance_valid(host_driver):
			host_driver.gate_own_reader()
var last_start: Dictionary = {}
var close_reason: String = ""
var dropped_packets: int = 0  ## from the other side, refused by the flood guard (too many in one tick, or oversized)

var _peer: MultiplayerPeer = null
var _relay_oversize_warned: bool = false
var _remote_id: int = 0
var _last_heard: int = 0
var _connect_started: int = 0
var _closed: bool = false
var _content_hash: String = ""
var _control_window: int = -1000  ## local tick the current one-second control-message window began
var _control_count: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -20


## Fakes a bad link on everything this side sends (tests and --net-lag).
func set_link(latency_ticks: int, jitter_ticks: int, loss: float, seed_value: int) -> void:
	link = NetLinkSim.new(latency_ticks, jitter_ticks, loss, seed_value)


func _ready() -> void:
	if Flags.args.has("net-lag") or Flags.args.has("net-loss") or Flags.args.has("net-jitter"):
		var ms_per_tick: float = 1000.0 / float(NetConfig.TICK_HZ)
		set_link(roundi(float(Flags.get_arg("net-lag", "0")) / ms_per_tick),
			roundi(float(Flags.get_arg("net-jitter", "0")) / ms_per_tick), float(Flags.get_arg("net-loss", "0")),
			Flags.seed_value() + (0 if role == ROLE_HOST else 1))


func host(port: int = NetConfig.DEFAULT_PORT, bind_ip: String = "*") -> Error:
	_reset()
	var enet := ENetMultiplayerPeer.new()
	enet.set_bind_ip(bind_ip)
	var err: Error = enet.create_server(port, 1)
	if err != OK:
		_fail("Could not listen on port %d (%s)" % [port, error_string(err)])
		return err
	_peer = enet
	role = ROLE_HOST
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	status_changed.emit("Waiting on port %d" % port)
	return OK


func join(address: String, port: int = NetConfig.DEFAULT_PORT) -> Error:
	_reset()
	var enet := ENetMultiplayerPeer.new()
	var err: Error = enet.create_client(address, port)
	if err != OK:
		_fail("Could not reach %s:%d (%s)" % [address, port, error_string(err)])
		return err
	_peer = enet
	role = ROLE_CLIENT
	_remote_id = HOST_PEER
	_connect_started = local_tick
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	status_changed.emit("Connecting to %s:%d" % [address, port])
	return OK


## Run the session over a peer someone else connected (a relay backend: EOS P2P, Steam). `as_role` is "host" or
## "client". The host waits for peer_connected; the client talks to the host's peer id (1, as on any Godot-style
## peer). The service must not poll the peer before handing it over, or peer_connected fires before we listen;
## a client peer that is already connected is greeted at once.
func adopt_peer(p: MultiplayerPeer, as_role: String) -> Error:
	_reset()
	if p == null or (as_role != ROLE_HOST and as_role != ROLE_CLIENT):
		_fail("No relay connection to use")
		return ERR_INVALID_PARAMETER
	_peer = p
	role = as_role
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	if role == ROLE_CLIENT:
		_remote_id = HOST_PEER
		_connect_started = local_tick
		status_changed.emit("Connecting through the relay")
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_on_peer_connected(HOST_PEER)
	else:
		status_changed.emit("Waiting for the other player (relay)")
	return OK


## True when the session runs over a non-ENet peer (relay backends).
func is_relay() -> bool:
	return _peer != null and not (_peer is ENetMultiplayerPeer)


func is_open() -> bool:
	return _peer != null and not _closed


func connected() -> bool:
	return is_open() and _remote_id != 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Round trip time to the other side in ms, from ENet (0 until known, and always 0 on a relay peer).
func rtt_ms() -> int:
	if not connected() or not (_peer is ENetMultiplayerPeer):
		return 0
	var p: ENetPacketPeer = (_peer as ENetMultiplayerPeer).get_peer(_remote_id)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p != null else 0


## Digest of the data JSON files and the Tuning values (see NetLobby.content_hash), computed once per session.
func content_hash() -> String:
	if _content_hash == "":
		var texts: Array = []
		var dir := DirAccess.open(DATA_DIR)
		if dir != null:
			var files: PackedStringArray = dir.get_files()
			files.sort()
			for fname: String in files:
				if fname.get_extension() == "json":
					texts.append(FileAccess.get_file_as_string(DATA_DIR + fname))
		_content_hash = NetLobby.content_hash(texts, Tuning.shared().to_dict())
	return _content_hash


func set_local(player_name: String, loadout: Dictionary) -> void:
	local_name = NetLobby.clean_name(player_name)
	local_loadout = LoadoutRules.sanitize(loadout)
	if not connected() or not remote_joined:
		return
	if role == ROLE_CLIENT:
		send(NetLobby.loadout_msg(local_loadout), true)
	else:
		send(NetLobby.lobby(local_name, local_loadout, true, "", content_hash()), true)


## Host: send START and build the match here too. `time_limit_s` <= 0 keeps the default.
func start_match(seed_value: int, time_limit_s: float = 0.0) -> bool:
	if role != ROLE_HOST or not remote_joined:
		return false
	var bytes: PackedByteArray = NetLobby.start(seed_value, [local_loadout, remote_loadout], time_limit_s, [local_name, remote_name])
	send(bytes, true)
	last_start = NetLobby.decode(bytes)
	match_requested.emit(last_start)
	return true


## A small reliable note to the other side ({t: "ready"} ...); dropped when nobody is connected.
func send_note(note: Dictionary) -> void:
	if remote_joined:
		send(NetLobby.encode(NetConfig.MSG_NOTE, note), true)


## Hang the host or client driver on a freshly set-up Match (call right after Match.setup()).
func attach_match(m: Match) -> void:
	detach_match()
	if role == ROLE_HOST:
		host_driver = NetHostDriver.new()
		host_driver.name = "NetHost"
		host_driver.session = self
		m.add_child(host_driver)
		host_driver.attach(m)
	else:
		client_driver = NetClientDriver.new()
		client_driver.name = "NetClient"
		client_driver.session = self
		m.add_child(client_driver)
		client_driver.attach(m)


func detach_match() -> void:
	input_blocked = false
	host_driver = null
	client_driver = null


func leave(reason: String = "left") -> void:
	if connected():
		send(NetLobby.leave(reason), true)
		_peer.poll()
	_close(reason)


func _exit_tree() -> void:
	if _peer != null:
		_peer.close()
		_peer = null


## Sends to the other side through the fake link (when active) and counts the bytes.
func send(bytes: PackedByteArray, reliable: bool) -> void:
	if not is_open() or _remote_id == 0:
		return
	bw_out.add(local_tick, bytes.size())
	var mt: int = NetConfig.msg_type(bytes)
	max_sent[mt] = maxi(int(max_sent.get(mt, 0)), bytes.size())
	if link.active():
		link.send(local_tick, _tag(bytes, reliable), reliable)
	else:
		_put(bytes, reliable)


func _tag(bytes: PackedByteArray, reliable: bool) -> PackedByteArray:
	var out := PackedByteArray([1 if reliable else 0])
	out.append_array(bytes)
	return out


func _put(bytes: PackedByteArray, reliable: bool) -> void:
	_peer.set_target_peer(_remote_id)
	_peer.transfer_channel = 0
	_peer.transfer_mode = transfer_mode_for(_peer is ENetMultiplayerPeer, reliable)
	if not (_peer is ENetMultiplayerPeer) and bytes.size() > RELAY_MAX_PACKET and not _relay_oversize_warned:
		_relay_oversize_warned = true
		push_warning("NetSession: %d-byte packet is over the relay limit (%d); the relay drops it" % [bytes.size(), RELAY_MAX_PACKET])
	_peer.put_packet(bytes)
	# Send now instead of at the next poll, a tick later: saves up to a tick each way.
	if _peer is ENetMultiplayerPeer:
		var h: ENetConnection = (_peer as ENetMultiplayerPeer).host
		if h != null:
			h.flush()


## ENet keeps unreliable packets in order (late ones are dropped); relay peers only have plain unreliable.
static func transfer_mode_for(enet: bool, reliable: bool) -> MultiplayerPeer.TransferMode:
	if reliable:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED if enet else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE


func _physics_process(_delta: float) -> void:
	local_tick += 1
	if _peer == null or _closed:
		return
	for tagged: PackedByteArray in link.receive(local_tick):
		if connected():
			_put(tagged.slice(1), tagged[0] == 1)
	_peer.poll()
	if _peer == null:
		return  # a handler closed us during the poll
	var handled: int = 0
	while _peer != null and _peer.get_available_packet_count() > 0:
		var from: int = _peer.get_packet_peer()
		var bytes: PackedByteArray = _peer.get_packet()
		if from != _remote_id:
			continue
		_last_heard = local_tick
		bw_in.add(local_tick, bytes.size())
		if handled >= MAX_PACKETS_PER_TICK or bytes.size() > MAX_PACKET_BYTES:
			dropped_packets += 1
			continue
		handled += 1
		_route(bytes)
	if _peer == null or _closed:
		return
	if role == ROLE_CLIENT and _remote_id != 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING \
			and local_tick - _connect_started > NetConfig.CONNECT_TIMEOUT_TICKS:
		_fail("No answer from the host")
	elif remote_joined and local_tick - _last_heard > NetConfig.DISCONNECT_TICKS and (host_driver != null or client_driver != null):
		_fail("Connection lost")


func _route(bytes: PackedByteArray) -> void:
	var t: int = NetConfig.msg_type(bytes)
	match t:
		NetConfig.MSG_INPUT:
			if host_driver != null and is_instance_valid(host_driver):
				host_driver.on_input(bytes)
		NetConfig.MSG_SNAP:
			if client_driver != null and is_instance_valid(client_driver):
				client_driver.on_snapshot(bytes)
		NetConfig.MSG_EVENTS:
			if client_driver != null and is_instance_valid(client_driver):
				client_driver.on_events(bytes)
		_:
			if local_tick - _control_window >= NetConfig.TICK_HZ:
				_control_window = local_tick
				_control_count = 0
			_control_count += 1
			if _control_count > MAX_CONTROL_PER_S:
				dropped_packets += 1
				return
			_on_control(NetLobby.decode(bytes))


func _on_control(d: Dictionary) -> void:
	if d.is_empty():
		return
	match int(d["_type"]):
		NetConfig.MSG_HELLO:
			if role != ROLE_HOST or remote_joined:
				return  # one hello per connection: a repeat cannot rename the player or swap its loadout mid-match
			var why: String = NetLobby.check_hello(d, content_hash())
			if why != "":
				send(NetLobby.lobby(local_name, local_loadout, false, why, content_hash()), true)
				status_changed.emit("Refused a player (%s)" % why)
				return
			remote_name = NetLobby.clean_name(str(d.get("name", "")))
			remote_loadout = LoadoutRules.sanitize(NetLobby.dict_of(d.get("loadout")))
			remote_joined = true
			send(NetLobby.lobby(local_name, local_loadout, true, "", content_hash()), true)
			status_changed.emit("%s joined" % remote_name)
			lobby_changed.emit()
		NetConfig.MSG_LOADOUT:
			if role == ROLE_HOST and remote_joined:
				remote_loadout = LoadoutRules.sanitize(NetLobby.dict_of(d.get("loadout")))
				lobby_changed.emit()
		NetConfig.MSG_LOBBY:
			if role != ROLE_CLIENT:
				return
			if not (d.get("accepted") is bool and bool(d["accepted"])):
				var why_not: String = str(d.get("reason", ""))
				if why_not.begins_with("version mismatch"):
					_fail(why_not)  # host and client both say it the same way
				else:
					_fail("Host refused: %s" % why_not)
				return
			var mismatch: String = NetLobby.check_peer(d, content_hash(), true)
			if mismatch != "":
				leave(mismatch)
				return
			remote_name = NetLobby.clean_name(str(d.get("name", "")))
			remote_loadout = LoadoutRules.sanitize(NetLobby.dict_of(d.get("loadout")))
			if not remote_joined:
				status_changed.emit("In %s's lobby" % remote_name)
			remote_joined = true
			lobby_changed.emit()
		NetConfig.MSG_START:
			if role == ROLE_CLIENT:
				last_start = d
				match_requested.emit(d)
		NetConfig.MSG_OVER:
			if role == ROLE_CLIENT:
				if client_driver != null and is_instance_valid(client_driver):
					client_driver.on_over(d)
				match_result.emit(d)
		NetConfig.MSG_NOTE:
			if remote_joined:
				note_received.emit(d)
		NetConfig.MSG_LEAVE:
			var why_left: String = str(d.get("reason", ""))
			if why_left.begins_with("version mismatch"):
				_close(why_left)
			else:
				_close("%s left" % (remote_name if remote_name != "" else "The other player"))


func _on_peer_connected(id: int) -> void:
	_no_throttle(id)
	if role == ROLE_HOST:
		if _remote_id != 0 and _remote_id != id:
			_peer.disconnect_peer.call_deferred(id)  # one opponent only
			return
		_remote_id = id
		_last_heard = local_tick
		status_changed.emit("Player connecting")
	elif id == HOST_PEER:
		_last_heard = local_tick
		send(NetLobby.hello(local_name, local_loadout, content_hash()), true)
		status_changed.emit("Connected, waiting for the host")


## ENet drops unreliable packets (snapshots, inputs) when the round trip time jumps, to ease a congested link. At
## 20 KB/s that never helps, and a frame hitch looks the same, so the snapshot stream lost half its packets for no
## reason: the throttle may rise again but never falls.
func _no_throttle(id: int) -> void:
	if not (_peer is ENetMultiplayerPeer):
		return
	var p: ENetPacketPeer = (_peer as ENetMultiplayerPeer).get_peer(id)
	if p != null:
		p.throttle_configure(NetConfig.THROTTLE_INTERVAL_MS, NetConfig.THROTTLE_ACCELERATION, 0)


func _on_peer_disconnected(id: int) -> void:
	if id != _remote_id:
		return
	if role == ROLE_HOST and host_driver == null:
		# Back to waiting in the lobby.
		_remote_id = 0
		remote_joined = false
		remote_name = ""
		status_changed.emit("Player left; waiting")
		lobby_changed.emit()
		return
	_close("%s disconnected" % (remote_name if remote_name != "" else "The other player"))


func _reset() -> void:
	if _peer != null:
		_close_later.call_deferred(_peer)
	_peer = null
	_closed = false
	_relay_oversize_warned = false
	close_reason = ""
	_remote_id = 0
	remote_joined = false
	remote_name = ""
	remote_loadout = {}
	role = ""


func _fail(reason: String) -> void:
	status_changed.emit(reason)
	_close(reason)


func _close(reason: String) -> void:
	if _closed:
		return
	_closed = true
	close_reason = reason
	if _peer != null:
		# Often called from a signal inside _peer.poll(): closing the ENet host there frees it mid-service and
		# crashes, so it closes on the next idle frame.
		_close_later.call_deferred(_peer)
	_peer = null
	closed.emit(reason)


func _close_later(p: MultiplayerPeer) -> void:
	if not (p is ENetMultiplayerPeer) and is_inside_tree():
		# A relay peer sends on the SDK's own tick: closing now would drop a LEAVE still in its queue.
		get_tree().create_timer(RELAY_CLOSE_DELAY_S, true).timeout.connect(p.close)
		return
	p.close()


## One line for the debug overlay and the sims.
func stats_line() -> String:
	return "%s rtt=%dms out=%.1fKB/s in=%.1fKB/s" % [role, rtt_ms(), bw_out.per_second(local_tick) / 1000.0,
		bw_in.per_second(local_tick) / 1000.0]
