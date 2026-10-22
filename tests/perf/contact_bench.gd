extends Node
## Sand-floor fill cost of the contact shadows: the sand alone fills the screen from above, with six live blobs
## under the camera ("on") or none ("off"), alternating in blocks so drift cancels. Prints one CONTACT_BENCH line.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --disable-vsync res://tests/perf/contact_bench.tscn -- --quality=0 [--blocks=12] [--frames=30] [--view=top|fight]
## Never part of the check suite (software GL: compare off and on, not absolute numbers).

var _sand: SandSurface = null
var _blocks: int = 12
var _frames: int = 30
var _frame: int = -60  ## warm-up frames first
var _last_us: int = 0
var _acc: Dictionary = {"off": [0.0, 0.0, 0], "on": [0.0, 0.0, 0]}  ## wall ms sum, render ms sum, frames
var _blobs: PackedVector4Array = PackedVector4Array()


func _ready() -> void:
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "0")))
	_blocks = int(Flags.get_arg("blocks", "12"))
	_frames = int(Flags.get_arg("frames", "30"))
	_sand = SandSurface.new()
	add_child(_sand)
	_sand.setup(Tuning.shared().arena_radius)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	if Flags.get_arg("view", "top") == "fight":
		cam.position = Vector3(0.0, 3.2, 6.0)  # about the fight camera's distance and height
		cam.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)
	else:
		cam.position = Vector3(0.0, 2.2, 0.0)  # worst case: the blobs' bound fills the screen
		cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.current = true
	var t: Tuning = Tuning.shared()
	var raw: Array[Vector4] = []
	for side: float in [-0.6, 0.6]:
		var feet: Array[Vector3] = [Vector3(side - 0.15, 0.05, 0.1), Vector3(side + 0.15, 0.05, -0.1)]
		raw.append_array(ContactShadow.fighter_blobs(feet, Vector3(side, 0.95, 0.0), t))
	_blobs = ContactShadow.pack(raw)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(_d: float) -> void:
	var now: int = Time.get_ticks_usec()
	var wall: float = float(now - _last_us) / 1000.0
	_last_us = now
	var block: int = floori(float(maxi(_frame, 0)) / float(_frames))
	var mode: String = "on" if block % 2 == 1 else "off"
	if _frame >= 1 and _frame % _frames != 0:  # skip each block's first frame (the switch)
		var vp: RID = get_viewport().get_viewport_rid()
		var a: Array = _acc[mode]
		a[0] = float(a[0]) + wall
		a[1] = float(a[1]) + RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.viewport_get_measured_render_time_gpu(vp)
		a[2] = int(a[2]) + 1
	if _frame >= 0 and _frame % _frames == 0:
		var next: String = "on" if block % 2 == 1 else "off"
		_sand.set_contacts(_blobs if next == "on" else PackedVector4Array())
	_frame += 1
	if _frame >= _blocks * _frames:
		var out: Dictionary = {"quality": GfxQuality.level, "view": Flags.get_arg("view", "top"), "live": ContactShadow.live_count(_blobs)}
		for k: String in _acc:
			var a: Array = _acc[k]
			out[k + "_wall_ms"] = snappedf(float(a[0]) / maxf(float(a[2]), 1.0), 0.01)
			out[k + "_render_ms"] = snappedf(float(a[1]) / maxf(float(a[2]), 1.0), 0.01)
		print("CONTACT_BENCH " + JSON.stringify(out))
		get_tree().quit()
