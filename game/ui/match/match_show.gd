class_name MatchShow
extends Node
## The match wrapper's in-fight half, one per watched Match (a child of it, so it goes when the match does): the
## pre-fight intro (plates, a slow camera move over the two fighters, crowd swell, FIGHT! stinger) and the FightTally
## the results screen reads. MenuFlow hangs one with `attach()` on every match it runs and calls `play_intro()` for
## vs CPU, local 2P and online; practice and bot loops get no intro.
##
## While the plates are up the fighters are held: offline each human reader reads the "none" device and each CPU brain
## is set aside (null reader + null brain = neutral input, the same path as the practice dummy), so the sim keeps
## ticking (camera primes, ragdolls settle, recorder sees neutral input) and nothing needs pausing. Online the hold is
## `hold_changed` (MenuFlow sets NetSession.input_blocked on each peer) and the clock is the match tick, so both peers
## release on the same host tick; online intros cannot be skipped. No new net traffic either way.

signal hold_changed(on: bool)
signal intro_finished

const CAM_FOV: float = 50.0
const CAM_PUSH: Vector2 = Vector2(1.25, 1.0)  ## landscape: distance as a multiple of the one that fits both fighters
const CAM_BEHIND: Vector2 = Vector2(6.2, 4.6)  ## portrait: metres behind the local fighter, start and end
const PORTRAIT_LIFT: float = 1.2  ## portrait: extra camera height, so both fighters sit low under the plates
const CAM_HEIGHT: Vector2 = Vector2(2.8, 1.9)
const CAM_ANGLE: Vector2 = Vector2(0.45, 0.15)  ## rad off side-on toward the local fighter's back, start and end
const FIT_MARGIN: float = 1.3  ## m of sand kept beyond each fighter at the edges of a landscape frame
const WALL_ROOM: float = 0.8  ## the camera stays this far inside the arena wall
## Look-at height over the midpoint, landscape and portrait (high, so the fighters sit low, under the plates).
const LOOK_HEIGHT: Vector2 = Vector2(1.4, 2.0)
const SWELL_START: float = 0.35  ## crowd excitement impulse as the plates come in
const SWELL_FIGHT: float = 0.6  ## and on FIGHT!

var match_node: Match = null
var tally: FightTally = FightTally.new()
var timeline: IntroTimeline = null
var online: bool = false
var local_side: int = 0  ## the fighter on this screen (an online client is side 1): the camera ends behind it
var intro_end_tick: int = 0  ## the match tick the fighters were released on (fight time counts from here)

var _intro: MatchIntro = null
var _cam: Camera3D = null
var _held: bool = false
var _stashed_devices: Array = ["", ""]
var _stashed_brains: Array = [null, null]
var _was_phase: String = ""
var _released: bool = false


func _init() -> void:
	name = "MatchShow"
	process_mode = Node.PROCESS_MODE_ALWAYS


## Hangs a show on `m` (its tally starts listening at once). Connect `hold_changed` before `play_intro`.
static func attach(m: Match, is_online: bool) -> MatchShow:
	var s := MatchShow.new()
	s.online = is_online
	s.match_node = m
	m.add_child(s)
	s._listen()
	return s


## Starts the intro with `plates` (MatchReport.plates_for). `intro_s` <= 0, or no presentation, means no intro.
func play_intro(plates: Array, intro_s: float, fight_s: float) -> void:
	if intro_s > 0.0 and match_node.presenter != null:
		_begin_intro(plates, intro_s, fight_s)


func intro_running() -> bool:
	return timeline != null and not timeline.done()


## "plates", "fight" or "" (no intro, or over).
func intro_phase() -> String:
	return timeline.phase() if timeline != null else ""


## Seconds of fighting so far (from the release), at `tick`.
func fight_seconds(tick: int) -> float:
	return float(maxi(tick - intro_end_tick, 0)) / float(Engine.physics_ticks_per_second)


func _listen() -> void:
	for f: Fighter in match_node.fighters:
		f.hit.connect(_on_hit)
		f.gore.connect(_on_gore.bind(f.side))


func _on_hit(ev: Dictionary) -> void:
	var tun: Tuning = Tuning.shared()
	tally.on_hit(ev, float(match_node.tick) / float(Engine.physics_ticks_per_second), tun.combo_gap_s, tun.combo_merge_s)


