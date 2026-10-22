extends "res://tests/sim/sim_base.gd"
## Touch controls proven without a phone. Synthetic InputEventScreenTouch/Drag go through Input.parse_input_event
## (so Godot's touch-to-mouse emulation runs as on Android) into the real TouchControls under an "auto" InputReader
## (the phone's player-1 device), and the reader's FighterInput drives a real Fighter. Checks: thumbstick walking (no
## stray SWING), dead zone, hand target follows the drag like the same aim from keyboard/mouse, a flick swing reaches
## the longsword feel target (15-25 m/s, sim_fighter_core), swing reversal latency after an overshoot, ROLL, CROUCH,
## hold-GRAB pickup, two thumbs plus a button at once, no stuck fingers after app pause/resume or a paused tree, and
## every button reachable inside the safe area at three landscape and three portrait phone shapes.

const FIGHTER: String = "res://game/fighter/fighter.gd"
const PHONE: Vector2i = Vector2i(2400, 1080)  ## 20:9 landscape, the main scenario screen
## [name, window size, safe insets "l,t,r,b" in screen px]: notch on the left in landscape, on top in portrait.
const SHAPES: Array = [
	["land_16x9", Vector2i(1920, 1080), "0,0,0,0"],
	["land_20x9", Vector2i(2400, 1080), "96,0,0,48"],
	["land_21x9", Vector2i(2520, 1080), "120,0,40,40"],
	["port_16x9", Vector2i(1080, 1920), "0,0,0,0"],
	["port_19x9", Vector2i(1080, 2340), "0,110,0,60"],
	["port_20x9", Vector2i(1080, 2400), "0,130,0,48"],
]

var _reader: InputReader = null
var _tc: Control = null
var _saved_size: Vector2i = Vector2i.ZERO
var _saved_args: Dictionary = {}


func run() -> Array:
	var rows: Array = []
	var root: Window = host.get_tree().root
	_saved_size = root.size
	_saved_args = Flags.args.duplicate()
	Flags.args["touch"] = "1"
	rows.append_array(await _walk())
	rows.append_array(await _dead_zone())
	rows.append_array(await _hand_follows())
	rows.append_array(await _swing())
	rows.append_array(await _reversal())
	rows.append_array(await _roll())
	rows.append_array(await _crouch())
	rows.append_array(await _pickup())
	rows.append_array(await _multi_touch())
	rows.append_array(await _pause_resume())
	rows.append_array(await _layouts())
	Flags.args = _saved_args
	root.size = _saved_size
	await host.get_tree().process_frame
	return rows


# --- harness ---

func _setup(screen: Vector2i = PHONE) -> void:
	await sandbox()
	host.get_tree().root.size = screen
	_floor()
	_reader = InputReader.new()
	_reader.device = "auto"
	world.add_child(_reader)
	_tc = _reader.get("_touch") as Control
	await host.get_tree().process_frame


func _teardown() -> void:
	for i: int in range(6):
		_send_touch(i, Vector2.ZERO, false)
	_reader = null
	_tc = null
	await clear()


func _floor() -> void:
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	world.add_child(fb)


func _fighter(wid: String) -> Node3D:
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.setup({"weapon": wid, "offhand": "", "armor": {}}, 0, Tuning.new())
	return f


## Window pixels per layout unit (the 1920x1080 design is stretched to the window).
func _k() -> float:
	return host.get_tree().root.get_final_transform().get_scale().x


