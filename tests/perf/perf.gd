extends Node
## Perf run: one presented bot-vs-bot match in a real window, sampled per frame. Args after `--`:
##   --seed=S  --quality=0|1|2 (graphics quality, default: the platform default)  --measure=N (frames, default 300)
##   --ff=N (fast-forward factor before the measured window, default 8)  --bloody=N (decal count that counts as a bloody point, default 60)  --max_ticks=N (fallback, default 5400)
## Waits until the blood decal count reaches --bloody (an observed state) or --max_ticks physics ticks passed, then
## averages `--measure` frames. Prints one `PERF {json}` line and quits. Run it through tools/perf.sh.

var _match: Match = null
var _frames: int = 0
var _measuring: bool = false
var _samples: Array = []
var _peak: Dictionary = {}
var _reached: String = ""
var _measure: int = 300
var _bloody: int = 60
var _max_ticks: int = 5400
var _t_start: int = 0
var _ff: float = 8.0
var _driven: bool = false
var _fx_us: int = 0
var _blood_us: int = 0
var _min_tick: int = 600
var _heavy: bool = false
var _mm_peak: Dictionary = {}
var _drops_live_peak: int = 0
## Section timing (microseconds summed over the measured window): script _process per script file, the physics
## callbacks before and after the fighters, the fighters' own steps, render CPU/GPU and the whole frame.
var _sec: Dictionary = {}
var _driven_nodes: Array[Node] = []
var _driven_keys: PackedStringArray = PackedStringArray()
var _sfx_driven: bool = false
var _y0: int = 0
var _y1: int = 0
var _y2: int = 0
var _p0: int = 0
var _last_frame_us: int = 0
var _yend: int = 0
var _frame_phys_us: int = 0  ## physics callbacks plus Jolt steps since the last process frame
var _inject_frame: int = -1
var _warmup: int = 30
var _bodies_last: Array = [0, 0, 0]
## --start: match-start and first-gore hitches. START_FRAMES real frames per match start, a forearm cut at GORE_AT,
## then a new Match (the next seed, so new loadouts) as the menu makes one, START_RUNS starts in all.
const START_FRAMES: int = 120
const GORE_AT: int = 60
const START_RUNS: int = 3
var _start_mode: bool = false
var _start_setup_us: int = 0
var _start_gore_us: int = 0
var _start_walls: Array[float] = []
var _starts: Array = []
const SPAWN_FRAMES: int = 8
var _spawn: Dictionary = {}  ## the gore spawn moment: script time of the injection and the next frames' wall ms
var _mon: Dictionary = {}
const SWEEP: Array[String] = ["none", "sand", "blood", "crowd", "fighters", "shadow", "hud", "stands", "none_end"]
const SWEEP_FRAMES: int = 30
var _sweep: bool = false
var _sweep_i: int = 0
var _sweep_f: int = 0
var _sweep_acc: Dictionary = {}
var _sweep_out: Dictionary = {}
var _undo: Array = []
var _prof_snap: Dictionary = {}
var _sections_snap: Dictionary = {}


## A timing mark at the very start or end of the process and physics callback order.
class _PerfMark extends Node:
	var perf: Node = null
	var tag: String = ""

	func _process(_delta: float) -> void:
		perf.call("_mark", "p_" + tag)

	func _physics_process(_delta: float) -> void:
		perf.call("_mark", "y_" + tag)


