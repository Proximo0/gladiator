class_name RatingChangeView
extends VBoxContainer
## After a rated online fight: the rating counts from its old value to the new one, the change pops in (ochre up,
## red down), the tier name follows the number and flashes when it changes, and a bar shows the way to the next tier.
## An unrated fight shows why in plain words. play(summary, animate) with an OnlineService.result_summary(); a panel
## rebuilt for the same result passes animate = false so it does not count twice.

const COUNT_S: float = 1.3  ## the number counts this long
const POP_S: float = 0.35  ## then the change pops in over this long
const UP: Color = Color(0.93, 0.74, 0.3)
const DOWN: Color = Color(0.86, 0.3, 0.24)
const BAR_H: float = 14.0

var summary: Dictionary = {}
var _t: float = 0.0
var _number: Label
var _delta: Label
var _tier: Label
var _bar: Control
var _note: Label


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	_number = MenuTheme.label("", 64, MenuTheme.PARCHMENT)
	_number.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.03, 0.9))
	_number.add_theme_constant_override("outline_size", 8)
	row.add_child(_number)
	_delta = MenuTheme.label("", 44, UP)
	row.add_child(_delta)
	_tier = MenuTheme.label("", MenuTheme.FONT_SMALL, MenuTheme.OCHRE)
	_tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tier)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(420.0, BAR_H + 6.0)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_note = MenuTheme.label("", 24, MenuTheme.DIM_TEXT)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	set_process(false)


func play(p_summary: Dictionary, animate: bool = true) -> void:
	summary = p_summary
	_t = 0.0 if animate else COUNT_S + POP_S
	set_process(animate)
	_redraw()


## Skip to the end (tests, captures).
func finish() -> void:
	_t = COUNT_S + POP_S
	set_process(false)
	_redraw()


func is_rated() -> bool:
	return bool(summary.get("rated", false))


func _process(delta: float) -> void:
	_t += delta
	if _t >= COUNT_S + POP_S:
		finish()
		return
	_redraw()


## The number shown `t` seconds in: eases out from `before` to `after` over COUNT_S.
static func shown_rating(before: int, after: int, t: float) -> int:
	var k: float = clampf(t / COUNT_S, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	return roundi(lerpf(float(before), float(after), k))


## 0..1 of the way from the bottom of `rating`'s tier to the next one (1 at the top tier).
static func tier_progress(rating: int) -> float:
	var nxt: Dictionary = Rating.next_tier(rating)
	if nxt.is_empty():
		return 1.0
	var i: int = Rating.tier_index(rating)
	var lo: int = int(Rating.TIERS[i - 1][0]) if i > 0 else int(Rating.TIERS[0][0]) - 200
	return clampf(float(rating - lo) / float(int(nxt["at"]) - lo), 0.0, 1.0)


func _redraw() -> void:
	if not is_rated():
		_number.text = ""
		_delta.text = ""
		_tier.text = ""
		_bar.visible = false
		_note.text = OnlineText.unrated_line(str(summary.get("why", ""))) if str(summary.get("status", "")) != "pending" \
			else "Waiting for the result..."
		return
	var before: int = int(summary.get("before", 0))
	var after: int = int(summary.get("after", 0))
	var shown: int = shown_rating(before, after, _t)
	var d: int = after - before
	_number.text = str(shown)
	var pop: float = clampf((_t - COUNT_S) / POP_S, 0.0, 1.0)
	_delta.text = "%+d" % d if _t >= COUNT_S * 0.5 else ""
	_delta.add_theme_color_override("font_color", UP if d >= 0 else DOWN)
	_delta.add_theme_font_size_override("font_size", int(lerpf(56.0, 44.0, pop)))
	var tier_now: String = Rating.tier(shown)
	var promoted: bool = Rating.tier_index(after) > Rating.tier_index(before)
	var demoted: bool = Rating.tier_index(after) < Rating.tier_index(before)
	if _t >= COUNT_S and promoted:
		_tier.text = "Promoted: %s!" % tier_now
	elif _t >= COUNT_S and demoted:
		_tier.text = "Down to %s" % tier_now
	else:
		_tier.text = tier_now
	_tier.add_theme_color_override("font_color", UP.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 12.0)) if promoted and _t >= COUNT_S
		else MenuTheme.OCHRE)
	_bar.visible = true
	_bar.set_meta("progress", tier_progress(shown))
	_bar.queue_redraw()
	var nxt: Dictionary = Rating.next_tier(after)
	var streak: String = OnlineText.streak_line(int(summary.get("streak", 0)))
	var parts: PackedStringArray = []
	if not nxt.is_empty():
		parts.append("%d to %s" % [int(nxt["need"]), str(nxt["name"])])
	if streak != "":
		parts.append(streak)
	_note.text = "   ".join(parts) if _t >= COUNT_S else ""


func _draw_bar() -> void:
	var w: float = _bar.size.x
	var y: float = (_bar.size.y - BAR_H) * 0.5
	_bar.draw_rect(Rect2(0.0, y, w, BAR_H), Color(0.12, 0.08, 0.05, 0.9))
	var p: float = float(_bar.get_meta("progress", 0.0))
	_bar.draw_rect(Rect2(0.0, y, w * p, BAR_H), MenuTheme.OCHRE)
	_bar.draw_rect(Rect2(0.0, y, w, BAR_H), MenuTheme.BRONZE, false, 2.0)
