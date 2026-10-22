class_name FighterWarmup
extends Node
## One-off shader warm-up (once per session): draws every outfit's body art, every weapon, every armor kind and the
## gore caps (glb caps and procedural faces of every outfit's blood palette) for a few frames in a small off-screen
## SubViewport with its own world (its own physics space: nothing touches the match). The Compatibility renderer
## compiles a material's shader on its first draw, so without this the first beheading or a weapon or outfit not
## seen before stalls a frame mid-fight. The drawn materials are kept for the session (`_kept`): Godot frees a
## StandardMaterial3D shader variant with its last user, and a later match would compile it again.
## Visual only. Start it with `FighterWarmup.start(parent)`; it frees itself when done.

const FRAMES: int = 8  ## frames drawn before the warm-up frees its scene (the blood needs a few to land)
const BLOOD_STEP: float = 0.05  ## blood seconds per warm-up frame, so drops fly, land and leave decals
const SIZE: int = 64

static var done: bool = false
static var _kept: Array[Material] = []

var _vp: SubViewport = null
var _frames: int = 0
var _blood: BloodFx = null
var _gored: Fighter = null


## Adds a warm-up under `parent` unless one already ran this session (or the run is headless). Returns it or null.
static func start(parent: Node) -> FighterWarmup:
	if done or parent == null or DisplayServer.get_name() == "headless":
		return null
	done = true
	var w := FighterWarmup.new()
	w.name = "FighterWarmup"
	parent.add_child(w)
	return w


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var main_env: Environment = get_viewport().find_world_3d().environment if get_viewport() != null else null
	var env := WorldEnvironment.new()
	env.environment = main_env if main_env != null else Environment.new()
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.4, 0.0)
	_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.0, 6.0)
	cam.fov = 100.0
	_vp.add_child(cam)
	cam.current = true
	_build_fighters()
	_build_weapons()
	_build_blood()


func _process(_delta: float) -> void:
	_frames += 1
	if _blood != null:
		_blood.step(BLOOD_STEP)
	if _frames < FRAMES:
		return
	_keep(_vp)
	set_process(false)
	queue_free()


## One fighter per outfit, wearing one armor piece of every kind it can, cut at the neck and the left elbow and knee
## so both caps of a cut show. Frozen, no control.
func _build_fighters() -> void:
	var armor: Dictionary = {}
	for aid: String in CombatData.armor_ids():
		for pn: Variant in CombatData.armor(aid).get("covers", []):
			if not armor.has(str(pn)):
				armor[str(pn)] = aid
				break
	var x: float = -2.0
	for oid: Variant in OutfitRules.ids():
		var f := Fighter.new()
		f.name = "Warm_%s" % str(oid)
		_vp.add_child(f)
		f.position = Vector3(x, 0.0, 0.0)
		x += 1.0
		f.setup(OutfitRules.with_outfit({"weapon": "fists", "offhand": "", "armor": armor}, str(oid)), 0, Tuning.shared())
		f.set_physics_process(false)
		f.set_process(false)
		for b: Variant in f.parts.values():
			(b as RigidBody3D).freeze = true
		for n: String in ["head", "forearm_l", "shin_l"]:
			f._art.cut(f.parts, n)
		if _gored == null:
			_gored = f


## The blood effects at the match's blood quality: a beheading fountain, a gut spill, a cut and a wound on one warm
## fighter, stepped every frame so droplets, mist, guts and ground decals all draw.
func _build_blood() -> void:
	if _gored == null:
		return
	_blood = BloodFx.new()
	_blood.name = "WarmBlood"
	_blood.auto_step = false
	_vp.add_child(_blood)
	_blood.set_quality(GfxQuality.blood_level())
	_blood.track(_gored)
	for kind: String in ["behead", "gut", "sever", "bleed"]:
		var part: String = {"behead": "head", "gut": "torso", "sever": "forearm_l", "bleed": "thigh_l"}[kind]
		var p: Vector3 = (_gored.parts[part] as Node3D).global_position
		_blood.on_gore({"kind": kind, "part": part, "point": p, "amount": 1.5, "normal": Vector3.BACK}, _gored)


## Every weapon and shield, frozen in a row above the fighters (lights on blades stay off: they would light the
## warm-up scene only).
func _build_weapons() -> void:
	var x: float = -3.0
	for wid: String in CombatData.weapon_ids():
		var d: Dictionary = CombatData.weapon(wid)
		if d.is_empty():
			continue
		var w := Weapon.new()
		w.name = "Warm_%s" % wid
		w.build(d, -1.0)
		w.freeze = true
		w.collision_layer = 0
		w.collision_mask = 0
		_vp.add_child(w)
		w.position = Vector3(x, 2.2, 0.0)
		x += 0.4
		for l: Node in w.find_children("*", "Light3D", true, false):
			(l as Light3D).visible = false


## Keeps every material drawn under `n` alive for the session (see the class note).
func _keep(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		_keep_mat(g.material_override)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for i: int in mi.mesh.get_surface_count():
					_keep_mat(mi.get_surface_override_material(i))
					_keep_mat(mi.mesh.surface_get_material(i))
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm: Mesh = (n as MultiMeshInstance3D).multimesh.mesh
			if mm != null:
				for i: int in mm.get_surface_count():
					_keep_mat(mm.surface_get_material(i))
	for c: Node in n.get_children():
		_keep(c)


func _keep_mat(m: Material) -> void:
	if m != null and not _kept.has(m):
		_kept.append(m)