func _ready() -> void:
	_measure = int(Flags.get_arg("measure", "300"))
	_bloody = int(Flags.get_arg("bloody", "60"))
	_max_ticks = int(Flags.get_arg("max_ticks", "5400"))
	_min_tick = int(Flags.get_arg("late_tick", "600"))
	_heavy = Flags.args.has("heavy")
	Fighter.prebuild_caps = not Flags.args.has("no_prebuild")  # A/B: the old behaviour builds caps in the frame of the cut
	_sweep = Flags.args.has("sweep")
	_warmup = maxi(int(Flags.get_arg("warmup", "30")), 1)
	_start_mode = Flags.args.has("start")
	if Flags.args.has("no_warm") or Flags.args.has("legacy"):
		FighterWarmup.done = true  # A/B: no shader warm-up
	if Flags.args.has("legacy"):
		# A/B: the tree before the hitch work (caps built in the frame of the cut, arena and tuning panel per match).
		Fighter.prebuild_caps = false
		MatchPresenter.keep_arena = false
		MatchPresenter.eager_panel = true
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "2")))
	_match = Match.new()
	add_child(_match)
	var ts: int = Time.get_ticks_usec()
	_match.setup({"mode": "bot_vs_bot", "seed": int(Flags.get_arg("seed", "1002")), "presentation": true,
			"loop": false, "time_limit_s": 600.0})
	_start_setup_us = Time.get_ticks_usec() - ts
	Engine.max_physics_steps_per_frame = 16
	_ff = float(Flags.get_arg("ff", "1" if _start_mode else "8"))
	Engine.time_scale = _ff  # fast-forward to the bloody point (software GL renders ~3 fps); measured at 1x
	if Flags.args.has("quality"):
		_match.presenter.blood.set_quality(GfxQuality.blood_level())  # MatchPresenter.build hard-codes 2 on desktop
	_t_start = Time.get_ticks_msec()
	process_physics_priority = 1  # after Flags and Match (0), before the fighters (10): drives the sound director
	for tag: String in ["start", "end"]:
		var m := _PerfMark.new()
		m.perf = self
		m.tag = tag
		m.name = "PerfMark_" + tag
		m.process_priority = -1000000 if tag == "start" else 1000000
		m.process_physics_priority = -1000000 if tag == "start" else 1000000
		add_child(m)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _add(key: String, us: int) -> void:
	if _samples.size() >= _measure:
		return  # the --sweep phase after the window
	_sec[key] = int(_sec.get(key, 0)) + us


func _mark(k: String) -> void:
	var now: int = Time.get_ticks_usec()
	match k:
		"y_start":
			_end_step(now)
			_y0 = now
			_y1 = now
			_y2 = now
		"y_end":
			_frame_phys_us += now - _y0
			_yend = now
			if _measuring:
				_add("phys_match_etc", _y1 - _y0)
				_add("phys_fighters", now - _y2)
				_add("phys_steps_n", 1)
		"p_start":
			_end_step(now)
			_p0 = now
		"p_end":
			if _measuring:
				_add("proc_script", now - _p0)


## The engine's physics step (Jolt) runs after the last physics callback: it ends at the next physics callback or
## at the start of the frame's process callbacks.
func _end_step(now: int) -> void:
	if _yend == 0:
		return
	_frame_phys_us += now - _yend
	if _measuring:
		_add("jolt", now - _yend)
	_yend = 0


func _physics_process(delta: float) -> void:
	_y1 = Time.get_ticks_usec()
	if _sfx_driven:
		_match.presenter.sfx.call("_physics_process", delta)
	_y2 = Time.get_ticks_usec()
	if _measuring:
		_add("phys_sfx", _y2 - _y1)


## Takes over every processing script node's _process (except the timing marks, blood and sand, which are driven
## already) so each script file's cost is timed; the sound director's physics step too.
func _drive_nodes() -> void:
	var stack: Array[Node] = [get_tree().root]
	var found: Array[Node] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var kids: Array[Node] = n.get_children()
		kids.reverse()
		stack.append_array(kids)
		if n == self or n is _PerfMark or n == _match.presenter.blood or n == _match.presenter.sand:
			continue
		if n.is_processing() and n.get_script() != null and n.has_method("_process"):
			found.append(n)
	found.sort_custom(func(a: Node, b: Node) -> bool: return a.process_priority < b.process_priority)
	for n: Node in found:
		n.set_process(false)
		_driven_nodes.append(n)
		_driven_keys.append("proc_" + (n.get_script() as Script).resource_path.get_file().get_basename())
	var sfx: Node = _match.presenter.sfx
	if sfx != null and sfx.is_physics_processing():
		sfx.set_physics_process(false)
		_sfx_driven = true


