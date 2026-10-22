class_name FeelAudio
extends Node
## Sound side of impact feel: a sub-bass thump under heavy hits, a bass drop on a finisher, and the finisher muffle
## (a low-pass on the Crowd and SFX buses that closes with the slow motion and opens as time returns). The low-pass
## effects are added to those buses at runtime, switched on only while muffled, and removed again on exit, so the
## bus layout is left as it was found. Bass plays on Master so the muffle never dulls it. Owned by FeelDirector.

const MUFFLE_BUSES: PackedStringArray = ["Crowd", "SFX"]
const SFX_MUFFLE_SHARE: float = 0.6  ## effects muffle less deep than the crowd (the gore must still read)
const THUMP_MIN_DB: float = -16.0
const THUMP_MAX_DB: float = -5.0

var muted: bool = false
var muffle: float = 0.0  ## current 0..1 depth (for tests and the debug overlay)
var bass_plays: int = 0
var thump_plays: int = 0

var _bass: AudioStreamPlayer = null
var _thump: AudioStreamPlayer = null
var _lpf: Dictionary = {}  ## bus name -> AudioEffectLowPassFilter


func _ready() -> void:
	_bass = AudioStreamPlayer.new()
	_bass.stream = FeelTones.to_wav(FeelTones.finisher_samples())
	_bass.bus = "Master"
	add_child(_bass)
	_thump = AudioStreamPlayer.new()
	_thump.stream = FeelTones.to_wav(FeelTones.thump_samples())
	_thump.bus = "Master"
	add_child(_thump)
	for bus: String in MUFFLE_BUSES:
		var bi: int = AudioServer.get_bus_index(bus)
		if bi < 0:
			continue
		var fx := AudioEffectLowPassFilter.new()
		fx.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bi, fx)
		AudioServer.set_bus_effect_enabled(bi, AudioServer.get_bus_effect_count(bi) - 1, false)
		_lpf[bus] = fx


func _exit_tree() -> void:
	for bus: Variant in _lpf:
		var bi: int = AudioServer.get_bus_index(str(bus))
		if bi < 0:
			continue
		for k: int in range(AudioServer.get_bus_effect_count(bi) - 1, -1, -1):
			if AudioServer.get_bus_effect(bi, k) == _lpf[bus]:
				AudioServer.remove_bus_effect(bi, k)
	_lpf.clear()


## The finisher's bass drop.
func bass(gain_db: float) -> void:
	if muted or _bass == null:
		return
	_bass.volume_db = gain_db
	_bass.play()
	bass_plays += 1


## A short sub-bass thump under a heavy hit, louder with impact `k` (0..1 above the floor).
func thump(k: float) -> void:
	if muted or _thump == null or (_bass != null and _bass.playing):
		return
	_thump.volume_db = lerpf(THUMP_MIN_DB, THUMP_MAX_DB, clampf(k, 0.0, 1.0))
	_thump.pitch_scale = 1.0 + 0.1 * (1.0 - clampf(k, 0.0, 1.0))  # lighter blows sit a little higher
	_thump.play()
	thump_plays += 1


## Sets the muffle depth (0 = open, filters bypassed).
func set_muffle(depth: float, tun: Tuning) -> void:
	muffle = clampf(depth, 0.0, 1.0)
	for bus: Variant in _lpf:
		var bi: int = AudioServer.get_bus_index(str(bus))
		if bi < 0:
			continue
		var share: float = SFX_MUFFLE_SHARE if str(bus) == "SFX" else 1.0
		var d: float = muffle * share
		var idx: int = -1
		for k: int in AudioServer.get_bus_effect_count(bi):
			if AudioServer.get_bus_effect(bi, k) == _lpf[bus]:
				idx = k
		if idx < 0:
			continue
		var on: bool = d > 0.001
		if AudioServer.is_bus_effect_enabled(bi, idx) != on:
			AudioServer.set_bus_effect_enabled(bi, idx, on)
		if on:
			(_lpf[bus] as AudioEffectLowPassFilter).cutoff_hz = FinisherCine.cutoff_hz(d, tun)
