class_name MenuNav
extends Node
## Pad and keyboard focus that never dead-ends, on every menu screen. Godot's own neighbour search stops at some
## container edges (a column inside a ScrollContainer never finds the footer buttons under it); when it finds nothing,
## this picks the nearest control in that direction itself (pick()), and up/down wrap round to the far end of the
## column. Controls that use left/right for their value (pickers, sliders, text fields) keep those keys.
## It also focuses the button or picker under the mouse (a tap arrives as the mouse too), so the highlight under the
## pointer and the pad/keyboard focus are always the same control. MenuFlow sets `root` to the open screen.

const SIDES: Array = [[SIDE_TOP, "ui_up"], [SIDE_BOTTOM, "ui_down"], [SIDE_LEFT, "ui_left"], [SIDE_RIGHT, "ui_right"]]
const LATERAL_WEIGHT: float = 2.0  ## sideways distance counts this much more than distance along the direction

var root: Control = null
var active: bool = true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not active or root == null or not root.is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		_hover_focus()
		return
	var vp: Viewport = get_viewport()
	for s: Array in SIDES:
		if not event.is_action_pressed(str(s[1]), true):
			continue
		var c: Control = vp.gui_get_focus_owner()
		if c == null or not root.is_ancestor_of(c):
			return
		var t: Control = gap_neighbor(c, int(s[0]), root)
		if t != null:
			t.grab_focus()
			vp.set_input_as_handled()
		return


## Where `side` from `c` goes when Godot's own search finds nothing (null when Godot's search works, or when `c`
## uses that key itself). The candidates are the focusable controls under `within`.
static func gap_neighbor(c: Control, side: int, within: Control) -> Control:
	if keeps_horizontal(c) and (side == SIDE_LEFT or side == SIDE_RIGHT):
		return null
	if c.find_valid_focus_neighbor(side as Side) != null:
		return null
	var cands: Array[Control] = focusables(within)
	cands.erase(c)
	var rects: Array[Rect2] = []
	for k: Control in cands:
		rects.append(k.get_global_rect())
	var i: int = pick(c.get_global_rect(), side, rects)
	return cands[i] if i >= 0 else null


## The control `side` reaches from `c`: Godot's own neighbour, else gap_neighbor.
static func neighbor(c: Control, side: int, within: Control) -> Control:
	if keeps_horizontal(c) and (side == SIDE_LEFT or side == SIDE_RIGHT):
		return null
	var n: Control = c.find_valid_focus_neighbor(side as Side)
	return n if n != null else gap_neighbor(c, side, within)


## Links `col` top to bottom: each control's up and down go to the one before and after it; the first's up goes to
## `above` and the last's down to `below` (null: leave Godot's own search there).
static func chain(col: Array[Control], above: Control, below: Control) -> void:
	for i: int in col.size():
		var c: Control = col[i]
		var up: Control = col[i - 1] if i > 0 else above
		var down: Control = col[i + 1] if i < col.size() - 1 else below
		c.focus_neighbor_top = c.get_path_to(up) if up != null else NodePath()
		c.focus_neighbor_bottom = c.get_path_to(down) if down != null else NodePath()


## Routes for a screen of columns over a footer of one or two buttons. `stacked` (portrait): the columns run as one
## long column. Otherwise the first column wraps through `foot_left` and the others through `foot_right`. The footer
## buttons go up to the end of their column and down to its top, and left/right to each other. A hidden or disabled
## footer button is skipped (the other one takes its routes).
static func link_screen(cols: Array, foot_left: Control, foot_right: Control, stacked: bool) -> void:
	var fl: Control = foot_left if _usable(foot_left) else null
	var fr: Control = foot_right if _usable(foot_right) else null
	if fl == null:
		fl = fr
	if fr == null:
		fr = fl
	var lists: Array = []
	if stacked:
		var all: Array[Control] = []
		for c: Array[Control] in cols:
			all.append_array(c)
		lists.append(all)
	else:
		lists = cols
	var first_col: Array[Control] = []
	var last_col: Array[Control] = []
	for i: int in lists.size():
		var col: Array[Control] = lists[i]
		if col.is_empty():
			continue
		var foot: Control = fl if (i == 0 and not stacked) else fr
		chain(col, foot, foot)
		if first_col.is_empty():
			first_col = col
		last_col = col
	if fl != null and not first_col.is_empty():
		var left_col: Array[Control] = first_col if not stacked else last_col
		link(fl, SIDE_TOP, left_col[left_col.size() - 1])
		link(fl, SIDE_BOTTOM, first_col[0])
	if fr != null and not last_col.is_empty():
		link(fr, SIDE_TOP, last_col[last_col.size() - 1])
		link(fr, SIDE_BOTTOM, last_col[0] if not stacked else first_col[0])
	if fl != null and fr != null:
		link(fl, SIDE_RIGHT, fr)
		link(fr, SIDE_LEFT, fl)
		link(fl, SIDE_LEFT, fl)
		link(fr, SIDE_RIGHT, fr)


