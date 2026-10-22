class_name IntroTimeline
extends RefCounted
## Pure clock of the pre-fight intro: "plates" (name plates up, fighters held) for `plates_s`, then "fight" (the
## FIGHT! stinger, fighters free) for `fight_s`, then "" (done). Offline it is fed frame time and a skip jumps ahead;
## online it is set from the match tick (both peers release on the same host tick) and cannot be skipped.

const PLATES: String = "plates"
const FIGHT: String = "fight"
const SLIDE_S: float = 0.35  ## plates slide in over this long
const OUT_S: float = 0.3  ## and out over this long once FIGHT! hits
const PUNCH_S: float = 0.18  ## the stinger's scale punch
const FADE_S: float = 0.3  ## the stinger's fade at its end

var plates_s: float = 2.3
var fight_s: float = 0.8
var skippable: bool = true
var t: float = 0.0


func _init(p_plates_s: float = 2.3, p_fight_s: float = 0.8, p_skippable: bool = true) -> void:
	plates_s = maxf(p_plates_s, 0.0)
	fight_s = maxf(p_fight_s, 0.05)
	skippable = p_skippable


func advance(delta: float) -> void:
	t += maxf(delta, 0.0)


## Online: the time is the match's (monotonic: a late snapshot never moves it back).
func set_time(seconds: float) -> void:
	t = maxf(t, seconds)


## Any button: the plates jump to FIGHT!, and a second press during FIGHT! ends it. Returns true when it did something.
func skip() -> bool:
	if not skippable or done():
		return false
	if t < plates_s:
		t = plates_s
	else:
		t = plates_s + fight_s
	return true


func phase() -> String:
	if t < plates_s:
		return PLATES
	if t < plates_s + fight_s:
		return FIGHT
	return ""


func done() -> bool:
	return phase() == ""


## True while the fighters are held (only during the plates).
func holding() -> bool:
	return phase() == PLATES


## 0..1: how far the plates are on screen (in, then out once FIGHT! hits).
func plate_in() -> float:
	if t < plates_s:
		return _ease_out(t / SLIDE_S)
	return 1.0 - _ease_out((t - plates_s) / OUT_S)


## The stinger's scale (big to 1 on the hit) and alpha (fades at the end); scale 0 when it is not up.
func stinger() -> Vector2:
	if phase() != FIGHT:
		return Vector2.ZERO
	var k: float = t - plates_s
	var scale: float = lerpf(1.8, 1.0, _ease_out(k / PUNCH_S))
	var alpha: float = clampf((fight_s - k) / FADE_S, 0.0, 1.0)
	return Vector2(scale, alpha)


static func _ease_out(x: float) -> float:
	var c: float = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c) * (1.0 - c)
