extends Node
## Houdini armor renders in the real (presented) arena: a fully armored gladiator (galea, manicae, greaves, iron
## cuirass, scutum) full length, close up and from behind, then the galea and a manica knocked off onto the sand.
## Run in a real (xvfb) window:
## godot --path . --resolution 1280x720 res://tests/render/armor_capture.tscn -- --out=DIR --name=land
## Shots key on state (the fighter standing, the props at rest) with frame fallbacks. Never part of the check suite;
## writes only the PNGs it is told to.

const LOADOUT: Dictionary = {"weapon": "gladius", "offhand": "scutum", "armor": {"head": "helm_iron",
		"torso": "cuirass_iron", "upper_arm_l": "bracers_iron", "thigh_l": "greaves_iron"}}
const SHOTS: Array = [
	# [tag, part looked at, distance, height above the part, camera yaw from the fighter's front (rad)]
	["front", "pelvis", 2.9, 0.25, 0.35],
	["right", "pelvis", 2.6, 0.25, -1.4],
	["head", "head", 1.0, 0.0, -0.9],
	["arm", "forearm_r", 0.9, 0.0, -1.2],
	["shin", "shin_r", 1.0, 0.1, -0.6],
]

const MAX_SIDE: float = 560.0

var _out: String = "/tmp/armor_capture/"
var _name: String = "shot"
var _match: Match = null
var _cam: Camera3D = null
var _frame: int = 0
var _stage: String = "wait_stand"
var _stage_at: int = 0
var _shot: int = 0
var _save_at: int = -1
var _save_tag: String = ""
var _props: Array = []
var _prop_shot: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "practice", "seed": 4242, "presentation": true, "loop": false,
			"loadouts": [LOADOUT.duplicate(true), LOADOUT.duplicate(true)]})
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)


func _dummy() -> Fighter:
	return _match.fighters[1] as Fighter if _match.fighters.size() > 1 else null


func _process(_d: float) -> void:
	_frame += 1
	var f: Fighter = _dummy()
	if f == null:
		return
	if _save_at >= 0:
		_cam.make_current()
		if _frame >= _save_at:
			_save(_save_tag)
			_save_at = -1
			RenderingServer.render_loop_enabled = false
		return
	match _stage:
		"wait_stand":
			if (f.state() == "standing" and Engine.get_physics_frames() > 90) or Engine.get_physics_frames() > 600:
				_stage = "shots"
		"shots":
			if _shot < SHOTS.size():
				var s: Array = SHOTS[_shot]
				_aim_at_fighter(f, str(s[1]), float(s[2]), float(s[3]), float(s[4]))
				_queue(str(s[0]))
				_shot += 1
			else:
				f.call("_dislodge", "helm_iron", "head", Vector3(1, 0, 0.3))
				f.call("_dislodge", "bracers_iron", "forearm_r", Vector3(0.6, 0, -0.8))
				_stage = "wait_props"
				_stage_at = Engine.get_physics_frames()
		"wait_props":
			var props: Array = get_tree().get_nodes_in_group("armor_props")
			var resting: bool = not props.is_empty()
			for p: Node in props:
				if (p as RigidBody3D).linear_velocity.length() > 0.05:
					resting = false
			var ticks: int = Engine.get_physics_frames() - _stage_at  # physics ticks: frames run fast while not drawn
			if (resting and ticks > 60) or ticks > 600:
				_props = props
				_stage = "prop_shots"
		"prop_shots":
			if _prop_shot < _props.size():
				var pr: RigidBody3D = _props[_prop_shot] as RigidBody3D
				_aim_at_prop(pr, f)
				_queue("knocked_off_%d" % _prop_shot)
				_prop_shot += 1
			else:
				_stage = "done"
		"done":
			get_tree().quit()


func _aim_at_fighter(f: Fighter, part: String, dist: float, up: float, yaw: float) -> void:
	var at: Vector3 = (f.parts[part] as Node3D).global_position
	var torso: Node3D = f.parts["torso"] as Node3D
	var fwd: Vector3 = -torso.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var dir: Vector3 = fwd.rotated(Vector3.UP, yaw)
	var look: Vector3 = at + Vector3.UP * up
	_cam.global_position = look + dir * dist + Vector3.UP * 0.15
	_cam.look_at(look, Vector3.UP)


## Looks down at one knocked-off piece from the side away from the fighter, so the fighter's feet sit behind it.
func _aim_at_prop(prop: Node3D, f: Fighter) -> void:
	var c: Vector3 = prop.global_position
	var away: Vector3 = c - (f.parts["pelvis"] as Node3D).global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.RIGHT
	_cam.global_position = c + away * 0.7 + Vector3.UP * 0.45
	_cam.look_at(c, Vector3.UP)


func _queue(tag: String) -> void:
	_cam.make_current()
	RenderingServer.render_loop_enabled = true
	_save_at = _frame + 4
	_save_tag = tag


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var k: float = minf(MAX_SIDE / float(maxi(img.get_width(), img.get_height())), 1.0)  # keeps a PNG near 300 KB
	img.resize(roundi(img.get_width() * k), roundi(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	var path: String = "%s%s_%s.png" % [_out, _name, tag]
	img.save_png(path)
	print("ARMORCAP saved ", path)
