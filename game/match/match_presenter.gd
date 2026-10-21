class_name MatchPresenter
extends Node
## Everything a watched match shows and plays: arena, sand (footprints, falls, furrows, sprays), blood, sound, HUD,
## camera, tuning panel. Owned by Match, built only when `presentation` is on. Never touches fight state: it reads
## the fighters (parts, velocities, debug frames) and the hit events and draws.

const FOOT_DOWN_Y: float = 0.075  ## foot-box centre height under which a foot counts as planted
const FOOT_UP_Y: float = 0.11  ## above which it counts as lifted again
const FOOT_RX: float = 0.06
const FOOT_RZ: float = 0.14
const FOOT_DEPTH: float = 0.018
const FOOT_SLIDE_SPEED: float = 0.9  ## planted-foot speed above which it ploughs a furrow, m/s
const BODY_TOUCH_MARGIN: float = 0.05
const BODY_RADIUS: Dictionary = {
	"head": 0.11, "torso": 0.19, "pelvis": 0.17, "upper_arm_l": 0.06, "upper_arm_r": 0.06, "forearm_l": 0.05,
	"forearm_r": 0.05, "thigh_l": 0.09, "thigh_r": 0.09,
}
const BODY_SLIDE_SPEED: float = 0.5
const TIP_DRAG_Y: float = 0.05
const TIP_DRAG_SPEED: float = 0.8
const TIP_STAB_SPEED: float = 3.5
const SPRAY_GAP_S: float = 0.08
const SPRAY_HEIGHT: float = 0.6
const MAX_DRAGS_PER_TICK: int = 4
const FOLLOW_MODE: String = "follow"
const WIDE_MODE: String = "wide"
const RUMBLE_GAP_S: float = 0.05  ## min game seconds between rumble pulses (a flurry does not re-trigger every tick)
const WIDE_FOV: float = 55.0  ## tighter than the default so two fighters fill more of the frame

var arena: Arena = null
var sand: Node = null
var blood: BloodFx = null
var sfx: SfxDirector = null
var hud: HUD = null
var camera: FightCamera = null
var panel: TuningPanel = null
var hit_fx: HitFx = null

var _fighters: Array = []
var _foot_down: Dictionary = {}
var _part_touch: Dictionary = {}
var _last_pos: Dictionary = {}
var _last_tip: Array = [Vector3.ZERO, Vector3.ZERO]
var _tip_valid: Array = [false, false]
var _spray_clock: float = 0.0
var _last_spray: float = -10.0
var _drags: int = 0
var _player_side: int = 0
var _last_rumble: float = -10.0


func build(camera_mode: String) -> void:
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	sand = arena.sand
	blood = BloodFx.new()
	blood.name = "BloodFx"
	blood.sand = sand
	add_child(blood)
	blood.set_quality(GfxQuality.blood_level())
	sfx = SfxDirector.new()
	sfx.name = "SfxDirector"
	add_child(sfx)
	if arena != null:
		sfx.crowd_reacted.connect(arena.crowd_react)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hit_fx = HitFx.new()
	hit_fx.name = "HitFx"
	add_child(hit_fx)
	camera = FightCamera.new()
	camera.name = "FightCamera"
	camera.arena_radius = Tuning.shared().arena_radius
	camera.mode = camera_mode
	camera.fov = WIDE_FOV if camera_mode == WIDE_MODE else camera.fov
	add_child(camera)
	camera.current = true
	panel = TuningPanel.new()
	panel.name = "TuningPanel"
	add_child(panel)


## Points everything at a fresh pair of fighters (also after a loop restart).
func begin(fighters: Array, names: Array, player_side: int) -> void:
	_fighters = fighters
	_foot_down.clear()
	_part_touch.clear()
	_last_pos.clear()
	_tip_valid = [false, false]
	_drags = 0
	for f: Fighter in fighters:
		blood.track(f)
		sfx.track(f)
	var human: int = clampi(player_side, 0, 1)
	_player_side = human
	hud.track((fighters[human] as Fighter).health, (fighters[1 - human] as Fighter).health,
			str(names[human]), str(names[1 - human]))
	camera.target = (fighters[human] as Fighter).parts["pelvis"]
	camera.look_at_node = (fighters[1 - human] as Fighter).parts["pelvis"]
	camera.snap()


