extends TestCase
## PlayerProgress: the counters behind weapon unlocks, their save format, and that tests never write player data.


func test_record_counts() -> void:
	var p := PlayerProgress.new()
	assert_eq(p.get_count("matches"), 0)
	assert_eq(p.record_match(false, false), ["buckler", "fasciae"], "the first fight earns a buckler and wraps")
	assert_eq(p.record_match(true, false), ["machete", "mace", "helm_secutor", "spaulders"], "2 fights and a win")
	assert_eq(p.get_count("matches"), 2)
	assert_eq(p.get_count("wins"), 1)
	assert_eq(p.get_count("ranked_wins"), 0)
	p.record_match(true, true)
	p.record_match(false, true)
	assert_eq(p.get_count("ranked_matches"), 2)
	assert_eq(p.get_count("ranked_wins"), 1)
	assert_eq(p.get_count("wins"), 2, "a ranked win is a win too")


func test_sync_ranked_never_lowers() -> void:
	var p := PlayerProgress.new()
	p.from_dict({"counters": {"ranked_matches": 6, "ranked_wins": 4}})
	assert_eq(p.sync_ranked(2, 1), [])
	assert_eq(p.get_count("ranked_wins"), 4)
	var q := PlayerProgress.new()
	assert_eq(q.sync_ranked(5, 3), ["halberd", "tower_shield"])
	assert_eq(q.sync_ranked(1, 9).size(), 0)
	assert_eq(q.get_count("ranked_wins"), 3, "wins never exceed games")


func test_clean_and_round_trip() -> void:
	var c: Dictionary = PlayerProgress.clean({"matches": -4, "wins": "x", "junk": 9, "ranked_wins": 2.0})
	assert_eq(c, {"matches": 0, "wins": 0, "ranked_matches": 0, "ranked_wins": 2})
	var p := PlayerProgress.new()
	p.record_match(true, true)
	var q := PlayerProgress.new()
	q.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(q.counters, p.counters)
	q.from_dict({"counters": "broken"})
	assert_eq(q.get_count("matches"), 0)


func test_not_persisting_never_writes() -> void:
	var path: String = "user://test_progress_should_not_exist.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var p := PlayerProgress.new(false, path)
	p.record_match(true, true)
	p.sync_ranked(10, 10)
	assert_false(FileAccess.file_exists(path))


func test_shared_instance() -> void:
	var a: PlayerProgress = PlayerProgress.shared()
	assert_true(a == PlayerProgress.shared())
	var b: PlayerProgress = PlayerProgress.open_shared(false)
	assert_true(b == PlayerProgress.shared() and not b.persist)
