class_name Match
extends Node3D
## One 1v1 fight in the sand arena, built in code. Owns two Fighters, a FighterBrain per bot side and an InputReader
## per human side. Every physics tick, before the fighters step (this node runs first, priority 0 vs the fighters'
## 10): one FighterInput per side is collected, `inputs_applied(tick, inputs)` is emitted with their `to_array()`s,
## then each fighter gets its input. With `presentation` off there is only a floor and a wall collider (fast and
## robust for bot runs); with it on, the MatchPresenter adds arena visuals, sand, blood, sound, HUD and camera.
## Bot vs bot loops with a new seed after a pause when `loop` is on (default for presented bot vs bot).
##
## setup(config) keys (all optional): mode, seed, loadouts, personalities, presentation, time_limit_s, loop,
## fight_start_tick.
## The fight clock (time limit, result "fight_ticks", ranked reports) runs from `fight_start_tick`, the tick the
## pre-fight intro releases the fighters: fixed by the host's START online, set by `start_fight_clock` offline, and
## held at 0 between `hold_fight_clock` and that call. Result "ticks" stays the match tick (replays, net sync).
## Pure helpers: MatchConfig (setup), MatchJudge (end rules), MatchStats (numbers).

signal inputs_applied(tick: int, inputs: Array)
signal match_over(result: Dictionary)

const BRAIN_SEED_MUL: int = 7919
const WALL_SIDES: int = 48
const WALL_DEPTH: float = 1.0
const WALL_HEIGHT: float = 3.0
const DEFAULT_PAUSE_S: float = 4.0
const VICTORY_DELAY_S: float = 1.4
const PLAYER_DEVICE: String = "kbm"
const PLAYER2_DEVICE: String = "pad1"

var tick: int = 0
var fighters: Array = []
var seed: int = 0
var config: Dictionary = {}
var stats: MatchStats = MatchStats.new()
var brains: Array = [null, null]
var readers: Array = [null, null]
var presenter: MatchPresenter = null
var result: Dictionary = {}
var over: bool = false
var names: Array = ["", ""]
var fight_start_tick: int = 0  ## the tick the fight clock starts from (the intro's release); 0 with no intro

var _judge: MatchJudge = null
var _built: bool = false
var _forced: Array = []
var _forced_from: int = 0
var _replaying: bool = false
var _pause_ticks: int = 0
var _victory_at: int = -1
var _start_msec: int = 0
var _slowmo_until: int = -1
var _slowmo_from: int = -1  ## tick the end slow motion started; its curve is FinisherCine's
var _slowmo_kind: String = ""
var _finisher_seen: String = ""
var _clock_held: bool = false


func _init() -> void:
	process_physics_priority = 0


func setup(p_config: Dictionary = {}) -> void:
	config = MatchConfig.normalize(p_config, Flags.seed_value())
	seed = int(config["seed"])
	if is_inside_tree() and not _built:
		_build()


func _ready() -> void:
	if not config.is_empty():
		_build()
	else:
		_default_setup.call_deferred()  ## setup() may still come right after add_child


func _default_setup() -> void:
	if not _built and config.is_empty():
		setup({})


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Replay mode: the next ticks use these recorded inputs ([[5 ints], [5 ints]] per tick) instead of brains and
## readers; past the end both fighters get neutral input.
func force_inputs(tick_inputs: Array) -> void:
	_forced = tick_inputs
	_forced_from = tick
	_replaying = true


func is_practice() -> bool:
	return str(config.get("mode", "")) == "practice"


## Practice only: rebuilds the bout (both fighters back at their spawns) with new loadouts; null keeps a side's.
## The training dummy's blood is set to `dummy_blood_frac` of the way from death (blood_death) to full when that is >= 0
## (a low value opens the finisher window).
func reset_practice(player_loadout: Variant = null, dummy_blood_frac: float = -1.0) -> void:
	if not is_practice() or not _built:
		return
	var lo: Array = config["loadouts"]
	if player_loadout is Dictionary:
		lo[0] = (player_loadout as Dictionary).duplicate(true)
	_teardown()
	_replaying = false
	_start_match()
	if dummy_blood_frac >= 0.0:
		var dead_l: float = Tuning.shared().blood_death
		(fighters[1] as Fighter).health.blood = lerpf(dead_l, FighterHealth.START_BLOOD, clampf(dummy_blood_frac, 0.0, 1.0))


func presenting() -> bool:
	return bool(config.get("presentation", true))


## Hash of both fighters and the tick, for replay comparison.
func state_hash() -> int:
	var a: Array = [tick]
	for f: Fighter in fighters:
		a.append(f.state_hash())
	return hash(a)


# --- build -------------------------------------------------------------------------------------------------------

func _build() -> void:
	_built = true
	if presenting():
		presenter = MatchPresenter.new()
		presenter.name = "Presenter"
		add_child(presenter)
		presenter.build("follow" if str(config["mode"]) in ["player_vs_cpu", "practice"] else "wide")
		Flags.register_hash(Callable(self, "state_hash"))
	else:
		_build_collision()
	_start_match()


