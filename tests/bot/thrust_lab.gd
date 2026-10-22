extends SceneTree
## Thrust lab: one fighter thrusts at a dummy on a flat floor and every weapon contact on the dummy is printed
## (kind, speed, part). Args after `--`:
##   --w=<weapon> --gap=<m> --ticks=N --brain=1 (FighterBrain drives side 0 instead of the script) --seed=S
##   --foe=<weapon> --foe_brain=1 (a second brain drives the dummy) --wind=N --drive=N --sprint=0|1 --press=N
## Script mode: hold SWING with the point on the dummy's chest for `wind` ticks while standing, then walk (sprint)
## in for `drive` ticks, pressing THRUST from tick `press` of the drive.
## Quiet: one `LAB` line per contact, then `LAB summary ...`.

const FIGHTER: String = "res://game/fighter/fighter.gd"

var _args: Dictionary = {}
var _fs: Array = []
var _hits: Array = []
var _brain: FighterBrain = null
var _brain1: FighterBrain = null
var _t: int = 0
var _ticks: int = 600
var _max_tip: float = 0.0
var _strike_tips: Array = []
var _cur_strike_max: float = -1.0
var _close_hist: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_ticks = int(_args.get("ticks", "600"))
	var root3d := Node3D.new()
	root.add_child(root3d)
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 1, 60)
	cs.shape = bx
	fb.add_child(cs)
	fb.position = Vector3(0, -0.5, 0)
	root3d.add_child(fb)
	var gap: float = float(_args.get("gap", "3.5"))
	for side: int in range(2):
		var f: Node3D = (load(FIGHTER) as GDScript).new()
		root3d.add_child(f)
		f.position = Vector3(0, 0, -gap * side)
		f.rotation.y = PI * side
		var wid: String = str(_args.get("w", "spear")) if side == 0 else str(_args.get("foe", "fists"))
		f.setup({"weapon": wid, "offhand": "", "armor": {}}, side, Tuning.new())
		_fs.append(f)
	_fs[0].opponent = _fs[1]
	_fs[1].opponent = _fs[0]
	(_fs[1] as Object).connect("hit", _on_hit)
	(_fs[0] as Object).connect("hit", _on_hit)
	var seed: int = int(_args.get("seed", "1"))
	if _args.has("brain"):
		_brain = FighterBrain.new(seed, {"preset": str(_args.get("preset", "duelist"))})
	if _args.has("foe_brain"):
		_brain1 = FighterBrain.new(seed + 77, {})
	physics_frame.connect(_tick)


func _on_hit(ev: Dictionary) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		return
	var v: float = (ev.get("rel_vel", Vector3.ZERO) as Vector3).length()
	var line: String = "LAB hit t=%d by=%s kind=%s speed=%.2f part=%s dmg=%.2f state=%s" % [_t, str(ev.get("weapon_id", "?")),
		str(ev.get("contact", "")), v, str(ev.get("part", "")), float(ev.get("total", 0.0)), _brain.state_name() if _brain else "-"]
	print(line)
	_hits.append([str(ev.get("weapon_id", "?")), str(ev.get("contact", "")), v, str(ev.get("part", ""))])


