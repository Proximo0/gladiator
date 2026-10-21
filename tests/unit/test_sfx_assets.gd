extends TestCase
## Catalog vs files on disk: every key in SfxLogic.VARIANTS has its wav files and the manifest agrees.


func test_manifest_matches_catalog() -> void:
	var f: FileAccess = FileAccess.open("res://assets/audio/manifest.json", FileAccess.READ)
	assert_true(f != null, "manifest.json exists (run tools/gen_sfx.py)")
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	var seen: int = 0
	for cat: String in m:
		for nm: String in m[cat]:
			var key: String = "%s/%s" % [cat, nm]
			assert_eq(SfxLogic.variant_count(key), int(m[cat][nm]), key)
			seen += 1
	assert_eq(seen, SfxLogic.VARIANTS.size())


func test_every_wav_exists_with_riff_header() -> void:
	for key: String in SfxLogic.VARIANTS:
		for i: int in range(SfxLogic.variant_count(key)):
			var p: String = SfxLogic.path_for(key, i)
			var f: FileAccess = FileAccess.open(p, FileAccess.READ)
			assert_true(f != null, "missing " + p)
			if f != null:
				assert_eq(f.get_buffer(4).get_string_from_ascii(), "RIFF", p)
				assert_true(f.get_length() > 2000, "tiny " + p)


func test_bus_layout_has_the_buses() -> void:
	var layout: AudioBusLayout = load(SfxDirector.LAYOUT_PATH) as AudioBusLayout
	assert_true(layout != null)
	if layout == null:
		return
	var prev: AudioBusLayout = AudioServer.generate_bus_layout()
	AudioServer.set_bus_layout(layout)
	for nm: String in ["Master", "SFX", "Crowd", "Voice", "Music"]:
		assert_true(AudioServer.get_bus_index(nm) >= 0, nm)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")), &"Master")
	AudioServer.set_bus_layout(prev)
