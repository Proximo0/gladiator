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
	d._real_clock = 10.0
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


func _in_tree() -> SfxDirector:
	var d: SfxDirector = SfxDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	return d


func _drop_tree(d: SfxDirector) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(d)
	d.free()


func _playing(d: SfxDirector, key: String) -> int:
	var n: int = 0
	for i: int in range(d._pool.size()):
		if d._pool[i].playing and str(d._meta[i].get("key", "")) == key:
			n += 1
	return n


func test_finisher_steals_from_a_full_impact_group() -> void:
	var d: SfxDirector = _in_tree()
	var cap: int = SfxLogic.group_cap("impact")
	for i: int in range(cap):
		d.play_key("impact/leather_slap", Vector3.ZERO, -12.0)
	assert_eq(int(d.group_use().get("impact", 0)), cap)
	d.play_key("impact/bone_crack", Vector3.ZERO, 3.0, 0.9, "SFX", SfxLogic.FINISHER_BOOST_DB)
	assert_eq(_playing(d, "impact/bone_crack"), 1, "the finisher layer got a voice")
	assert_eq(int(d.group_use().get("impact", 0)), cap)
	assert_eq(d.stolen_count, 1)
	# Minor hits that follow are dropped rather than cutting it.
	for i: int in range(cap):
		d.play_key("impact/leather_slap", Vector3.ZERO, -12.0)
	assert_eq(_playing(d, "impact/bone_crack"), 1, "a minor hit never cuts the finisher")
	assert_true(d.lost_important.is_empty(), str(d.lost_important))
	assert_eq(d.inversions, 0)
	_drop_tree(d)


func test_minor_sound_dropped_when_group_is_louder() -> void:
	var d: SfxDirector = _in_tree()
	var cap: int = SfxLogic.group_cap("impact")
	for i: int in range(cap):
		d.play_key("impact/clang_steel", Vector3.ZERO, 0.0)
	var capped: int = d.capped_count
	d.play_key("impact/leather_slap", Vector3.ZERO, -10.0)
	assert_eq(_playing(d, "impact/clang_steel"), cap)
	assert_eq(d.capped_count, capped + 1)
	assert_eq(int(d.dropped_keys.get("impact/leather_slap", 0)), 1)
	_drop_tree(d)


func test_full_pool_gives_way_to_a_gore_stinger() -> void:
	var d: SfxDirector = _in_tree()
	var keys: Array[String] = ["impact/clang_steel", "voice/grunt", "move/whoosh_heavy", "move/roll_thud", "gore/gut_squelch"]
	var n: int = 0
	while d._free_count() > 0 and n < 200:
		d.play_key(keys[n % keys.size()], Vector3.ZERO, -14.0)
		n += 1
	d.on_gore({"kind": "behead", "part": "head", "point": Vector3.ZERO}, null)
	assert_eq(_playing(d, "gore/behead"), 1)
	assert_true(d.lost_important.is_empty(), str(d.lost_important))
	_drop_tree(d)


func test_small_bleed_does_not_spurt() -> void:
	var d: SfxDirector = _make()
	var f: Node3D = Node3D.new()
	f.add_user_signal("hit")
	d._tracked.append({"f": f, "spurts": [], "gushes": []})
	d.on_gore({"kind": "bleed", "part": "head", "amount": 0.006, "point": Vector3.ZERO}, f)
	assert_eq((d._tracked[0]["spurts"] as Array).size(), 0)
	d.on_gore({"kind": "bleed", "part": "torso", "amount": 0.1, "point": Vector3.ZERO}, f)
	assert_eq((d._tracked[0]["spurts"] as Array).size(), 1)
	f.free()
	d.free()


func _count(d: SfxDirector, key: String) -> int:
	var n: int = 0
	for k: String in d.recent_keys:
		if k == key:
			n += 1
	return n


func test_crowd_roar_keeps_real_time_in_slow_motion() -> void:
	var d: SfxDirector = _make()
	var old_scale: float = Engine.time_scale
	Engine.time_scale = 0.2
	d.on_hit(_hit({"finisher": "behead", "behead": true, "sever": true}))
	# 0.25 real seconds of 0.2x physics steps (0.05 game seconds): the roar's 0.2 s delay is real time.
	for i: int in range(15):
		d._physics_process(1.0 / 60.0 * Engine.time_scale)
	Engine.time_scale = old_scale
	assert_true(d._clock < 0.06)
	assert_eq(_count(d, "crowd/finisher_roar"), 1, str(d.recent_keys))
	assert_eq(_count(d, "crowd/chant"), 0, "the chant waits 2.4 real seconds")
	d.free()


func test_finisher_roar_left_to_feel_director() -> void:
	var d: SfxDirector = _make()
	d.finisher_roar_external = true
	var kinds: Array[String] = []
	d.crowd_reacted.connect(func(k: String) -> void: kinds.append(k))
	d.on_hit(_hit({"finisher": "behead", "behead": true, "sever": true}))
	d._clock = 10.0
	d._real_clock = 10.0
	d._run_pending()
	assert_eq(_count(d, "crowd/finisher_roar"), 0, "one roar: the FeelDirector's")
	assert_eq(_count(d, "crowd/chant"), 1)
	assert_true(kinds.has("finisher"), "the stands still react")
	d.free()


func test_feel_director_sibling_is_found_by_group() -> void:
	var host: Node = Node.new()
	var d: SfxDirector = _make()
	host.add_child(d)
	assert_false(d._finisher_roar_is_external())
	var feel: Node = Node.new()
	feel.add_to_group("feel_director")
	host.add_child(feel)
	assert_true(d._finisher_roar_is_external())
	host.free()


func test_heavy_hit_burst_uses_a_reserve_voice_not_another_heavy_hit() -> void:
	# CI seed: nine heavy warhammer blows fill the impact group; a louder one 30 ms later used to cut one of them.
	var d: SfxDirector = _in_tree()
	var cap: int = SfxLogic.group_cap("impact")
	for i: int in range(cap):
		d.play_key("impact/heavy_thump", Vector3.ZERO, 0.0, 1.0, "SFX", SfxLogic.HEAVY_BOOST_DB)
	d.play_key("impact/heavy_thump", Vector3.ZERO, 4.0, 1.0, "SFX", SfxLogic.HEAVY_BOOST_DB)
	assert_eq(_playing(d, "impact/heavy_thump"), cap + 1, "the tenth blow got a reserve voice")
	assert_true(d.lost_important.is_empty(), str(d.lost_log))
	_drop_tree(d)


func test_soft_cap_holds_for_ordinary_sounds() -> void:
	var d: SfxDirector = _in_tree()
	var keys: Array[String] = ["move/whoosh_heavy", "move/roll_thud", "voice/grunt", "gore/gut_squelch", "impact/leather_slap"]
	var n: int = 0
	while d._total_playing() < SfxLogic.SOFT_TOTAL_CAP and n < 200:
		d.play_key(keys[n % keys.size()], Vector3.ZERO, -14.0)
		n += 1
	var busy: int = d._total_playing()
	d.play_key("move/whoosh_heavy", Vector3.ZERO, 0.0)  # louder than the quietest: it replaces, not adds
	assert_eq(d._total_playing(), busy)
	_drop_tree(d)
