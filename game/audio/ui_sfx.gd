class_name UiSfx
extends RefCounted
## Menu-side one-shots that play outside a match (no SfxDirector there). The player frees itself when done.

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


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
