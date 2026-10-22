class_name PracticeSession
extends Node
## Drives a Match of mode "practice": feeds PracticeLogic with what the player's fighter really does each tick,
## sets the scene up for steps (drops the weapon for "grab", drains the dummy for "finish"), resets the dummy when it
## dies, and runs free practice (any weapon) after the last step. The prompt card is a PracticePanel.
## Never writes player data in scripted runs (PracticeSave persists only when not Flags.is_scripted_run()).

signal step_done(id: String)
signal completed
signal quick_match_requested

const PLAYER_LOADOUT: Dictionary = {"weapon": "gladius", "offhand": "", "armor": {}}
const DUMMY_LOADOUT: Dictionary = {"weapon": "fists", "offhand": "", "armor": {}}

var logic: PracticeLogic = null
var match_node: Match = null
var panel: PracticePanel = null
var free_mode: bool = false
var hits: int = 0
var finishers: int = 0
var shoves: int = 0  ## shoves and kicks the player landed on the dummy (counted across bout resets)
var kicks: int = 0
var weapon_index: int = 0
var resets: int = 0

var _last_inputs: Array = []
var _hooked: Array = []
var _reset_in: float = -1.0
var _pending_blood: float = -1.0
var _weapons: Array = []
var _tip: float = 0.0
var _min_speed: float = 3.0
var _save: PracticeSave = null
var _kill_credited: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## `m` is a Match built with mode "practice". `p_panel` may be null (headless sims).
func attach(m: Match, p_panel: PracticePanel, skip_steps: bool = false) -> void:
	match_node = m
	panel = p_panel
	_save = PracticeSave.shared()
	logic = PracticeLogic.new(PracticeLogic.load_config())
	_weapons = weapon_list()
	weapon_index = maxi(_weapons.find(str(PLAYER_LOADOUT["weapon"])), 0)
	m.inputs_applied.connect(_on_inputs)
	if panel != null:
		panel.action.connect(_on_action)
	_hook_fighters()
	if skip_steps:
		_enter_free()
	else:
		_refresh_panel()


## Practice weapons: every non-shield weapon, lightest tier first.
static func weapon_list() -> Array:
	var ids: Array = []
	for id: String in CombatData.weapon_ids():
		if str(CombatData.weapon(id).get("shape", "")) != "shield":
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ta: int = int(CombatData.weapon(a).get("tier", 0))
		var tb: int = int(CombatData.weapon(b).get("tier", 0))
		return ta < tb or (ta == tb and a < b))
	return ids


func _hook_fighters() -> void:
	for f: Variant in _hooked:
		if is_instance_valid(f) and (f as Fighter).hit.is_connected(_on_hit):
			(f as Fighter).hit.disconnect(_on_hit)
		if is_instance_valid(f) and (f as Fighter).close.is_connected(_on_close):
			(f as Fighter).close.disconnect(_on_close)
	_hooked = match_node.fighters.duplicate()
	for f: Variant in _hooked:
		(f as Fighter).hit.connect(_on_hit)
		(f as Fighter).close.connect(_on_close)


func _on_hit(ev: Dictionary) -> void:
	if int(ev.get("attacker", -1)) != 0 or int(ev.get("target", -1)) != 1 or bool(ev.get("hit_on_weapon", false)):
		return
	if float(ev.get("total", 0.0)) <= 0.0 and str(ev.get("finisher", "")) == "":
		return
	hits += 1
	if str(ev.get("finisher", "")) != "":
		finishers += 1


func _on_close(ev: Dictionary) -> void:
	if int(ev.get("attacker", -1)) != 0 or not bool(ev.get("landed", false)):
		return
	match str(ev.get("kind", "")):
		"shove":
			shoves += 1
		"kick":
			kicks += 1


func _on_inputs(_tick: int, inputs: Array) -> void:
	_last_inputs = inputs
	var f0: Fighter = match_node.fighters[0]
	var f1: Fighter = match_node.fighters[1]
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	_min_speed = Tuning.shared().damage_min_speed
	if not free_mode and logic.step_id() == "finish" and f1.health.dead and not _kill_credited:
		_kill_credited = true  # the drained dummy died of the player's blows: a kill is the finish
		finishers += 1
	var frame: Dictionary = f0.debug_frame()
	_tip = float(frame.get("tip_speed", 0.0))
	var pel: Vector3 = frame.get("pelvis_pos", Vector3.ZERO)
	var inp: Array = inputs[0]
	var btn: int = int(inp[4])
	var obs: Dictionary = {
		"pos": Vector2(pel.x, pel.z), "aim": Vector2(float(inp[2]) / 1000.0, float(inp[3]) / 1000.0),
		"tip_speed": _tip, "min_speed": _min_speed, "swing": (btn & FighterInput.SWING) != 0,
		"thrust": (btn & FighterInput.THRUST) != 0, "rolling": f0.rolling(), "armed": f0.weapon != null,
		"hits": hits, "finishers": finishers, "shoves": shoves, "kicks": kicks,
		"holding": str((frame.get("close", {}) as Dictionary).get("holding", "")) != "",
	}
	if not free_mode:
		var events: Array = logic.update(obs, delta)
		for e: Variant in events:
			_on_event(str(e))
	# The dummy (or the player) down for good: rebuild the bout after a short beat.
	var down: bool = f1.state() == "dead" or f0.state() == "dead"
	if down and _reset_in < 0.0:
		_reset_in = float(logic.cfg.get("dummy_reset_delay_s", 1.5))
	if _reset_in >= 0.0:
		_reset_in -= delta
		if _reset_in < 0.0:
			_reset_in = -1.0
			reset_bout.call_deferred()  # never free the fighters in the middle of Match's tick
	if panel != null:
		panel.update_live(_tip, _min_speed, logic.progress() if not free_mode else 0.0, logic.best_tip)
		if not free_mode and not logic.complete and logic.stuck():
			_refresh_panel()  # same text; the card just keeps itself current


