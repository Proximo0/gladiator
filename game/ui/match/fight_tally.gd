class_name FightTally
extends RefCounted
## Pure per-side fight numbers for the results screen that MatchStats does not keep: limbs each side cut off the
## other, and the first finishing blow. Fed from the fighters' hit and gore signals, on the host and on an online
## client alike (the client re-emits the host's events). Blows landed and combos are MatchStats' (`blows_by_side`,
## `longest_combo`), so "Hits landed" and "Longest combo" count the same blows.

var severs: Array[int] = [0, 0]  ## limbs (and heads) each side cut off the other
var finisher: String = ""


## A Fighter.hit payload.
func on_hit(ev: Dictionary) -> void:
	if bool(ev.get("hit_on_weapon", false)):
		return
	var fin: String = str(ev.get("finisher", ""))
	if fin != "" and finisher == "":
		finisher = fin


## A Fighter.gore payload from the fighter on `victim_side`.
func on_gore(ev: Dictionary, victim_side: int) -> void:
	var kind: String = str(ev.get("kind", ""))
	if (kind == "sever" or kind == "behead") and (victim_side == 0 or victim_side == 1):
		severs[1 - victim_side] += 1
