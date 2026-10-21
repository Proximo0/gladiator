class_name MenuSettings
extends RefCounted
## Player options: master, sfx and crowd volume (audio buses Master, SFX, Crowd), graphics quality (low/medium/high: crowd, sand, shadows, MSAA and blood, see GfxQuality), fullscreen.
## Saved to user://settings.cfg, never in scripted runs (CLAUDE.md). `apply()` pushes the values to the engine.

const PATH: String = "user://settings.cfg"
const BUSES: Dictionary = {"master": "Master", "sfx": "SFX", "crowd": "Crowd"}
const QUALITY_NAMES: Array = [["0", "Low"], ["1", "Medium"], ["2", "High"]]

var volumes: Dictionary = {"master": 1.0, "sfx": 1.0, "crowd": 1.0}
var gfx_quality: int = GfxQuality.default_level()
var fullscreen: bool = false
var reduced_motion: bool = false  ## no camera kick, shake or zoom punch (FeelOptions)
var rumble: bool = true  ## gamepad rumble and phone vibration (FeelOptions)
var _base_db: Dictionary = {}


## Slider fraction 0..1 to a dB offset: 1 is unchanged, 0 is silent.
static func fraction_to_db(f: float) -> float:
	if f <= 0.001:
		return -80.0
	return linear_to_db(clampf(f, 0.0, 1.0))


func load_file() -> void:
	if Flags.is_scripted_run():
		return
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k: String in volumes:
		volumes[k] = clampf(float(cf.get_value("audio", k, 1.0)), 0.0, 1.0)
	# Older files only have the blood picker; it used the same low/medium/high scale, so it carries over.
	var old: Variant = cf.get_value("graphics", "blood_quality", gfx_quality)
	gfx_quality = clampi(int(cf.get_value("graphics", "gfx_quality", old)), GfxQuality.LOW, GfxQuality.HIGH)
	fullscreen = bool(cf.get_value("graphics", "fullscreen", false))
	reduced_motion = bool(cf.get_value("feel", "reduced_motion", false))
	rumble = bool(cf.get_value("feel", "rumble", true))


func save_file() -> void:
	if Flags.is_scripted_run():
		return
	var cf := ConfigFile.new()
	for k: String in volumes:
		cf.set_value("audio", k, volumes[k])
	cf.set_value("graphics", "gfx_quality", gfx_quality)
	cf.set_value("graphics", "fullscreen", fullscreen)
	cf.set_value("feel", "reduced_motion", reduced_motion)
	cf.set_value("feel", "rumble", rumble)
	cf.save(PATH)


## The level to build a match with: the `--quality=N` run argument wins (captures and perf runs), else the setting.
func match_quality() -> int:
	if Flags.args.has("quality"):
		return clampi(int(Flags.get_arg("quality", str(gfx_quality))), GfxQuality.LOW, GfxQuality.HIGH)
	return gfx_quality


## Sets the global graphics level. Call before `Match.new()` / `setup()`: the arena, sand and blood read it when built.
func apply_quality() -> void:
	GfxQuality.set_level(match_quality())


func apply() -> void:
	FeelOptions.reduced_motion = reduced_motion
	FeelOptions.rumble_enabled = rumble
	for k: String in BUSES:
		var idx: int = AudioServer.get_bus_index(BUSES[k])
		if idx < 0:
			continue
		if not _base_db.has(k):
			_base_db[k] = AudioServer.get_bus_volume_db(idx)
		AudioServer.set_bus_volume_db(idx, float(_base_db[k]) + fraction_to_db(float(volumes[k])))
	if DisplayServer.get_name() != "headless" and not OS.has_feature("mobile"):
		var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
