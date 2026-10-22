class_name UiSfx
extends RefCounted
## Menu-side one-shots that play outside a match (no SfxDirector there). The player frees itself when done.

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _tones: Dictionary = {}  ## UiTones kind -> AudioStreamWAV, built on first use
static var _last_frame: Dictionary = {}  ## kind -> process frame it last played (one of a kind per frame)


## The "Unlocked: X!" fanfare. `host` is any node in the tree. Returns false when it could not play.
static func play_unlock(host: Node) -> bool:
	return play_key(host, "ui/unlock_sting", "SFX")


static func play_key(host: Node, key: String, bus: String) -> bool:
	if host == null or not host.is_inside_tree() or Flags.is_scripted_run():
		return false
	var path: String = SfxLogic.path_for(key, _rng.randi_range(0, SfxLogic.variant_count(key) - 1))
	if not ResourceLoader.exists(path):
		return false
	SfxDirector.ensure_buses()
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = load(path) as AudioStream
	p.volume_db = SfxLogic.base_db(key)
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	host.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return true


## A synthesised menu sound (UiTones kind: focus, select, back, swoosh, locked). Plays while the tree is paused.
static func play_ui(host: Node, kind: String) -> bool:
	if host == null or not host.is_inside_tree() or Flags.is_scripted_run() or not UiTones.LENGTHS.has(kind):
		return false
	var frame: int = Engine.get_process_frames()
	if int(_last_frame.get(kind, -1)) == frame:
		return false
	_last_frame[kind] = frame
	if not _tones.has(kind):
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = UiTones.RATE
		w.stereo = false
		w.data = UiTones.pcm16(UiTones.samples(kind))
		_tones[kind] = w
	SfxDirector.ensure_buses()
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = _tones[kind]
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.pitch_scale = 1.0 + _rng.randf_range(-0.03, 0.03) if kind == "focus" else 1.0
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	host.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return true