func _on_gore(ev: Dictionary, side: int) -> void:
	tally.on_gore(ev, side)


## The two intro plates in screen order (local player first). `mode` is the Match mode or "online".
func plates(mode: String, local_side: int, ratings: Array) -> Array:
	return MatchReport.plates_for({"mode": mode, "names": match_node.names,
		"loadouts": match_node.config.get("loadouts", []), "personalities": match_node.config.get("personalities", []),
		"local_side": local_side, "ratings": ratings})


## The results screen's content (MatchReport.build) for `result`: hits from MatchStats (an online client's stats see
## the host's replayed hits), blood lost from the result's stats or the fighters, severs and combos from the tally,
## fight time from the release. `rating` is the rating service's summary ({} unrated), `notes` extra lines.
func report(result: Dictionary, local_side: int, is_online: bool, rating: Dictionary, notes: String) -> Dictionary:
	var m: Match = match_node
	var stats: Dictionary = result.get("stats", {})
	var lost: Array = [0.0, 0.0]
	for i: int in mini(m.fighters.size(), 2):
		var left: float = (m.fighters[i] as Fighter).health.blood
		if stats.has("blood_left"):
			left = float((stats["blood_left"] as Array)[i])
		lost[i] = FighterHealth.START_BLOOD - left
	return MatchReport.build({
		"mode": "online" if is_online else str(m.config.get("mode", "")), "names": m.names, "local_side": local_side,
		"winner": int(result.get("winner", -1)), "reason": str(result.get("reason", "")),
		"hits": m.stats.hits_by_side, "blood_lost": lost, "severs": tally.severs, "combos": tally.longest_combo,
		"fight_s": fight_seconds(int(result.get("ticks", m.tick))), "rating": rating, "unlocked": notes,
	})


## Hides the touch buttons (the readers' overlay layers) under the results screen.
func hide_touch() -> void:
	_show_touch(false)


func _show_touch(on: bool) -> void:
	for r: Variant in match_node.readers:
		if r != null and is_instance_valid(r):
			for c: Node in (r as Node).get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = on


## The fight's own overlays (blood meters, aim aid, touch buttons) step aside while the plates are up.
func _fight_ui(on: bool) -> void:
	var p: MatchPresenter = match_node.presenter
	if p != null:
		if p.hud != null:
			p.hud.visible = on
		if p.aim != null:
			p.aim.visible = on
	_show_touch(on)


# --- intro -------------------------------------------------------------------------------------------------------

func _begin_intro(plates: Array, intro_s: float, fight_s: float) -> void:
	timeline = IntroTimeline.new(intro_s, fight_s, not online)
	_intro = MatchIntro.new()
	_intro.name = "MatchIntro"
	add_child(_intro)
	_intro.setup(plates, timeline.skippable)
	_hold(true)
	_fight_ui(false)
	_cam = Camera3D.new()
	_cam.name = "IntroCamera"
	_cam.fov = CAM_FOV
	match_node.add_child(_cam)
	_cam.current = true
	_swell("cheer", SWELL_START)
	_was_phase = timeline.phase()
	_step(0.0)


func _process(delta: float) -> void:
	if timeline == null or _intro == null:
		return
	_step(delta)


func _step(delta: float) -> void:
	if online:
		timeline.set_time(float(match_node.tick) / float(Engine.physics_ticks_per_second))
	else:
		timeline.advance(delta)
	var ph: String = timeline.phase()
	if ph != _was_phase:
		_was_phase = ph
		if ph != IntroTimeline.PLATES and not _released:
			_release()
	if _cam != null:
		_place_camera(clampf(timeline.t / maxf(timeline.plates_s, 0.01), 0.0, 1.0))
	_intro.show_at(timeline)
	if timeline.done():
		_intro.queue_free()
		_intro = null
		intro_finished.emit()


