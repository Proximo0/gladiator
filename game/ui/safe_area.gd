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
## `--safe-insets=L,T,R,B` (screen px) fakes a phone's cutouts on any machine, for captures and sims.
static func window_insets() -> Vector4:
	var fake: Vector4 = parse_arg(str(Flags.args.get("safe-insets", "")))
	if fake != Vector4.ZERO:
		return fake
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win: Vector2i = DisplayServer.window_get_size()
	return insets(Rect2(DisplayServer.get_display_safe_area()), Vector2(win))


## "L,T,R,B" in screen px to insets; anything malformed (or negative) gives zero.
static func parse_arg(text: String) -> Vector4:
	var p: PackedStringArray = text.split(",")
	if p.size() != 4:
		return Vector4.ZERO
	var v: Array[float] = []
	for t: String in p:
		if not t.strip_edges().is_valid_float() or t.to_float() < 0.0:
			return Vector4.ZERO
		v.append(t.to_float())
	return Vector4(v[0], v[1], v[2], v[3])