func _send_touch(index: int, layout_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = layout_pos * _k()
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _send_drag(index: int, layout_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = layout_pos * _k()
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _area() -> Vector2:
	return _tc.size


func _aim_r() -> float:
	return float(_tc.call("aim_radius")) if _tc.has_method("aim_radius") else minf(_area().x, _area().y) * 0.25


func _stick_r() -> float:
	return float(_tc.call("stick_radius")) if _tc.has_method("stick_radius") else minf(_area().x, _area().y) * 0.2


func _button(bit: int) -> Dictionary:
	for b: Dictionary in _tc.call("_layout"):
		if int(b["bit"]) == bit:
			return b
	return {}


## One tick: read the reader, drive the fighter (if any), step physics.
func _tick(f: Node3D) -> FighterInput:
	var inp: FighterInput = _reader.read()
	if f != null:
		f.apply_input(inp)
	await step(1)
	return inp


## Position along a straight finger path.
func _lerp_path(a: Vector2, b: Vector2, i: int, n: int) -> Vector2:
	return a.lerp(b, clampf(float(i) / float(maxi(n, 1)), 0.0, 1.0))


# --- scenarios ---

## Left thumb pushed straight up for 3 s: the fighter walks forward near move_speed, and no SWING leaks in from
## Godot's emulated left mouse button (the first finger down is also "the mouse").
func _walk() -> Array:
	await _setup()
	var f: Node3D = _fighter("longsword")
	var start := Vector2(_area().x * 0.2, _area().y * 0.65)
	var swing_ticks: int = 0
	var min_move_y: int = 1000
	var z0: float = 0.0
	for i: int in range(240):
		if i == 30:
			_send_touch(0, start, true)
			z0 = (f.debug_frame()["pelvis_pos"] as Vector3).z
		if i >= 30 and i < 40:
			_send_drag(0, _lerp_path(start, start + Vector2(0, -_stick_r()), i - 30, 9))
		var inp: FighterInput = await _tick(f)
		if i >= 40:
			min_move_y = mini(min_move_y, inp.move_y)
		if inp.has(FighterInput.SWING):
			swing_ticks += 1
	var dist: float = z0 - (f.debug_frame()["pelvis_pos"] as Vector3).z
	var speed: float = dist / (200.0 * DT)
	var tun := Tuning.new()
	await _teardown()
	var ok: bool = min_move_y >= 990 and speed >= tun.move_speed * 0.6 and swing_ticks == 0
	return [row("touch_walk", ok, "move_y>=%d speed=%.2f m/s (move_speed %.1f) swing_ticks=%d" % [min_move_y, speed, tun.move_speed, swing_ticks])]


## A resting thumb wobbles a few pixels: the stick and the aim must not drift.
func _dead_zone() -> Array:
	await _setup()
	var s := Vector2(_area().x * 0.2, _area().y * 0.6)
	var a := Vector2(_area().x * 0.7, _area().y * 0.35)
	_send_touch(0, s, true)
	_send_touch(1, a, true)
	var worst_move: int = 0
	var worst_aim: int = 0
	for i: int in range(12):
		var wob := Vector2(4.0 * sin(i * 1.7), 4.0 * cos(i * 2.3)) / _k()  # +-4 screen px
		_send_drag(0, s + wob)
		_send_drag(1, a + wob)
		var inp: FighterInput = await _tick(null)
		worst_move = maxi(worst_move, maxi(absi(inp.move_x), absi(inp.move_y)))
		worst_aim = maxi(worst_aim, maxi(absi(inp.aim_x), absi(inp.aim_y)))
	# Just past the dead zone the output starts from 0, not with a jump.
	_send_drag(0, s + Vector2(_stick_r() * 0.2, 0.0))
	var inp2: FighterInput = await _tick(null)
	await _teardown()
	var ok: bool = worst_move == 0 and worst_aim <= 30 and inp2.move_x > 0 and inp2.move_x < 300
	return [row("touch_dead_zone", ok, "4px wobble: move<=%d aim<=%d; 20%% push move_x=%d" % [worst_move, worst_aim, inp2.move_x])]


## Hand target (in the fighter's frame) for an aim finger dragged by `off` (in aim radii), against the same aim
## fed straight in as a FighterInput, the way the mouse produces it.
func _hand_at(off: Vector2, touch: bool) -> Array:
	await _setup()
	var f: Node3D = _fighter("longsword")
	var a := Vector2(_area().x * 0.72, _area().y * 0.45)
	var last := FighterInput.new()
	for i: int in range(90):
		var inp: FighterInput
		if touch:
			if i == 20:
				_send_touch(1, a, true)
			if i >= 20 and i < 30:
				_send_drag(1, _lerp_path(a, a + off * _aim_r(), i - 20, 9))
			inp = await _tick(f)
		else:
			inp = FighterInput.new()
			if i >= 20:
				var u: Vector2 = off.limit_length(1.0)
				inp.aim_x = roundi(u.x * 1000.0)
				inp.aim_y = roundi(-u.y * 1000.0)
				inp.buttons = FighterInput.SWING
			f.apply_input(inp)
			await step(1)
		last = inp
	var d: Dictionary = f.debug_frame()
	var local: Vector3 = (d["hand_target"] as Vector3) - (d["pelvis_pos"] as Vector3)
	await _teardown()
	return [local, last]


func _hand_follows() -> Array:
	var rows: Array = []
	var dirs: Dictionary = {"right": Vector2(1, 0), "left": Vector2(-1, 0), "up": Vector2(0, -1), "down": Vector2(0, 1)}
	var got: Dictionary = {}
	var worst: float = 0.0
	var info: PackedStringArray = []
	for n: String in dirs:
		var t: Array = await _hand_at(dirs[n], true)
		var k: Array = await _hand_at(dirs[n], false)
		got[n] = t[0]
		var gap: float = ((t[0] as Vector3) - (k[0] as Vector3)).length()
		worst = maxf(worst, gap)
		var ti: FighterInput = t[1]
		info.append("%s aim=(%d,%d) gap=%.3f" % [n, ti.aim_x, ti.aim_y, gap])
	var dir_ok: bool = (got["right"] as Vector3).x - (got["left"] as Vector3).x > 0.4 \
		and (got["up"] as Vector3).y - (got["down"] as Vector3).y > 0.4
	rows.append(row("touch_hand_follows_drag", dir_ok and worst < 0.05, "right-left=%.2f m up-down=%.2f m worst touch-vs-mouse gap=%.3f m; %s" % [
		(got["right"] as Vector3).x - (got["left"] as Vector3).x, (got["up"] as Vector3).y - (got["down"] as Vector3).y, worst, ", ".join(info)]))
	return rows


## Wind up to the upper right (finger held = SWING), then flick across to the lower left in `n` ticks.
## `over` scales the wind-up drag in aim radii (2.0 = the finger overshoots well past the ring).
## Returns [peak tip speed, ticks from flick start until aim_x < 0].
func _flick(wid: String, n: int, over: float) -> Array:
	await _setup()
	var f: Node3D = _fighter(wid)
	var r: float = _aim_r()
	var a := Vector2(_area().x * 0.7, _area().y * 0.5)
	var wind: Vector2 = a + Vector2(0.9, -0.44) * r * over
	var finish: Vector2 = wind + Vector2(-2.0, 0.75) * r
	var best: float = 0.0
	var lag: int = -1
	for i: int in range(150):
		if i == 40:
			_send_touch(1, a, true)
		if i >= 40 and i < 50:
			_send_drag(1, _lerp_path(a, wind, i - 40, 9))
		if i >= 80 and i <= 80 + n:
			_send_drag(1, _lerp_path(wind, finish, i - 80, n))
		var inp: FighterInput = await _tick(f)
		if i >= 80:
			best = maxf(best, float(f.debug_frame()["tip_speed"]))
			if lag < 0 and inp.aim_x < 0:
				lag = i - 80
	await _teardown()
	return [best, lag]


## The mouse's reference sweep (sim_fighter_core): aim right-high to left-low in 8 ticks with SWING held.
func _mouse_sweep(wid: String) -> float:
	await _setup()
	var f: Node3D = _fighter(wid)
	var inp := FighterInput.new()
	var best: float = 0.0
	for i: int in range(150):
		if i >= 40 and i < 80:
			inp.aim_x = 1000
			inp.aim_y = 500
		elif i >= 80:
			var t: float = clampf((i - 80) / 8.0, 0.0, 1.0)
			inp.aim_x = int(lerpf(1000, -1000, t))
			inp.aim_y = int(lerpf(500, -300, t))
			inp.buttons = FighterInput.SWING
		f.apply_input(inp)
		await step(1)
		if i >= 80:
			best = maxf(best, float(f.debug_frame()["tip_speed"]))
	await _teardown()
	return best


func _swing() -> Array:
	var fast: Array = await _flick("longsword", 8, 1.0)
	var slow: Array = await _flick("longsword", 14, 1.0)
	var club: Array = await _flick("club", 8, 1.0)
	var mouse: float = await _mouse_sweep("longsword")
	var ls: float = float(fast[0])
	return [
		row("touch_swing_longsword", ls >= 14.0 and ls <= 28.0 and ls >= mouse * 0.85,
			"flick 8 ticks (2 aim radii): tip_speed=%.1f m/s, mouse sweep %.1f m/s (target 15-25)" % [ls, mouse]),
		row("touch_swing_slow_flick", float(slow[0]) >= 8.0, "flick 14 ticks: tip_speed=%.1f m/s" % float(slow[0])),
		row("touch_swing_club", float(club[0]) >= 8.0 and float(club[0]) <= 28.0, "flick 8 ticks: tip_speed=%.1f m/s" % float(club[0])),
	]


## The finger winds up far past the ring and flicks back: the hand must turn round at once, not wait for the finger
## to come back inside the ring (dead travel reads as input lag).
func _reversal() -> Array:
	var inside: Array = await _flick("longsword", 8, 1.0)
	var over: Array = await _flick("longsword", 8, 2.0)
	var ok: bool = int(over[1]) >= 0 and int(over[1]) <= int(inside[1]) + 1 and float(over[0]) >= 14.0
	return [row("touch_swing_overshoot", ok, "aim crosses centre after %d ticks (finger kept inside the ring: %d) tip_speed=%.1f m/s" % [
		over[1], inside[1], float(over[0])])]


## Left thumb pushes right, a right finger taps ROLL: the roll starts.
func _roll() -> Array:
	await _setup()
	var f: Node3D = _fighter("longsword")
	var s := Vector2(_area().x * 0.2, _area().y * 0.6)
	var b: Dictionary = _button(FighterInput.ROLL)
	var rolled: int = -1
	for i: int in range(150):
		if i == 50:
			_send_touch(0, s, true)
			_send_drag(0, s + Vector2(_stick_r(), 0.0))
		if i == 60 and not b.is_empty():
			_send_touch(1, b["center"], true)
		if i == 64:
			_send_touch(1, b.get("center", Vector2.ZERO), false)
		await _tick(f)
		if rolled < 0 and bool(f.debug_frame()["rolling"]):
			rolled = i
	await _teardown()
	var ok: bool = rolled >= 60 and rolled <= 70
	return [row("touch_roll", ok, "rolling at tick %d (ROLL tapped at 60)" % rolled)]


## Tap CROUCH: the fighter stays low with no finger held (so both thumbs stay free); tap again to stand.
func _crouch() -> Array:
	await _setup()
	var f: Node3D = _fighter("longsword")
	var b: Dictionary = _button(FighterInput.CROUCH)
	if b.is_empty():
		await _teardown()
		return [row("touch_crouch", false, "no CROUCH button")]
	var stand: float = 0.0
	var low: float = 0.0
	var back: float = 0.0
	for i: int in range(260):
		if i == 60 or i == 160:
			_send_touch(2, b["center"], true)
		if i == 63 or i == 163:
			_send_touch(2, b["center"], false)
		await _tick(f)
		var y: float = (f.debug_frame()["pelvis_pos"] as Vector3).y
		if i == 59:
			stand = y
		if i == 150:
			low = y
		if i == 259:
			back = y
	await _teardown()
	var ok: bool = stand - low >= 0.12 and absf(back - stand) <= 0.05
	return [row("touch_crouch", ok, "pelvis stand=%.2f crouched=%.2f after second tap=%.2f" % [stand, low, back])]


## Unarmed, a gladius on the sand just ahead: walk is not needed, hold GRAB alone (one thumb) and it is picked up.
func _pickup() -> Array:
	await _setup()
	var f: Node3D = _fighter("gladius")
	var idle := FighterInput.new()
	for i: int in range(30):
		f.apply_input(idle)
		await step(1)
	var w: Weapon = f.get("weapon") as Weapon
	f.call("drop_weapon")
	w.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.15, 0.05, -0.5))
	w.linear_velocity = Vector3.ZERO
	w.angular_velocity = Vector3.ZERO
	for i: int in range(30):
		f.apply_input(idle)
		await step(1)
	var b: Dictionary = _button(FighterInput.GRAB)
	_send_touch(2, b["center"], true)
	var picked: int = -1
	var states: Dictionary = {}
	for i: int in range(300):
		await _tick(f)
		var d: Dictionary = f.debug_frame()
		states[d["state"]] = true
		if str(d["weapon_id"]) == "gladius":
			picked = i
			break
	_send_touch(2, b["center"], false)
	var after: FighterInput = _reader.read()
	await _teardown()
	var ok: bool = picked >= 0 and picked <= 180 and not states.has("down") and after.buttons == 0
	return [row("touch_hold_grab_pickup", ok, "picked_tick=%d states=%s buttons_after_release=%d" % [picked, states.keys(), after.buttons])]


