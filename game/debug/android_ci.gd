class_name AndroidCi
extends Node
## Emulator smoke run (.github/workflows/android.yml, docs/android.md). An APK exported with the custom feature
## `android_ci` boots straight into one presented bot vs bot match (Flags adds --mode=bot_vs_bot --android_ci
## --scripted). This node watches that match and prints to logcat (tag "godot"):
##   ANDROID_CI start renderer=<..> adapter=<..> size=<w>x<h>
##   ANDROID_CI shot tick=<n> path=<png>           a 640 px frame saved to user:// (the workflow pulls it with run-as)
##   ANDROID_CI progress tick=<n> wall_s=<s> fps=<f>
##   ANDROID_CI hitch tick=<n> wall_s=<s> ms=<frame ms>  the first HITCH_LINES frames over HITCH_MS (all are counted)
##   ANDROID_CI PASS|FAIL winner=.. reason=.. ticks=.. hits=.. frames=.. fps=.. frame_ms_avg/p50/p95/p99/max=..
##        ticks_per_s=.. why=..
## then quits. PASS needs match_over before the fallback limits, at least one hit and no physics explosions.

const SHOT_TICK: int = 600  ## 10 game seconds in: both fighters are engaged
const PROGRESS_EVERY_S: float = 10.0
const SPARE_TICKS: int = 600  ## ticks past the match time limit before it counts as hung
const WALL_LIMIT_S: float = 900.0  ## wall-clock fallback when the emulator renders very slowly
const HITCH_MS: float = 250.0
const HITCH_LINES: int = 20
const SHOT_PATH: String = "user://android_ci_fight.png"
const SHOT_WIDTH: int = 640
const THUMB_PATH: String = "user://android_ci_fight_small.jpg"  ## printed into the CI log as base64
const THUMB_WIDTH: int = 256

var _match: Match = null
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _t0_us: int = 0
var _last_us: int = 0
var _next_progress_s: float = PROGRESS_EVERY_S
var _shot: bool = false
var _done: bool = false
var _hitches: int = 0


func watch(m: Match) -> void:
	_match = m
	_match.match_over.connect(_on_match_over)


func _ready() -> void:
	_t0_us = Time.get_ticks_usec()
	_last_us = _t0_us
	var size: Vector2i = get_viewport().get_visible_rect().size
	print("ANDROID_CI start renderer=%s adapter=%s size=%dx%d" % [
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "?")),
		RenderingServer.get_video_adapter_name(), size.x, size.y])


func _process(_delta: float) -> void:
	if _done or _match == null:
		return
	var now: int = Time.get_ticks_usec()
	var dt_ms: float = float(now - _last_us) / 1000.0
	_frame_ms.append(dt_ms)
	_last_us = now
	var wall_s: float = float(now - _t0_us) / 1000000.0
	if dt_ms > HITCH_MS:
		_hitches += 1
		if _hitches <= HITCH_LINES:
			print("ANDROID_CI hitch tick=%d wall_s=%.1f ms=%.0f" % [_match.tick, wall_s, dt_ms])
	if not _shot and _match.tick >= SHOT_TICK:
		_shot = true
		var img: Image = get_viewport().get_texture().get_image()  # null with the headless display driver
		var err: Error = ERR_UNAVAILABLE
		if img != null:
			img.resize(SHOT_WIDTH, maxi(1, img.get_height() * SHOT_WIDTH / maxi(img.get_width(), 1)))
			err = img.save_png(SHOT_PATH)
			img.resize(THUMB_WIDTH, maxi(1, img.get_height() * THUMB_WIDTH / maxi(img.get_width(), 1)))
			img.save_jpg(THUMB_PATH, 0.6)
		print("ANDROID_CI shot tick=%d path=%s err=%d" % [_match.tick, ProjectSettings.globalize_path(SHOT_PATH), err])
	if wall_s >= _next_progress_s:
		_next_progress_s += PROGRESS_EVERY_S
		print("ANDROID_CI progress tick=%d wall_s=%.0f fps=%.1f" % [_match.tick, wall_s, Engine.get_frames_per_second()])
	var limit: int = int(float(_match.config.get("time_limit_s", 60.0)) * 60.0) + SPARE_TICKS
	if _match.tick > limit or wall_s > WALL_LIMIT_S:
		_finish({}, "match_over never fired (tick=%d wall_s=%.0f)" % [_match.tick, wall_s])


func _on_match_over(result: Dictionary) -> void:
	_finish(result, "")


func _finish(result: Dictionary, hung: String) -> void:
	if _done:
		return
	_done = true
	var stats: Dictionary = result.get("stats", {}) as Dictionary
	var hits: int = int(stats.get("hits", 0))
	var expl: int = int(stats.get("explosions", 0))
	var why: PackedStringArray = PackedStringArray()
	if hung != "":
		why.append(hung)
	if expl > 0:
		why.append("explosions=%d" % expl)
	if hung == "" and hits == 0:
		why.append("no hits")
	var wall_s: float = float(Time.get_ticks_usec() - _t0_us) / 1000000.0
	var ms: Array = Array(_frame_ms)
	ms.sort()
	var n: int = ms.size()
	var total: float = 0.0
	for v: float in ms:
		total += v
	print("ANDROID_CI %s winner=%s reason=%s ticks=%d hits=%d explosions=%d frames=%d wall_s=%.1f fps=%.1f frame_ms_avg=%.2f frame_ms_p50=%.2f frame_ms_p95=%.2f frame_ms_p99=%.2f frame_ms_max=%.2f hitches=%d ticks_per_s=%.1f why=%s" % [
		"PASS" if why.is_empty() else "FAIL", str(result.get("winner", -1)), str(result.get("reason", "hang")),
		_match.tick, hits, expl, n, wall_s, float(n) / maxf(wall_s, 0.001), total / float(maxi(n, 1)),
		_ci_pct(ms, 0.5), _ci_pct(ms, 0.95), _ci_pct(ms, 0.99), _ci_pct(ms, 1.0), _hitches, float(_match.tick) / maxf(wall_s, 0.001),
		"none" if why.is_empty() else ";".join(why).replace(" ", "_")])
	get_tree().quit(0 if why.is_empty() else 1)


func _ci_pct(sorted_ms: Array, q: float) -> float:
	if sorted_ms.is_empty():
		return 0.0
	return float(sorted_ms[clampi(int(ceil(q * float(sorted_ms.size()))) - 1, 0, sorted_ms.size() - 1)])
