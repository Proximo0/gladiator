class_name WeaponCoat
extends RefCounted
## How bloody one weapon (or fist) is: a coat that grows from the tip down the blade (or over a club's head, a
## shield's face, a fist's knuckles) with every bleeding hit, plus blots where the hits really landed, in the weapon's
## own frame (+Y to the tip, +X the edge). Blood stays and dries; it never washes off in a match. Pure data: no
## nodes, no RNG. Presentation only.

const MAX_BLOTS: int = 4
const DRY_TAU: float = 45.0
const COAT_PER_POINT: float = 0.008  ## coat gained per damage point of cut + pierce
const COAT_PER_BLUNT: float = 0.006
const COAT_MIN_HIT: float = 0.05  ## a bleeding hit always adds at least this much
const BLOT_MIN: float = 0.02  ## blot radius (m)
const BLOT_MAX: float = 0.07
const BLOT_MERGE: float = 0.04
const FIST_BLOT_MAX: float = 0.035  ## knuckles, not the whole fist

var coat: float = 0.0  ## 0 clean .. 1 drenched
var age: float = 1.0e3  ## seconds since the last fresh blood
var slot: int = 0  ## whose blood is on it (palette slot); the last bleeding hit wins
var blots: Array = []  ## Vector4(x, y, z, radius) in the weapon frame, oldest first
var blot_age: PackedFloat32Array = PackedFloat32Array()
var dirty: bool = false


## Blood from a hit: `local_point` in the weapon frame, `cut`/`pierce`/`blunt` the hit's damage, `pal` the victim's
## palette slot. Hits that do not bleed (bruises only) add a little; nothing below MIN_WOUND-sized hits.
func add_hit(local_point: Vector3, cut: float, pierce: float, blunt: float, pal: int, max_blot: float = BLOT_MAX) -> void:
	var sharp: float = cut + pierce
	if sharp < WoundMarks.MIN_WOUND and blunt * 0.35 < WoundMarks.MIN_WOUND:
		return
	var gain: float = maxf(sharp * COAT_PER_POINT + blunt * COAT_PER_BLUNT, COAT_MIN_HIT)
	coat = minf(coat + gain, 1.0)
	age = 0.0
	slot = pal
	var r: float = clampf(BLOT_MIN + (sharp + 0.3 * blunt) * 0.0015, minf(BLOT_MIN, max_blot), max_blot)
	for i: int in blots.size():
		var b: Vector4 = blots[i]
		if Vector3(b.x, b.y, b.z).distance_to(local_point) < BLOT_MERGE:
			blots[i] = Vector4(b.x, b.y, b.z, minf(maxf(b.w, r) + 0.008, max_blot))
			blot_age[i] = 0.0
			dirty = true
			return
	blots.append(Vector4(local_point.x, local_point.y, local_point.z, r))
	blot_age.append(0.0)
	while blots.size() > MAX_BLOTS:
		blots.remove_at(0)
		blot_age.remove_at(0)
	dirty = true


func step(dt: float) -> void:
	age += dt
	for i: int in blot_age.size():
		blot_age[i] += dt


func dryness() -> float:
	return 1.0 - exp(-maxf(age, 0.0) / DRY_TAU)


## Shader uniforms: coat, dryness, slot, blot count and the blots (MAX_BLOTS vec4, unused ones zero).
func pack() -> Dictionary:
	var arr: PackedVector4Array = PackedVector4Array()
	arr.resize(MAX_BLOTS)
	for i: int in blots.size():
		arr[i] = blots[i]
	return {"coat": coat, "dry": dryness(), "slot": slot, "count": blots.size(), "blots": arr}


func is_bloody() -> bool:
	return coat > 0.0 or not blots.is_empty()