func _tick() -> void:
	_t += 1
	var f0: Node3D = _fs[0]
	var f1: Node3D = _fs[1]
	var me: Dictionary = f0.debug_frame()
	var foe: Dictionary = f1.debug_frame()
	_max_tip = maxf(_max_tip, float(me["tip_speed"]))
	if _brain != null:
		f0.apply_input(_brain.think(me, foe, 1.0 / 60.0))
		var striking: bool = _brain.state_name() == "strike"
		var ck: String = "%d/%s" % [_brain._close_step, _brain.state_name()]
		_close_hist[ck] = int(_close_hist.get(ck, 0)) + 1
		if _args.has("trace") and (_brain.state_name() in ["windup", "strike", "recover"] or (_t % 5 == 0 and _args.get("trace") == "all")):
			var mp: Vector3 = me["pelvis_pos"]
			var fp: Vector3 = foe["pelvis_pos"]
			var chest: Vector3 = (foe["parts"]["torso"] as Dictionary)["pos"]
			var tip: Vector3 = me["tip_pos"]
			var hand: Vector3 = me["hand_pos"]
			print("TR t=%d miss=%.2f st=%s dist=%.2f tip_chest=%.2f tip_v=%.2f pel_v=%.2f blade_on_foe=%.2f up=%.2f _=%.1f tip_y=%.2f chest_y=%.2f" % [_t, FighterBrain.pole_miss(hand, tip, chest, Vector3(1, 0, 0) if true else Vector3.ZERO).length(),
				_brain.state_name(), Vector2(mp.x - fp.x, mp.z - fp.z).length(), tip.distance_to(chest), float(me["tip_speed"]),
				(me["pelvis_vel"] as Vector3).length(), (tip - hand).normalized().dot(Vector3(fp.x - mp.x, 0, fp.z - mp.z).normalized()), (tip - hand).normalized().y,
				0.0, tip.y, chest.y])
		if striking:
			_cur_strike_max = maxf(_cur_strike_max, float(me["tip_speed"]))
		elif _cur_strike_max >= 0.0:
			_strike_tips.append([_cur_strike_max, str(_brain.plan().get("kind", ""))])
			_cur_strike_max = -1.0
	else:
		f0.apply_input(_script_input(me, foe))
	f1.apply_input(_brain1.think(foe, me, 1.0 / 60.0) if _brain1 != null else FighterInput.new())
	if _t >= _ticks:
		var pts: Array = _hits.filter(func(h: Array) -> bool: return h[1] == "point" and h[0] == str(_args.get("w", "spear")))
		var ps: float = 0.0
		for h: Array in pts:
			ps += float(h[2])
		var st: String = ""
		for s: Array in _strike_tips:
			st += "%s:%.1f " % [str(s[1]).substr(0, 2), float(s[0])]
		print("LAB summary w=%s hits=%d point=%d point_speed=%.2f max_tip=%.2f strikes=[%s]" % [str(_args.get("w", "spear")),
			_hits.size(), pts.size(), ps / maxf(pts.size(), 1), _max_tip, st])
		var by: Dictionary = {}
		for h: Array in _hits:
			var k: String = "%s:%s" % [h[0], h[1]]
			by[k] = int(by.get(k, 0)) + 1
		print("LAB close ", _close_hist, " hits ", by)
		quit()


var _ph: int = 0
var _ph_t: int = 0
var _aim_brain: FighterBrain = null


## Settle in the pole stance (point servoed on the chest), drive in (sprint, THRUST once the point is within
## `press_d` of the chest), back off, repeat.
func _script_input(me: Dictionary, foe: Dictionary) -> FighterInput:
	var i := FighterInput.new()
	if _aim_brain == null:
		_aim_brain = FighterBrain.new(1, {})
	_aim_brain._geometry(me, foe)
	var chest: Vector3 = (foe["parts"]["torso"] as Dictionary)["pos"]
	chest.y += float(_args.get("dy", "0"))
	var aim: Vector2 = _aim_brain._pole_servo(me, chest)
	_aim_brain._last_aim = aim
	i.aim_x = roundi(aim.x * 1000.0)
	i.aim_y = roundi(aim.y * 1000.0)
	i.buttons = FighterInput.SWING
	if _t < 30:
		return i
	_ph_t += 1
	var tc: float = (me["tip_pos"] as Vector3).distance_to(chest)
	var mp: Vector3 = me["pelvis_pos"]
	var fp: Vector3 = foe["pelvis_pos"]
	var dist: float = Vector2(mp.x - fp.x, mp.z - fp.z).length()
	match _ph:
		0:
			var want: float = float(_args.get("gap", "3.5"))
			i.move_y = clampi(roundi((dist - want) * 2000.0), -600, 600)
			if _ph_t > int(_args.get("wind", "60")):
				_ph = 1
				_ph_t = 0
		1:
			i.move_y = 1000
			if _args.get("sprint", "1") == "1":
				i.buttons |= FighterInput.SPRINT
			if tc < float(_args.get("press_d", "99")):
				i.buttons |= FighterInput.THRUST
			if _args.has("trace"):
				print("TR t=%d dist=%.2f tc=%.2f tip_v=%.2f pel_v=%.2f" % [_t, dist, tc, float(me["tip_speed"]), (me["pelvis_vel"] as Vector3).length()])
			if _ph_t > int(_args.get("drive", "40")) or dist < 1.6:
				_ph = 2
				_ph_t = 0
		2:
			i.move_y = -1000
			if _ph_t > 60:
				_ph = 0
				_ph_t = 0
	return i