func _on_event(e: String) -> void:
	if e.begins_with("enter:"):
		var id: String = e.trim_prefix("enter:")
		if id == "grab":
			(match_node.fighters[0] as Fighter).drop_weapon()
		elif id == "finish":
			_drain_dummy()
		_refresh_panel()
	elif e.begins_with("done:"):
		step_done.emit(e.trim_prefix("done:"))
		if panel != null:
			panel.flash()
		if match_node.presenter != null and not logic.skipped.has(e.trim_prefix("done:")):
			match_node.presenter.announce("BENE / Well done")
	elif e == "complete":
		_save.mark_completed()
		completed.emit()
		_enter_free.call_deferred()


func _drain_dummy() -> void:
	_kill_credited = false
	var f1: Fighter = match_node.fighters[1]
	var frac: float = float(logic.cfg.get("finish_dummy_blood_frac", 0.15))
	f1.health.bleed_rate = 0.0  # it must not bleed out before the finisher lands
	f1.health.blood = lerpf(Tuning.shared().blood_death, FighterHealth.START_BLOOD, frac)
	_pending_blood = frac


## Rebuilds the bout: both fighters at their spawns, the dummy full (or drained again during the finisher step).
func reset_bout(player_loadout: Variant = null) -> void:
	var drain: float = -1.0
	if not free_mode and logic != null and logic.step_id() == "finish":
		drain = float(logic.cfg.get("finish_dummy_blood_frac", 0.15))
	match_node.reset_practice(player_loadout, drain)
	resets += 1
	_kill_credited = false
	_hook_fighters()
	if not free_mode and logic != null and logic.step_id() == "grab":
		(match_node.fighters[0] as Fighter).drop_weapon()


func _enter_free() -> void:
	free_mode = true
	_reset_in = -1.0
	if match_node.presenter != null:
		match_node.presenter.announce("PROBATVS / Training complete")
	reset_bout(_player_loadout())
	_refresh_panel()


func _player_loadout() -> Dictionary:
	var lo: Dictionary = PLAYER_LOADOUT.duplicate(true)
	lo["weapon"] = str(_weapons[weapon_index])
	return lo


func cycle_weapon() -> void:
	weapon_index = (weapon_index + 1) % _weapons.size()
	reset_bout(_player_loadout())
	_refresh_panel()


func skip_step() -> void:
	if free_mode or logic == null:
		return
	for e: Variant in logic.skip_step():
		_on_event(str(e))
	if not logic.complete:
		# The next tick enters the step; refresh the card now so the text changes at once.
		_refresh_panel()


func skip_all() -> void:
	if free_mode or logic == null:
		return
	for e: Variant in logic.skip_all():
		_on_event(str(e))


func _on_action(id: String) -> void:
	match id:
		"skip":
			skip_step()
		"skip_all":
			skip_all()
		"reset":
			reset_bout(_player_loadout() if free_mode else null)
		"weapon":
			cycle_weapon()
		"quick":
			quick_match_requested.emit()


func _input(event: InputEvent) -> void:
	if match_node == null or not match_node.is_inside_tree() or Flags.is_scripted_run():
		return
	var key: int = -1
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		key = (event as InputEventKey).physical_keycode
	if key == KEY_N:
		skip_step()
	elif key == KEY_R:
		reset_bout(_player_loadout() if free_mode else null)
	elif key == KEY_T and free_mode:
		cycle_weapon()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b: int = (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_BACK:
			skip_step()
		elif b == JOY_BUTTON_Y:
			reset_bout(_player_loadout() if free_mode else null)
		elif b == JOY_BUTTON_DPAD_RIGHT and free_mode:
			cycle_weapon()


func device() -> String:
	var touch: bool = TouchControls.active() or Flags.args.has("touch") or DisplayServer.is_touchscreen_available()
	return PracticeText.device_for(not Input.get_connected_joypads().is_empty(), touch)


func _refresh_panel() -> void:
	if panel == null:
		return
	var dev: String = device()
	if free_mode:
		panel.show_free(["LIBERE", "Free practice"], "Try any weapon on the dummy. It stands still and never hits back. Walk off and come back, or reset it.",
				PracticeText.free_hint(dev), LoadoutRules.display_name(str(_weapons[weapon_index])), dev == "touch")
		return
	var id: String = logic.step_id()
	panel.show_step(PracticeText.heading(id), PracticeText.step_line(logic.index, logic.step_count()), logic.counter_text(),
			PracticeText.body(id, dev, _min_speed), PracticeText.skip_hint(dev),
			id == "swing" or id == "thrust" or id == "strike" or id == "finish", dev == "touch")
