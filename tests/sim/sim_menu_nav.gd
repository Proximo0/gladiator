extends "res://tests/sim/sim_base.gd"
## Menu focus and transitions on every menu screen, through MenuFlow as the game builds it: each screen has a
## focused control the moment it opens (a pad or keyboard can act at once), the screen is fully shown within 250 ms
## of process time, pressing down through it never loses the focus or leaves the screen, every focusable control
## can be reached with the d-pad / arrows from where the screen starts (pickers use left/right for their value, so
## only up/down count for them), and a click off every control followed by a d-pad press brings the focus back.

const SETTLE_S: float = 0.26
const DOWN_PRESSES: int = 14


func _press(action: String) -> void:
	for down: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await host.get_tree().process_frame


## Waits SETTLE_S of process time (the frames' own delta), so the check matches what a player sees.
func _settle() -> float:
	var t: float = 0.0
	var n: int = 0
	while t < SETTLE_S and n < 600:
		await host.get_tree().process_frame
		t += host.get_process_delta_time()
		n += 1
	return t


func _focusables(root: Control) -> Array:
	return Array(MenuNav.focusables(root))


func _reachable(start: Control, within: Control) -> Dictionary:
	var seen: Dictionary = {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var c: Control = todo.pop_back()
		var sides: Array = [SIDE_TOP, SIDE_BOTTOM] if c is MenuPicker else [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]
		for side: Side in sides:
			var n: Control = MenuNav.neighbor(c, side, within)
			if n != null and not seen.has(n) and within.is_ancestor_of(n):
				seen[n] = true
				todo.append(n)
	return seen


func _faded_in(c: Control) -> bool:
	return c.modulate.a > 0.999 and c.scale.is_equal_approx(Vector2.ONE)


func run() -> Array:
	var rows: Array = []
	await sandbox()
	var root := Node3D.new()
	world.add_child(root)
	var flow := MenuFlow.new()
	root.add_child(flow)
	flow.setup(root)
	await step(2)
	var screens: Array = [
		["title", func() -> void: flow.call("_show_title"), "_title"],
		["loadout", func() -> void: flow.call("_open_loadout", "player_vs_cpu"), "_loadout"],
		["loadout_2p", func() -> void: flow.call("_open_loadout", "local_2p"), "_loadout"],
		["shop", func() -> void: flow.call("_open_shop", false), "_shop"],
		["leaderboard", func() -> void: flow.call("_open_leaderboard"), "_leaderboard"],
		["options", func() -> void: flow.call("_on_title", "options"), "_options"],
		["online", func() -> void: flow.call("_open_online", false), "_online"],
	]
	var vp: Viewport = host.get_viewport()
	var win: Window = host.get_tree().root
	var size0: Vector2i = win.size
	for shape: Array in [["", Vector2i(1280, 720)], ["_portrait", Vector2i(540, 960)]]:
		win.size = shape[1]
		await step(2)
		rows.append_array(await _screens(flow, screens, str(shape[0]), vp))
	win.size = size0
	await step(2)
	rows.append_array(await _cards(flow, vp))
	flow.call("_show_title")
	await step(2)
	root.remove_child(flow)
	flow.free()
	await clear()
	return rows


func _screens(flow: MenuFlow, screens: Array, tag: String, vp: Viewport) -> Array:
	var rows: Array = []
	for s: Array in screens:
		var nm: String = str(s[0]) + tag
		(s[1] as Callable).call()
		var scr: Control = flow.get(str(s[2]))
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var f0: Control = vp.gui_get_focus_owner()
		var first_ok: bool = f0 != null and scr.is_ancestor_of(f0) and f0.is_visible_in_tree()
		var t: float = await _settle()
		var shown: bool = _faded_in(scr)
		rows.append(row("menu_%s_open" % nm, first_ok and shown,
			"focus on open %s, fully shown after %.2f s: %s" % [str(f0.name) if f0 != null else "none", t, str(shown)]))
		var all: Array = _focusables(scr)
		var reach: Dictionary = _reachable(f0, scr) if f0 != null else {}
		var missing: PackedStringArray = []
		for c: Control in all:
			if not reach.has(c):
				missing.append("%s(%s)" % [str(c.name), c.get_class()])
		rows.append(row("menu_%s_reach" % nm, missing.is_empty() and all.size() > 0,
			"%d of %d focusable controls reachable by d-pad%s" % [reach.size(), all.size(), ("; missing " + ", ".join(missing)) if not missing.is_empty() else ""]))
		var lost: int = 0
		var distinct: Dictionary = {}
		for _i: int in DOWN_PRESSES:
			await _press("ui_down")
			var f: Control = vp.gui_get_focus_owner()
			if f == null or not scr.is_ancestor_of(f):
				lost += 1
			else:
				distinct[f] = true
		rows.append(row("menu_%s_walk" % nm, lost == 0 and distinct.size() >= mini(2, all.size()),
			"%d down presses: focus lost %d times, %d controls visited" % [DOWN_PRESSES, lost, distinct.size()]))
		var cur: Control = vp.gui_get_focus_owner()
		if cur != null:
			cur.release_focus()
		await _press("ui_down")
		var back: Control = vp.gui_get_focus_owner()
		rows.append(row("menu_%s_refocus" % nm, back != null and scr.is_ancestor_of(back),
			"after a click off every control, a d-pad press focuses %s" % (str(back.name) if back != null else "nothing")))
	return rows


## The pause card and the end-of-fight card wrap, and pop in under 250 ms.
func _cards(flow: MenuFlow, vp: Viewport) -> Array:
	var rows: Array = []
	flow.call("_show_practice_offer")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var card: Control = flow.get("_pause")
	var top: Control = vp.gui_get_focus_owner()
	await _press("ui_up")
	var wrapped: Control = vp.gui_get_focus_owner()
	var t2: float = await _settle()
	rows.append(row("menu_card_wrap", top != null and wrapped != null and wrapped != top and card.is_ancestor_of(wrapped) and _faded_in(card),
		"up from the first button goes to %s; card shown after %.2f s" % [str(wrapped.name) if wrapped != null else "none", t2]))
	return rows
