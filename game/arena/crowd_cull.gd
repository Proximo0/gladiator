class_name CrowdCull
extends RefCounted
## Which spectators of a MultiMesh group are drawn at a given excitement (pure). A standing seat owns a calm and a
## cheering twin that share a cheer threshold; only one of them is ever shown. Instead of hiding the other in the
## vertex shader (it would still cost its vertices), each group is sorted by threshold and the MultiMesh draws only
## its first `shown_count` instances: cheering groups ascending (a seat appears once excitement passes its
## threshold), calm groups descending (a seat leaves once it does). Seats that never cheer sit in a calm group with
## threshold NEVER and are always drawn.

const NEVER: float = 9.0
const BACK_ROW_BIAS: float = 0.012  ## threshold added per metre of distance from the arena's inner ring
const MAX_THRESHOLD: float = 0.97


## Excitement at which the seat of `seed_value`, `out_r` metres from the arena centre, starts cheering.
static func threshold(seed_value: int, out_r: float, ring_inner: float) -> float:
	return minf(CrowdMood.threshold_for(seed_value) + (out_r - ring_inner) * BACK_ROW_BIAS, MAX_THRESHOLD)


## Indices that sort `thr` ascending (or descending). Stable for equal values.
static func order(thr: PackedFloat32Array, ascending: bool) -> PackedInt32Array:
	var idx: Array = []
	for i: int in thr.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		if thr[a] == thr[b]:
			return a < b
		return thr[a] < thr[b] if ascending else thr[a] > thr[b])
	return PackedInt32Array(idx)


## How many leading instances of a sorted group are shown at excitement `e`.
static func shown_count(sorted_thr: PackedFloat32Array, ascending: bool, e: float) -> int:
	var lo: int = 0
	var hi: int = sorted_thr.size()
	while lo < hi:
		var mid: int = (lo + hi) / 2
		var cheering: bool = CrowdMood.cheering(e, sorted_thr[mid])
		# ascending: leading seats are the cheering ones; descending: leading seats are the calm ones.
		var lead: bool = cheering if ascending else not cheering
		if lead:
			lo = mid + 1
		else:
			hi = mid
	return lo
