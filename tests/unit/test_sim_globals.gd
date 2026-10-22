extends TestCase
## tests/sim/sim_globals.gd: what a sim leaves behind in the process is put back before the next sim file, so two sims
## start from identical state.

const GLOBALS: String = "res://tests/sim/sim_globals.gd"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## What one sim might leave behind: changed statics (a packed array edited in place among them), a slowed engine,
## run flags, a stray node, a held action, a quieter bus.
func _dirty(level: int, stray: String) -> void:
	GfxQuality.level = level
	FeelOptions.reduced_motion = not FeelOptions.reduced_motion
	Tuning.shared().set_value("move_speed", 1.0 + float(level))
	CombatData.weapon_ids()
	GutArt._floors.append(float(level))
	Engine.time_scale = 0.25
	Flags.args[stray] = "1"
	Flags.commands += 3
	Flags.register_hash(func() -> int: return level)
	var n := Node.new()
	n.name = stray
	_root().add_child(n)
	var actions: Array[StringName] = InputMap.get_actions()
	if not actions.is_empty():
		Input.action_press(actions[0])
	AudioServer.set_bus_volume_db(0, AudioServer.get_bus_volume_db(0) - 12.0)


func test_reset_puts_everything_back() -> void:
	var g: RefCounted = (load(GLOBALS) as GDScript).new()
	var root: Window = _root()
	g.capture(root)
	var before: Dictionary = g.snapshot(root)
	_dirty(0, "StraySimNode")
	var dirty: PackedStringArray = g.diff(before, g.snapshot(root))
	assert_true(dirty.size() >= 8, "the mutations show in the snapshot: %s" % "; ".join(dirty))
	var changed: PackedStringArray = g.reset(root)
	for want: String in ["static gfx_quality.level", "static gut_art._floors", "engine time_scale",
			"Flags.args", "Flags.commands", "Flags hash providers", "root node StraySimNode", "audio buses"]:
		assert_true(changed.has(want), "reset reports %s (got %s)" % [want, ", ".join(changed)])
	assert_eq(g.diff(before, g.snapshot(root)), PackedStringArray(), "after reset")
	assert_true(root.get_node_or_null("StraySimNode") == null, "stray node freed")
	assert_near(Engine.time_scale, 1.0)
	assert_near(Tuning.shared().move_speed, float(Tuning.field_info("move_speed")["default"]), 0.0001, "shared tuning")


## A shared Tuning that existed before the first sim and was edited in place goes back to its values.
func test_shared_tuning_edited_in_place() -> void:
	var g: RefCounted = (load(GLOBALS) as GDScript).new()
	var root: Window = _root()
	var tun: Tuning = Tuning.shared()
	var was: float = tun.gravity
	g.capture(root)
	tun.set_value("gravity", was + 1.0)
	var changed: PackedStringArray = g.reset(root)
	assert_true(changed.has("static tuning._shared values"), ", ".join(changed))
	assert_near(Tuning.shared().gravity, was)
	assert_true(is_same(Tuning.shared(), tun), "same object kept")


func test_two_sims_start_identical() -> void:
	var g: RefCounted = (load(GLOBALS) as GDScript).new()
	var root: Window = _root()
	g.capture(root)
	_dirty(0, "FirstSimLeftover")
	g.reset(root)
	var first: Dictionary = g.snapshot(root)
	_dirty(1, "SecondSimLeftover")
	g.reset(root)
	var second: Dictionary = g.snapshot(root)
	assert_eq(g.diff(first, second), PackedStringArray(), "second start vs first start")
	assert_eq(first, second)


func test_reset_gives_a_fresh_physics_world() -> void:
	var g: RefCounted = (load(GLOBALS) as GDScript).new()
	var root: Window = _root()
	g.capture(root)
	var w0: World3D = root.world_3d
	var space0: RID = w0.space
	g.reset(root)
	assert_false(is_same(root.world_3d, w0), "new World3D")
	assert_true(root.world_3d.space != space0, "new physics space")


func test_untouched_state_reports_nothing() -> void:
	var g: RefCounted = (load(GLOBALS) as GDScript).new()
	var root: Window = _root()
	g.capture(root)
	assert_eq(g.reset(root), PackedStringArray())
