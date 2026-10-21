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


func _ready() -> void:
	_measure = int(Flags.get_arg("measure", "300"))
	_bloody = int(Flags.get_arg("bloody", "60"))
	_max_ticks = int(Flags.get_arg("max_ticks", "5400"))
	_min_tick = int(Flags.get_arg("late_tick", "600"))
	if Flags.args.has("quality"):
		GfxQuality.set_level(int(Flags.get_arg("quality", "2")))
	_match = Match.new()
	add_child(_match)
	_match.setup({"mode": "bot_vs_bot", "seed": int(Flags.get_arg("seed", "1002")), "presentation": true,
			"loop": false, "time_limit_s": 600.0})
	Engine.max_physics_steps_per_frame = 16
	_ff = float(Flags.get_arg("ff", "8"))
	Engine.time_scale = _ff  # fast-forward to the bloody point (software GL renders ~3 fps); measured at 1x
	if Flags.args.has("quality"):
		_match.presenter.blood.set_quality(GfxQuality.blood_level())  # MatchPresenter.build hard-codes 2 on desktop
	_t_start = Time.get_ticks_msec()


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
	var c: Dictionary = _counts()
	for k: String in c:
		_peak[k] = maxi(int(_peak.get(k, 0)), int(c[k]))
	var tick: int = _match.tick
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
			_match.presenter.blood.set("prof", {})
			_match.presenter.sand.set("prof", {})
		return
	if _frames < 5:
		return
	_samples.append({
		"proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"fx": float(_fx_us) / 1000.0,
		"blood": float(_blood_us) / 1000.0,
	})
	for k: String in c:
		_peak[k] = maxi(int(_peak.get(k, 0)), int(c[k]))
	if _samples.size() >= _measure:
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


func _stat(key: String) -> Dictionary:
	var v: Array = []
	for s: Dictionary in _samples:
		v.append(float(s[key]))
	v.sort()
	var sum: float = 0.0
	for x: float in v:
		sum += x
	return {"mean": snappedf(sum / float(v.size()), 0.01), "p95": snappedf(v[int(v.size() * 0.95)], 0.01),
			"max": snappedf(v[v.size() - 1], 0.01)}


func _report(tick: int) -> void:
	var out: Dictionary = {
		"seed": int(Flags.get_arg("seed", "1002")), "quality": GfxQuality.level,
		"reached": _reached, "tick": tick, "frames": _samples.size(),
		"process_ms": _stat("proc"), "physics_ms": _stat("phys"), "fx_ms": _stat("fx"), "blood_ms": _stat("blood"), "census": _census(), "crowd": _crowd(), "sections_ms": _prof(), "draw_calls": _stat("calls"),
		"primitives": _stat("prims"), "objects": _stat("objs"), "peak": _peak,
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
	var p: MatchPresenter = _match.presenter
	for part: String in Flags.get_arg("hide", "").split(",", false):
		match part:
			"crowd":
				p.arena.crowd.visible = false
			"hud":
				p.hud.visible = false
			"shadow":
				p.arena.sun.shadow_enabled = false
			"sand":
				(p.sand as Node3D).visible = false
			"blood":
				p.blood.visible = false
			"fighters":
				for f: Node3D in _match.fighters:
					f.visible = false
			"stands":
				for c: Node in p.arena.get_children():
					if c is MeshInstance3D:
						(c as MeshInstance3D).visible = false
