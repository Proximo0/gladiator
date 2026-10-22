extends Node
## Close-range move renders in a real match (presentation on): side 0 walks in on side 1 and kicks, shoves or grabs.
## The move keys on distance (an observed condition) with a tick fallback; the shot keys on the move's own state.
## Run in a real (xvfb) window:
## godot --path . --resolution 1280x720 res://tests/render/close_capture.tscn -- --out=DIR --name=wide --move=kick|shove|grab
## Never part of the check suite; writes only the PNGs it is told to.

var _out: String = "/tmp/close_capture/"
var _name: String = "shot"
var _move: String = "kick"
var _match: Match = null
var _tick: int = 0
var _pressed: int = -1
var _shot: bool = false
var _hold_ticks: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--move="):
			_move = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	process_physics_priority = -100  # inputs go in before the match's tick
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_match = Match.new()
	add_child(_match)
	var lo: Dictionary = {"weapon": "gladius", "offhand": "", "armor": {"torso": "cuirass_leather"}}
	_match.setup({"mode": "bot_vs_bot", "seed": 4242, "loadouts": [lo, lo.duplicate(true)], "time_limit_s": 60})


func _physics_process(_d: float) -> void:
	_tick += 1
	if _match == null or _match.fighters.size() < 2:
		return
	var a: Fighter = _match.fighters[0]
	var b: Fighter = _match.fighters[1]
	var d: float = (a.parts["pelvis"] as RigidBody3D).global_position.distance_to((b.parts["pelvis"] as RigidBody3D).global_position)
	var ia := FighterInput.new()
	var want: float = 1.15 if _move == "kick" else 0.9
	if _pressed < 0 and _tick > 30:
		if d > want and _tick < 600:
			ia.move_y = 1000
		else:
			_pressed = _tick
	var bit: int = {"kick": FighterInput.KICK, "shove": FighterInput.SHOVE, "grab": FighterInput.CLINCH}.get(_move, FighterInput.KICK)
	if _pressed >= 0 and (_tick - _pressed < 3 or _move == "grab"):
		ia.buttons |= bit
	_match.force_inputs([[ia.to_array(), FighterInput.new().to_array()]])
	if _shot or _pressed < 0:
		return
	var c: Dictionary = a.debug_frame()["close"]
	var u_kick: float = CloseCombat.progress(a._close.kick_t, a._t("kick_time"))
	if a._close.holding():
		_hold_ticks += 1
	var ready: bool = (_move == "kick" and u_kick >= 0.48) or (_move == "shove" and a._close.shove_landed and a._close.shove_t > 0.2) \
		or (_move == "grab" and _hold_ticks >= 30) or _tick - _pressed > 120
	if ready:
		_shot = true
		print("CLOSECAP %s tick=%d dist=%.2f close=%s" % [_move, _tick, d, c])
		RenderingServer.render_loop_enabled = true
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("%s%s_%s.png" % [_out, _name, _move])
		get_tree().quit()
