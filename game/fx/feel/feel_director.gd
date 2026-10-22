class_name FeelDirector
extends Node
## Impact feel beyond the camera and the hit flash, presentation only and local to each screen (never physics, never
## the online stream): hit-stop (HitStop), the screen punch (ScreenPunch), the sub-bass thump and finisher bass drop,
## the finisher cinematic (muffle, grade and crowd roar on the FinisherCine timeline; Match drives the matching
## slow motion) and rumble / phone vibration patterns per hit class (RumblePatterns). Fed by MatchPresenter.

const RUMBLE_GAP_S: float = 0.05  ## min real seconds between two rumble patterns for one pad (a flurry does not re-trigger)
const LOG_SIZE: int = 512
const PHONE_DEVICE: int = -2  ## pulse target key for the phone motor

var hit_stop: HitStop = null
var punch: ScreenPunch = null
var audio: FeelAudio = null
var camera: Camera3D = null
var sfx: SfxDirector = null
var player_side: int = 0
var hit_log: Array[Dictionary] = []  ## {class, impact, hold} per resolved hit, newest last (sims and the overlay)
var roars: int = 0

var _cine_kind: String = ""
var _cine_t: float = -1.0
var _roared: bool = false
var _clock: float = 0.0
var _pulses: Array[Dictionary] = []  ## {at (clock), dev, weak, strong, dur, ms, amp, fin}
var _last_pattern: Dictionary = {}  ## device -> clock of its last pattern


var _clock_real: RealClock = RealClock.new()

func _ready() -> void:
	hit_stop = HitStop.new()
	hit_stop.name = "HitStop"
	add_child(hit_stop)
	punch = ScreenPunch.new()
	punch.name = "ScreenPunch"
	add_child(punch)
	audio = FeelAudio.new()
	audio.name = "FeelAudio"
	add_child(audio)


func setup(p_camera: Camera3D, p_sfx: SfxDirector) -> void:
	camera = p_camera
	sfx = p_sfx
	if punch != null:
		punch.camera = p_camera


func begin(fighters: Array, p_player_side: int) -> void:
	player_side = p_player_side
	hit_stop.bind(fighters)
	_end_cine()
	_pulses.clear()


func end_match() -> void:
	hit_stop.bind([])
	_end_cine()
	_pulses.clear()


## One resolved hit with its FeelLogic impact. `victim` is the struck Fighter or null.
func on_hit(ev: Dictionary, _victim: Object, imp: float) -> void:
	var tun: Tuning = Tuning.shared()
	var cls: String = HitStopLogic.hit_class(ev, imp, tun)
	var held: float = hit_stop.on_hit(ev, imp)
	if hit_log.size() >= LOG_SIZE:
		hit_log.remove_at(0)
	hit_log.append({"class": cls, "impact": imp, "hold": held})
	var strength: float = ScreenPunchLogic.strength_for(ev, imp, tun)
	if strength > 0.0:
		punch.kick(strength, cls == HitStopLogic.CLASS_FINISHER, ev.get("point", Vector3.ZERO), FeelOptions.reduced_motion)
	audio.muted = sfx != null and sfx.muted
	if cls == HitStopLogic.CLASS_FINISHER:
		audio.bass(tun.feel_cine_bass_db)
		var kind: String = str(ev.get("finisher", ""))
		if FinisherCine.is_cine(kind) and _cine_t < 0.0:
			_cine_kind = kind
			_cine_t = 0.0
			_roared = false
	elif imp >= tun.feel_bass_min and cls != HitStopLogic.CLASS_CLASH:
		audio.thump((imp - tun.feel_bass_min) / maxf(1.0 - tun.feel_bass_min, 0.001))
	_rumble(ev, cls, imp, tun)


func _process(delta: float) -> void:
	var real: float = _clock_real.step(delta, Engine.time_scale)
	_clock += real
	_tick_cine(real)
	_run_pulses()


