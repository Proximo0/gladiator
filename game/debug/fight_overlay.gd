class_name FightOverlay
extends Node3D
## Fight debug overlay, built in code. F1 shows or hides it. Shown, it has a text readout per fighter (state,
## balance, stamina, consciousness, blood, tip speed, weapon, grip, the brain's state) and 3D markers: hand target
## and hand, a 0.5 s tip trail coloured by speed, contact points flashing by contact kind (from the `hit` signal),
## knockback arrows, and the guard plane. F2 slow motion (Engine.time_scale 0.25). F3 freeze (get_tree().paused,
## this node processes always). "." advances one physics step while frozen. It only reads fighters
## (debug_frame, the hit signal) and never changes gameplay. Attach with attach(fighters); `brains` maps each
## Fighter to its FighterBrain for the state name. Times come from physics frames, so a frozen fight stays still.

const TOGGLE_SHOW: StringName = &"debug_overlay"
const TOGGLE_SLOWMO: StringName = &"debug_slowmo"
const TOGGLE_FREEZE: StringName = &"debug_freeze"
const TOGGLE_STEP: StringName = &"debug_step"
const LAYER: int = 99
const FONT_PX: int = 15
const MARGIN_PX: float = 8.0
const PLATE_COLOR := Color(0.05, 0.06, 0.09, 0.82)
const SIDE_COLORS: Array = [Color(1.0, 0.72, 0.6), Color(0.6, 0.78, 1.0)]
const STATUS_COLOR := Color(0.95, 0.95, 0.92)
## Runs after the fighters (their physics priority is 10), so a stepped tick is complete before the re-freeze.
const LAST_PRIORITY: int = 1000
const HIT_KEEP: int = 64
## Distance from the torso centre to the guard origin, as in Fighter._arms (chest lift and guard drop).
const CHEST_LIFT_M: float = 0.1
const GUARD_DROP_M: float = 0.05

var fighters: Array = []
var brains: Dictionary = {}
var shown: bool = false

var _hud: CanvasLayer = null
var _labels: Array[Label] = []
var _status: Label = null
var _mesh: MeshInstance3D = null
var _im: ImmediateMesh = null
var _mat: StandardMaterial3D = null
var _trails: Dictionary = {}
var _contacts: Array = []
var _knocks: Array = []
var _segs := PackedVector3Array()
var _cols := PackedColorArray()
var _slowmo: bool = false
var _froze: bool = false
var _step_pending: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = LAST_PRIORITY
	_build_hud()
	_build_mesh()
	set_shown(shown)


func _exit_tree() -> void:
	if _slowmo:
		Engine.time_scale = 1.0
		_slowmo = false
	if _froze and is_inside_tree() and get_tree().paused:
		get_tree().paused = false
		_froze = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_SHOW):
		set_shown(not shown)
	elif event.is_action_pressed(TOGGLE_SLOWMO):
		set_slowmo(not _slowmo)
	elif event.is_action_pressed(TOGGLE_FREEZE):
		set_frozen(not get_tree().paused)
	elif event.is_action_pressed(TOGGLE_STEP):
		step_once()
	else:
		return
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var stepped: bool = _step_pending
	_step_pending = false
	if shown and not get_tree().paused:
		_sample()
	if stepped:
		get_tree().paused = true


func _process(_delta: float) -> void:
	if _status != null:
		_status.text = OverlayDraw.format_status(_slowmo, get_tree().paused)
	if not shown:
		return
	_update_text()
	_redraw()


## Registers the fighters and listens to their `hit` signals. Call again to replace the list.
func attach(list: Array) -> void:
	for f: Variant in fighters:
		var old: Fighter = _as_fighter(f)
		if old != null and old.hit.is_connected(_on_hit):
			old.hit.disconnect(_on_hit)
	fighters = list.duplicate()
	for f: Variant in fighters:
		var fi: Fighter = _as_fighter(f)
		if fi != null and not fi.hit.is_connected(_on_hit):
			fi.hit.connect(_on_hit)


func _as_fighter(f: Variant) -> Fighter:
	if not is_instance_valid(f):
		return null
	return f as Fighter