func _run_driven(delta: float) -> void:
	for i: int in _driven_nodes.size():
		var n: Node = _driven_nodes[i]
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var t0: int = Time.get_ticks_usec()
		n.call("_process", delta)
		_add(_driven_keys[i], Time.get_ticks_usec() - t0)


func _sample_monitors() -> void:
	var mons: Dictionary = {
		"objects": Performance.OBJECT_COUNT, "nodes": Performance.OBJECT_NODE_COUNT,
		"orphans": Performance.OBJECT_ORPHAN_NODE_COUNT, "resources": Performance.OBJECT_RESOURCE_COUNT,
	}
	var vals: Dictionary = {}
	for k: String in mons:
		vals[k] = Performance.get_monitor(mons[k])
	if _frames % 10 == 0 or not _mon.has("bodies"):
		# Jolt reports no active-body or pair counts: count the rigid bodies ourselves (all, sleeping, colliding).
		var bodies: int = 0
		var asleep: int = 0
		var layered: int = 0
		var stack: Array[Node] = [_match]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is RigidBody3D:
				bodies += 1
				asleep += 1 if (n as RigidBody3D).sleeping else 0
				layered += 1 if (n as RigidBody3D).collision_layer != 0 else 0
		_bodies_last = [bodies, asleep, layered]
	vals["bodies"] = _bodies_last[0]
	vals["asleep"] = _bodies_last[1]
	vals["layered"] = _bodies_last[2]
	for k: String in vals:
		var v: float = float(vals[k])
		var m: Array = _mon.get(k, [0.0, 0.0])
		_mon[k] = [float(m[0]) + v, maxf(float(m[1]), v)]


func _counts() -> Dictionary:
	var p: MatchPresenter = _match.presenter
	var d: Dictionary = {}
	if p == null or p.blood == null or p.blood.decals == null:
		return d
	d["decals"] = p.blood.decals.count
	d["decal_cap"] = p.blood.decals.capacity
	d["drops"] = p.blood.sim.count
	d["mist"] = p.blood.mist.count
	if p.sand != null:
		var fx: Variant = p.sand.get("_fx")
		if fx != null:
			d["grains"] = int((fx as SandFx).count)
	return d