func _input(event: InputEvent) -> void:
	if not intro_running():
		return
	var press: bool = (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not press:
		return
	get_viewport().set_input_as_handled()  # nothing else (pause, a swing) takes a press while the intro is up
	if timeline.skip():
		_step(0.0)


## FIGHT!: the fighters are free, the fight camera takes over and the crowd roars.
func _release() -> void:
	_released = true
	_hold(false)
	_fight_ui(true)
	intro_end_tick = match_node.tick
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if match_node.presenter != null and match_node.presenter.camera != null:
		match_node.presenter.camera.current = true
	_swell("roar", SWELL_FIGHT)


func _hold(on: bool) -> void:
	if on == _held:
		return
	_held = on
	if online:
		hold_changed.emit(on)
		return
	for i: int in 2:
		if on:
			var r: Variant = match_node.readers[i]
			if r != null and is_instance_valid(r):
				_stashed_devices[i] = (r as InputReader).device
				(r as InputReader).device = "none"
			_stashed_brains[i] = match_node.brains[i]
			match_node.brains[i] = null
		else:
			var r2: Variant = match_node.readers[i]
			if r2 != null and is_instance_valid(r2) and str(_stashed_devices[i]) != "":
				(r2 as InputReader).device = str(_stashed_devices[i])
			if _stashed_brains[i] != null and match_node.brains[i] == null:
				match_node.brains[i] = _stashed_brains[i]
			_stashed_devices[i] = ""
			_stashed_brains[i] = null


## A slow push-in over both fighters: side-on on a landscape screen (both across the frame, a little behind the
## local fighter), end-on from behind the local fighter on a portrait one. `k` 0..1 over the plates.
func _place_camera(k: float) -> void:
	if match_node.fighters.size() < 2:
		return
	var me: Vector3 = ((match_node.fighters[local_side] as Fighter).parts["pelvis"] as Node3D).global_position
	var them: Vector3 = ((match_node.fighters[1 - local_side] as Fighter).parts["pelvis"] as Node3D).global_position
	var mid: Vector3 = Vector3((me.x + them.x) * 0.5, 0.0, (me.z + them.z) * 0.5)
	var line: Vector3 = Vector3(them.x - me.x, 0.0, them.z - me.z)
	var gap: float = line.length()
	line = line.normalized() if gap > 0.01 else Vector3.FORWARD
	var side: Vector3 = line.cross(Vector3.UP)
	var e: float = k * k * (3.0 - 2.0 * k)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	var ang: float
	var dist: float
	var height: float
	if aspect >= 1.2:
		var half_w: float = tan(deg_to_rad(CAM_FOV * 0.5)) * aspect  # tan of half the horizontal view
		var fit: float = (gap * 0.5 + FIT_MARGIN) / half_w
		ang = lerpf(CAM_ANGLE.x, CAM_ANGLE.y, e)
		dist = fit * lerpf(CAM_PUSH.x, CAM_PUSH.y, e)
		height = lerpf(CAM_HEIGHT.x, CAM_HEIGHT.y, e)
	else:
		ang = PI * 0.5 - lerpf(CAM_ANGLE.x, CAM_ANGLE.y, e) * 0.5
		dist = gap * 0.5 + lerpf(CAM_BEHIND.x, CAM_BEHIND.y, e)
		height = lerpf(CAM_HEIGHT.x, CAM_HEIGHT.y, e) + PORTRAIT_LIFT
	var dir: Vector3 = side * cos(ang) - line * sin(ang)
	var pos: Vector3 = mid + dir * dist
	var room: float = Tuning.shared().arena_radius - WALL_ROOM
	if Vector2(pos.x, pos.z).length() > room:  # stay inside the wall
		var flat: Vector2 = Vector2(pos.x, pos.z).normalized() * room
		pos = Vector3(flat.x, 0.0, flat.y)
	_cam.global_position = pos + Vector3.UP * height
	_cam.look_at(mid + Vector3.UP * (LOOK_HEIGHT.x if aspect >= 1.2 else LOOK_HEIGHT.y), Vector3.UP)


## Crowd noise and the stands jumping, through the presenter's own sound director and arena.
func _swell(kind: String, impulse: float) -> void:
	var p: MatchPresenter = match_node.presenter
	if p == null:
		return
	if p.sfx != null:
		p.sfx.crowd.add(impulse)
		p.sfx.play_2d("crowd/%s" % kind)
	if p.arena != null:
		p.arena.crowd_react(kind)


func _exit_tree() -> void:
	if _held and not online:
		_hold(false)