func set_shown(on: bool) -> void:
	shown = on
	if _hud != null:
		_hud.visible = on
	if _mesh != null:
		_mesh.visible = on
	if not on:
		_trails.clear()
		_contacts.clear()
		_knocks.clear()
		if _im != null:
			_im.clear_surfaces()


func set_slowmo(on: bool) -> void:
	_slowmo = on
	Engine.time_scale = OverlayDraw.time_scale_for(on)


func set_frozen(on: bool) -> void:
	_froze = on
	get_tree().paused = on
	if not on:
		_step_pending = false


## While frozen, runs exactly one physics tick: unpauses for this frame, and _physics_process pauses again after it.
func step_once() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	_step_pending = true


func _on_hit(ev: Dictionary) -> void:
	var now: int = Engine.get_physics_frames()
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	_contacts.append({"pos": p, "kind": str(ev.get("contact", "")), "frame": now})
	while _contacts.size() > HIT_KEEP:
		_contacts.pop_front()
	var kb: Vector3 = ev.get("knockback", Vector3.ZERO)
	if kb.length_squared() > 0.0:
		var shown_kb: Vector3 = kb * Tuning.shared().knockback_scale
		_knocks.append({"from": p, "vec": shown_kb.normalized() * OverlayDraw.knock_length(shown_kb.length()),
			"frame": now})
		while _knocks.size() > HIT_KEEP:
			_knocks.pop_front()


## Physics-frame sample of each fighter's tip for the trail; prunes what is older than the trail life.
func _sample() -> void:
	var now: int = Engine.get_physics_frames()
	var tps: float = float(Engine.physics_ticks_per_second)
	for f: Variant in fighters:
		var fi: Fighter = _live(f)
		if fi == null:
			continue
		var d: Dictionary = fi.debug_frame()
		var trail: Array = _trails.get(fi, [])
		trail.append({"pos": d["tip_pos"], "speed": d["tip_speed"], "frame": now})
		while trail.size() > 0 and OverlayDraw.age_s(now, int(trail[0]["frame"]), tps) > OverlayDraw.TRAIL_LIFE_S:
			trail.pop_front()
		_trails[fi] = trail
	_prune(_contacts, OverlayDraw.CONTACT_LIFE_S, now, tps)
	_prune(_knocks, OverlayDraw.KNOCK_LIFE_S, now, tps)


func _prune(list: Array, life: float, now: int, tps: float) -> void:
	while list.size() > 0 and OverlayDraw.age_s(now, int(list[0]["frame"]), tps) > life:
		list.pop_front()


## The fighter if it is alive, in the tree and built; null otherwise.
func _live(f: Variant) -> Fighter:
	if not is_instance_valid(f):
		return null
	var fi: Fighter = f as Fighter
	if fi == null or not fi.is_inside_tree() or fi.parts.is_empty():
		return null
	return fi


func _update_text() -> void:
	for i: int in _labels.size():
		var fi: Fighter = _live(fighters[i]) if i < fighters.size() else null
		if fi == null:
			_labels[i].text = "P%d  -" % (i + 1)
			continue
		var brain: FighterBrain = brains.get(fi) as FighterBrain
		var brain_state: String = brain.state_name() if brain != null else ""
		_labels[i].text = OverlayDraw.format_fighter(fi.debug_frame(), brain_state)


