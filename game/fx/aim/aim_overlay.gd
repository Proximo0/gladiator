class_name AimOverlay
extends CanvasLayer
## Local-only aim aid for the human fighter, drawn over the 3D view: a soft trail, a ring at the weapon tip, a faint
## line along the weapon, a reticle where the hand is being steered, and, once disarmed, a weapon-lost prompt with an
## arrow to the nearest loose weapon. Never shown for the opponent, never sent online (it only reads the fighter).
## Switched off by FeelOptions.aim_aid. Sizes are screen pixels so it reads the same on a phone and a monitor.

const AIM_LAYER: int = 9  ## Under the HUD (10).
const TIP_R_PX: float = 9.0
const RETICLE_R_PX: float = 15.0
const LINE_PX: float = 3.0
const TRAIL_PX: float = 9.0
const ARROW_PX: float = 26.0
const EDGE_PX: float = 56.0
const PROMPT_PX: float = 30.0
const PROMPT_SUB_PX: float = 19.0
const TIP_COLOR: Color = Color(1.0, 0.86, 0.45)
const RETICLE_COLOR: Color = Color(0.55, 0.9, 1.0)
const LOST_COLOR: Color = Color(1.0, 0.55, 0.25)
const SHADOW: Color = Color(0.05, 0.03, 0.02, 0.7)
## Plate baseline, as a share of the viewport height. Landscape: over the crowd, between the controls hint (top) and the
## HUD banner (top at 0.24). Portrait: under the banner (it ends near 0.31) and above the fighters, clear of the
## meters, the pause button and the practice card.
const PROMPT_Y_LAND: float = 0.17
const PROMPT_Y_PORTRAIT: float = 0.355
const MIN_SHAFT_M: float = 0.25

var fighter: Fighter = null
var camera: Camera3D = null
var _canvas: Control = null
var _trail: AimLogic = AimLogic.new()
var _was_armed: bool = false
var _lost_s: float = 0.0
var _pad_last: bool = false
var _t: float = 0.0


func _init() -> void:
	layer = AIM_LAYER
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_aid)
	add_child(_canvas)


func bind(f: Fighter, cam: Camera3D) -> void:
	fighter = f
	camera = cam
	_trail.clear()
	_was_armed = false
	_lost_s = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_pad_last = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad_last = false


func device() -> String:
	if TouchControls.active():
		return "touch"
	return "pad" if _pad_last else "kbm"


func _usable() -> bool:
	return FeelOptions.aim_aid and fighter != null and is_instance_valid(fighter) and camera != null and is_instance_valid(camera) \
			and fighter.is_inside_tree() and camera.is_inside_tree()


func _process(delta: float) -> void:
	_t += delta
	if not _usable():
		_canvas.visible = false
		return
	_canvas.visible = true
	var tun: Tuning = Tuning.shared()
	var w: Weapon = fighter.weapon
	var armed: bool = w != null and not w.is_fist
	_lost_s = AimLogic.lost_time(_lost_s, _was_armed, armed, delta)
	_was_armed = _was_armed or armed
	_trail.max_age = tun.aim_trail_s
	var tip_w: Weapon = w if w != null else fighter.fist_r
	if tip_w != null and not _fighter_down():
		_trail.push(tip_w.tip_position(), delta)
	else:
		_trail.clear()
	_canvas.queue_redraw()


func _fighter_down() -> bool:
	var st: String = fighter.state_name()
	return st == "dead" or st == "ko"


## Pixels per layout unit (the project stretches a 1920x1080 design), so a size in px stays the same on screen.
func _unit() -> float:
	var k: float = _canvas.get_viewport().get_final_transform().get_scale().x
	return 1.0 / maxf(k, 0.0001)


