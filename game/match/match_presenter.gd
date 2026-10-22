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
const BODY_ROLL_GAP: float = 0.6  ## a rolling drag segment longer than this is a teleport, not a furrow
const BODY_HALF_LEN: Dictionary = {
	"torso": 0.14, "pelvis": 0.10, "upper_arm_l": 0.10, "upper_arm_r": 0.10, "forearm_l": 0.12, "forearm_r": 0.12,
	"thigh_l": 0.15, "thigh_r": 0.15,
}  ## half the part's long axis between its end caps (pelvis lies along local x, the rest along local y)
const TIP_DRAG_Y: float = 0.05
const TIP_DRAG_SPEED: float = 0.8
const TIP_STAB_SPEED: float = 3.5
const SPRAY_GAP_S: float = 0.08
const SPRAY_HEIGHT: float = 0.6
const MAX_DRAGS_PER_TICK: int = 4
const FOLLOW_MODE: String = "follow"
const WIDE_MODE: String = "wide"
const WIDE_FOV: float = 55.0  ## tighter than the default so two fighters fill more of the frame

var arena: Arena = null
var sand: Node = null
var blood: BloodFx = null
var wounds: WoundFx = null  ## wound marks on bodies, blood on weapons and fists
var sfx: SfxDirector = null
var hud: HUD = null
var camera: FightCamera = null
var aim: AimOverlay = null  ## the human fighter's aim aid (local only)
var _finale_done: Array[bool] = [false, false]
var _finale_fighter: Fighter = null  ## the finale's victim, to see when its head comes off
var panel: TuningPanel = null  ## built on the first toggle press (open_panel)
var hit_fx: HitFx = null
var killcam: KillCam = null  ## instant replay of the finishing blow (records every shown tick)
var feel: FeelDirector = null  ## hit-stop, screen punch, bass, finisher cinematic, rumble patterns

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
## The arena (stands, crowd, sand, about 160-200 ms to build) outlives its match: when a presenter leaves the tree its
## arena is kept here, out of the tree, and the next match at the same graphics quality takes it back (sand cleared)
## instead of building a new one. Not in headless runs (nothing is drawn; no orphan left at exit).
static var _spare_arena: Arena = null
static var _spare_level: int = -1
## A/B knobs for tests/perf (--legacy): rebuild the arena every match and build the tuning panel with it, as before.
static var keep_arena: bool = true
static var eager_panel: bool = false
## Perf sections (tests/perf only): microseconds per section while `prof_on`.
var prof_on: bool = false
var prof: Dictionary = {}


func build(camera_mode: String) -> void:
	arena = _take_spare_arena()
	if arena == null:
		arena = Arena.new()
		arena.name = "Arena"
	add_child(arena)
	sand = arena.sand
	blood = BloodFx.new()
	blood.name = "BloodFx"
	blood.sand = sand
	add_child(blood)
	wounds = WoundFx.new()
	wounds.name = "WoundFx"
	add_child(wounds)
	blood.body_marks = wounds
	blood.set_quality(GfxQuality.blood_level())
	sfx = SfxDirector.new()
	sfx.name = "SfxDirector"
	add_child(sfx)
	if arena != null:
		sfx.crowd_reacted.connect(arena.crowd_react)
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	aim = AimOverlay.new()
	aim.name = "AimOverlay"
	add_child(aim)
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
	feel = FeelDirector.new()
	feel.name = "FeelDirector"
	add_child(feel)
	feel.setup(camera, sfx)
	killcam = KillCam.new()
	killcam.name = "KillCam"
	killcam.presenter = self
	killcam.arena_radius = Tuning.shared().arena_radius
	add_child(killcam)
	# The tuning panel (about 1,500 Control nodes) is built on its first toggle, not with every match.
	if eager_panel:
		open_panel()
		panel.visible = false
	var opener := _PanelOpener.new()
	opener.name = "TuningPanelOpener"
	opener.presenter = self
	add_child(opener)
	# Compile every fighter, weapon and gore material once, off-screen, before the first blow (once per session).
	FighterWarmup.start(self)


func _exit_tree() -> void:
	if arena == null or not is_instance_valid(arena) or arena.get_parent() != self:
		return
	if not keep_arena or DisplayServer.get_name() == "headless" or not arena.is_node_ready():
		return
	if _spare_arena != null and is_instance_valid(_spare_arena) and _spare_arena != arena:
		_spare_arena.free()
	remove_child(arena)
	_spare_arena = arena
	_spare_level = GfxQuality.level


## The kept arena when it was built at the current graphics quality (freed otherwise), reset for a new match; or null.
static func _take_spare_arena() -> Arena:
	var a: Arena = _spare_arena
	_spare_arena = null
	if a == null or not is_instance_valid(a):
		return null
	if _spare_level != GfxQuality.level:
		a.free()
		return null
	if a.sand != null and a.sand.has_method("clear"):
		a.sand.call("clear")
	a.set_crowd_excitement(0.0)
	return a


## Builds the tuning panel (once) and shows it. Called by the first toggle press.
func open_panel() -> void:
	if panel == null:
		panel = TuningPanel.new()
		panel.name = "TuningPanel"
		add_child(panel)
	panel.visible = true


## Waits for the tuning panel's toggle (also while paused) and builds the panel then; afterwards the panel toggles itself.
class _PanelOpener extends Node:
	var presenter: MatchPresenter = null

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _unhandled_input(event: InputEvent) -> void:
		if presenter != null and presenter.panel == null and TuningPanel.is_toggle_event(event):
			presenter.open_panel()
			get_viewport().set_input_as_handled()
			queue_free()