## Floor, wall and dressing colliders only: the same shapes the Arena builds, without any visual.
func _build_collision() -> void:
	var radius: float = Tuning.shared().arena_radius
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.0
	floor_body.physics_material_override = pm
	var fshape := BoxShape3D.new()
	var side: float = radius * 2.0 + 10.0
	fshape.size = Vector3(side, 1.0, side)
	var fcs := CollisionShape3D.new()
	fcs.shape = fshape
	fcs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(fcs)
	add_child(floor_body)
	var wall := StaticBody3D.new()
	wall.name = "WallBody"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var apothem_out: float = radius + WALL_DEPTH
	var width: float = 2.0 * apothem_out * tan(PI / float(WALL_SIDES)) + 0.3
	for i: int in WALL_SIDES:
		var a: float = TAU * (float(i) + 0.5) / float(WALL_SIDES)
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, WALL_HEIGHT + 2.5, WALL_DEPTH)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Arena.ring_basis(a),
				Vector3((radius + WALL_DEPTH * 0.5) * cos(a), (WALL_HEIGHT - 2.5) * 0.5, (radius + WALL_DEPTH * 0.5) * sin(a)))
		wall.add_child(cs)
	ArenaDressing.add_colliders(wall, DecorLayout.colliders(radius))
	add_child(wall)


func _start_match() -> void:
	tick = 0
	over = false
	result = {}
	stats = MatchStats.new()
	stats.combo_gap_s = Tuning.shared().combo_gap_s
	stats.combo_merge_s = Tuning.shared().combo_merge_s
	fight_start_tick = int(config.get("fight_start_tick", 0))
	_clock_held = false
	_pause_ticks = 0
	_victory_at = -1
	_slowmo_until = -1
	_finisher_seen = ""
	_start_msec = Time.get_ticks_msec()
	Engine.time_scale = 1.0
	_judge = MatchJudge.new(float(config["time_limit_s"]))
	names = MatchConfig.names_for(seed)
	if is_practice():
		names = ["Discipulus", "Palus"]
	var mode: String = str(config["mode"])
	var radius: float = Tuning.shared().arena_radius
	fighters = []
	for side: int in 2:
		var f := Fighter.new()
		f.name = "Fighter%d" % side
		add_child(f)
		f.global_transform = Arena.spawn_transform(side, radius)
		if mode == "practice":  # the training dummy starts close, so the first swing can reach it
			f.global_transform.origin.z = signf(f.global_transform.origin.z) * Tuning.shared().practice_half_gap
		f.look_seed = seed
		f.setup((config["loadouts"] as Array)[side], side, Tuning.shared())
		fighters.append(f)
	(fighters[0] as Fighter).opponent = fighters[1]
	(fighters[1] as Fighter).opponent = fighters[0]
	for side: int in 2:
		var f: Fighter = fighters[side]
		f.hit.connect(_on_hit)
		f.gore.connect(_on_gore)
	brains = [null, null]
	readers = [null, null]
	for side: int in 2:
		var human: bool = (mode == "local_2p") or ((mode == "player_vs_cpu" or mode == "practice") and side == 0)
		if human:
			var r := InputReader.new()
			r.device = _device_for(side, mode)
			r.name = "Reader%d" % side
			add_child(r)
			readers[side] = r
		elif mode != "practice":  # practice: the training dummy has no brain and stands still
			brains[side] = FighterBrain.new(seed * BRAIN_SEED_MUL + side * 104729 + 17,
					(config["personalities"] as Array)[side])
	if presenter != null:
		presenter.begin(fighters, names, 0)


func _device_for(side: int, mode: String) -> String:
	if mode == "local_2p":
		return PLAYER_DEVICE if side == 0 else PLAYER2_DEVICE
	return InputReader.default_device(DisplayServer.is_touchscreen_available(), Flags.args)


func _teardown() -> void:
	if presenter != null:
		presenter.end_match()
	for f: Variant in fighters:
		if is_instance_valid(f):
			remove_child(f as Node)
			(f as Node).free()
	for r: Variant in readers:
		if r != null and is_instance_valid(r):
			remove_child(r as Node)
			(r as Node).free()
	fighters = []
	readers = [null, null]


# --- the tick ----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _built or fighters.size() < 2:
		return
	if over:
		_tick_after()
		return
	var frames: Array = [(fighters[0] as Fighter).debug_frame(), (fighters[1] as Fighter).debug_frame()]
	for i: int in 2:
		frames[i]["blood"] = (fighters[i] as Fighter).health.blood
		frames[i]["hp"] = (fighters[i] as Fighter).health.hp_total_frac()
	stats.on_frames(frames, delta)
	if presenter != null:
		presenter.tick(frames, delta)
	var verdict: Dictionary = {} if is_practice() else _judge.update(frames, fight_ticks(), delta)
	if not verdict.is_empty():
		_finish(verdict, frames)
		_apply_idle()
		return
	var inputs: Array = _collect_inputs(frames, delta)
	var arrays: Array = [(inputs[0] as FighterInput).to_array(), (inputs[1] as FighterInput).to_array()]
	inputs_applied.emit(tick, arrays)
	for i: int in 2:
		(fighters[i] as Fighter).apply_input(inputs[i])
	tick += 1


