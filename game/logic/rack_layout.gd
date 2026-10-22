class_name RackLayout
extends RefCounted
## What stands in each arena weapon rack and how (pure, no nodes): the rack behind spawn `side` holds that fighter's
## spares (a copy of its weapon, its shield leaning against the front) and is filled out with starter weapons, one
## slot left empty where the fighter's own weapon came from. Poses are in the rack's frame (assets/dressing/
## weapon_rack.glb, front +Z toward the arena): long weapons stand butt-down in the iron cups and lean on the top bar,
## shorter ones hang blade-down from the bar's notches. Every pose keeps the weapon's flat (+Z) toward the arena.
## Presentation only: the racked weapons are visual copies with no physics.

## Slot empties of the rack model (tools/houdini/build_props.py RACK_SLOTS): x across, the butt cups' height and depth.
const SLOT_X: Array[float] = [-0.55, -0.33, -0.11, 0.11, 0.33, 0.55]
const CUP_Y: float = 0.27
const CUP_Z: float = -0.06
const BAR_Y: float = 1.46  ## where a standing weapon leans on the top bar
const BAR_Z: float = 0.0
const HANG_Y: float = 1.56  ## grip origin of a weapon hung blade-down: just above the notch pegs (1.42-1.5 m)
## A weapon at least this long reaches the top bar from a cup and stands; shorter ones hang.
const STAND_MIN_LENGTH: float = 1.2
## The order slots are filled in; the third stays empty (the fighter's own weapon came from it).
const SLOT_ORDER: Array[int] = [1, 0, 3, 4, 5]
const FILL: int = 5
const FILL_LOW: int = 3  ## phones: fewer copies, fewer draw calls
## Shields lean against the rack's feet, off centre toward the empty slot side.
const SHIELD_X: float = -0.2
const SHIELD_FRONT_Z: float = 0.36
const SHIELD_LEAN: float = 0.2  ## radians back toward the rack
const SHIELD_LIFT: float = 0.02
## Starter weapons that fill the racks, in order; each side starts at a different point so the racks differ.
const FILLER_STEP: int = 3


## Rack contents for `side` with this loadout ({"weapon", "offhand"}): [{"id", "xf": Transform3D}] in the rack's
## frame. `fill` caps how many slot weapons stand (the shield is extra).
static func stock(loadout: Dictionary, side: int, fill: int = FILL) -> Array[Dictionary]:
	var ids: Array[String] = []
	var own: String = str(loadout.get("weapon", ""))
	if _rackable(own):
		ids.append(own)
	var pool: Array[String] = filler_pool()
	var start: int = (side * FILLER_STEP) % maxi(pool.size(), 1)
	for k: int in pool.size():
		if ids.size() >= mini(fill, SLOT_ORDER.size()):
			break
		var id: String = pool[(start + k) % pool.size()]
		if not ids.has(id):
			ids.append(id)
	var out: Array[Dictionary] = []
	for i: int in ids.size():
		out.append({"id": ids[i], "xf": slot_pose(CombatData.weapon(ids[i]), SLOT_ORDER[i])})
	var off: String = str(loadout.get("offhand", ""))
	if off != "" and LoadoutRules.is_shield(off) and not CombatData.weapon(off).is_empty():
		out.append({"id": off, "xf": shield_pose(CombatData.weapon(off))})
	return out


## Starter weapons for the racks: no fists, shields, unlockables or premium weapons.
static func filler_pool() -> Array[String]:
	var out: Array[String] = []
	for id: String in CombatData.weapon_ids():
		if _rackable(id) and not WeaponUnlocks.is_unlockable(id) and not LoadoutRules.is_premium_weapon(id):
			out.append(id)
	return out


## Pose of weapon def `d` in slot `slot` (rack frame): standing in the cup or hung from the bar.
static func slot_pose(d: Dictionary, slot: int) -> Transform3D:
	var x: float = SLOT_X[clampi(slot, 0, SLOT_X.size() - 1)]
	var grip: float = float(d.get("grip_offset", 0.0))
	if stands(d):
		# Butt in the cup, shaft leaning on the bar: tilt +Y toward +Z by the cup-to-bar slope.
		var lean: float = atan2(BAR_Z - CUP_Z, BAR_Y - CUP_Y)
		var b := Basis(Vector3.RIGHT, lean)
		return Transform3D(b, Vector3(x, CUP_Y, CUP_Z) + b.y * grip)
	# Hung tip-down: half a turn about the flat normal (+Z stays toward the arena).
	return Transform3D(Basis(Vector3.BACK, PI), Vector3(x, HANG_Y, BAR_Z))


static func stands(d: Dictionary) -> bool:
	return float(d.get("length", 0.3)) >= STAND_MIN_LENGTH


## Pose of shield def `d` leaning on the rack's front feet, face (+Z) toward the arena, rim on the sand.
static func shield_pose(d: Dictionary) -> Transform3D:
	var b := Basis(Vector3.RIGHT, -SHIELD_LEAN)
	var half: float = float(d.get("length", 0.6)) * 0.5
	var face: Vector3 = Vector3(SHIELD_X, half * cos(SHIELD_LEAN) + SHIELD_LIFT, SHIELD_FRONT_Z)
	var c: Variant = d.get("center", [])
	var centre := Vector3.ZERO
	if c is Array and (c as Array).size() == 2:
		centre = Vector3(float((c as Array)[0]), float((c as Array)[1]), 0.0)
	return Transform3D(b, face - b * centre)


static func _rackable(id: String) -> bool:
	if id == "" or LoadoutRules.is_shield(id):
		return false
	var d: Dictionary = CombatData.weapon(id)
	return not d.is_empty() and str(d.get("shape", "")) != "fist"