## Drops the old fighters' tracking and clears the sand and blood for the next match.
func end_match() -> void:
	for f: Variant in _fighters:
		if is_instance_valid(f):
			blood.untrack(f as Node)
	_fighters = []
	blood.clear()
	if sand != null and sand.has_method("clear"):
		sand.call("clear")


func announce(text: String) -> void:
	if hud != null and text != "":
		hud.announce(text)


## Called with every resolved hit: ground sprays for low blows.
func on_hit(ev: Dictionary) -> void:
	_feel(ev)
	var p: Vector3 = ev.get("point", Vector3.ZERO)
	if p.y > SPRAY_HEIGHT or _spray_clock - _last_spray < SPRAY_GAP_S:
		return
	var total: float = float(ev.get("total", 0.0))
	if total < 1.0:
		return
	_last_spray = _spray_clock
	var rel: Vector3 = ev.get("rel_vel", Vector3.ZERO)
	_spray(Vector3(p.x, 0.0, p.z), rel * 0.4, clampf(total / 40.0, 0.2, 1.2))


## Combat feel for one hit, all scaled by the hit's impact: camera kick, shake and finisher zoom, the flash on the
## struck part, sparks for metal, pad rumble and phone vibration. Presentation only.
func _feel(ev: Dictionary) -> void:
	var tun: Tuning = Tuning.shared()
	var imp: float = FeelLogic.impact(ev, tun)
	var tgt: int = int(ev.get("target", -1))
	var victim: Object = _fighters[tgt] if tgt >= 0 and tgt < _fighters.size() and is_instance_valid(_fighters[tgt]) else null
	if hit_fx != null:
		hit_fx.on_hit(ev, victim, imp)
	if camera != null:
		var strength: float = FeelLogic.camera_strength(imp, tun) * (1.0 if tgt == _player_side else 0.8)
		var fin: bool = FeelLogic.is_finisher(ev)
		camera.hit_impact(FeelLogic.blow_dir(ev), strength, fin, FeelOptions.motion_scale(tun))
	_rumble(ev, imp, tun)


## Gamepad rumble for the fighter who landed the blow and the one who took it, and phone vibration for the human side.
func _rumble(ev: Dictionary, imp: float, tun: Tuning) -> void:
	if Flags.is_scripted_run() or _spray_clock - _last_rumble < RUMBLE_GAP_S:
		return
	var scale: float = FeelOptions.rumble_scale(tun)
	var pads: Array[int] = []
	for d: int in Input.get_connected_joypads():
		pads.append(d)
	var atk: int = int(ev.get("attacker", -1))
	var tgt: int = int(ev.get("target", -1))
	var any: bool = false
	for side: int in [atk, tgt]:
		var taken: bool = side == tgt
		var r: Dictionary = FeelLogic.rumble(imp, taken, tun, scale)
		if float(r["dur"]) <= 0.0:
			continue
		var dev: int = FeelLogic.pad_for_side(side, _player_side, pads)
		if dev >= 0:
			Input.start_joy_vibration(dev, float(r["weak"]), float(r["strong"]), float(r["dur"]))
			any = true
		if side == _player_side and (OS.has_feature("android") or OS.has_feature("ios")):
			var v: Dictionary = FeelLogic.vibrate(imp, taken, tun, scale)
			if int(v["ms"]) > 0:
				Input.vibrate_handheld(int(v["ms"]), float(v["amp"]))
				any = true
	if any:
		_last_rumble = _spray_clock


func _spray(pos: Vector3, vel: Vector3, amount: float) -> void:
	if sand != null and sand.has_method("spray"):
		sand.call("spray", pos, vel, amount)


## Once per physics tick, after the fighters' frames were built.
func tick(frames: Array, delta: float) -> void:
	_spray_clock += delta
	_drags = 0
	if sand == null or not sand.has_method("stamp_ellipse"):
		return
	for i: int in _fighters.size():
		var f: Fighter = _fighters[i]
		if not is_instance_valid(f) or f.parts.is_empty():
			continue
		_feet(f, i)
		_bodies(f, i, delta)
		_tip(frames[i], i)


