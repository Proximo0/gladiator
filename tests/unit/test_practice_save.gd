extends TestCase

const PATH: String = "user://test_practice_save.json"


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_in_memory_never_offers_and_never_writes() -> void:
	var s := PracticeSave.new(false, PATH)
	assert_false(s.should_offer())
	s.mark_completed()
	assert_true(s.completed)
	assert_false(FileAccess.file_exists(PATH))


func test_offer_once_then_remembered() -> void:
	_clean()
	var s := PracticeSave.new(true, PATH)
	assert_true(s.should_offer())
	s.mark_offered()
	assert_false(s.should_offer())
	assert_false(PracticeSave.new(true, PATH).should_offer())
	assert_false(PracticeSave.new(true, PATH).completed)
	_clean()


func test_completion_persists() -> void:
	_clean()
	var s := PracticeSave.new(true, PATH)
	s.mark_completed()
	var r := PracticeSave.new(true, PATH)
	assert_true(r.completed and r.offered)
	assert_false(r.should_offer())
	_clean()


func test_headless_shared_instance_does_not_persist() -> void:
	PracticeSave.open_shared(not Flags.is_scripted_run())
	assert_false(PracticeSave.shared().persist)