func _process(delta: float) -> void:
	_frames += 1
	if _start_mode:
		_start_step()
		return
	if _match.presenter == null:
		return
	var p: MatchPresenter = _match.presenter
	if p.blood != null and not _driven:
		_driven = true  # drive the fx ourselves so their script cost is timed apart from the renderer
		p.blood.set_process(false)
		(p.sand as Node).set_process(false)
		p.blood.set("profile_on", true)
		p.sand.set("profile_on", true)
	var t0: int = Time.get_ticks_usec()
	if _driven:
		p.blood.step(delta)
		_blood_us = Time.get_ticks_usec() - t0
		(p.sand as Node).call("_process", delta)
	_fx_us = Time.get_ticks_usec() - t0
	if _measuring:
		_add("proc_fx", _fx_us)
		_run_driven(delta)
	var c: Dictionary = _counts()
	for k: String in c:
		_peak[k] = maxi(int(_peak.get(k, 0)), int(c[k]))
	var tick: int = _match.tick
	var now_us: int = Time.get_ticks_usec()
	var wall_us: int = now_us - _last_frame_us
	_last_frame_us = now_us
	var phys_us: int = _frame_phys_us
	_frame_phys_us = 0
	if _frames % 120 == 0 and not _measuring:
		print("PERF progress tick=%d wall=%ds %s" % [tick, (Time.get_ticks_msec() - _t_start) / 1000, str(c)])
	if not _measuring:
		if int(c.get("decals", 0)) >= _bloody and tick >= _min_tick:
			_reached = "decals>=%d" % _bloody
		elif tick >= _max_ticks:
			_reached = "fallback_ticks"
		elif _match.over and tick > 0:
			_reached = "match_over"
		if _reached != "":
			_measuring = true
			Engine.time_scale = 1.0
			_frames = 0
			_hide_parts()
			_drive_nodes()
			Fighter.prof_on = true
			_match.presenter.prof_on = true
		return
	if _frames <= _warmup:
		# Warm-up at 1x: the first frames after the fast-forward (and any shader compiles) are not measured.
		_sec.clear()
		_mon.clear()
		Fighter.prof.clear()
		_match.presenter.prof.clear()
		_match.presenter.blood.set("prof", {})
		_match.presenter.sand.set("prof", {})
		if _frames == _warmup and _heavy:
			_inject_frame = _frames
			_inject_gore()
		return
	if _sweep and _samples.size() >= _measure:
		_sweep_step(tick, wall_us)
		return
	if _inject_frame >= 0 and _frames - _inject_frame <= SPAWN_FRAMES:
		(_spawn["wall_ms"] as Array).append(snappedf(float(wall_us) / 1000.0, 0.01))
	_add("frame_wall", wall_us)
	var vp: RID = get_viewport().get_viewport_rid()
	_add("render_cpu", roundi(RenderingServer.viewport_get_measured_render_time_cpu(vp) * 1000.0
			+ RenderingServer.get_frame_setup_time_cpu() * 1000.0))
	_add("render_gpu", roundi(RenderingServer.viewport_get_measured_render_time_gpu(vp) * 1000.0))
	_sample_monitors()
	_drops_live_peak = maxi(_drops_live_peak, p.blood.live_droplets())
	if _frames % 20 == 0:
		var mt: Dictionary = _mm_tris()
		if int(mt.get("_total", 0)) >= int(_mm_peak.get("_total", 0)):
			_mm_peak = mt
	_samples.append({
		"wall": float(wall_us) / 1000.0,
		"physr": float(phys_us) / 1000.0,
		"proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"fx": float(_fx_us) / 1000.0,
		"blood": float(_blood_us) / 1000.0,
	})
	if _samples.size() >= _measure:
		_prof_snap = _prof()
		_sections_snap = _sections()
		Fighter.prof_on = false
		_match.presenter.prof_on = false
		if not _sweep:
			_report(tick)


func _prof() -> Dictionary:
	var out: Dictionary = {}
	var n: float = float(maxi(_samples.size(), 1))
	var sets: Array = [_match.presenter.blood.get("prof"), _match.presenter.sand.get("prof")]
	for ps: Variant in sets:
		if ps == null:
			continue
		for k: String in (ps as Dictionary):
			out[k] = snappedf(float((ps as Dictionary)[k]) / n, 0.01)
	return out


