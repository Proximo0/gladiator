extends TestCase


func _data() -> Dictionary:
	return MatchReport.build({"mode": "online", "names": ["Crixus", "Verus"], "local_side": 0, "winner": 0,
		"reason": "gut", "hits": [5, 2], "blood_lost": [0.5, 2.6], "severs": [1, 0], "combos": [3, 1], "fight_s": 40.0,
		"rating": {"status": "single", "before": 1000, "after": 1022, "delta": 22}, "unlocked": ""})


func _buttons(n: Node, out: Array[Button]) -> Array[Button]:
	for c: Node in n.get_children():
		if c is Button:
			out.append(c as Button)
		_buttons(c, out)
	return out


func _texts(n: Node, out: PackedStringArray) -> PackedStringArray:
	for c: Node in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_texts(c, out)
	return out


func test_buttons_emit_their_ids() -> void:
	var r := MatchResults.new()
	r.build(_data(), [["rematch", "Rematch"], ["loadout", "Loadout"], ["title", "Menu"]], false, false)
	var got: Array[String] = []
	r.chosen.connect(func(id: String) -> void: got.append(id))
	var btns: Array[Button] = _buttons(r, [] as Array[Button])
	assert_eq(btns.size(), 3)
	assert_eq(r.button_count(), 3)
	btns[1].pressed.emit()
	assert_eq(got, ["loadout"] as Array[String])
	for b: Button in btns:
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "pads and keys can reach %s" % b.text)
	r.free()


func test_shows_verdict_stats_and_rating() -> void:
	var r := MatchResults.new()
	r.build(_data(), [["online", "Find another opponent"], ["title", "Leave"]], true, false)
	var t: PackedStringArray = _texts(r, PackedStringArray())
	for want: String in ["VICTORIA", "You won", "CRIXUS", "VERUS", "Hits landed", "Blood lost", "Limbs severed",
			"Longest combo", "2.6 L", "Fight time  0:40", "Rating 1000 -> 1022   +22", "VICTOR"]:
		assert_true(t.has(want), "label '%s' in %s" % [want, str(t)])
	assert_true(str(t).contains("Gutted"))
	r.free()


func test_portrait_stacks_buttons() -> void:
	var r := MatchResults.new()
	r.build(_data(), [["rematch", "Rematch"], ["title", "Menu"]], true, false)
	var btns: Array[Button] = _buttons(r, [] as Array[Button])
	assert_true(btns[0].get_parent() is VBoxContainer, "portrait: one button per row")
	assert_true(btns[0].custom_minimum_size.y >= 80.0, "thumb-sized")
	r.free()
	var l := MatchResults.new()
	l.build(_data(), [["rematch", "Rematch"], ["title", "Menu"]], false, false)
	assert_true(_buttons(l, [] as Array[Button])[0].get_parent() is HBoxContainer, "landscape: a row")
	l.free()
