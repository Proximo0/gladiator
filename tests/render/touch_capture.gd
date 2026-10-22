extends Node
## Touch overlay renders in the real game (player vs CPU through the menu flow) with synthetic fingers: the left thumb
## on the stick, a right finger dragging the aim, and the OFF toggle lit. Faked safe-area cutouts are drawn black.
## Run in a real (xvfb) window:
## godot --path . --resolution 960x540 res://tests/render/touch_capture.tscn -- --touch --capture --out=DIR --name=land_16x9 [--safe-insets=L,T,R,B] [--half]
## --half also saves a half-size copy (for committing big screens under 300 KB). Never part of the check suite.

var _out: String = "/tmp/touch_capture/"
var _name: String = "shot"
var _half: bool = false
var _main: Node = null
var _frame: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a == "--half":
			_half = true
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


## Black where the faked insets are, so the picture shows what the buttons must avoid.
func _draw_cutouts(c: Control) -> void:
	var ins: Vector4 = SafeArea.window_insets()
	var k: float = maxf(get_viewport().get_final_transform().get_scale().x, 0.01)
	var s: Vector2 = c.size
	var black := Color(0, 0, 0, 1)
	c.draw_rect(Rect2(0, 0, ins.x / k, s.y), black)
	c.draw_rect(Rect2(0, 0, s.x, ins.y / k), black)
	c.draw_rect(Rect2(s.x - ins.z / k, 0, ins.z / k, s.y), black)
	c.draw_rect(Rect2(0, s.y - ins.w / k, s.x, ins.w / k), black)


func _touch(i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = down
	Input.parse_input_event(e)


func _drag(i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = p
	Input.parse_input_event(e)


func _process(_d: float) -> void:
	_frame += 1
	var win := Vector2(get_window().size)
	var short: float = minf(win.x, win.y)
	var ins: Vector4 = SafeArea.window_insets()
	if _frame == 20:
		(_main.get("_flow") as Object).call("_begin_fight", "player_vs_cpu")
	if _frame == 200:
		var s := Vector2(ins.x + win.x * 0.16, win.y * 0.72)
		_touch(0, s, true)
		_drag(0, s + Vector2(short * 0.12, -short * 0.14))
		var a := Vector2(win.x * 0.66, win.y * 0.36)
		_touch(1, a, true)
		_drag(1, a + Vector2(short * 0.17, -short * 0.12))
	if _frame == 202:
		# Tap the OFF toggle: the first button labelled OFF in the overlay's own layout.
		var tc: Control = _find_touch(_main)
		if tc != null:
			var k: float = maxf(get_viewport().get_final_transform().get_scale().x, 0.01)
			for b: Dictionary in tc.call("_layout"):
				if str(b["label"]) == "OFF":
					_touch(2, (b["center"] as Vector2) * k, true)
					_touch(2, (b["center"] as Vector2) * k, false)
	if _frame == 236:
		RenderingServer.render_loop_enabled = true
	if _frame == 240:
		_save()
		get_tree().quit()


func _find_touch(n: Node) -> Control:
	if n is TouchControls:
		return n as Control
	for c: Node in n.get_children():
		var f: Control = _find_touch(c)
		if f != null:
			return f
	return null


func _save() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s.png" % [_out, _name])
	if _half:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s%s_half.png" % [_out, _name])