## Both thumbs and a third finger: stick, aim (SWING) and SPRINT together; lifting one finger leaves the others.
func _multi_touch() -> Array:
	await _setup()
	var s := Vector2(_area().x * 0.25, _area().y * 0.6)
	var a := Vector2(_area().x * 0.7, _area().y * 0.3)
	var sp: Dictionary = _button(FighterInput.SPRINT)
	_send_touch(0, s, true)
	_send_touch(1, a, true)
	_send_touch(2, sp["center"], true)
	for i: int in range(5):
		_send_drag(0, s + Vector2(0.0, -_stick_r() * (i + 1) / 5.0))
		_send_drag(1, a + Vector2(-_aim_r() * (i + 1) / 5.0, 0.0))
		await _tick(null)
	var all3: FighterInput = _reader.read()
	_send_touch(1, a, false)
	var no_aim: FighterInput = _reader.read()
	_send_touch(2, sp["center"], false)
	_send_touch(0, s, false)
	var none: FighterInput = _reader.read()
	await _teardown()
	var want: int = FighterInput.SWING | FighterInput.SPRINT
	var ok: bool = all3.move_y >= 990 and all3.aim_x <= -990 and (all3.buttons & want) == want \
		and no_aim.move_y >= 990 and no_aim.aim_x == 0 and not no_aim.has(FighterInput.SWING) and no_aim.has(FighterInput.SPRINT) \
		and none.to_array() == [0, 0, 0, 0, 0]
	return [row("touch_multi_touch", ok, "all=%s aim_lifted=%s none=%s" % [all3.to_array(), no_aim.to_array(), none.to_array()])]