func _feet(f: Fighter, side: int) -> void:
	var vel: Vector3 = (f.parts["pelvis"] as RigidBody3D).linear_velocity
	for n: String in ["shin_l", "shin_r"]:
		if f.is_limb_cut(n):
			continue
		var b: RigidBody3D = f.parts[n]
		var foot: Vector3 = b.global_transform * FighterRig.FOOT_OFFSET
		var key: String = "%d/%s" % [side, n]
		var was_down: bool = bool(_foot_down.get(key, false))
		var down: bool = foot.y < (FOOT_UP_Y if was_down else FOOT_DOWN_Y)
		var fwd: Vector3 = -b.global_transform.basis.z
		var yaw: float = atan2(-fwd.x, -fwd.z)
		if down and not was_down:
			var push: Vector3 = Vector3(vel.x, 0.0, vel.z) * 0.4
			var impact: float = clampf(absf(b.linear_velocity.y) * 0.02, 0.0, 0.03)
			sand.call("stamp_ellipse", Vector3(foot.x, 0.0, foot.z), FOOT_RX, FOOT_RZ, yaw, FOOT_DEPTH + impact, push)
		elif down and was_down and _drags < MAX_DRAGS_PER_TICK:
			var hv: Vector3 = Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z)
			if hv.length() > FOOT_SLIDE_SPEED:
				var prev: Vector3 = _last_pos.get(key, foot)
				sand.call("drag", Vector3(prev.x, 0.0, prev.z), Vector3(foot.x, 0.0, foot.z), FOOT_RX, FOOT_DEPTH * 0.6)
				_drags += 1
		_foot_down[key] = down
		_last_pos[key] = foot


func _bodies(f: Fighter, side: int, _delta: float) -> void:
	for n: String in BODY_RADIUS:
		if f.is_limb_cut(n) and n != "head":
			continue
		var b: RigidBody3D = f.parts[n]
		var r: float = BODY_RADIUS[n]
		var pos: Vector3 = b.global_position
		var key: String = "%d/%s" % [side, n]
		var touching: bool = pos.y < r + BODY_TOUCH_MARGIN
		var was: bool = bool(_part_touch.get(key, false))
		var flat: Vector3 = Vector3(pos.x, 0.0, pos.z)
		if touching and not was:
			var impact: float = clampf(absf(b.linear_velocity.y) / 4.0, 0.0, 1.0)
			sand.call("stamp", flat, r * 1.5, 0.012 + 0.05 * impact, Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z) * 0.2)
			if impact > 0.45:
				_spray(flat, Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z), impact)
		elif touching and was and _drags < MAX_DRAGS_PER_TICK:
			var hv: Vector3 = Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z)
			if hv.length() > BODY_SLIDE_SPEED:
				var prev: Vector3 = _last_pos.get(key, pos)
				sand.call("drag", Vector3(prev.x, 0.0, prev.z), flat, r, 0.014)
				_drags += 1
		_part_touch[key] = touching
		_last_pos[key] = pos


func _tip(fr: Dictionary, side: int) -> void:
	var tip: Vector3 = fr.get("tip_pos", Vector3.ZERO)
	var spd: float = float(fr.get("tip_speed", 0.0))
	var low: bool = tip.y < TIP_DRAG_Y and str(fr.get("weapon_id", "fists")) != "fists"
	if low and bool(_tip_valid[side]) and spd > TIP_DRAG_SPEED and _drags < MAX_DRAGS_PER_TICK:
		var prev: Vector3 = _last_tip[side]
		sand.call("drag", Vector3(prev.x, 0.0, prev.z), Vector3(tip.x, 0.0, tip.z), 0.025, 0.012)
		_drags += 1
		if spd > TIP_STAB_SPEED:
			_spray(Vector3(tip.x, 0.0, tip.z), (tip - prev) * 60.0, 0.4)
	_tip_valid[side] = low
	_last_tip[side] = tip


func _process(_delta: float) -> void:
	# The stands follow the crowd's noise level.
	if arena != null and sfx != null:
		arena.set_crowd_excitement(sfx.crowd_excitement())
