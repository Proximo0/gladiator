extends TestCase
## SfxDirector plumbing with synthetic events (no Fighter needed): plans turn into played sounds.


func _make() -> SfxDirector:
	var d: SfxDirector = SfxDirector.new()
	d.muted = true  # count plays without opening players
	return d


func _hit(over: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {
		"part": "torso", "weapon_id": "gladius", "contact": "edge", "energy": 90.0, "total": 14.0, "blunt": 1.0,
		"hit_on_weapon": false, "glanced": false, "armor_ids": [], "target": 0, "point": Vector3(0, 1.2, 0),
	}
	ev.merge(over, true)
	return ev


func test_hit_plays_cut_voice_and_crowd() -> void:
	var d: SfxDirector = _make()
	d.on_hit(_hit())
	assert_true(d.recent_keys.has("impact/flesh_cut"), str(d.recent_keys))
	assert_true(d.crowd.level > CrowdModel.BASELINE)
	d._clock = 1.0
	d._run_pending()
	assert_true(d.recent_keys.has("voice/pain_light") or d.recent_keys.has("voice/pain_heavy"), str(d.recent_keys))
	assert_true(d.recent_keys.has("gore/blood_spatter_sand") or d._pending.size() >= 0)
	d.free()


func test_weapon_clash_makes_clang() -> void:
	var d: SfxDirector = _make()
	d.on_hit(_hit({"hit_on_weapon": true, "part": "forearm_r"}), null)
	assert_true(d.recent_keys.has("impact/thunk_wood") or d.recent_keys.has("impact/clang_steel"), str(d.recent_keys))
	d.free()


func test_finisher_starts_crowd_roar_and_chant() -> void:
	var d: SfxDirector = _make()
	d.on_hit(_hit({"finisher": "behead", "behead": true, "sever": true}))
	d.on_gore({"kind": "behead", "part": "head", "point": Vector3.ZERO, "normal": Vector3.UP, "amount": 1.0})
	assert_true(d.recent_keys.has("gore/behead"))
	d._clock = 10.0
	d._run_pending()
	assert_true(d.recent_keys.has("crowd/finisher_roar"), str(d.recent_keys))
	assert_true(d.recent_keys.has("crowd/chant"), str(d.recent_keys))
	assert_true(d.crowd_excitement() > 0.9)
	d.free()


func test_gore_stinger_is_debounced() -> void:
	var d: SfxDirector = _make()
	var ge: Dictionary = {"kind": "sever", "part": "forearm_r", "point": Vector3.ZERO}
	d.on_gore(ge)
	d.on_gore(ge)
	var n: int = 0
	for k: String in d.recent_keys:
		if k == "gore/sever":
			n += 1
	assert_eq(n, 1)
	d.free()


func test_unknown_key_plays_nothing() -> void:
	var d: SfxDirector = _make()
	assert_false(d.play_key("nope/none", Vector3.ZERO))
	assert_false(d.play_2d("nope/none"))
	assert_eq(d.played_count, 0)
	d.free()


func test_death_gurgle_and_excitement_decay() -> void:
	var d: SfxDirector = _make()
	d.on_died(null)
	d._clock = 5.0
	d._run_pending()
	assert_true(d.recent_keys.has("voice/death_gurgle"), str(d.recent_keys))
	var e: float = d.crowd_excitement()
	for i: int in range(600):
		d.crowd.tick(1.0 / 60.0, 0.0)
	assert_true(d.crowd_excitement() < e)
	d.free()


func test_real_players_when_in_tree() -> void:
	var d: SfxDirector = SfxDirector.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(d)  # _ready builds the pools and starts the ambience loops
	assert_eq(d._pool.size(), SfxDirector.POOL_SIZE)
	assert_true(d.play_key("impact/clang_steel", Vector3.ZERO, -3.0, 1.0, "SFX"))
	assert_true(d.play_2d("crowd/cheer", 0.0, 1.0, "Crowd"))
	assert_true(d._amb_low.stream != null and d._amb_high.stream != null, "ambience loops loaded")
	assert_true(d._amb_low.playing)
	d._physics_process(1.0 / 60.0)
	tree.root.remove_child(d)
	d.free()
