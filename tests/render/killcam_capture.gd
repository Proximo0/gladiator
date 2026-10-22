extends Node
## Instant replay renders from a real fight: two longsword bots with their blood pinned inside the finisher window
## (so the first clean edge or point blow is a beheading or a gutting), then the KillCam replays the finishing blow.
## Saves one PNG per moment, keyed on replay state (shot and replay tick), with a frame-count fallback:
## <name>_live (the fight's own finale camera), _hero, _impact, _orbit, _close. Run in a real (xvfb) window:
## godot --path . --fixed-fps 60 --resolution 1280x720 res://tests/render/killcam_capture.tscn -- --out=DIR [--seed=N] [--name=shot]
## Never part of the check suite; writes only the PNGs it is told to.

const PIN_FRAC: float = 0.3  ## blood held at this share of the way from death to full: deep in the finisher window
const FIGHT_CAP: int = 60 * 90
const WAIT_AFTER: int = 204  ## physics ticks from match_over to the replay (the menu's 3.4 s)

var _out: String = "/tmp/killcam_capture/"
var _name: String = "killcam"
var _seed: int = 9100
var _m: Match = null
var _over_at: int = -1
var _frame: int = 0
var _phys: int = 0
var _saved: Dictionary = {}
var _render_left: int = 0
var _pending: String = ""
var _started: bool = false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_m = Match.new()
	add_child(_m)
	var lo: Dictionary = {"weapon": "longsword", "offhand": "", "armor": {"head": "helm_leather"}}
	_m.setup({"mode": "bot_vs_bot", "seed": _seed, "presentation": true, "loop": false, "time_limit_s": 90.0,
		"loadouts": [lo.duplicate(true), {"weapon": "axe", "offhand": "", "armor": {}}]})
	_m.match_over.connect(func(_r: Dictionary) -> void: _over_at = _phys)


func _physics_process(_d: float) -> void:
	_phys += 1
	if _m == null or _m.fighters.size() < 2:
		return
	if _over_at < 0:
		var dead_l: float = Tuning.shared().blood_death
		for f: Fighter in _m.fighters:
			if f.health != null and not f.health.dead:
				f.health.blood = lerpf(dead_l, FighterHealth.START_BLOOD, PIN_FRAC)
				f.health.bleed_rate = 0.0
		if _phys % 600 == 0:
			print("KCAP fighting tick ", _phys)
		if _phys > FIGHT_CAP:
			print("KCAP no finisher by the cap")
			get_tree().quit(1)
	elif not _started and _phys - _over_at == WAIT_AFTER - 2:
		_grab("live")
	elif not _started and _phys - _over_at >= WAIT_AFTER and _pending == "":
		_started = true
		var kc: KillCam = _m.presenter.killcam
		print("KCAP result ", _m.result.get("reason"), " plan ", kc.plan_for(_m.result))
		if not kc.play(_m.result):
			print("KCAP nothing to replay")
			get_tree().quit(1)
			return
		kc.finished.connect(_done)


func _process(_d: float) -> void:
	_frame += 1
	if _pending != "":
		_render_left -= 1
		if _render_left <= 0:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s%s_%s.png" % [_out, _name, _pending])
			print("KCAP saved ", _pending)
			var kc: KillCam = _m.presenter.killcam
			if _pending == "close" and not (kc.get("_wound") as Dictionary).is_empty():
				var w: Array = kc.call("_wound_now")
				var cam: Vector3 = (kc.get("_cam") as Camera3D).global_position
				var to_cam: Vector3 = (cam - (w[0] as Vector3)).normalized()
				print("KCAP close wound: camera %.0f deg off the wound's facing, %.2f m away, %.2f m above it" % [
					rad_to_deg(to_cam.angle_to(w[1] as Vector3)), cam.distance_to(w[0] as Vector3), cam.y - (w[0] as Vector3).y])
			_saved[_pending] = true
			_pending = ""
			RenderingServer.render_loop_enabled = false
		return
	if not _started or _m == null:
		return
	var kc: KillCam = _m.presenter.killcam
	if not kc.playing:
		return
	var shot: int = int(kc.get("_shot"))
	var st: float = float(kc.get("_shot_t"))
	var pos: float = float(kc.get("_pos"))
	var kill: float = float(kc.plan.get("kill_tick", 0))
	if shot == KillcamPlan.HERO and st >= 1.5:
		_grab("hero")
	elif shot == KillcamPlan.ORBIT and st >= 2.6:
		_grab("orbit")
	elif shot == KillcamPlan.ORBIT and pos >= kill + 2.0 and not _saved.has("impact"):
		_grab("impact")
	elif shot == KillcamPlan.CLOSE and st >= 1.0:
		_grab("close")


## Renders two frames and saves the second (the first after a long pause can still hold the previous image).
func _grab(tag: String) -> void:
	if _saved.has(tag) or _pending != "":
		return
	_pending = tag
	_render_left = 2
	RenderingServer.render_loop_enabled = true


func _done() -> void:
	var st: Dictionary = _m.presenter.killcam.stats()
	print("KCAP stats ", st, " real_s ", _m.presenter.killcam.last_real_s)
	get_tree().quit()
