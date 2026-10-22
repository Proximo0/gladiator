extends Node
## Match presentation renders in the real game: the pre-fight intro, the fight just after it, and the results screen.
## Run in a real (xvfb) window:
## godot --path . --fixed-fps 60 --resolution 1280x720 res://tests/render/match_show_capture.tscn -- --out=DIR --name=land [--touch]
## A Fight vs CPU from the menu flow; after the intro a few scripted blows land (player 1 cuts, severs an arm) and the
## CPU bleeds out, so the results screen has numbers. Shots key on game state (intro phase, result screen) with a frame
## fallback. Never part of the check suite; writes only the PNGs it is told to.

const FALLBACK_FRAMES: int = 2400

var _out: String = "/tmp/match_show_capture/"
var _name: String = "shot"
var _main: Node = null
var _frame: int = 0
var _step: int = 0
var _mark: int = 0
var _render_until: int = -1
var _pending: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _flow() -> Object:
	return _main.get("_flow")


func _match() -> Match:
	var f: Object = _flow()
	return f.get("current_match") as Match if f != null else null


## The intro phase name, or "" when there is no intro (before this branch) or it is over.
func _intro_phase() -> String:
	var f: Object = _flow()
	if f == null or not f.has_method("intro_phase"):
		return ""
	return str(f.call("intro_phase"))


func _process(_d: float) -> void:
	_frame += 1
	if _frame > FALLBACK_FRAMES:
		print("MSCAP fallback quit at step ", _step)
		get_tree().quit()
		return
	if _pending != "":
		if _frame >= _render_until:
			_save(_pending)
			_pending = ""
			RenderingServer.render_loop_enabled = false
		return
	match _step:
		0:
			if _frame >= 20:
				(_flow() as Object).call("_begin_fight", "player_vs_cpu")
				_step = 1
				_mark = _frame
		1:
			# Plates in and settled (or, with no intro, the opening frames of the fight).
			var ph: String = _intro_phase()
			if ph == "plates" and _frame - _mark > 70 or (ph == "" and _frame - _mark > 40) or _frame - _mark > 400:
				_shoot("intro")
				_step = 2
		2:
			var ph2: String = _intro_phase()
			if ph2 == "fight" or _frame - _mark > 600:
				_shoot("stinger")
				_step = 3
		3:
			if _intro_phase() == "" and _match() != null and _match().tick > 30:
				_shoot("fight")
				_script_blows()
				_step = 4
				_mark = _frame
		4:
			var scr: int = int((_flow() as Object).get("screen"))
			if scr == MenuFlow.Screen.RESULT:
				_mark = _frame
				_step = 5
		5:
			if _frame - _mark > 90:
				_shoot("result")
				_step = 6
		6:
			get_tree().quit()


## Lands a few blows from side 0 (a sever among them) and bleeds side 1 out, through the fighters' own signals.
func _script_blows() -> void:
	var m: Match = _match()
	if m == null:
		return
	var foe: Fighter = m.fighters[1]
	var me: Fighter = m.fighters[0]
	var at: Vector3 = (foe.parts["torso"] as Node3D).global_position
	for i: int in 5:
		foe.hit.emit({"attacker": 0, "target": 1, "part": "torso", "contact": "edge", "total": 12.0 + float(i),
			"point": at, "normal": Vector3.UP, "rel_vel": Vector3(0.0, 0.0, 6.0)})
	me.hit.emit({"attacker": 1, "target": 0, "part": "thigh_l", "contact": "blunt", "total": 6.0,
		"point": (me.parts["thigh_l"] as Node3D).global_position, "normal": Vector3.UP, "rel_vel": Vector3(0.0, 0.0, -4.0)})
	foe.gore.emit({"kind": "sever", "part": "forearm_l", "point": at, "normal": Vector3.UP, "amount": 1.0})
	me.health.blood = 3.9
	foe.health.blood = 0.4


func _shoot(tag: String) -> void:
	RenderingServer.render_loop_enabled = true
	_pending = tag
	_render_until = _frame + 4


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
	print("MSCAP saved ", tag)
