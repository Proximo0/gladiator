extends TestCase
## NetSession.adopt_peer(): the lobby runs over any MultiplayerPeer a relay backend hands over. A pair of in-memory
## fake peers models EOSG's EOSGMultiplayerPeer (server id 1, client CONNECTING until the server's id arrives, no
## "unreliable ordered" mode); a real ENet pair wrapped through adopt_peer checks the ENet path still works.

const DT: float = 1.0 / 60.0


## In-memory relay peer: what one side puts lands in the other side's inbox. Connection events fire on poll(),
## like EOSG, and every transfer mode used for a packet is recorded.
class NetFakeRelayPeer extends MultiplayerPeerExtension:
	var other: NetFakeRelayPeer = null
	var my_id: int = 0
	var server: bool = false
	var status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
	var inbox: Array = []  ## [from, bytes]
	var events: Array = []  ## [connected: bool, id] waiting for the next poll
	var modes_sent: Array[int] = []
	var closed_count: int = 0
	var _mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var _channel: int = 0
	var _target: int = 0

	func _get_packet_script() -> PackedByteArray:
		var p: Array = inbox.pop_front()
		return p[1]

	func _put_packet_script(buf: PackedByteArray) -> Error:
		if status != MultiplayerPeer.CONNECTION_CONNECTED or other == null:
			return ERR_UNCONFIGURED
		modes_sent.append(_mode)
		other.inbox.append([my_id, buf])
		return OK

	func _get_available_packet_count() -> int:
		return inbox.size()

	func _get_max_packet_size() -> int:
		return 1164

	func _get_packet_channel() -> int:
		return 0

	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE

	func _set_transfer_channel(p_channel: int) -> void:
		_channel = p_channel

	func _get_transfer_channel() -> int:
		return _channel

	func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
		_mode = p_mode

	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return _mode

	func _set_target_peer(p_peer: int) -> void:
		_target = p_peer

	func _get_packet_peer() -> int:
		return int((inbox[0] as Array)[0]) if not inbox.is_empty() else 0

	func _is_server() -> bool:
		return server

	func _poll() -> void:
		var now: Array = events.duplicate()
		events.clear()
		for e: Array in now:
			if bool(e[0]):
				peer_connected.emit(int(e[1]))
			else:
				peer_disconnected.emit(int(e[1]))

	func _close() -> void:
		closed_count += 1
		if status != MultiplayerPeer.CONNECTION_DISCONNECTED and other != null:
			other.events.append([false, my_id])
		status = MultiplayerPeer.CONNECTION_DISCONNECTED

	func _disconnect_peer(_p_peer: int, _p_force: bool) -> void:
		pass

	func _get_unique_id() -> int:
		return my_id

	func _set_refuse_new_connections(_p_enable: bool) -> void:
		pass

	func _is_refusing_new_connections() -> bool:
		return false

	func _is_server_relay_supported() -> bool:
		return false

	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return status


## [host_peer, client_peer], linked; the client is still connecting.
static func make_pair() -> Array:
	var h := NetFakeRelayPeer.new()
	h.my_id = 1
	h.server = true
	h.status = MultiplayerPeer.CONNECTION_CONNECTED
	var c := NetFakeRelayPeer.new()
	c.my_id = 777
	c.status = MultiplayerPeer.CONNECTION_CONNECTING
	h.other = c
	c.other = h
	return [h, c]


## The relay finishes connecting: both sides learn the other's id on their next poll.
static func link_up(h: NetFakeRelayPeer, c: NetFakeRelayPeer) -> void:
	c.status = MultiplayerPeer.CONNECTION_CONNECTED
	h.events.append([true, c.my_id])
	c.events.append([true, h.my_id])


static func step(sessions: Array, ticks: int) -> void:
	for _i: int in ticks:
		for s: NetSession in sessions:
			s._physics_process(DT)


func test_relay_pair_reaches_the_lobby_and_starts() -> void:
	var pair: Array = make_pair()
	var hp: NetFakeRelayPeer = pair[0]
	var cp: NetFakeRelayPeer = pair[1]
	var host := NetSession.new()
	var client := NetSession.new()
	host.set_local("Verus", {})
	client.set_local("Cato", {})
	assert_eq(host.adopt_peer(hp, NetSession.ROLE_HOST), OK)
	assert_eq(client.adopt_peer(cp, NetSession.ROLE_CLIENT), OK)
	assert_true(host.is_relay() and client.is_relay(), "fake peers count as relay")
	assert_eq(host.role, NetSession.ROLE_HOST)
	assert_eq(client.role, NetSession.ROLE_CLIENT)
	step([host, client], 3)
	assert_false(host.remote_joined, "nobody joined before the relay links")
	link_up(hp, cp)
	step([host, client], 6)
	assert_true(host.remote_joined, "host saw the client's hello")
	assert_true(client.remote_joined, "client got the lobby reply")
	assert_eq(host.remote_name, "Cato")
	assert_eq(client.remote_name, "Verus")
	var starts: Array = []
	client.match_requested.connect(func(d: Dictionary) -> void: starts.append(d))
	assert_true(host.start_match(4242), "host starts")
	step([host, client], 2)
	assert_eq(starts.size(), 1, "client got START")
	if starts.size() == 1:
		assert_eq(int((starts[0] as Dictionary).get("seed", -1)), 4242)
	assert_eq(host.rtt_ms(), 0, "no ENet round trip time on a relay")
	_unlink(pair)
	_free([host, client])


