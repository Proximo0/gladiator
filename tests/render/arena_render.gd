extends Node3D
## Arena dressing renders and build stats: builds the Arena at one graphics level, prints its build time, node count
## and triangle count, and saves a few fixed views. Run in a real (xvfb) window:
## godot --path . res://tests/render/arena_render.tscn -- --out=/tmp/arena/ --quality=2 --tag=after --res=540x960
## Never part of the game or the check suite; writes only the PNGs it is told to.

var _cam: Camera3D
var _out: String = "/tmp/arena_render/"
var _tag: String = "shot"


func _ready() -> void:
	var q: int = 2
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--quality="):
			q = int(a.substr(10))
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--res="):
			var wh: PackedStringArray = a.substr(6).split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
	GfxQuality.set_level(q)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	var t0: int = Time.get_ticks_usec()
	var arena := Arena.new()
	add_child(arena)
	var build_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var stats: Array[int] = [0, 0, 0]
	_count(arena, stats)
	print("ARENA quality=%s build_ms=%.1f nodes=%d tris=%d decor_tris=%d" % [GfxQuality.name_of(q), build_ms, stats[0], stats[1], stats[2]])
	await _frames(4)
	var size: Vector2i = get_viewport().get_texture().get_image().get_size()
	var res: String = "%dx%d" % [size.x, size.y]
	# Fight view from behind spawn 0 toward the imperial box (-Z), a wide view, and both gates.
	await _shot(Vector3(0.6, 2.3, 7.4), Vector3(0, 1.2, -4.0), "%s_%s_q%d_fight" % [_tag, res, q])
	await _shot(Vector3(-3.0, 6.5, 9.0), Vector3(0, 1.0, -3.0), "%s_%s_q%d_wide" % [_tag, res, q])
	await _shot(Vector3(-4.0, 1.8, 2.5), Vector3(10.5, 1.5, -0.5), "%s_%s_q%d_gate" % [_tag, res, q])
	await _shot(Vector3(4.0, 2.0, 3.0), Vector3(-10.5, 1.8, 0.0), "%s_%s_q%d_gate2" % [_tag, res, q])
	# Close: the +X gate with its rack and barrier, and the imperial box with the statue behind it.
	await _shot(Vector3(5.5, 1.7, 1.5), Vector3(10.5, 1.4, 1.0), "%s_%s_q%d_gate_close" % [_tag, res, q])
	await _shot(Vector3(0.0, 2.0, -4.0), Vector3(0.0, 5.5, -14.0), "%s_%s_q%d_box" % [_tag, res, q])
	print("RENDER done ", _out)
	get_tree().quit()


## stats: [nodes, triangles, triangles under nodes named Decor*]
func _count(n: Node, stats: Array[int], in_decor: bool = false) -> void:
	stats[0] += 1
	var decor: bool = in_decor or String(n.name).begins_with("Decor")
	var tris: int = 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		tris = _mesh_tris((n as MeshInstance3D).mesh)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var shown: int = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		if mm.mesh != null:
			tris = _mesh_tris(mm.mesh) * shown
	stats[1] += tris
	if decor:
		stats[2] += tris
	for c: Node in n.get_children():
		_count(c, stats, decor)


func _mesh_tris(m: Mesh) -> int:
	var t: int = 0
	for s: int in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		t += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _shot(from: Vector3, at: Vector3, file: String) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await _frames(3)
	var img: Image = get_viewport().get_texture().get_image()
	if img.get_width() > 960:
		img.resize(960, img.get_height() * 960 / img.get_width(), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(_out + file + ".jpg", 0.82)