## Fingers down when the app goes to the background never send their release. After resume nothing is held. A
## finger lifted while the tree is paused (pause menu) is not stuck either.
func _pause_resume() -> Array:
	await _setup()
	var s := Vector2(_area().x * 0.25, _area().y * 0.6)
	var a := Vector2(_area().x * 0.7, _area().y * 0.3)
	var gb: Dictionary = _button(FighterInput.GRAB)
	_send_touch(0, s, true)
	_send_drag(0, s + Vector2(_stick_r(), 0.0))
	_send_touch(1, a, true)
	_send_drag(1, a + Vector2(0.0, _aim_r()))
	_send_touch(2, gb["center"], true)
	var held: FighterInput = _reader.read()
	var root: Window = host.get_tree().root
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _tick(null)
	var resumed: FighterInput = _reader.read()
	# The same finger index pressing again after resume starts fresh, not from the stale origin.
	_send_touch(1, a, true)
	var fresh: FighterInput = _reader.read()
	_send_touch(1, a, false)
	# Paused tree: the aim finger lifts while the pause menu is up.
	_send_touch(1, a, true)
	host.get_tree().paused = true
	_send_touch(1, a, false)
	host.get_tree().paused = false
	var unpaused: FighterInput = _reader.read()
	await _teardown()
	var ok: bool = held.buttons != 0 and resumed.to_array() == [0, 0, 0, 0, 0] and fresh.aim_x == 0 and fresh.aim_y == 0 \
		and not unpaused.has(FighterInput.SWING)
	return [row("touch_pause_resume", ok, "held=%s after_resume=%s fresh_press=%s released_while_paused=%s" % [
		held.to_array(), resumed.to_array(), fresh.to_array(), unpaused.to_array()])]