static func _usable(c: Control) -> bool:
	return c != null and c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled)


static func link(c: Control, side: int, to: Control) -> void:
	if c == null:
		return
	var path: NodePath = c.get_path_to(to) if to != null else NodePath()
	match side:
		SIDE_TOP:
			c.focus_neighbor_top = path
		SIDE_BOTTOM:
			c.focus_neighbor_bottom = path
		SIDE_LEFT:
			c.focus_neighbor_left = path
		SIDE_RIGHT:
			c.focus_neighbor_right = path


## True for controls that take left/right themselves (a value to change, a caret to move).
static func keeps_horizontal(c: Control) -> bool:
	return c is MenuPicker or c is Range or c is LineEdit or c is TextEdit


## Touch screens: every button and picker under `within` at least `min_h` units tall (a finger, not a cursor).
## Screens that lay their rows out smaller again are corrected on the next call (MenuFlow calls it every frame).
static func enforce_touch_height(within: Control, min_h: float) -> void:
	for k: Control in focusables(within):
		if (k is BaseButton or k is MenuPicker) and not (k is TitleMenuItem) and k.custom_minimum_size.y < min_h:
			k.custom_minimum_size.y = min_h


static func focusables(within: Control) -> Array[Control]:
	var out: Array[Control] = []
	for n: Node in within.find_children("*", "Control", true, false):
		var k := n as Control
		if k.focus_mode == Control.FOCUS_ALL and k.is_visible_in_tree() and not (k is BaseButton and (k as BaseButton).disabled):
			out.append(k)
	return out


## Index in `rects` of the best target from `from` toward `side` (-1: none). Nearest along the direction, with
## sideways distance weighted LATERAL_WEIGHT; up/down with nothing ahead wrap to the far end, preferring rects that
## share the column.
static func pick(from: Rect2, side: int, rects: Array[Rect2]) -> int:
	var vertical: bool = side == SIDE_TOP or side == SIDE_BOTTOM
	var sign_d: float = -1.0 if (side == SIDE_TOP or side == SIDE_LEFT) else 1.0
	var best: int = -1
	var best_score: float = INF
	for i: int in rects.size():
		var r: Rect2 = rects[i]
		var ahead: float
		var lateral: float
		if vertical:
			ahead = (r.position.y - from.end.y) if sign_d > 0.0 else (from.position.y - r.end.y)
			lateral = maxf(0.0, maxf(r.position.x - from.end.x, from.position.x - r.end.x))
		else:
			ahead = (r.position.x - from.end.x) if sign_d > 0.0 else (from.position.x - r.end.x)
			lateral = maxf(0.0, maxf(r.position.y - from.end.y, from.position.y - r.end.y))
		if ahead < -1.0:
			continue
		var score: float = maxf(ahead, 0.0) + lateral * LATERAL_WEIGHT
		if score < best_score:
			best_score = score
			best = i
	if best >= 0 or not vertical:
		return best
	# Wrap: the far end in the other direction, nearest the same column.
	var far: float = -INF
	for i: int in rects.size():
		var r: Rect2 = rects[i]
		var lateral2: float = absf(r.get_center().x - from.get_center().x)
		var depth: float = (from.position.y - r.position.y) if sign_d > 0.0 else (r.end.y - from.end.y)
		var score2: float = depth - lateral2 * LATERAL_WEIGHT
		if score2 > far:
			far = score2
			best = i
	return best


func _hover_focus() -> void:
	var hov: Control = get_viewport().gui_get_hovered_control()
	if hov == null or hov.has_focus() or hov.focus_mode != Control.FOCUS_ALL or not hov.is_visible_in_tree():
		return
	if not root.is_ancestor_of(hov):
		return
	if hov is MenuPicker or (hov is BaseButton and not (hov as BaseButton).disabled):
		hov.grab_focus()
