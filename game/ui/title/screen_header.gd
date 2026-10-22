class_name ScreenHeader
extends Control
## The heading of a menu screen, in one style everywhere: the Latin word in large outlined capitals between two
## Greek-key rules, the plain English under it in ochre (art direction: Latin flavour, English underneath).
## set_text("ARMA / Choose your arms") splits on " / ".

const LATIN_PX: int = 56
const LATIN_COMPACT_PX: int = 44
const ENGLISH_PX: int = 26
const RULE_CELL: float = 12.0

var latin: String = ""
var english: String = ""
var _compact: bool = false


func _init(text: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_text(text)


func set_text(text: String) -> void:
	var parts: PackedStringArray = text.split(" / ", true, 1)
	latin = parts[0].to_upper()
	english = parts[1] if parts.size() > 1 else ""
	_refit()


## Smaller on a portrait phone.
func set_compact(compact: bool) -> void:
	_compact = compact
	_refit()


func _latin_px() -> int:
	return LATIN_COMPACT_PX if _compact else LATIN_PX


func _refit() -> void:
	var h: float = float(_latin_px()) * 1.1 + (float(ENGLISH_PX) * 1.2 if english != "" else 0.0) + 4.0
	custom_minimum_size = Vector2(0.0, h)
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var f: Font = MenuTheme.caps_font()
	var lp: int = _latin_px()
	var lw: float = f.get_string_size(latin, HORIZONTAL_ALIGNMENT_LEFT, -1, lp).x
	var base: float = float(lp) * 0.86
	var x: float = (size.x - lw) * 0.5
	var outline: int = maxi(4, lp / 9)
	draw_string(f, Vector2(x + 2.0, base + 4.0), latin, HORIZONTAL_ALIGNMENT_LEFT, -1, lp, Color(0.0, 0.0, 0.0, 0.45))
	draw_string_outline(f, Vector2(x, base), latin, HORIZONTAL_ALIGNMENT_LEFT, -1, lp, outline, Color(0.08, 0.04, 0.02, 0.95))
	draw_string(f, Vector2(x, base - 1.5), latin, HORIZONTAL_ALIGNMENT_LEFT, -1, lp, Color(1.0, 0.9, 0.7))
	draw_string(f, Vector2(x, base), latin, HORIZONTAL_ALIGNMENT_LEFT, -1, lp, MenuTheme.PARCHMENT.lerp(MenuTheme.OCHRE, 0.25))
	# Greek-key rules either side of the word, at its middle.
	var gap: float = 26.0
	var ry: float = base - float(lp) * 0.36 - RULE_CELL * 0.5
	var rw: float = minf(x - gap - 8.0, 360.0)
	if rw > RULE_CELL * 3.0:
		MenuTheme.draw_meander(self, x - gap - rw, ry, rw, RULE_CELL, 3.0)
		MenuTheme.draw_meander(self, x + lw + gap, ry, rw, RULE_CELL, 3.0)
	if english != "":
		var ew: float = f.get_string_size(english, HORIZONTAL_ALIGNMENT_LEFT, -1, ENGLISH_PX).x
		var ey: float = base + float(ENGLISH_PX) * 1.15
		draw_string_outline(f, Vector2((size.x - ew) * 0.5, ey), english, HORIZONTAL_ALIGNMENT_LEFT, -1, ENGLISH_PX, 4, Color(0.08, 0.04, 0.02, 0.9))
		draw_string(f, Vector2((size.x - ew) * 0.5, ey), english, HORIZONTAL_ALIGNMENT_LEFT, -1, ENGLISH_PX, MenuTheme.OCHRE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
