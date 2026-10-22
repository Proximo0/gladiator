extends Node
## Accumulated-damage renders: a seeded presented bot fight runs headless-fast (only saved frames are drawn), then
## close-ups of both fighters and their weapons are saved. Run in a real (xvfb) window:
## godot --path . --fixed-fps 60 --resolution 1280x720 res://tests/render/wound_capture.tscn -- --out=DIR --name=wide
## Options: --seed=N, --secs=20, --alien (side 1 wears the alien outfit). Never part of the check suite; writes only
## the PNGs it is told to.

const SHOTS: Array = [["cam", 0, 0.0], ["f0", 0, 1.25], ["f1", 1, 1.25], ["w0", 0, 0.55], ["w1", 1, 0.55]]  ## cam: the fight camera

var _out: String = "/tmp/wound_capture/"
var _name: String = "shot"
var _seed: int = 7
var _secs: float = 20.0
var _alien: bool = false
var _match: Match = null
var _frame: int = 0
var _cam: Camera3D = null
var _shot: int = -1
var _shot_frame: int = 0
var _end_tick: int = -1


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a == "--alien":
			_alien = true
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	var lo0: Dictionary = {"weapon": "gladius", "offhand": "", "armor": {"head": "helm_leather"}}
	var lo1: Dictionary = {"weapon": "club", "offhand": "", "armor": {"torso": "cuirass_leather"}}
	if _alien:
		lo1["outfit"] = "alien"
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": _seed, "loadouts": [lo0, lo1], "loop": false, "time_limit_s": 600.0})
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)


func _process(_d: float) -> void:
	_frame += 1
	if _match == null or _match.fighters.size() < 2:
		return
	if _shot < 0:
		# Keyed on the fight: the time is up, or the match is over and the loser has had 1.5 s to fall (frames, since
		# the match tick may stop at the end).
		var done: bool = _match.tick >= int(_secs * 60.0) or (_match.over and _end_tick >= 0 and _frame > _end_tick + 90)
		if _match.over and _end_tick < 0:
			_end_tick = _frame
		if _frame % 300 == 0:
			print("WOUNDCAP tick ", _match.tick)
		if done:
			print("WOUNDCAP fight ticks=", _match.tick, " over=", _match.over, " result=", _match.result.get("reason", ""))
			_shot = 0
			_shot_frame = _frame
			_hide_ui()
			_report()
		return
	var spec: Array = SHOTS[_shot]
	if _frame == _shot_frame + 1:
		if str(spec[0]) == "cam":
			_match.presenter.camera.current = true
		else:
			_aim(int(spec[1]), float(spec[2]), str(spec[0]).begins_with("w"))
		RenderingServer.render_loop_enabled = true
	elif _frame == _shot_frame + 4:
		_save(str(spec[0]))
		RenderingServer.render_loop_enabled = false
		_shot += 1
		_shot_frame = _frame
		if _shot >= SHOTS.size():
			get_tree().quit()


## Marks and coats per fighter (when the tree has WoundFx; the before-tree prints nothing), and the BloodFx stain quads
## left on each fighter's body parts.
func _report() -> void:
	for side: int in 2:
		var quads: int = 0
		for b: Variant in (_match.fighters[side] as Fighter).parts.values():
			quads += ((b as Node).get_meta("bfx_stains", []) as Array).size()
		print("WOUNDCAP side=%d body_stain_quads=%d" % [side, quads])
	var wfx: Variant = _match.presenter.get("wounds") if _match.presenter != null else null
	if not (wfx is Node):
		return
	for side: int in 2:
		var wm: Variant = (wfx as Node).call("marks_of", side)
		var by: Dictionary = {}
		for part: String in (wm as Object).get("marks"):
			for m: Object in (wm as Object).get("marks")[part]:
				var k: int = int(m.get("kind"))
				by[k] = int(by.get(k, 0)) + 1
		var f: Fighter = _match.fighters[side]
		var coats: Array = []
		for w: Variant in [f.weapon, f.fist_r, f.fist_l]:
			if w != null:
				var c: Variant = (wfx as Node).call("coat_of", w)
				coats.append("%s=%.2f" % [(w as Weapon).weapon_id, float((c as Object).get("coat")) if c != null else 0.0])
		print("WOUNDCAP side=%d marks=%d kinds(gash,punct,bruise,smear)=%s parts=%s coats=%s shells=%d" % [side,
				(wm as Object).call("count", ""), str(by), str(((wm as Object).get("marks") as Dictionary).keys()),
				" ".join(coats), int((wfx as Object).get("stat_shells"))])


func _hide_ui() -> void:
	var p: MatchPresenter = _match.presenter
	if p != null and p.hud != null:
		p.hud.visible = false
	if p != null and p.aim != null:
		p.aim.visible = false


## Points the capture camera at fighter `side` (its torso, or its weapon when `weapon`) from `dist` metres, on the
## opponent's side so the front (where the hits land) is in view.
func _aim(side: int, dist: float, weapon: bool) -> void:
	var f: Fighter = _match.fighters[side]
	var o: Fighter = _match.fighters[1 - side]
	var at: Vector3 = (f.parts["torso"] as Node3D).global_position
	if weapon:
		var w: Node3D = f.weapon if f.weapon != null else f.fist_r
		at = (w.global_position + w.global_transform * Vector3(0, w.get("tip_local").y * 0.6, 0)) * 0.5
	# In front of the fighter (its torso's -Z), a little to the side; straight above when it lies in the sand.
	var dir: Vector3 = -(f.parts["torso"] as Node3D).global_transform.basis.z
	dir.y = 0.0
	if dir.length() < 0.3:
		dir = (o.parts["torso"] as Node3D).global_position - at
		dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	# Swing toward the sun so the front is lit, not a backlit silhouette.
	var sun: Vector3 = _sun_dir()
	dir = (dir + sun * 0.9).normalized() if (dir + sun * 0.9).length() > 0.2 else dir.rotated(Vector3.UP, 0.35)
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	_cam.keep_aspect = Camera3D.KEEP_WIDTH if vp.y > vp.x else Camera3D.KEEP_HEIGHT
	var lying: bool = (f.parts["torso"] as Node3D).global_position.y < 0.7
	_cam.global_position = at + (dir * 0.45 + Vector3(0, 0.95, 0)) * dist if lying else at + dir * dist + Vector3(0, 0.25 * dist, 0)
	_cam.look_at(at, Vector3.UP)
	_cam.current = true


## Flat direction toward the arena's sun (zero when there is none).
func _sun_dir() -> Vector3:
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var z: Vector3 = (n as Node3D).global_transform.basis.z
		z.y = 0.0
		return z.normalized() if z.length() > 0.01 else Vector3.ZERO
	return Vector3.ZERO


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
