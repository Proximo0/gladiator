extends Node3D
## Main scene: boots to the title screen (MenuFlow). With `-- --mode=...` it skips the menus and starts that match
## (bots, CI, tools/windows/*.bat). Debug layer: F10 frame stamp, F4/F6-F9 render toggles, F1 fight overlay,
## F12 save recording, backquote tuning panel.

var _match: Match = null
var _overlay: FightOverlay
var _rec: FlightRecorder
var _flow: MenuFlow = null
var _attached: Array = []


func _ready() -> void:
	add_child(FrameStamp.new())
	add_child(RenderToggles.new())
	_overlay = FightOverlay.new()
	add_child(_overlay)
	_rec = FlightRecorder.new()  # F12 saves a recording to user://recordings
	add_child(_rec)
	if Flags.args.has("mode"):
		var mode: String = Flags.get_arg("mode", "bot_vs_bot")
		_match = Match.new()
		add_child(_match)
		_match.setup({"mode": mode, "seed": Flags.seed_value()})
		_rec.attach(_match)
		if mode != "bot_vs_bot" and not Flags.is_scripted_run():
			# Keep Esc pause and the end-of-match menu for command-line player matches.
			_flow = _new_flow()
			_flow.adopt(_match, mode)
	else:
		_flow = _new_flow()
		_flow.setup(self)
		if Flags.args.has("online"):
			_flow.call("_open_online")


func _new_flow() -> MenuFlow:
	var flow := MenuFlow.new()
	add_child(flow)
	flow.match_started.connect(_on_match_started)
	flow.match_closed.connect(_on_match_closed)
	return flow


func _on_match_started(m: Match) -> void:
	_match = m
	_attached = []
	_rec.attach(m)


func _on_match_closed() -> void:
	_match = null
	_attached = []
	_overlay.attach([])


func _process(_delta: float) -> void:
	# The bot loop replaces the fighters after each match, so re-attach the overlay when they change.
	if _match == null or not is_instance_valid(_match) or _match.fighters.size() < 2 or _match.fighters == _attached:
		return
	_attached = _match.fighters.duplicate()
	_overlay.attach(_attached)
	_overlay.brains = {_attached[0]: _match.brains[0], _attached[1]: _match.brains[1]}
