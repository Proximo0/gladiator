class_name MatchJudge
extends RefCounted
## Pure end-of-match rules. `update(frames, tick, delta)` returns {} while the fight goes on, else
## {winner, reason}. Reasons: "blood_loss", "behead", "gut", "run_through", "skull_crush", "ko", "time". A knock-out while the loser is
## under FAINT_BLOOD_L is the blood cap on consciousness, so it counts as "blood_loss".
## The Match tells it how each fighter died with `note_cause`; a death with no note is "blood_loss".

const DEFAULT_KO_HOLD_S: float = 2.5
const DRAW_BLOOD_L: float = 0.25  ## at the time limit, the blood lead needed to win on points
const FAINT_BLOOD_L: float = 2.75  ## a knocked-out fighter below this much blood fainted from blood loss (cap 0.2 at 2.7 L)
const CAUSES: PackedStringArray = ["behead", "gut", "run_through", "skull_crush"]

var time_limit_s: float = 180.0
var ko_hold_s: float = DEFAULT_KO_HOLD_S
var _causes: Array = ["", ""]
var _ko_time: Array = [0.0, 0.0]


func _init(p_time_limit_s: float = 180.0, p_ko_hold_s: float = DEFAULT_KO_HOLD_S) -> void:
	time_limit_s = p_time_limit_s
	ko_hold_s = p_ko_hold_s


## How `side` died: one of CAUSES. The first note wins.
func note_cause(side: int, cause: String) -> void:
	if side >= 0 and side < 2 and _causes[side] == "" and CAUSES.has(cause):
		_causes[side] = cause


## frames: both debug_frames in side order, each optionally carrying "blood" (litres) for the time-limit decision.
func update(frames: Array, tick: int, delta: float) -> Dictionary:
	var dead: Array = [false, false]
	for i: int in 2:
		var st: String = str(frames[i].get("state", "standing"))
		dead[i] = st == "dead"
		if st == "ko":
			_ko_time[i] = float(_ko_time[i]) + delta
		else:
			_ko_time[i] = 0.0
	if dead[0] and dead[1]:
		return {"winner": -1, "reason": _reason(0)}
	if dead[0] or dead[1]:
		var loser: int = 0 if dead[0] else 1
		return {"winner": 1 - loser, "reason": _reason(loser)}
	var ko0: bool = float(_ko_time[0]) >= ko_hold_s
	var ko1: bool = float(_ko_time[1]) >= ko_hold_s
	if ko0 != ko1:
		var out: int = 0 if ko0 else 1
		var faint: bool = float(frames[out].get("blood", 5.0)) < FAINT_BLOOD_L
		return {"winner": 1 - out, "reason": "blood_loss" if faint else "ko"}
	if float(tick) * delta >= time_limit_s:
		var b0: float = float(frames[0].get("blood", 5.0))
		var b1: float = float(frames[1].get("blood", 5.0))
		var winner: int = -1
		if b0 - b1 > DRAW_BLOOD_L:
			winner = 0
		elif b1 - b0 > DRAW_BLOOD_L:
			winner = 1
		return {"winner": winner, "reason": "time"}
	return {}


func _reason(loser: int) -> String:
	var c: String = _causes[loser]
	return c if c != "" else "blood_loss"


## Banner text ("LATIN / English") for a killing blow kind; "" for anything else.
static func finisher_banner(kind: String) -> String:
	match kind:
		"run_through":
			return "TRANSFIXVS / Run through"
		"gut":
			return "VISCERA EFFVSA / Gutted"
		"behead":
			return "CAPVT ABSCISSVM / Beheaded"
		"skull_crush":
			return "CALVARIA FRACTA / Skull crushed"
	return ""


## Banner for the end of the fight.
static func result_banner(result: Dictionary, names: Array) -> String:
	var w: int = int(result.get("winner", -1))
	if w < 0:
		return "AEQVO MARTE / Evenly matched"
	return "VICTOR / %s" % str(names[w])