## Points everything at a fresh pair of fighters (also after a loop restart).
func begin(fighters: Array, names: Array, player_side: int) -> void:
	_fighters = fighters
	_foot_down.clear()
	_part_touch.clear()
	_last_pos.clear()
	_tip_valid = [false, false]
	_drags = 0
	killcam.track(fighters)  # first, so it reads each event before the blood effects use their RNG
	for f: Fighter in fighters:
		# Blood colour follows the outfit in the fighter's loadout (online it is the loadout both sides already have).
		blood.set_palette(f.side, OutfitRules.blood_palette_of(f.loadout))
		blood.track(f)
		wounds.set_palette(f.side, OutfitRules.blood_palette_of(f.loadout))
		wounds.track(f)
		sfx.track(f)
		f.died.connect(_on_fighter_died.bind(f.side))
	var human: int = clampi(player_side, 0, 1)
	_player_side = human
	hud.track((fighters[human] as Fighter).health, (fighters[1 - human] as Fighter).health,
			str(names[human]), str(names[1 - human]))
	hud.bind_clock(get_parent())  # the Match: fight clock and time limit
	aim.bind(fighters[human] as Fighter, camera)
	feel.begin(fighters, human)
	camera.target = (fighters[human] as Fighter).parts["pelvis"]
	camera.look_at_node = (fighters[1 - human] as Fighter).parts["pelvis"]
	# Prime after the ragdolls have had a physics tick to settle, not on the freshly placed pose.
	camera.snap_after_ticks(roundi(Tuning.shared().feel_prime_ticks))
	_finale_done = [false, false]
	_finale_fighter = null


## Drops the old fighters' tracking and clears the sand and blood for the next match.
func end_match() -> void:
	for f: Variant in _fighters:
		if is_instance_valid(f):
			blood.untrack(f as Node)
	_fighters = []
	feel.end_match()
	blood.clear()
	wounds.clear()
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
## struck part, sparks for metal, then FeelDirector (hit-stop, screen punch, bass, rumble). Presentation only.
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
		if fin or (victim != null and (victim as Fighter).health != null and (victim as Fighter).health.dead):
			_finale(tgt, ev.get("point", Vector3.ZERO))
	if feel != null:
		feel.on_hit(ev, victim, imp)


func _on_fighter_died(side: int) -> void:
	if camera != null and side >= 0 and side < _fighters.size() and is_instance_valid(_fighters[side]):
		_finale(side, ((_fighters[side] as Fighter).parts["pelvis"] as Node3D).global_position)


## Finisher / death camera for fighter `tgt`, once per fighter per match. Presentation only (client-local).
func _finale(tgt: int, hit: Vector3) -> void:
	if tgt < 0 or tgt >= _fighters.size() or _finale_done[tgt] or not is_instance_valid(_fighters[tgt]):
		return
	var victim: Fighter = _fighters[tgt]
	var other: Fighter = _fighters[1 - tgt]
	if not victim.parts.has("pelvis") or not other.parts.has("pelvis"):
		return
	_finale_done[tgt] = true
	camera.start_finale((other.parts["pelvis"] as Node3D).global_position, victim.parts["pelvis"] as Node3D, hit,
			FeelOptions.motion_scale(Tuning.shared()), victim.parts.get("head") as Node3D)
	_finale_fighter = victim


func _spray(pos: Vector3, vel: Vector3, amount: float) -> void:
	if sand != null and sand.has_method("spray"):
		sand.call("spray", pos, vel, amount)


## Once per physics tick, after the fighters' frames were built.
func tick(frames: Array, delta: float) -> void:
	if not prof_on:
		_tick_sand(frames, delta)
		return
	var t0: int = Time.get_ticks_usec()
	_tick_sand(frames, delta)
	prof["pres_tick"] = int(prof.get("pres_tick", 0)) + Time.get_ticks_usec() - t0


func _tick_sand(frames: Array, delta: float) -> void:
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
		var rolling: bool = f.rolling()
		if touching and not was and not rolling:
			var impact: float = clampf(absf(b.linear_velocity.y) / 4.0, 0.0, 1.0)
			var push: Vector3 = Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z) * 0.2
			if BODY_HALF_LEN.has(n):
				var ax: Vector3 = b.global_transform.basis.x if n == "pelvis" else b.global_transform.basis.y
				var half: Vector3 = Vector3(ax.x, 0.0, ax.z) * float(BODY_HALF_LEN[n])
				sand.call("stamp_capsule", flat - half, flat + half, r * 1.3, 0.012 + 0.05 * impact, push)
			else:
				sand.call("stamp", flat, r * 1.5, 0.012 + 0.05 * impact, push)
			if impact > 0.45:
				_spray(flat, Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z), impact)
		elif touching and (was or rolling) and _drags < MAX_DRAGS_PER_TICK:
			var hv: Vector3 = Vector3(b.linear_velocity.x, 0.0, b.linear_velocity.z)
			var prev: Vector3 = _last_pos.get(key, pos)
			var gap: float = Vector2(prev.x - pos.x, prev.z - pos.z).length()
			if (hv.length() > BODY_SLIDE_SPEED or rolling) and gap < BODY_ROLL_GAP:
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
	if camera != null and camera.finale.active and is_instance_valid(_finale_fighter):
		camera.finale_head_free = _finale_fighter.is_limb_cut("head")
	# The stands follow the crowd's noise level.
	if arena != null and sfx != null:
		arena.set_crowd_excitement(sfx.crowd_excitement())
