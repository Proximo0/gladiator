extends Node
## Wound marks on a standing training dummy, close up: scripted hits (cuts, stabs, blunt blows) land on the front of
## its torso, arms, thighs and head, then the marks age and the shots are saved. Checks how each kind of mark reads
## without depending on where a bot fight happens to land. Run in a real (xvfb) window:
## godot --path . --fixed-fps 60 --resolution 1280x720 res://tests/render/wound_lab.tscn -- --out=DIR --name=lab [--alien]
## Never part of the check suite; writes only the PNGs it is told to.

## [part, contact, cut, pierce, blunt, offset across the part (m, along its right), offset along the bone (m)]
const HITS: Array = [
	["torso", "edge", 24.0, 0.0, 2.0, -0.06, 0.08],
	["torso", "point", 3.0, 22.0, 0.0, 0.08, -0.06],
	["torso", "blunt", 0.0, 0.0, 30.0, 0.05, 0.14],
	["upper_arm_l", "edge", 14.0, 0.0, 1.0, 0.0, 0.0],
	["forearm_r", "blunt", 0.0, 0.0, 22.0, 0.0, 0.03],
	["thigh_l", "edge", 30.0, 0.0, 1.0, 0.0, 0.05],
	["thigh_r", "point", 2.0, 16.0, 0.0, 0.0, -0.04],
	["head", "blunt", 0.0, 0.0, 26.0, 0.04, 0.01],
	["pelvis", "edge", 10.0, 0.0, 0.0, -0.05, 0.0],
]

var _out: String = "/tmp/wound_lab/"
var _name: String = "lab"
var _alien: bool = false
var _match: Match = null
var _frame: int = 0
var _cam: Camera3D = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a == "--alien":
			_alien = true
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false
	var dummy: Dictionary = {"weapon": "fists", "offhand": "", "armor": {}}
	if _alien:
		dummy["outfit"] = "alien"
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "practice", "seed": 5, "loadouts": [{"weapon": "gladius", "offhand": "", "armor": {}}, dummy]})
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)


func _process(_d: float) -> void:
	_frame += 1
	if _match == null or _match.fighters.size() < 2:
		return
	if _frame == 60:
		_hit_all()
	if _frame == 60 + 360:  # 6 s: the trickles have run
		_aim(1.7, 0.95)
		RenderingServer.render_loop_enabled = true
	elif _frame == 424:
		_save("body")
		_aim(0.75, 1.3)
	elif _frame == 428:
		_save("torso")
		_match.presenter.blood.visible = false  # marks only: no droplets, mist or BloodFx's body stain quads
		for part: Node in (_match.fighters[1] as Fighter).parts.values():
			for c: Node in part.get_children():
				if c is MeshInstance3D and c.has_meta("born"):
					(c as MeshInstance3D).visible = false
		_aim(0.75, 1.3)
	elif _frame == 432:
		_save("marks_torso")
		_aim(1.7, 0.95)
	elif _frame == 436:
		_save("marks")
		var atk: Fighter = _match.fighters[0]
		var hand: Vector3 = atk.fist_r.global_position
		_cam.global_position = hand + (_lit_side() * 0.5 + Vector3(0, 0.25, 0))
		_cam.look_at(hand.lerp(atk.weapon.tip_position(), 0.35), Vector3.UP)
	elif _frame == 440:
		_save("hands")
		get_tree().quit()


func _hit_all() -> void:
	var f: Fighter = _match.fighters[1]
	var atk: Fighter = _match.fighters[0]
	for h: Array in HITS:
		var b: Node3D = f.parts[str(h[0])]
		var front: Vector3 = _lit_side()  # the side facing the sun, where the camera looks from
		var up: Vector3 = b.global_transform.basis.y
		var right: Vector3 = up.cross(front).normalized()
		var p: Vector3 = b.global_position + front * 0.3 + right * float(h[5]) + up * float(h[6])
		var ev: Dictionary = {"attacker": atk.side, "target": f.side, "part": str(h[0]), "contact": str(h[1]),
			"point": p, "normal": -front, "rel_vel": (right * 0.8 - up * 0.6) * 9.0 - front * 2.0,
			"cut": float(h[2]), "pierce": float(h[3]), "blunt": float(h[4]),
			"total": float(h[2]) + float(h[3]) + float(h[4]), "weapon_id": "gladius"}
		f.hit.emit(ev)
	for k: int in 6:  # punches: the attacker's right fist gets bloody knuckles
		var head: Node3D = f.parts["head"]
		var fist: Node3D = atk.fist_r
		var pt: Vector3 = fist.global_position + (head.global_position - fist.global_position).normalized() * 0.05
		f.hit.emit({"attacker": atk.side, "target": f.side, "part": "head", "contact": "blunt", "point": pt,
			"normal": Vector3.FORWARD, "rel_vel": Vector3(0, 0, -6), "cut": 0.0, "pierce": 0.0, "blunt": 24.0,
			"total": 24.0, "weapon_id": "fists"})


func _aim(dist: float, height: float) -> void:
	var f: Fighter = _match.fighters[1]
	var t: Node3D = f.parts["torso"]
	var at: Vector3 = t.global_position + Vector3(0, height - 1.33, 0)
	var front: Vector3 = _lit_side()
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	_cam.keep_aspect = Camera3D.KEEP_WIDTH if vp.y > vp.x else Camera3D.KEEP_HEIGHT
	_cam.global_position = at + front.rotated(Vector3.UP, 0.3) * dist + Vector3(0, 0.15, 0)
	_cam.look_at(at, Vector3.UP)
	_cam.current = true
	var p: MatchPresenter = _match.presenter
	if p != null and p.hud != null:
		p.hud.visible = false
	if p != null and p.aim != null:
		p.aim.visible = false


## Flat direction toward the sun (the arena's DirectionalLight3D), so the marked side is lit.
func _lit_side() -> Vector3:
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var z: Vector3 = (n as Node3D).global_transform.basis.z
		z.y = 0.0
		if z.length() > 0.01:
			return z.normalized()
	return Vector3.BACK


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
