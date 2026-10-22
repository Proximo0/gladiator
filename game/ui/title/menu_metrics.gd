class_name MenuMetrics
extends RefCounted
## Sizes for menus on every screen: how tall a touch target must be in layout units, and how the title menu lays
## out its items (one column, or a wide first item over two columns when one column will not fit).

const TOUCH_MM: float = 8.0  ## smallest finger target, in millimetres on the glass
const TOUCH_MIN_PX: float = 56.0  ## and never under this many window pixels (a desktop run with --touch, no dpi)
const MM_PER_INCH: float = 25.4


## Smallest touch target in window pixels for a screen of `dpi` (0 or less: unknown).
static func touch_px(dpi: float) -> float:
	if dpi <= 0.0:
		return TOUCH_MIN_PX
	return maxf(TOUCH_MIN_PX, TOUCH_MM * dpi / MM_PER_INCH)


## The same in layout units, given on-screen pixels per layout unit.
static func touch_units(dpi: float, px_per_unit: float) -> float:
	return touch_px(dpi) / maxf(px_per_unit, 0.001)


## Title menu grid: {"columns": 1 or 2, "rows": n, "item_h": units}. `count` items, the first one (the main mode)
## always spans the full width. One column while every item fits at least `min_h` tall in `avail_h` (with `gap`
## between); otherwise two columns. item_h grows up to `max_h` to fill the space.
static func title_grid(count: int, avail_h: float, min_h: float, max_h: float, gap: float) -> Dictionary:
	if count <= 0:
		return {"columns": 1, "rows": 0, "item_h": min_h}
	var one_h: float = (avail_h - gap * float(count - 1)) / float(count)
	if one_h >= min_h:
		return {"columns": 1, "rows": count, "item_h": minf(one_h, max_h)}
	var rows: int = 1 + ceili(float(count - 1) / 2.0)
	var two_h: float = (avail_h - gap * float(rows - 1)) / float(rows)
	return {"columns": 2, "rows": rows, "item_h": clampf(two_h, min_h, max_h)}