func _tick_cine(real: float) -> void:
	if _cine_t < 0.0:
		return
	var tun: Tuning = Tuning.shared()
	_cine_t += real
	audio.set_muffle(FinisherCine.muffle_at(_cine_kind, _cine_t, tun), tun)
	punch.logic.grade = FinisherCine.grade_at(_cine_kind, _cine_t, tun)
	var roar: float = FinisherCine.roar_at(_cine_kind, tun)
	if not _roared and roar >= 0.0 and _cine_t >= roar:
		_roared = true
		if sfx != null and not sfx.muted:
			sfx.play_2d("crowd/roar", 2.0, 1.0, "Crowd")
		roars += 1
	if _cine_t >= FinisherCine.length_s(_cine_kind, tun):
		_end_cine()


func _end_cine() -> void:
	_cine_kind = ""
	_cine_t = -1.0
	_roared = false
	if audio != null:
		audio.set_muffle(0.0, Tuning.shared())
	if punch != null:
		punch.logic.grade = 0.0


## The finisher cinematic is playing (real seconds since the blow, or -1).
func cine_time() -> float:
	return _cine_t


# --- rumble ------------------------------------------------------------------------------------------------------

## Patterns for the pads of the fighter who landed the blow and the one who took it, and the phone of the human side.
func _rumble(ev: Dictionary, cls: String, imp: float, tun: Tuning) -> void:
	if Flags.is_scripted_run() or cls == HitStopLogic.CLASS_NONE:
		return
	var scale: float = FeelOptions.rumble_scale(tun)
	if scale <= 0.0:
		return
	var pads: Array[int] = []
	for d: int in Input.get_connected_joypads():
		pads.append(d)
	var phone: bool = OS.has_feature("android") or OS.has_feature("ios")
	var atk: int = int(ev.get("attacker", -1))
	var tgt: int = int(ev.get("target", -1))
	for side: int in [atk, tgt]:
		var taken: bool = side == tgt
		var pulses: Array[Dictionary] = RumblePatterns.pattern(cls, imp, taken, tun, scale)
		if pulses.is_empty():
			continue
		var dev: int = FeelLogic.pad_for_side(side, player_side, pads)
		if dev >= 0:
			_queue(dev, pulses, cls == HitStopLogic.CLASS_FINISHER)
		if phone and side == player_side:
			_queue(PHONE_DEVICE, pulses, cls == HitStopLogic.CLASS_FINISHER)


## Replaces the pending pulses of device `dev` with `pulses` (a finisher's pattern is never cut short by a lesser one).
func _queue(dev: int, pulses: Array[Dictionary], fin: bool) -> void:
	if not fin and _clock - float(_last_pattern.get(dev, -10.0)) < RUMBLE_GAP_S:
		return
	for p: Dictionary in _pulses:
		if int(p["dev"]) == dev and bool(p["fin"]) and not fin:
			return
	var i: int = _pulses.size() - 1
	while i >= 0:
		if int(_pulses[i]["dev"]) == dev:
			_pulses.remove_at(i)
		i -= 1
	_last_pattern[dev] = _clock
	var list: Array[Dictionary] = RumblePatterns.phone(pulses) if dev == PHONE_DEVICE else pulses
	for p: Dictionary in list:
		var q: Dictionary = p.duplicate()
		q["at"] = _clock + float(p["at"])
		q["dev"] = dev
		q["fin"] = fin
		_pulses.append(q)
	_run_pulses()


func _run_pulses() -> void:
	var i: int = 0
	while i < _pulses.size():
		var p: Dictionary = _pulses[i]
		if float(p["at"]) > _clock:
			i += 1
			continue
		_pulses.remove_at(i)
		var dev: int = int(p["dev"])
		if dev == PHONE_DEVICE:
			Input.vibrate_handheld(int(p["ms"]), float(p["amp"]))
		else:
			Input.start_joy_vibration(dev, float(p["weak"]), float(p["strong"]), float(p["dur"]))
