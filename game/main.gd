extends Node3D
## Main scene: one Match (bot vs bot by default; `-- --mode=player_vs_cpu` etc.) plus the debug layer
## (F10 frame stamp, F4/F6-F9 render toggles, F1 fight overlay, F12 save recording, backquote tuning panel).

var _match: Match
var _overlay: FightOverlay
var _attached: Array = []


func _ready() -> void:
	add_child(FrameStamp.new())
	add_child(RenderToggles.new())
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": Flags.get_arg("mode", "bot_vs_bot"), "seed": Flags.seed_value()})
	_overlay = FightOverlay.new()
	add_child(_overlay)
	var rec: FlightRecorder = FlightRecorder.new()  # F12 saves a recording to user://recordings
	add_child(rec)
	rec.attach(_match)


func _process(_delta: float) -> void:
	# The bot loop replaces the fighters after each match, so re-attach the overlay when they change.
	if _match.fighters.size() < 2 or _match.fighters == _attached:
		return
	_attached = _match.fighters.duplicate()
	_overlay.attach(_attached)
	_overlay.brains = {_attached[0]: _match.brains[0], _attached[1]: _match.brains[1]}
