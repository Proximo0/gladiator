class_name BladeTrailLogic
extends RefCounted
## Pure state of a glowing blade's motion trail: a short history of (base, tip) edge positions that fades with age.
## Samples are recorded only while the blade moves faster than MIN_SPEED, so a resting blade leaves no smear, and the
## cap on stored samples comes from the graphics tier (0 = no trail). Presentation only. Unit-tested.

const MIN_SPEED: float = 3.5
const MAX_AGE: float = 0.16

var max_samples: int = 18
var _bases: Array[Vector3] = []
var _tips: Array[Vector3] = []
var _ages: Array[float] = []


func count() -> int:
	return _ages.size()


## Adds this frame's edge line when `speed` is high enough. Returns whether it was recorded.
func push(base: Vector3, tip: Vector3, speed: float) -> bool:
	if max_samples <= 0 or speed < MIN_SPEED:
		return false
	_bases.append(base)
	_tips.append(tip)
	_ages.append(0.0)
	while _ages.size() > max_samples:
		_bases.remove_at(0)
		_tips.remove_at(0)
		_ages.remove_at(0)
	return true


## Ages every sample and drops the old ones.
func step(delta: float) -> void:
	var i: int = _ages.size() - 1
	while i >= 0:
		_ages[i] += delta
		if _ages[i] > MAX_AGE:
			# Samples are in age order, so everything before this one is older still.
			_bases = _bases.slice(i + 1)
			_tips = _tips.slice(i + 1)
			_ages = _ages.slice(i + 1)
			break
		i -= 1


## Opacity 0..1 of sample `i` (newest brightest).
func alpha(i: int) -> float:
	if i < 0 or i >= _ages.size():
		return 0.0
	return clampf(1.0 - _ages[i] / MAX_AGE, 0.0, 1.0)


func base_at(i: int) -> Vector3:
	return _bases[i]


func tip_at(i: int) -> Vector3:
	return _tips[i]


func clear() -> void:
	_bases.clear()
	_tips.clear()
	_ages.clear()