func _project(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func _draw_aid() -> void:
	if not _usable():
		return
	var u: float = _unit()
	var tun: Tuning = Tuning.shared()
	var a: float = tun.aim_alpha
	var vp: Vector2 = _canvas.get_viewport_rect().size
	if not _fighter_down():
		_draw_weapon_aid(u, a)
	if AimLogic.prompt_due(_lost_s, tun.aim_lost_delay_s, not _fighter_down()):
		_draw_lost(u, vp, a)


func _draw_weapon_aid(u: float, a: float) -> void:
	var w: Weapon = fighter.weapon if fighter.weapon != null else fighter.fist_r
	if w == null:
		return
	var tip3: Vector3 = w.tip_position()
	if camera.is_position_behind(tip3):
		return
	var tip: Vector2 = _project(tip3)
	# The trail: older samples thinner and fainter.
	var n: int = _trail.count()
	var prev: Vector2 = Vector2.ZERO
	for i: int in n:
		var p3: Vector3 = _trail.point(i)
		if camera.is_position_behind(p3):
			continue
		var p: Vector2 = _project(p3)
		if i > 0 and prev != Vector2.ZERO:
			var f: float = 1.0 - _trail.age_frac(i)
			_canvas.draw_line(prev, p, Color(TIP_COLOR, 0.55 * a * f), TRAIL_PX * u * f + 1.0, true)
		prev = p
	# A faint line along the weapon so its direction reads against the sand.
	var grip3: Vector3 = w.global_position
	if grip3.distance_to(tip3) > MIN_SHAFT_M and not camera.is_position_behind(grip3):
		var g: Vector2 = _project(grip3)
		_canvas.draw_line(g, tip, Color(SHADOW, 0.35 * a), (LINE_PX + 2.0) * u, true)
		_canvas.draw_line(g, tip, Color(TIP_COLOR, 0.5 * a), LINE_PX * u, true)
	# Tip marker: dark ring under a bright one.
	_canvas.draw_arc(tip, TIP_R_PX * u, 0.0, TAU, 20, Color(SHADOW, a), 4.0 * u, true)
	_canvas.draw_arc(tip, TIP_R_PX * u, 0.0, TAU, 20, Color(TIP_COLOR, a), 2.5 * u, true)
	_canvas.draw_circle(tip, 2.5 * u, Color(TIP_COLOR, a))
	# Hand reticle: where the hand is being steered (the target), a line from the hand when it lags behind.
	var target: Vector3 = fighter.hand_target()
	if target != Vector3.ZERO and not camera.is_position_behind(target):
		var tp: Vector2 = _project(target)
		var r: float = RETICLE_R_PX * u
		_canvas.draw_arc(tp, r, 0.0, TAU, 28, Color(SHADOW, a), 4.0 * u, true)
		_canvas.draw_arc(tp, r, 0.0, TAU, 28, Color(RETICLE_COLOR, a), 2.0 * u, true)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_canvas.draw_line(tp + d * r * 0.45, tp + d * r * 1.35, Color(RETICLE_COLOR, a), 2.0 * u, true)


func _nearest_prop() -> Weapon:
	var props: Array = []
	var ws: Array[Weapon] = []
	for n: Node in fighter.get_tree().get_nodes_in_group(Weapon.PROP_GROUP):
		var pw: Weapon = n as Weapon
		if pw == null or pw.is_fist or pw.holder != null or pw.lodged_in != null:
			continue
		ws.append(pw)
		props.append(pw.global_position)
	var i: int = AimLogic.nearest((fighter.parts["pelvis"] as Node3D).global_position, props)
	return ws[i] if i >= 0 else null


func _draw_lost(u: float, vp: Vector2, a: float) -> void:
	var font: Font = MenuTheme.caps_font()
	var pulse: float = 0.75 + 0.25 * sin(_t * 6.0)
	var dev: String = device()
	var c: Color = Color(LOST_COLOR, a)
	var title: String = "WEAPON LOST"
	var tf: int = roundi(PROMPT_PX * u)
	var sf: int = roundi(PROMPT_SUB_PX * u)
	var y: float = vp.y * (PROMPT_Y_PORTRAIT if vp.x < vp.y else PROMPT_Y_LAND)
	var sub: String = AimLogic.pickup_hint(dev)
	var plate_w: float = maxf(font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sf).x, font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tf).x) + 36.0 * u
	var plate: Rect2 = Rect2(vp.x * 0.5 - plate_w * 0.5, y - float(tf) * 1.05, plate_w, float(tf + sf) * 1.35 + 20.0 * u)
	_canvas.draw_rect(plate, Color(0.07, 0.05, 0.03, 0.72 * a))
	_canvas.draw_rect(plate, Color(LOST_COLOR, 0.8 * a), false, 2.0 * u)
	for line: Array in [[title, tf, c], [sub, sf, Color(0.95, 0.9, 0.78, a)]]:
		var txt: String = line[0]
		var px: int = line[1]
		var wd: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		var pos: Vector2 = Vector2(vp.x * 0.5 - wd * 0.5, y)
		_canvas.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, roundi(6.0 * u), SHADOW)
		_canvas.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, line[2])
		y += float(px) * 1.35
	var prop: Weapon = _nearest_prop()
	if prop == null:
		return
	var p3: Vector3 = prop.global_position
	var m: Dictionary = AimLogic.edge_marker(_project(p3), camera.is_position_behind(p3), vp, EDGE_PX * u)
	var pos2: Vector2 = m["pos"]
	var ang: float = float(m["angle"])
	var dist: float = p3.distance_to((fighter.parts["pelvis"] as Node3D).global_position)
	var s: float = ARROW_PX * u * pulse
	var dir: Vector2 = Vector2.from_angle(ang)
	if bool(m["on_screen"]):
		dir = Vector2.DOWN  # on screen: a chevron above the weapon pointing down at it
		pos2 += Vector2(0.0, -s * 1.6)
	var side: Vector2 = dir.orthogonal()
	var tri: PackedVector2Array = PackedVector2Array([pos2 + dir * s, pos2 - dir * s * 0.6 + side * s * 0.7, pos2 - dir * s * 0.6 - side * s * 0.7])
	_canvas.draw_colored_polygon(tri, c)
	_canvas.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), SHADOW, 3.0 * u, true)
	var label: String = "%s  %.0f m" % [prop.weapon_id.to_upper(), dist] if dist >= 1.0 else prop.weapon_id.to_upper()
	var lf: int = roundi(PROMPT_SUB_PX * u)
	var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, lf).x
	var lp: Vector2 = pos2 - dir * s * 1.6 - Vector2(lw * 0.5, -float(lf) * 0.35)
	lp.x = clampf(lp.x, 8.0 * u, vp.x - lw - 8.0 * u)
	lp.y = clampf(lp.y, float(lf) + 8.0 * u, vp.y - 8.0 * u)
	_canvas.draw_rect(Rect2(lp + Vector2(-8.0 * u, -float(lf) * 1.05), Vector2(lw + 16.0 * u, float(lf) * 1.4)), Color(0.07, 0.05, 0.03, 0.7 * a))
	_canvas.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, lf, roundi(5.0 * u), SHADOW)
	_canvas.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, lf, Color(0.95, 0.9, 0.78, a))
