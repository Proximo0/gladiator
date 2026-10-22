extends Node
## Low/medium/high droplet look in the real arena light: one process, the same frozen droplets drawn with each quality's
## droplet mesh. Run in a real (xvfb) window:
## godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/render/blood_capture.tscn -- --out=DIR
## Prints `BLOODCAP q=<level> mean_r=.. mean_g=.. px=..` per shot (mean colour of the blood pixels). Never part of the
## check suite; writes only the PNGs it is told to.

var _out: String = "/tmp/blood_capture/"
var _match: Match = null
var _cam: Camera3D = null
var _frame: int = 0
var _q: int = 0
var _view: String = "front"  ## --view=front|close|top
var _only: int = -1  ## --quality=N: run the whole match at that graphics level and shoot only that droplet mesh


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--view="):
			_view = a.substr(7)
		elif a.begins_with("--quality="):
			_only = int(a.substr(10))
			GfxQuality.set_level(_only)
			_q = _only
	DirAccess.make_dir_recursive_absolute(_out)
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": 1002, "presentation": true, "loop": false, "time_limit_s": 600.0})


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		_match.process_mode = Node.PROCESS_MODE_DISABLED  # freeze the fight; the blood is driven by hand below
		for f: Node3D in _match.fighters:
			f.visible = false
		_match.presenter.blood.set_process(false)
		_cam = Camera3D.new()
		add_child(_cam)
		var eye: Vector3 = {"front": Vector3(0.0, 1.6, 3.2), "close": Vector3(-0.5, 0.95, 0.45),
				"top": Vector3(0.0, 5.0, 4.0)}.get(_view, Vector3(0.0, 1.6, 3.2))
		_cam.global_position = eye
		_cam.look_at(Vector3(-0.5, 0.95, 0.0) if _view == "close" else Vector3(0.0, 1.0, 0.0))
		_cam.fov = 40.0
		_cam.make_current()
	if _frame >= 30 and (_frame - 30) % 12 == 0 and _q <= 2:
		if _frame > 30:
			_save(_q)
			_q = 3 if _only >= 0 else _q + 1
		if _q <= 2:
			_place(_q)
	if _q > 2:
		print("BLOODCAP done")
		get_tree().quit()


## The same grid of drops at every quality: still round ones in the left half, fast streaks in the right half.
func _place(q: int) -> void:
	var b: BloodFx = _match.presenter.blood
	b.set_quality(q)
	b.sim.resize(b.sim.capacity)
	for iy: int in 8:
		for ix: int in 16:
			var p: Vector3 = Vector3(-0.9 + 0.12 * ix, 0.55 + 0.12 * iy, 0.0)
			var v: Vector3 = Vector3.ZERO if ix < 8 else Vector3(2.0, -3.0 + 0.5 * iy, 1.0)
			b.sim.emit(p, v, 0.012 + 0.002 * (iy % 3), 1.0, 100.0, 0.0, 0)
	b.call("_upload")


func _save(q: int) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%sdrops_%s_%s%s.png" % [_out, _view, GfxQuality.name_of(q), "_tier" if _only >= 0 else ""])
	var sr: float = 0.0
	var sg: float = 0.0
	var n: int = 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.r8 > 60 and c.r8 > 3 * c.g8 + 20 and c.r8 > 3 * c.b8 + 20:
				sr += c.r8
				sg += c.g8
				n += 1
	print("BLOODCAP view=%s q=%s mean_r=%.0f mean_g=%.0f px=%d" % [_view, GfxQuality.name_of(q), sr / maxf(n, 1), sg / maxf(n, 1), n])