func _start_step() -> void:
	var now_us: int = Time.get_ticks_usec()
	if _frames > 1:
		_start_walls.append(float(now_us - _last_frame_us) / 1000.0)
	_last_frame_us = now_us
	if _start_walls.size() == GORE_AT:
		var f: Fighter = _match.fighters[1]
		var tg: int = Time.get_ticks_usec()
		f.call("_sever", "forearm_l")
		_match.presenter.blood.on_gore({"kind": "sever", "part": "forearm_l", "amount": 1.0,
				"point": (f.parts["forearm_l"] as Node3D).global_position, "normal": Vector3.UP}, f)
		_start_gore_us = Time.get_ticks_usec() - tg
	if _start_walls.size() < START_FRAMES:
		return
	var head: Array[float] = _start_walls.slice(0, 10)
	var gore: Array[float] = _start_walls.slice(GORE_AT, GORE_AT + 10)
	var mid: Array[float] = _start_walls.slice(20, GORE_AT)
	mid.sort()
	_starts.append({"setup_ms": snappedf(float(_start_setup_us) / 1000.0, 0.1),
			"first10_max": snappedf(head.max(), 0.1), "first10_sum": snappedf(_sum(head), 0.1),
			"steady_p50": snappedf(mid[mid.size() / 2], 0.1), "gore_script_ms": snappedf(float(_start_gore_us) / 1000.0, 0.1),
			"gore10_max": snappedf(gore.max(), 0.1), "first10": head.map(func(x: float) -> float: return snappedf(x, 0.1)),
			"gore10": gore.map(func(x: float) -> float: return snappedf(x, 0.1))})
	_start_walls.clear()
	if _starts.size() >= START_RUNS:
		print("PERF_START " + JSON.stringify({"legacy": Flags.args.has("legacy"), "warm": not FighterWarmup._kept.is_empty(), "prebuild": Fighter.prebuild_caps,
				"quality": GfxQuality.level, "starts": _starts}))
		get_tree().quit(0)
		return
	# A new Match, as the menu starts one (MenuFlow._close_match: remove_child, free, then Match.new()).
	var next_seed: int = _match.seed + 1
	var ts: int = Time.get_ticks_usec()
	remove_child(_match)
	_match.free()
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": next_seed, "presentation": true, "loop": false, "time_limit_s": 600.0})
	_start_setup_us = Time.get_ticks_usec() - ts
	_last_frame_us = Time.get_ticks_usec()


func _sum(a: Array[float]) -> float:
	var t: float = 0.0
	for x: float in a:
		t += x
	return t


## Script and engine sections per frame (ms): `proc_script` is every script `_process` (fx and `proc_<file>` are its
## parts), `phys_match_etc` the physics callbacks before the fighters (Flags, Match with its brains, judge, stats and
## the presenter's sand tick), `phys_sfx` the sound director, `phys_fighters` both fighters (`f_*`, `debug_frame` are
## parts, `debug_frame_n` is calls per frame), `jolt` the engine physics steps after the callbacks (timed between
## marks, real time), `render_etc` the rest of the frame (renderer, swap, physics sync), `render_*` the renderer's
## own measure. All are means over real frames.
func _sections() -> Dictionary:
	var n: float = float(maxi(_samples.size(), 1))
	var out: Dictionary = {}
	var srcs: Array = [_sec, Fighter.prof, _match.presenter.prof]
	for src: Variant in srcs:
		for k: String in (src as Dictionary):
			out[k] = snappedf(float((src as Dictionary)[k]) / n / (1.0 if k.ends_with("_n") else 1000.0), 0.01)
	var phys: float = float(_stat("physr")["mean"])
	out["render_etc"] = snappedf(float(out.get("frame_wall", 0.0)) - phys - float(out.get("proc_script", 0.0)), 0.01)
	return out


func _monitors() -> Dictionary:
	var n: float = float(maxi(_samples.size(), 1))
	var out: Dictionary = {}
	for k: String in _mon:
		out[k] = [snappedf(float(_mon[k][0]) / n, 0.1), float(_mon[k][1])]
	return out


func _stat(key: String) -> Dictionary:
	var v: Array = []
	for s: Dictionary in _samples:
		v.append(float(s[key]))
	v.sort()
	var sum: float = 0.0
	for x: float in v:
		sum += x
	return {"mean": snappedf(sum / float(v.size()), 0.01), "p50": snappedf(v[int(v.size() * 0.5)], 0.01),
			"p95": snappedf(v[int(v.size() * 0.95)], 0.01), "max": snappedf(v[v.size() - 1], 0.01)}