func test_relay_never_uses_unreliable_ordered() -> void:
	var pair: Array = make_pair()
	var hp: NetFakeRelayPeer = pair[0]
	var cp: NetFakeRelayPeer = pair[1]
	var host := NetSession.new()
	var client := NetSession.new()
	host.adopt_peer(hp, NetSession.ROLE_HOST)
	client.adopt_peer(cp, NetSession.ROLE_CLIENT)
	link_up(hp, cp)
	step([host, client], 4)
	host.send(PackedByteArray([NetConfig.MSG_SNAP, 1, 2, 3]), false)
	client.send(PackedByteArray([NetConfig.MSG_INPUT, 1]), false)
	assert_true(hp.modes_sent.has(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE), "host sent unreliable")
	assert_true(cp.modes_sent.has(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE), "client sent unreliable")
	assert_false(hp.modes_sent.has(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED), "EOSG would turn it reliable")
	assert_false(cp.modes_sent.has(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED))
	_unlink(pair)
	_free([host, client])


func test_transfer_modes() -> void:
	assert_eq(NetSession.transfer_mode_for(true, false), MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)
	assert_eq(NetSession.transfer_mode_for(false, false), MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	assert_eq(NetSession.transfer_mode_for(true, true), MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(NetSession.transfer_mode_for(false, true), MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func test_host_drop_closes_the_client() -> void:
	var pair: Array = make_pair()
	var hp: NetFakeRelayPeer = pair[0]
	var cp: NetFakeRelayPeer = pair[1]
	var host := NetSession.new()
	var client := NetSession.new()
	host.adopt_peer(hp, NetSession.ROLE_HOST)
	client.adopt_peer(cp, NetSession.ROLE_CLIENT)
	link_up(hp, cp)
	step([host, client], 4)
	var reasons: Array = []
	client.closed.connect(func(r: String) -> void: reasons.append(r))
	hp.close()  # the host's relay connection dies
	step([client], 2)
	assert_eq(reasons.size(), 1, "client closed once")
	assert_false(client.is_open())
	_unlink(pair)
	_free([host, client])


func test_already_connected_client_says_hello_at_once() -> void:
	var pair: Array = make_pair()
	var hp: NetFakeRelayPeer = pair[0]
	var cp: NetFakeRelayPeer = pair[1]
	cp.status = MultiplayerPeer.CONNECTION_CONNECTED  # the service polled it before the hand-over
	var client := NetSession.new()
	client.adopt_peer(cp, NetSession.ROLE_CLIENT)
	assert_eq(hp.inbox.size(), 1, "hello sent during adopt_peer")
	if hp.inbox.size() == 1:
		assert_eq(NetConfig.msg_type((hp.inbox[0] as Array)[1]), NetConfig.MSG_HELLO)
	_unlink(pair)
	_free([client])


func test_bad_arguments_are_refused() -> void:
	var s := NetSession.new()
	var reasons: Array = []
	s.closed.connect(func(r: String) -> void: reasons.append(r))
	assert_eq(s.adopt_peer(null, NetSession.ROLE_HOST), ERR_INVALID_PARAMETER)
	var pair: Array = make_pair()
	assert_eq(s.adopt_peer(pair[0], "spectator"), ERR_INVALID_PARAMETER)
	assert_false(s.is_open())
	assert_eq(reasons.size(), 2, "each refusal closes the session")
	_unlink(pair)
	_free([s])


func test_enet_pair_through_adopt_peer() -> void:
	var server := ENetMultiplayerPeer.new()
	if server.create_server(0, 1) != OK:
		failures.append("could not open an ENet server")
		return
	var port: int = server.host.get_local_port()
	var cl := ENetMultiplayerPeer.new()
	if cl.create_client("127.0.0.1", port) != OK:
		failures.append("could not open an ENet client")
		server.close()
		return
	var host := NetSession.new()
	var client := NetSession.new()
	host.set_local("Verus", {})
	client.set_local("Cato", {})
	host.adopt_peer(server, NetSession.ROLE_HOST)
	client.adopt_peer(cl, NetSession.ROLE_CLIENT)
	assert_false(host.is_relay(), "ENet is not a relay")
	var waited: int = 0
	while waited < 3000 and not (host.remote_joined and client.remote_joined):
		step([host, client], 1)
		OS.delay_msec(5)
		waited += 5
	assert_true(host.remote_joined and client.remote_joined, "ENet lobby through adopt_peer (%d ms)" % waited)
	assert_eq(client.remote_name, "Verus")
	host.leave("test over")
	client.leave("test over")
	_free([host, client])


## The two fakes point at each other: break the cycle so they are freed.
func _unlink(pair: Array) -> void:
	for p: NetFakeRelayPeer in pair:
		p.other = null
		p.inbox.clear()


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()
