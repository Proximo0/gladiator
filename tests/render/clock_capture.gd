extends Node
## HUD match clock renders in the real game (Fight vs CPU through the menu flow): one shot a few seconds into the
## fight (m:ss) and one in the last-30-s countdown (the fight clock is moved on so the countdown is near). Shots key
## on game state (the fight clock running, the clock's text); a frame cap ends a stuck run. Faked safe-area cutouts
## are drawn black. Run in a real (xvfb) window:
## godot --path . --resolution 540x960 res://tests/render/clock_capture.tscn -- [--touch] --out=DIR/ --name=port [--safe-insets=L,T,R,B]
## Never part of the check suite.

const FIGHT_TICKS: int = 180  ## the first shot: 3 s of fight
const LEFT_S: float = 25.4  ## the countdown shot: about this much of the time limit left
const CAP_FRAMES: int = 6000

var _out: String = "/tmp/clock_capture/"
var _name: String = "shot"
var _main: Node = null
var _frame: int = 0
var _stage: int = 0
var _skipped: bool = false
var _wait: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var cut := Control.new()
	cut.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cut.draw.connect(_draw_cutouts.bind(cut))
	layer.add_child(cut)


func _draw_cutouts(c: Control) -> void:
	var ins: Vector4 = SafeArea.window_insets()
	var k: float = maxf(get_viewport().get_final_transform().get_scale().x, 0.01)
	var s: Vector2 = c.size
	var black := Color(0, 0, 0, 1)
	c.draw_rect(Rect2(0, 0, ins.x / k, s.y), black)
	c.draw_rect(Rect2(0, 0, s.x, ins.y / k), black)
	c.draw_rect(Rect2(s.x - ins.z / k, 0, ins.z / k, s.y), black)
	c.draw_rect(Rect2(0, s.y - ins.w / k, s.x, ins.w / k), black)


func _find_match(n: Node) -> Match:
	if n is Match:
		return n as Match
	for c: Node in n.get_children():
		var f: Match = _find_match(c)
		if f != null:
			return f
	return null


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 20:
		(_main.get("_flow") as Object).call("_begin_fight", "player_vs_cpu")
	if _frame > CAP_FRAMES:
		print("CLOCK_CAPTURE FAIL %s stuck at stage %d" % [_name, _stage])
		get_tree().quit(1)
		return
	var m: Match = _find_match(_main) if _frame > 20 else null
	if m == null or m.presenter == null:
		return
	if not _skipped and _frame > 40:  # skip the intro like a player would
		_skipped = true
		var e := InputEventKey.new()
		e.keycode = KEY_SPACE
		e.pressed = true
		Input.parse_input_event(e)
	var label: Label = m.presenter.hud.get("_clock_label")
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_save("%s_%s" % [_name, "fight" if _stage == 1 else "countdown"])
			RenderingServer.render_loop_enabled = false
			if _stage == 2:
				print("CLOCK_CAPTURE %s done" % _name)
				get_tree().quit()
		return
	if _stage == 0 and m.fight_clock_running() and m.fight_ticks() >= FIGHT_TICKS:
		_stage = 1
		_arm()
		print("CLOCK_CAPTURE %s fight text=%s" % [_name, label.text])
	elif _stage == 1:
		var limit_s: float = float(m.config["time_limit_s"])
		m.fight_start_tick = m.tick - roundi((limit_s - LEFT_S) * 60.0)
		_stage = 2
	elif _stage == 2 and label.text.begins_with("0:2"):
		_arm()
		print("CLOCK_CAPTURE %s countdown text=%s" % [_name, label.text])


func _arm() -> void:
	RenderingServer.render_loop_enabled = true
	_wait = 4


func _save(file: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg("%s%s.jpg" % [_out, file], 0.85)