## Ticks of fighting so far: from `fight_start_tick`, 0 before it and while the clock is held.
func fight_ticks() -> int:
	return 0 if _clock_held else maxi(tick - fight_start_tick, 0)


## Offline intro: the fight clock waits (fight_ticks() stays 0) until `start_fight_clock`.
func hold_fight_clock() -> void:
	_clock_held = true


## Offline intro release: the fight clock counts from this tick.
func start_fight_clock() -> void:
	_clock_held = false
	fight_start_tick = tick


func _collect_inputs(frames: Array, delta: float) -> Array:
	if _replaying:
		var k: int = tick - _forced_from
		if k >= 0 and k < _forced.size():
			var row: Array = _forced[k]
			return [FighterInput.from_array(row[0]), FighterInput.from_array(row[1])]
		return [FighterInput.new(), FighterInput.new()]
	var out: Array = []
	for i: int in 2:
		if readers[i] != null:
			out.append((readers[i] as InputReader).read())
		elif brains[i] == null:
			out.append(FighterInput.new())  # the practice dummy
		else:
			out.append((brains[i] as FighterBrain).think(frames[i], frames[1 - i], delta))
	return out


func _apply_idle() -> void:
	for f: Fighter in fighters:
		f.apply_input(FighterInput.new())


func _finish(verdict: Dictionary, frames: Array) -> void:
	over = true
	stats.wall_time_s = float(Time.get_ticks_msec() - _start_msec) / 1000.0
	for i: int in 2:
		stats.blood_left[i] = (fighters[i] as Fighter).health.blood
	result = {
		"winner": int(verdict["winner"]), "reason": str(verdict["reason"]), "ticks": tick, "fight_ticks": fight_ticks(), "seed": seed,
		"loadouts": (config["loadouts"] as Array).duplicate(true),
		"personalities": (config["personalities"] as Array).duplicate(true), "stats": stats.to_dict(),
	}
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	_pause_ticks = roundi(_t("match_pause_s", DEFAULT_PAUSE_S) / delta)
	if presenter != null:
		var slow: bool = _finisher_seen != "" or str(verdict["reason"]) == "ko"
		if slow:
			_slowmo_kind = _finisher_seen
			_slowmo_from = tick
			_slowmo_until = tick + roundi(FinisherCine.length_s(_slowmo_kind, Tuning.shared()) / delta)
			Engine.time_scale = FinisherCine.time_scale_at(_slowmo_kind, 0.0, Tuning.shared())
		if str(verdict["reason"]) == "ko":
			presenter.announce("SOPITVS / Knocked out")
		_victory_at = tick + roundi(VICTORY_DELAY_S / delta)
	match_over.emit(result)


func _tick_after() -> void:
	tick += 1
	_apply_idle()
	if presenter == null:
		set_physics_process(false)
		return
	if _slowmo_until >= 0 and tick >= _slowmo_until:
		_slowmo_until = -1
		Engine.time_scale = 1.0
	elif _slowmo_until >= 0:
		# Ticks are real time (the physics step shrinks, the tick rate does not).
		Engine.time_scale = FinisherCine.time_scale_at(_slowmo_kind, float(tick - _slowmo_from) / float(Engine.physics_ticks_per_second), Tuning.shared())
	if _victory_at >= 0 and tick >= _victory_at:
		_victory_at = -1
		presenter.announce(MatchJudge.result_banner(result, names))
	_pause_ticks -= 1
	if _pause_ticks <= 0 and bool(config.get("loop", false)):
		_restart()


func _restart() -> void:
	var next_cfg: Dictionary = {
		"mode": config["mode"], "seed": seed + 1, "presentation": config["presentation"],
		"time_limit_s": config["time_limit_s"], "loop": config["loop"],
	}
	_teardown()
	config = MatchConfig.normalize(next_cfg, seed + 1)
	seed = int(config["seed"])
	_replaying = false
	_start_match()


# --- events ------------------------------------------------------------------------------------------------------

func _on_hit(ev: Dictionary) -> void:
	stats.on_hit(ev, float(tick) / float(Engine.physics_ticks_per_second))
	var fin: String = str(ev.get("finisher", ""))
	var tgt: int = int(ev.get("target", -1))
	if tgt >= 0 and tgt < 2 and fighters.size() == 2:
		var victim: Fighter = fighters[tgt]
		if victim.health != null and victim.health.dead:
			var cause: String = fin
			if cause == "" and (bool(ev.get("behead", false)) or (bool(ev.get("sever", false)) and str(ev.get("part", "")) == "head")):
				cause = "behead"
			_judge.note_cause(tgt, cause)
	if fin != "" and not bool(ev.get("hit_on_weapon", false)):
		_finisher_seen = fin
		if presenter != null:
			presenter.announce(MatchJudge.finisher_banner(fin))
	if presenter != null:
		presenter.on_hit(ev)


func _on_gore(ev: Dictionary) -> void:
	stats.on_gore(ev)


func _t(field: String, fallback: float) -> float:
	var v: Variant = Tuning.shared().get(field)
	return float(v) if (v is float or v is int) else fallback
