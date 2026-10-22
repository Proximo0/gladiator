class_name FightTally
extends RefCounted
## Pure per-side fight numbers for the results screen that MatchStats does not keep: blows landed, limbs each side
## cut off the other, and each side's longest combo. Fed from the fighters' hit and gore signals with the fight
## time of the event, on the host and on an online client alike (the client re-emits the host's events).
##
## A combo is a run of blows by one fighter with no blow landed back, each within `gap_s` of the previous one.
## Contacts closer than `merge_s` to the last counted blow are the same swing touching several parts: one blow.

var hits: Array[int] = [0, 0]  ## blows landed by each side (merged contacts count once)
var severs: Array[int] = [0, 0]  ## limbs (and heads) each side cut off the other
var longest_combo: Array[int] = [0, 0]
var finisher: String = ""

var _run_side: int = -1
var _run_len: int = 0
var _last_t: float = -1.0e9


## A Fighter.hit payload at fight time `t_s` (seconds).
func on_hit(ev: Dictionary, t_s: float, gap_s: float, merge_s: float) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		return
	var att: int = int(ev.get("attacker", -1))
	var tgt: int = int(ev.get("target", -1))
	if att < 0 or att > 1 or att == tgt:
		return
	var fin: String = str(ev.get("finisher", ""))
	if fin != "" and finisher == "":
		finisher = fin
	var dt: float = t_s - _last_t
	if att == _run_side and dt < merge_s:
		return  # the same swing touching another part
	hits[att] += 1
	if att == _run_side and dt <= gap_s:
		_run_len += 1
	else:
		_run_side = att
		_run_len = 1
	_last_t = t_s
	longest_combo[att] = maxi(longest_combo[att], _run_len)


## A Fighter.gore payload from the fighter on `victim_side`.
func on_gore(ev: Dictionary, victim_side: int) -> void:
	var kind: String = str(ev.get("kind", ""))
	if (kind == "sever" or kind == "behead") and (victim_side == 0 or victim_side == 1):
		severs[1 - victim_side] += 1
