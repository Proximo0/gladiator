extends Node3D
## Weapon rack renders in the real arena: both racks stocked for a sample loadout pair, a close shot of each and a wide
## fight-camera view. Run in a real (xvfb) window: godot --path . --resolution 1280x720 res://tests/render/rack_capture.tscn
## -- --out=DIR --name=after [--quality=0|1|2] [--empty] (racks left empty: the before shot). Waits until the racked
## copies are drawn (RackDressing.is_ready) with a frame fallback. Never part of the check suite; writes only its PNGs.

const LOADOUTS: Array = [{"weapon": "longsword", "offhand": "shield_round"}, {"weapon": "spear", "offhand": ""}]
const FALLBACK_FRAMES: int = 240
const SETTLE_FRAMES: int = 20

var _out: String = "/tmp/rack_capture/"
var _name: String = "shot"
var _empty: bool = false
var _arena: Arena
var _cam: Camera3D
var _shots: Array = []  ## [name, camera position, look target]
var _frame: int = 0
var _start: int = -1


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--quality="):
			GfxQuality.set_level(int(a.substr(10)))
		elif a == "--empty":
			_empty = true
	DirAccess.make_dir_recursive_absolute(_out)
	_arena = Arena.new()
	add_child(_arena)
	if not _empty:
		_arena.stock_racks(LOADOUTS)
	elif _arena.racks != null:
		_arena.racks.queue_free()
		_arena.racks = null
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	var racks: Array[Transform3D] = DecorLayout.transforms(_arena.radius, "weapon_rack")
	for i: int in racks.size():
		var xf: Transform3D = racks[i]
		_shots.append(["rack%d" % i, xf * Vector3(0.6, 1.5, 3.2), xf * Vector3(0.0, 0.95, 0.0)])
	_shots.append(["wide", Vector3(-1.5, 3.0, -2.5), racks[0] * Vector3(0.0, 0.8, 0.0)])


func _process(_d: float) -> void:
	_frame += 1
	if _start < 0:
		var ready: bool = _empty or _arena.racks == null or _arena.racks.is_ready()
		if ready or _frame > FALLBACK_FRAMES:
			_start = _frame
			print("RACKCAP %s ready=%s copies=%d frame=%d rebuild_ms=%.1f" % [_name, ready, _arena.racks.copies() if _arena.racks != null else 0,
					_frame, _arena.racks.rebuild_ms if _arena.racks != null else 0.0])
		return
	var i: int = (_frame - _start) / SETTLE_FRAMES
	if i >= _shots.size():
		get_tree().quit()
		return
	var spec: Array = _shots[i]
	_cam.look_at_from_position(spec[1] as Vector3, spec[2] as Vector3)
	if (_frame - _start) % SETTLE_FRAMES == SETTLE_FRAMES - 1:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s%s_%dx%d_q%d_%s.jpg" % [_out, _name, img.get_width(), img.get_height(), GfxQuality.level, spec[0]], 0.85)
