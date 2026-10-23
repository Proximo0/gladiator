class_name ReachPlan
extends RefCounted
## Pure helpers for the CPU's answer to reach (FighterBrain). A fighter outreached by the foe's blade baits: it stands
## just outside his reach, steps in for a short stretch to draw his swing, then falls back out; the closing plan
## (ThrustPlan) rushes in when the swing has passed. A fighter holding a long two-handed blade over-commits now and
## then: a lunging swing and a long recovery, so a foe who waited for it can get inside. No Nodes, no clock.


## True for a long two-handed blade (the dai-katana): the one weapon whose reach and guard data cannot be trimmed.
static func is_holder(shape: String, two_handed: bool, length: float, min_length: float) -> bool:
	return shape == "sword" and two_handed and length >= min_length


## Standing distance (pelvis to pelvis) for a fighter waiting outside a longer blade. `t` is ticks into a bait cycle of
## `cycle` ticks; from `in_start` for `in_len` ticks it stands `depth` inside the foe's reach `foe` (the bait),
## otherwise `gap` outside it.
static func bait_hold(t: int, cycle: int, in_start: int, in_len: int, foe: float, gap: float, depth: float) -> float:
	var c: int = t % maxi(cycle, 1)
	if c >= in_start and c < in_start + in_len:
		return foe - depth
	return foe + gap


## True while the bait is out (see bait_hold).
static func baiting(t: int, cycle: int, in_start: int, in_len: int) -> bool:
	var c: int = t % maxi(cycle, 1)
	return c >= in_start and c < in_start + in_len


## Recovery ticks after a swing: `base`, stretched by `mult` when the swing was an over-commit.
static func recover_ticks(base: int, over_commit: bool, mult: float, max_ticks: int) -> int:
	if not over_commit:
		return base
	return clampi(roundi(float(base) * mult), base, max_ticks)