func _redraw() -> void:
	_segs = PackedVector3Array()
	_cols = PackedColorArray()
	var now: int = Engine.get_physics_frames()
	var tps: float = float(Engine.physics_ticks_per_second)
	for f: Variant in fighters:
		var fi: Fighter = _live(f)
		if fi == null:
			continue
		var d: Dictionary = fi.debug_frame()
		_put(_guard_corners(fi, d), OverlayDraw.GUARD_COLOR)
		var target: Vector3 = d["hand_target"]
		var hand: Vector3 = d["hand_pos"]
		_put(OverlayDraw.cross(target, OverlayDraw.HAND_MARK_M), OverlayDraw.TARGET_COLOR)
		_put(OverlayDraw.cross(hand, OverlayDraw.HAND_MARK_M * 0.8), OverlayDraw.HAND_COLOR)
		_put(PackedVector3Array([target, hand]), OverlayDraw.GAP_COLOR)
		var trail: Array = _trails.get(fi, [])
		_put_trail(trail, now, tps)
	for c: Dictionary in _contacts:
		var age: float = OverlayDraw.age_s(now, int(c["frame"]), tps)
		var alpha: float = OverlayDraw.flash_alpha(age, OverlayDraw.CONTACT_LIFE_S)
		if alpha <= 0.0:
			continue
		var col: Color = OverlayDraw.contact_color(str(c["kind"]))
		col.a = alpha
		var size: float = OverlayDraw.CONTACT_MARK_M * (1.0 + OverlayDraw.fade(age, OverlayDraw.CONTACT_LIFE_S))
		_put(OverlayDraw.cross(c["pos"], size), col)
	for k: Dictionary in _knocks:
		var age: float = OverlayDraw.age_s(now, int(k["frame"]), tps)
		var col: Color = OverlayDraw.KNOCK_COLOR
		col.a = OverlayDraw.fade(age, OverlayDraw.KNOCK_LIFE_S)
		if col.a > 0.0:
			_put(OverlayDraw.arrow(k["from"], k["vec"]), col)
	OverlayDraw.emit(_im, _mat, _segs, _cols)


func _put(segs: PackedVector3Array, col: Color) -> void:
	_segs.append_array(segs)
	_cols.append_array(OverlayDraw.paint(segs, col))


func _put_trail(trail: Array, now: int, tps: float) -> void:
	var points := PackedVector3Array()
	var speeds := PackedFloat32Array()
	var ages := PackedFloat32Array()
	for s: Dictionary in trail:
		points.append(s["pos"])
		speeds.append(float(s["speed"]))
		ages.append(OverlayDraw.age_s(now, int(s["frame"]), tps))
	var t: Dictionary = OverlayDraw.trail(points, speeds, ages)
	_segs.append_array(t["segs"])
	_cols.append_array(t["cols"])


## The guard plane at the fighter's guard origin, as in Fighter._arms (aim 0, no thrust).
func _guard_corners(fi: Fighter, d: Dictionary) -> PackedVector3Array:
	var yaw: float = float(d.get("facing_yaw", 0.0))
	var yb := Basis(Vector3.UP, yaw)
	var fwd: Vector3 = -yb.z
	var torso: RigidBody3D = fi.parts.get("torso") as RigidBody3D
	var t: Tuning = Tuning.shared()
	var chest: Vector3 = torso.global_position + Vector3.UP * CHEST_LIFT_M
	var origin: Vector3 = chest + fwd * t.guard_forward - Vector3.UP * GUARD_DROP_M
	return OverlayDraw.guard_corners(origin, yb.x, Vector3.UP, t.guard_width, t.guard_height)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = LAYER
	add_child(_hud)
	_labels = []
	for i: int in 2:
		var lab: Label = _plate(i == 1)
		lab.add_theme_color_override("font_color", SIDE_COLORS[i])
		_labels.append(lab)
	_status = _plate(false, true)
	_status.add_theme_color_override("font_color", STATUS_COLOR)


## A dark plate with one label. Left and right plates sit in the top corners, the status plate at top centre.
func _plate(right_side: bool, centred: bool = false) -> Label:
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PLATE_COLOR
	style.set_content_margin_all(6.0)
	plate.add_theme_stylebox_override("panel", style)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.anchor_top = 0.0
	plate.anchor_bottom = 0.0
	plate.offset_top = MARGIN_PX
	if centred:
		plate.anchor_left = 0.5
		plate.anchor_right = 0.5
		plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	elif right_side:
		plate.anchor_left = 1.0
		plate.anchor_right = 1.0
		plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		plate.offset_right = -MARGIN_PX
	else:
		plate.anchor_left = 0.0
		plate.anchor_right = 0.0
		plate.offset_left = MARGIN_PX
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", FONT_PX)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(lab)
	_hud.add_child(plate)
	return lab


func _build_mesh() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	_mesh.top_level = true
	_mesh.extra_cull_margin = 1000.0
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
