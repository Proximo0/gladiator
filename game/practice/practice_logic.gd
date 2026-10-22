class_name PracticeLogic
extends RefCounted
## Pure step machine for the guided Practice mode. Each tick the session feeds it an observation of the real fighter
## and it advances when the observed state satisfies the current step: no timers decide success, only skip does.
## Steps: move, aim, swing, thrust, strike, shove, kick, hold, roll, grab, finish. After the last one `complete` is true
## (free practice).
##
## Observation keys given to update(): pos (Vector2 x,z metres), aim (Vector2, -1..1, x right y up), tip_speed (m/s),
## min_speed (the damage threshold, Tuning.damage_min_speed), swing (bool), thrust (bool), rolling (bool),
## armed (bool, a real weapon in the right hand), hits (int, cumulative real hits the player landed on the dummy),
## finishers (int, cumulative killing blows the player landed), shoves and kicks (int, cumulative shoves and kicks
## that landed on the dummy), holding (bool, the player's free hand holds the dummy).
## update() returns event strings: "enter:<id>" (the session sets the scene up: grab drops the weapon, finish lowers the
## dummy's blood), "done:<id>", "complete".

const STEP_IDS: PackedStringArray = ["move", "aim", "swing", "thrust", "strike", "shove", "kick", "hold", "roll", "grab",
	"finish"]
const DATA_PATH: String = "res://data/practice.json"
const DEFAULTS: Dictionary = {
	"move_distance_m": 4.0, "aim_extreme": 0.6, "aim_extremes_needed": 3, "swings_needed": 3, "swing_rearm_frac": 0.6,
	"thrusts_needed": 2, "thrust_window_s": 0.7, "hits_needed": 3, "rolls_needed": 2, "grab_unarmed_s": 0.01,
	"stuck_after_s": 40.0, "finish_dummy_blood_frac": 0.15, "dummy_reset_delay_s": 1.5, "shoves_needed": 2,
	"kicks_needed": 2, "hold_s": 1.0,
}

var cfg: Dictionary = {}
var index: int = 0
var complete: bool = false
var skipped: PackedStringArray = PackedStringArray()
var step_time: float = 0.0
var best_tip: float = 0.0  ## the highest tip speed seen during the current step (the prompt shows it)

var _entered: bool = false
var _last_pos: Vector2 = Vector2.INF
var _dist: float = 0.0
var _dirs: Dictionary = {}
var _count: int = 0
var _armed_swing: bool = true
var _thrust_prev: bool = false
var _thrust_t: float = -1.0
var _thrust_hit: bool = false
var _roll_prev: bool = false
var _base_hits: int = 0
var _base_fin: int = 0
var _seen_unarmed_t: float = 0.0
var _hits_now: int = 0
var _fin_now: int = 0
var _base_close: int = 0  ## the shove or kick count when the step began
var _close_now: int = 0
var _held_t: float = 0.0  ## seconds the current hold has lasted


static func load_config() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			for k: Variant in (parsed as Dictionary):
				out[k] = (parsed as Dictionary)[k]
	return out


func _init(p_cfg: Dictionary = {}) -> void:
	cfg = DEFAULTS.duplicate()
	for k: Variant in p_cfg:
		cfg[k] = p_cfg[k]


func step_id() -> String:
	return "" if complete else STEP_IDS[index]


func step_count() -> int:
	return STEP_IDS.size()


## 0..1 progress through the current step (1 once complete).
func progress() -> float:
	if complete:
		return 1.0
	match STEP_IDS[index]:
		"move":
			return clampf(_dist / _f("move_distance_m"), 0.0, 1.0)
		"aim":
			return clampf(float(_dirs.size()) / _f("aim_extremes_needed"), 0.0, 1.0)
		"swing", "thrust", "roll":
			return clampf(float(_count) / _need(STEP_IDS[index]), 0.0, 1.0)
		"shove", "kick":
			return clampf(float(_close_now - _base_close) / _need(STEP_IDS[index]), 0.0, 1.0)
		"hold":
			return clampf(_held_t / _f("hold_s"), 0.0, 1.0)
		"strike":
			return clampf(float(_hits_now - _base_hits) / _f("hits_needed"), 0.0, 1.0)
		"grab":
			return 0.5 if _seen_unarmed_t >= _f("grab_unarmed_s") else 0.0
		"finish":
			return 0.0
	return 0.0


## "2 / 3" style counter for the prompt ("" for steps without one).
func counter_text() -> String:
	if complete:
		return ""
	var id: String = STEP_IDS[index]
	match id:
		"swing", "thrust", "roll":
			return "%d / %d" % [mini(_count, int(_need(id))), int(_need(id))]
		"shove", "kick":
			return "%d / %d" % [clampi(_close_now - _base_close, 0, int(_need(id))), int(_need(id))]
		"strike":
			return "%d / %d" % [clampi(_hits_now - _base_hits, 0, int(_f("hits_needed"))), int(_f("hits_needed"))]
		"aim":
			return "%d / %d" % [mini(_dirs.size(), int(_f("aim_extremes_needed"))), int(_f("aim_extremes_needed"))]
		"move":
			return "%d / %d m" % [mini(int(_dist), int(_f("move_distance_m"))), int(_f("move_distance_m"))]
	return ""


