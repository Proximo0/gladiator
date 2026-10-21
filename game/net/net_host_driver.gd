class_name NetHostDriver
extends Node
## Host side of an online match, a child of the Match. Puts a NetRemoteBrain on side 1 (fed by the client's input
## stream through a NetInputBuffer), then every SNAP_EVERY_TICKS physics ticks sends a snapshot of both fighters,
## sends hit and gore events as they happen (reliable, stamped with the tick) and the result when the match ends.
## Runs after the fighters (priority 20), so a snapshot shows the tick's final control state.

const PRIORITY: int = 20

var session: NetSession = null
var match_node: Match = null
var inputs: NetInputBuffer = NetInputBuffer.new()
var snapshots_sent: int = 0
var events_sent: int = 0
var events_at_over: int = -1  ## events sent when the match ended (hits can still land during the end pause)
var last_snapshot: NetSnapshot = null
var history: Dictionary = {}  ## tick -> NetSnapshot, the last few seconds (for the sims to compare)
var keep_history: bool = false

var _armor: Array = [[], []]
var _pending: Array = []
var _last_sent_tick: int = -1
var _over_sent: bool = false
var _reader_device: String = ""  ## the host's own reader's real device while it is switched to "none" behind the Esc menu


func _init() -> void:
	process_physics_priority = PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS


func attach(m: Match) -> void:
	match_node = m
	m.brains[1] = NetRemoteBrain.new(inputs)
	for side: int in 2:
		var f: Fighter = m.fighters[side]
		_armor[side] = NetWorld.armor_order(f)
		f.hit.connect(_on_event.bind(side, "hit"))
		f.gore.connect(_on_event.bind(side, "gore"))
	m.match_over.connect(_on_over)


func on_input(bytes: PackedByteArray) -> void:
	for r: Array in NetInputPacker.unpack(bytes):
		inputs.push(int(r[0]), r[1] as FighterInput)


func _on_event(ev: Dictionary, side: int, kind: String) -> void:
	if _over_sent or (match_node != null and match_node.over):
		return  # the end pause: the result is out, nothing after it plays on the client
	_pending.append([match_node.tick if match_node != null else 0, side, kind, ev])


func _on_over(result: Dictionary) -> void:
	_flush_events()
	events_at_over = events_sent
	if session != null and not _over_sent:
		session.send(NetLobby.over(result), true)
		_over_sent = true


func capture() -> NetSnapshot:
	var s := NetSnapshot.new()
	s.tick = match_node.tick
	s.ack_input_tick = inputs.last_applied_tick
	s.over = match_node.over
	s.time_scale = Engine.time_scale
	for side: int in 2:
		var a: Array[String] = []
		a.assign(_armor[side])
		s.fighters.append(NetWorld.capture(match_node.fighters[side] as Fighter, a))
	return s


func _flush_events() -> void:
	if _over_sent:
		_pending.clear()
		return
	while not _pending.is_empty() and session != null:
		var chunk: Array = _pending.slice(0, NetEvents.MAX_PER_PACKET)
		_pending = _pending.slice(chunk.size())
		session.send(NetEvents.encode(chunk), true)
		events_sent += chunk.size()


## While the Esc menu is open the host's own reader reads a device that does not exist (neutral input), so its keys
## do not move its fighter; the real device comes back when the menu closes (NetSession calls this when the flag flips).
func gate_own_reader() -> void:
	if match_node == null or not is_instance_valid(match_node):
		return
	var r: Variant = match_node.readers[0]
	if r == null or not is_instance_valid(r):
		return
	var rd: InputReader = r as InputReader
	if session.input_blocked and _reader_device == "":
		_reader_device = rd.device
		rd.device = "none"
	elif not session.input_blocked and _reader_device != "":
		rd.device = _reader_device
		_reader_device = ""


func _physics_process(_delta: float) -> void:
	if session == null or match_node == null or not is_instance_valid(match_node) or match_node.fighters.size() < 2:
		return
	_flush_events()
	gate_own_reader()
	var t: int = match_node.tick
	if t == _last_sent_tick or t % NetConfig.SNAP_EVERY_TICKS != 0:
		return
	_last_sent_tick = t
	var s: NetSnapshot = capture()
	last_snapshot = s
	if keep_history:
		history[t] = s
		history.erase(t - NetConfig.TICK_HZ * 4)
	session.send(s.encode(), false)
	snapshots_sent += 1
