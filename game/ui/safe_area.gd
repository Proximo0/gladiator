class_name SafeArea
extends RefCounted
## Screen-edge insets (notch, rounded corners, gesture bar) in screen pixels, as Vector4(left, top, right, bottom).

const MAX_FRAC: float = 0.15  ## An inset never exceeds this share of the matching screen side (guards bad reports).


## Insets that leave `safe` (the usable rect) inside a screen of `screen` px. An empty or oversized rect gives zero.
static func insets(safe: Rect2, screen: Vector2) -> Vector4:
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO
	var l: float = clampf(safe.position.x, 0.0, screen.x * MAX_FRAC)
	var t: float = clampf(safe.position.y, 0.0, screen.y * MAX_FRAC)
	var r: float = clampf(screen.x - safe.end.x, 0.0, screen.x * MAX_FRAC)
	var b: float = clampf(screen.y - safe.end.y, 0.0, screen.y * MAX_FRAC)
	return Vector4(l, t, r, b)


## Live insets of the game window. Only phones report a meaningful safe area; a desktop window is not inset.
static func window_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win: Vector2i = DisplayServer.window_get_size()
	return insets(Rect2(DisplayServer.get_display_safe_area()), Vector2(win))