## True once the player has been on a step a long while without finishing it (the prompt then offers Skip loudly).
func stuck() -> bool:
	return not complete and step_time >= _f("stuck_after_s")


func skip_step() -> Array:
	if complete:
		return []
	skipped.append(STEP_IDS[index])
	return _advance()


## Skips everything left; returns the events.
func skip_all() -> Array:
	var ev: Array = []
	while not complete:
		ev.append_array(skip_step())
	return ev


func update(obs: Dictionary, delta: float) -> Array:
	var ev: Array = []
	if complete:
		return ev
	if not _entered:
		_enter(obs, ev)
	step_time += delta
	_hits_now = int(obs.get("hits", 0))
	_fin_now = int(obs.get("finishers", 0))
	if STEP_IDS[index] == "shove" or STEP_IDS[index] == "kick":
		_close_now = int(obs.get(STEP_IDS[index] + "s", 0))
	var tip: float = float(obs.get("tip_speed", 0.0))
	best_tip = maxf(best_tip, tip)
	var min_speed: float = maxf(float(obs.get("min_speed", 3.0)), 0.01)
	var ok: bool = false
	match STEP_IDS[index]:
		"move":
			var p: Vector2 = obs.get("pos", Vector2.ZERO)
			if _last_pos != Vector2.INF:
				_dist += minf(p.distance_to(_last_pos), 0.5)  # a teleport (a reset) is not walking
			_last_pos = p
			ok = _dist >= _f("move_distance_m")
		"aim":
			var a: Vector2 = obs.get("aim", Vector2.ZERO)
			var e: float = _f("aim_extreme")
			if a.x <= -e:
				_dirs["left"] = true
			if a.x >= e:
				_dirs["right"] = true
			if a.y >= e:
				_dirs["up"] = true
			if a.y <= -e:
				_dirs["down"] = true
			ok = _dirs.size() >= int(_f("aim_extremes_needed"))
		"swing":
			if bool(obs.get("swing", false)) and _armed_swing and tip >= min_speed:
				_count += 1
				_armed_swing = false
			elif tip < min_speed * _f("swing_rearm_frac"):
				_armed_swing = true
			ok = _count >= int(_need("swing"))
		"thrust":
			var th: bool = bool(obs.get("thrust", false))
			if th and not _thrust_prev:
				_thrust_t = 0.0
				_thrust_hit = false
			if _thrust_t >= 0.0:
				_thrust_t += delta
				if tip >= min_speed and not _thrust_hit:
					_thrust_hit = true
					_count += 1
				if _thrust_t > _f("thrust_window_s"):
					_thrust_t = -1.0
			_thrust_prev = th
			ok = _count >= int(_need("thrust"))
		"strike":
			ok = _hits_now - _base_hits >= int(_f("hits_needed"))
		"shove", "kick":
			ok = _close_now - _base_close >= int(_need(STEP_IDS[index]))
		"hold":
			_held_t = _held_t + delta if bool(obs.get("holding", false)) else 0.0  # one unbroken hold
			ok = _held_t >= _f("hold_s")
		"roll":
			var r: bool = bool(obs.get("rolling", false))
			if r and not _roll_prev:
				_count += 1
			_roll_prev = r
			ok = _count >= int(_need("roll"))
		"grab":
			if not bool(obs.get("armed", true)):
				_seen_unarmed_t += delta
			elif _seen_unarmed_t >= _f("grab_unarmed_s"):
				ok = true  # it was really off, and it is in the hand again
		"finish":
			ok = _fin_now > _base_fin
	if ok:
		ev.append_array(_advance())
	return ev


func _enter(obs: Dictionary, ev: Array) -> void:
	_entered = true
	step_time = 0.0
	best_tip = 0.0
	_last_pos = Vector2.INF
	_dist = 0.0
	_dirs = {}
	_count = 0
	_armed_swing = true
	_thrust_prev = bool(obs.get("thrust", false))
	_thrust_t = -1.0
	_roll_prev = bool(obs.get("rolling", false))
	_base_hits = int(obs.get("hits", 0))
	_base_fin = int(obs.get("finishers", 0))
	_seen_unarmed_t = 0.0
	_held_t = 0.0
	if STEP_IDS[index] == "shove" or STEP_IDS[index] == "kick":
		_base_close = int(obs.get(STEP_IDS[index] + "s", 0))
		_close_now = _base_close
	ev.append("enter:" + STEP_IDS[index])


func _advance() -> Array:
	var ev: Array = ["done:" + STEP_IDS[index]]
	index += 1
	_entered = false
	best_tip = 0.0
	if index >= STEP_IDS.size():
		complete = true
		index = STEP_IDS.size() - 1
		ev.append("complete")
	return ev


func _f(key: String) -> float:
	return float(cfg.get(key, DEFAULTS.get(key, 0.0)))


func _need(id: String) -> float:
	match id:
		"swing":
			return _f("swings_needed")
		"thrust":
			return _f("thrusts_needed")
		"roll":
			return _f("rolls_needed")
		"shove":
			return _f("shoves_needed")
		"kick":
			return _f("kicks_needed")
	return 1.0
