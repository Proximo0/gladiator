extends Node3D
## Sand depth renders: footprint trail, fall crater, sprint spray, strike spray. Run in a real (xvfb) window:
## godot --path . res://tests/render/sand_render.tscn -- --out=/mnt/project-files/renders/sand/ [--quality=2]
## Never part of the game or the check suite; writes only the PNGs it is told to.

var _sand: SandSurface
var _cam: Camera3D
var _out: String = "/tmp/sand_render/"
var _body_mat: StandardMaterial3D


func _ready() -> void:
	var q: int = 2
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--quality="):
			q = int(a.substr(10))
	GfxQuality.set_level(q)
	DirAccess.make_dir_recursive_absolute(_out)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.9, 0.8)
	env.ambient_light_energy = 0.55
	_cam = Camera3D.new()
	_cam.environment = env
	_cam.fov = 50.0
	add_child(_cam)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 50.0, 0.0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.93, 0.8)
	add_child(sun)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.55, 0.35, 0.3)
	_sand = SandSurface.new()
	add_child(_sand)
	_sand.setup(11.0)
	await _frames(3)
	await _footprints()
	await _crater()
	await _sprint()
	await _strike()
	print("RENDER done ", _out)
	get_tree().quit()


func _frames(k: int) -> void:
	for i in range(k):
		await get_tree().process_frame


func _look(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)


func _shot(name: String) -> void:
	await _frames(2)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(_out + name + ".png")


func _mesh(m: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _body_mat
	mi.position = pos
	mi.rotation_degrees = rot
	add_child(mi)
	return mi


func _foot(pos: Vector3, yaw: float, push: Vector3) -> void:
	_sand.stamp_ellipse(Vector3(pos.x, 0.0, pos.z), 0.06, 0.14, yaw, 0.018, push)


func _footprints() -> void:
	var x: float = -3.0
	var side: float = 1.0
	while x < 1.6:
		_foot(Vector3(x, 0, side * 0.16), PI * 0.5, Vector3(0.6, 0, 0))
		side = -side
		x += 0.34
		await _frames(2)
	# a knee and a heel drag
	_sand.stamp(Vector3(-0.6, 0, 0.9), 0.1, 0.03)
	_sand.drag(Vector3(0.6, 0, -0.7), Vector3(1.4, 0, -0.9), 0.07, 0.02)
	await _frames(30)
	_look(Vector3(-1.2, 1.5, 2.3), Vector3(-0.6, 0.0, 0.0))
	await _shot("footprints")


func _crater() -> void:
	var c: Vector3 = Vector3(0.0, 0, -4.0)
	var caps: CapsuleMesh = CapsuleMesh.new()
	caps.radius = 0.16
	caps.height = 0.9
	_sand.stamp_capsule(c + Vector3(-0.3, 0, 0.0), c + Vector3(0.3, 0, 0.1), 0.2, 0.062, Vector3(0.5, 0, 0))
	_sand.stamp_capsule(c + Vector3(0.1, 0, 0.1), c + Vector3(0.9, 0, 0.5), 0.1, 0.05)
	_mesh(caps, c + Vector3(0.0, 0.13, 0.05), Vector3(0, 0, 90))
	_mesh(caps, c + Vector3(0.5, 0.1, 0.3), Vector3(0, 0, 90)).scale = Vector3(0.7, 0.7, 0.7)
	await _frames(14)
	_look(c + Vector3(-1.0, 1.5, 2.0), c)
	await _shot("fall_crater")
	await _frames(60)
	await _shot("fall_crater_settled")


func _sprint() -> void:
	var p: Vector3 = Vector3(2.0, 0, 3.0)
	var caps: CapsuleMesh = CapsuleMesh.new()
	caps.radius = 0.2
	caps.height = 1.7
	var body: MeshInstance3D = _mesh(caps, p + Vector3(0, 0.9, 0))
	var side: float = 1.0
	var prev: Vector3 = p
	for i in range(54):
		p.x -= 0.075
		body.position = p + Vector3(0, 0.9, 0)
		var foot: Vector3 = p + Vector3(0.0, 0.0, side * 0.15)
		if i % 5 == 0:
			_foot(foot, PI * 0.5, Vector3(-1.0, 0, 0))
			side = -side
		_sand.drag(Vector3(prev.x, 0, prev.z + side * 0.15), Vector3(foot.x, 0, foot.z), 0.06, 0.012)
		prev = p
		await get_tree().process_frame
	_look(Vector3(p.x + 2.6, 1.7, p.z + 3.6), p + Vector3(0.9, 0.3, 0.0))
	await _frames(6)
	await _shot("sprint_spray")
	body.queue_free()


func _strike() -> void:
	var tip: Vector3 = Vector3(-4.0, 0, 3.0)
	var blade: CylinderMesh = CylinderMesh.new()
	blade.top_radius = 0.02
	blade.bottom_radius = 0.02
	blade.height = 1.2
	var sword: MeshInstance3D = _mesh(blade, tip + Vector3(-0.4, 0.55, 0.0), Vector3(0, 0, -30))
	_body_mat.albedo_color = Color(0.7, 0.72, 0.75)
	for i in range(14):
		var nt: Vector3 = tip + Vector3(0.14, 0, 0)
		_sand.drag(tip, nt, 0.025, 0.012)
		tip = nt
		await get_tree().process_frame
	_sand.spray(tip, Vector3(6, 0, 0), 1.0)
	_sand.stamp(tip, 0.06, 0.03)
	sword.position = tip + Vector3(-0.5, 0.5, 0)
	for i in range(8):
		await get_tree().process_frame
	_look(tip + Vector3(0.6, 0.9, 1.9), tip + Vector3(-0.3, 0.2, 0))
	await _shot("strike_spray")