func _report(tick: int) -> void:
	var out: Dictionary = {
		"seed": int(Flags.get_arg("seed", "1002")), "quality": GfxQuality.level,
		"reached": _reached, "tick": tick, "frames": _samples.size(),
		"frame_ms": _stat("wall"), "physics_ms": _stat("physr"), "spawn": _spawn, "fx_ms": _stat("fx"), "blood_ms": _stat("blood"), "census": _census(), "crowd": _crowd(), "sections_ms": _prof_snap, "script_ms": _sections_snap, "sweep": _sweep_out, "monitors": _monitors(), "draw_calls": _stat("calls"),
		"mm_tris": _mm_peak, "live_drops": _drops_live_peak, "primitives": _stat("prims"), "objects": _stat("objs"), "peak": _peak,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"wall_s": snappedf(float(Time.get_ticks_msec() - _t_start) / 1000.0, 0.1),
	}
	print("PERF " + JSON.stringify(out))
	get_tree().quit(0)


## Draw-call suspects: every visible geometry node grouped by name (digits stripped), with its surface count and,
## for MultiMeshes, instance count. Top groups by surfaces.
func _census() -> Array:
	var groups: Dictionary = {}
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if not (n is GeometryInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var key: String = String(n.name).rstrip("0123456789_@")
		if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			key += " [shadow]"
		var surfaces: int = 1
		var inst: int = 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			surfaces = (n as MeshInstance3D).mesh.get_surface_count()
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			inst = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		var g: Dictionary = groups.get(key, {"nodes": 0, "surfaces": 0, "instances": 0})
		g["nodes"] = int(g["nodes"]) + 1
		g["surfaces"] = int(g["surfaces"]) + surfaces
		g["instances"] = int(g["instances"]) + inst
		groups[key] = g
	var rows: Array = []
	for k: String in groups:
		var g2: Dictionary = groups[k]
		rows.append([int(g2["surfaces"]), "%s nodes=%d surfaces=%d instances=%d" % [k, g2["nodes"], g2["surfaces"], g2["instances"]]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var out: Array = []
	for r: Array in rows.slice(0, 10):
		out.append(r[1])
	return out


func _crowd() -> Dictionary:
	var c: Crowd = _match.presenter.arena.crowd
	return {"seats": c.seat_count, "tris": c.triangle_count, "shown_tris": c.shown_triangles, "calls": c.draw_calls}


## --hide=crowd,hud,shadow,sand,blood,fighters,stands: switch parts off for the measured window to see what each one
## costs (diagnosis only; the difference in draw calls and primitives is that part's share).
func _hide_parts() -> void:
	_hide(Flags.get_arg("hide", "").split(",", false))


## Hides `names` (see --hide), recording each change in `_undo` so `_unhide` restores it.
func _hide(names: PackedStringArray) -> void:
	var p: MatchPresenter = _match.presenter
	for part: String in names:
		match part:
			"crowd":
				_set_undo(p.arena.crowd, "visible", false)
			"hud":
				_set_undo(p.hud, "visible", false)
			"shadow":
				_set_undo(p.arena.sun, "shadow_enabled", false)
			"sand":
				_set_undo(p.sand, "visible", false)
			"blood":
				_set_undo(p.blood, "visible", false)
			"fighters":
				for f: Node3D in _match.fighters:
					_set_undo(f, "visible", false)
			"stands":
				for c: Node in p.arena.get_children():
					if c is MeshInstance3D:
						_set_undo(c, "visible", false)


func _set_undo(o: Object, prop: String, v: Variant) -> void:
	if o == null:
		return
	_undo.append([o, prop, o.get(prop)])
	o.set(prop, v)


func _unhide() -> void:
	for i: int in range(_undo.size() - 1, -1, -1):
		var u: Array = _undo[i]
		if is_instance_valid(u[0]):
			(u[0] as Object).set(str(u[1]), u[2])
	_undo.clear()


## --sweep: after the measured window, `SWEEP_FRAMES` frames per hidden part (baseline first and last, gore still
## live), so each part's render cost is the baseline minus its row. Prints one `PERF_SWEEP {json}` line.
func _sweep_step(tick: int, wall_us: int) -> void:
	var name: String = SWEEP[_sweep_i]
	if _sweep_f == 0:
		_unhide()
		if name != "none" and name != "none_end":
			_hide(PackedStringArray([name]))
		_sweep_acc = {"proc": 0.0, "render_cpu": 0.0, "render_gpu": 0.0, "calls": 0.0, "n": 0.0}
	_sweep_f += 1
	if _sweep_f > 3:
		var vp: RID = get_viewport().get_viewport_rid()
		_sweep_acc["proc"] += float(wall_us) / 1000.0
		_sweep_acc["render_cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_sweep_acc["render_gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_sweep_acc["calls"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_sweep_acc["n"] += 1.0
	if _sweep_f < SWEEP_FRAMES + 3:
		return
	var row: Dictionary = {}
	var n: float = maxf(float(_sweep_acc["n"]), 1.0)
	for k: String in ["proc", "render_cpu", "render_gpu", "calls"]:
		row[k] = snappedf(float(_sweep_acc[k]) / n, 0.01)
	_sweep_out[name] = row
	_sweep_i += 1
	_sweep_f = 0
	if _sweep_i >= SWEEP.size():
		_unhide()
		print("PERF_SWEEP " + JSON.stringify(_sweep_out))
		_report(tick)


## --heavy: worst case. At the end of the warm-up both fighters get a beheading, a gut spill and severed arms (the
## fountains, rope sims, stump wounds and drips all running at once); the head and forearm are really cut off the
## fighter (`Fighter._sever`: joint, cut caps). `spawn` reports the script ms of both and the next frames' wall ms.
func _inject_gore() -> void:
	var b: BloodFx = _match.presenter.blood
	var sever_us: int = 0
	var blood_us: int = 0
	for i: int in _match.fighters.size():
		var f: Node3D = _match.fighters[i]
		var parts: Variant = f.get("parts")
		if not (parts is Dictionary):
			continue
		var d: Dictionary = parts
		var other: Vector3 = Vector3.FORWARD
		if _match.fighters.size() > 1:
			other = ((_match.fighters[1 - i] as Node3D).global_position - f.global_position).normalized()
		var ev: Dictionary = {"kind": "behead" if i == 0 else "gut", "amount": 1.5, "normal": other}
		for kind: String in ["behead", "gut", "sever", "bleed"]:
			var part: String = {"behead": "head", "gut": "torso", "sever": "forearm_l", "bleed": "thigh_l"}[kind]
			if not d.has(part):
				continue
			var n: Node3D = d[part]
			if kind == "behead" or kind == "sever":
				# The fighter's own cut (joint, caps, dropped weapon), as a real sever does before its gore event.
				var ts: int = Time.get_ticks_usec()
				f.call("_sever", part)
				sever_us += Time.get_ticks_usec() - ts
			# A big gutting (organs fall out); the other kinds clamp their strength at 1.5 anyway.
			var amt: float = 60.0 if kind == "gut" else 1.5
			var tb: int = Time.get_ticks_usec()
			b.on_gore({"kind": kind, "part": part, "point": n.global_position, "amount": amt, "normal": other}, f)
			blood_us += Time.get_ticks_usec() - tb
	_spawn = {"sever_ms": snappedf(float(sever_us) / 1000.0, 0.01), "on_gore_ms": snappedf(float(blood_us) / 1000.0, 0.01),
			"wall_ms": []}


## MultiMesh triangles drawn per group (instances shown x mesh faces), the counter Godot's primitives skip.
func _mm_tris() -> Dictionary:
	var out: Dictionary = {}
	var total: int = 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if not (n is MultiMeshInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			continue
		var inst: int = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		var tris: int = 0
		for si: int in mm.mesh.get_surface_count():
			var arr: Array = mm.mesh.surface_get_arrays(si)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var t: int = inst * tris
		out[String(n.name)] = [inst, tris, t]
		total += t
	out["_total"] = total
	return out
