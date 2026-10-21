class_name MatchStats
extends RefCounted
## Pure per-match numbers. Fed from the fighters' hit and gore events and from both debug_frames every tick; the
## Match owns one and puts `to_dict()` into its result. No Nodes, no wall clock (the Match sets `wall_time_s`).
##
## Definitions: a "hit" is a resolved weapon contact on a body (weapon-on-weapon contacts count as `parries`).
## "Swinging" is a tip speed of SWING_SPEED or more. "Stuck" is both fighters' pelvis speed under STUCK_SPEED and
## both tips slower than STUCK_TIP; `stuck_s` is the time spent stuck beyond STUCK_GRACE_S, summed over the match.
## An "explosion" is a tick where any body part moves faster than EXPLODE_SPEED, is NaN/inf, or falls below FALL_Y.

const SWING_SPEED: float = 2.5
const STUCK_SPEED: float = 0.2
const STUCK_TIP: float = 1.5
const STUCK_GRACE_S: float = 3.0
const EXPLODE_SPEED: float = 40.0
const FALL_Y: float = -3.0
const FINISHERS: PackedStringArray = ["run_through", "gut", "behead", "skull_crush"]
const DOWN_STATES: PackedStringArray = ["down", "ko", "getting_up"]

var ticks: int = 0
var hits: int = 0
var hits_by_side: Array = [0, 0]
var contact_kinds: Dictionary = {"edge": 0, "point": 0, "flat": 0, "blunt": 0}
var parries: int = 0
var max_tip_speed: float = 0.0
var severs: int = 0
var finisher: String = ""
var disarms: int = 0
var armor_dislodged: int = 0
var self_hits: int = 0
var knockdowns: int = 0
var time_down_s: float = 0.0
var stuck_s: float = 0.0
var explosions: int = 0
var wall_time_s: float = 0.0
var blood_left: Array = [5.0, 5.0]

var _swing_sum: float = 0.0
var _swing_ticks: int = 0
var _stuck_run: float = 0.0
var _prev_pos: Dictionary = {}
var _prev_state: Array = ["", ""]


## A resolved hit event (Fighter.hit payload).
func on_hit(ev: Dictionary) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		if bool(ev.get("disarmed", false)):
			disarms += 1
		parries += 1
		return
	hits += 1
	var att: int = int(ev.get("attacker", 0))
	var tgt: int = int(ev.get("target", 1 - att))
	if att == 0 or att == 1:
		hits_by_side[att] = int(hits_by_side[att]) + 1
	if att == tgt:
		self_hits += 1
	var kind: String = str(ev.get("contact", ""))
	if contact_kinds.has(kind):
		contact_kinds[kind] = int(contact_kinds[kind]) + 1
	if bool(ev.get("disarmed", false)):
		disarms += 1
	if bool(ev.get("dislodge", false)):
		armor_dislodged += 1
	var fin: String = str(ev.get("finisher", ""))
	if fin != "":
		finisher = fin


## A Fighter.gore payload.
func on_gore(ev: Dictionary) -> void:
	var kind: String = str(ev.get("kind", ""))
	if kind == "sever" or kind == "behead":
		severs += 1
	if finisher == "" and FINISHERS.has(kind) and kind != "gut":
		finisher = kind


## Both fighters' debug_frame() dictionaries (side order), once per physics tick.
func on_frames(frames: Array, dt: float) -> void:
	ticks += 1
	var still: bool = true
	for fr: Dictionary in frames:
		var side: int = int(fr.get("side", 0))
		var tip: float = float(fr.get("tip_speed", 0.0))
		if tip == tip:
			max_tip_speed = maxf(max_tip_speed, tip)
			if tip >= SWING_SPEED:
				_swing_sum += tip
				_swing_ticks += 1
		var state: String = str(fr.get("state", "standing"))
		if DOWN_STATES.has(state):
			time_down_s += dt
		if side >= 0 and side < 2:
			var prev: String = _prev_state[side]
			if state == "down" and prev != "" and prev != "down" and prev != "ko":
				knockdowns += 1
			_prev_state[side] = state
		var pv: Vector3 = fr.get("pelvis_vel", Vector3.ZERO)
		if not (pv.length() < STUCK_SPEED) or not (tip < STUCK_TIP):
			still = false
		if _check_explosion(fr, dt):
			explosions += 1
	if still and frames.size() >= 2:
		_stuck_run += dt
		if _stuck_run > STUCK_GRACE_S:
			stuck_s += dt
	else:
		_stuck_run = 0.0


func _check_explosion(fr: Dictionary, dt: float) -> bool:
	var bad: bool = false
	var side: int = int(fr.get("side", 0))
	var parts: Dictionary = fr.get("parts", {})
	for n: Variant in parts:
		var p: Vector3 = (parts[n] as Dictionary).get("pos", Vector3.ZERO)
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)) or p.y < FALL_Y:
			bad = true
			continue
		var key: String = "%d/%s" % [side, n]
		if _prev_pos.has(key) and dt > 0.0:
			var spd: float = ((_prev_pos[key] as Vector3).distance_to(p)) / dt
			if not (spd <= EXPLODE_SPEED):
				bad = true
		_prev_pos[key] = p
	var pel: Vector3 = fr.get("pelvis_vel", Vector3.ZERO)
	if not (pel.length() <= EXPLODE_SPEED):
		bad = true
	return bad


func mean_tip_speed() -> float:
	return _swing_sum / float(_swing_ticks) if _swing_ticks > 0 else 0.0


func to_dict() -> Dictionary:
	return {
		"ticks": ticks, "hits": hits, "hits_by_side": hits_by_side.duplicate(),
		"contact_kinds": contact_kinds.duplicate(), "parries": parries,
		"max_tip_speed": max_tip_speed, "mean_tip_speed": mean_tip_speed(), "severs": severs, "finisher": finisher,
		"disarms": disarms, "armor_dislodged": armor_dislodged, "self_hits": self_hits, "knockdowns": knockdowns,
		"time_down_s": time_down_s, "stuck_s": stuck_s, "explosions": explosions, "wall_time_s": wall_time_s,
		"blood_left": blood_left.duplicate(),
	}
