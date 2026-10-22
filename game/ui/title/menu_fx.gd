class_name MenuFx
extends RefCounted
## Screen transitions for the menus: a screen fades in while sliding a few units into place, a card pops in, the
## view fades up from black after a scene change. Every transition is under 250 ms, runs while the tree is paused,
## and never blocks input: the screen is visible and focusable from its first frame, only its look is animated.

const IN_S: float = 0.16  ## fade and slide of a screen
const STAGGER_S: float = 0.018  ## between items that come in one after another
const STAGGER_MAX: int = 4  ## items after this one come in together (keeps the whole entry under MAX_S)
const SLIDE: float = 26.0  ## layout units a screen slides
const VEIL_S: float = 0.22  ## fade up from black after a scene change
const MAX_S: float = 0.25

static var _tweens: Dictionary = {}  ## instance id -> the Tween running on that control


## Total time of a staggered reveal of `count` items (for tests: always under MAX_S).
static func staggered_length(count: int) -> float:
	return IN_S + STAGGER_S * float(clampi(count - 1, 0, STAGGER_MAX))


## Fades `c` in from transparent and slides it from `from` (an offset in its parent's units) back to where it is.
static func reveal(c: Control, from: Vector2 = Vector2(0.0, SLIDE), delay: float = 0.0) -> void:
	if c == null or not c.is_inside_tree():
		return
	_kill(c)
	var end_pos: Vector2 = c.position
	c.modulate.a = 0.0
	c.position = end_pos + from
	var tw: Tween = c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 1.0, IN_S).set_delay(delay)
	tw.tween_property(c, "position", end_pos, IN_S).set_delay(delay)
	_tweens[c.get_instance_id()] = tw


## Reveals `items` one after another (a menu column); each slides from `from`.
static func reveal_items(items: Array, from: Vector2) -> void:
	var i: int = 0
	for it: Variant in items:
		if it is Control and (it as Control).visible:
			reveal(it as Control, from, STAGGER_S * float(mini(i, STAGGER_MAX)))
			i += 1


## A card (pause, result) grows from 94 % and fades in about its centre.
static func pop(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	_kill(c)
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.94, 0.94)
	c.modulate.a = 0.0
	var tw: Tween = c.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(c, "scale", Vector2.ONE, IN_S)
	tw.tween_property(c, "modulate:a", 1.0, IN_S * 0.8)
	_tweens[c.get_instance_id()] = tw


## Fades a full-screen black veil from opaque to clear (it ignores the mouse, so input goes straight through).
static func veil(v: ColorRect) -> void:
	if v == null or not v.is_inside_tree():
		return
	_kill(v)
	v.visible = true
	v.color = Color(0.0, 0.0, 0.0, 1.0)
	var tw: Tween = v.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(v, "color:a", 0.0, VEIL_S).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void: v.visible = false)
	_tweens[v.get_instance_id()] = tw


## Ends any running transition on `c` at its final look (so a fast second open never leaves it half faded).
static func settle(c: Control) -> void:
	_kill(c)
	c.modulate.a = 1.0
	c.scale = Vector2.ONE


static func _kill(c: Control) -> void:
	var id: int = c.get_instance_id()
	if _tweens.has(id):
		var tw: Tween = _tweens[id]
		if tw != null and tw.is_valid():
			tw.custom_step(10.0)  # jump to the end values, so a restarted reveal starts from the real resting place
			tw.kill()
		_tweens.erase(id)