## Every phone shape: each button is hit by a finger on its centre, sits inside the safe area, is thumb-sized and
## clear of its neighbours; the stick and aim zones still start where expected.
func _layouts() -> Array:
	var rows: Array = []
	for sh: Array in SHAPES:
		Flags.args["safe-insets"] = str(sh[2])
		await _setup(sh[1])
		var k: float = _k()
		var win := Vector2(sh[1])
		var ins: PackedStringArray = str(sh[2]).split(",")
		var safe := Rect2(float(ins[0]), float(ins[1]), win.x - float(ins[0]) - float(ins[2]), win.y - float(ins[1]) - float(ins[3]))
		var bad: PackedStringArray = []
		var layout: Array = _tc.call("_layout")
		var min_r: float = 9999.0
		for b: Dictionary in layout:
			var c: Vector2 = b["center"]
			var rr: float = float(b["radius"])
			min_r = minf(min_r, rr * k)
			var box := Rect2((c - Vector2.ONE * rr) * k, Vector2.ONE * rr * 2.0 * k)
			if not safe.encloses(box):
				bad.append("%s outside safe" % b["label"])
			_send_touch(3, c, true)
			var inp: FighterInput = _reader.read()
			_send_touch(3, c, false)
			if (inp.buttons & int(b["bit"])) == 0:
				bad.append("%s not hit" % b["label"])
			if (int(b["bit"]) & TouchControls.TOGGLE_BITS) != 0:  # a toggle: tap again to clear it
				_send_touch(3, c, true)
				_send_touch(3, c, false)
			for o: Dictionary in layout:
				if o != b and c.distance_to(o["center"]) < rr + float(o["radius"]):
					bad.append("%s overlaps %s" % [b["label"], o["label"]])
		var held: FighterInput = _reader.read()
		if held.buttons != 0:
			bad.append("buttons left held %d" % held.buttons)
		# Stick from the lower left, aim from the upper right.
		_send_touch(0, Vector2(safe.position.x / k + 160.0, _area().y * 0.7), true)
		_send_drag(0, Vector2(safe.position.x / k + 160.0, _area().y * 0.7) + Vector2(0.0, -_stick_r()))
		_send_touch(1, Vector2(_area().x * 0.75, _area().y * 0.25), true)
		var both: FighterInput = _reader.read()
		if both.move_y < 990 or not both.has(FighterInput.SWING):
			bad.append("stick/aim zones %s" % str(both.to_array()))
		await _teardown()
		Flags.args.erase("safe-insets")
		rows.append(row("touch_layout_%s" % sh[0], bad.is_empty() and min_r >= 28.0, "%dx%d insets=%s buttons=%d min_radius=%.0f px %s" % [
			sh[1].x, sh[1].y, sh[2], layout.size(), min_r, "; ".join(bad)]))
	return rows
