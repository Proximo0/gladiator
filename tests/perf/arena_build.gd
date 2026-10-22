extends Node
## Arena build timing: builds the presented Arena `--repeat` times (default 3) at `--quality` in a real window and
## prints one `ARENA_BUILD {json}` line per build (per-step ms, sand setup steps under "sand.<step>"), then quits.
## The first build in a process pays the asset loads; later ones show the steady cost. Run via tools/arena_build.sh.

var _left: int = 3
var _builds: int = 0


func _ready() -> void:
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality")))
	_left = maxi(1, int(Flags.get_arg("repeat", "3")))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 14)
	add_child(cam)
	cam.look_at(Vector3.ZERO)
	_build_once.call_deferred()


func _build_once() -> void:
	var arena := Arena.new()
	var t0: int = Time.get_ticks_usec()
	add_child(arena)
	var p: Dictionary = arena.build_profile()
	p["add_child"] = float(Time.get_ticks_usec() - t0) / 1000.0
	p["build"] = _builds
	p["quality"] = GfxQuality.level
	ProfileLog.emit("ARENA_BUILD", p)
	_builds += 1
	_left -= 1
	# Let a frame draw it (uploads), then free and go again.
	await get_tree().process_frame
	await get_tree().process_frame
	arena.queue_free()
	await get_tree().process_frame
	if _left > 0:
		_build_once()
	else:
		get_tree().quit()
