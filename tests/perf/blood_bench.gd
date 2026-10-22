extends SceneTree
## Gore-moment blood bench, headless: a run-through and a beheading on two still bodies over a real SandSurface, per
## blood quality. Prints one `BENCH {json}` line per quality: drops emitted in the gore frame and the worst frame, the
## worst blood step and flush_splats (ms), sand texels stamped per frame (mean and worst) and the apply_blood time.
## godot --headless --path . -s res://tests/perf/blood_bench.gd [-- --quality=0|1|2] [--frames=N]
## Never part of the check suite.


class _BbHealth extends RefCounted:
	var blood: float = 4.2
	var dead: bool = false


class _BbBody extends Node3D:
	var side: int = 0
	var health: _BbHealth = _BbHealth.new()
	var parts: Dictionary = {}


class _BbSand extends Node:  ## forwards to the real sand and counts the texels each add_blood can touch
	var real: Node = null
	var texels: int = 0
	var us: int = 0

	func add_blood(pos: Vector3, radius_m: float, litres: float, slot: int = 0) -> void:
		var tpm: float = float(real.get("texels_per_m"))
		var ext: float = SandMap.blood_spread_radius(litres, radius_m) * tpm * 2.0 + 1.0
		texels += int(4.0 * ext * ext)
		var t0: int = Time.get_ticks_usec()
		real.call("add_blood", pos, radius_m, litres, slot)
		us += Time.get_ticks_usec() - t0

	func height_at(p: Vector3) -> float:
		return float(real.call("height_at", p))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var levels: Array[int] = [0, 1, 2]
	var frames: int = 240
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			levels = [int(a.substr(10))]
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--spawn_frames="):
			Tuning.shared().gore_spawn_frames = float(a.substr(15))
	for q: int in levels:
		_bench(q, frames)
	quit()


func _body(side: int, at: Vector3) -> _BbBody:
	var b: _BbBody = _BbBody.new()
	b.side = side
	root.add_child(b)
	for part: String in ["torso", "head", "neck"]:
		var n: Node3D = Node3D.new()
		b.add_child(n)
		n.position = at + (Vector3(0, 1.2, 0) if part == "torso" else Vector3(0, 1.6, 0))
		b.parts[part] = n
	return b


func _bench(q: int, frames: int) -> void:
	GfxQuality.set_level(q)
	var sand_real: Node = (load("res://game/sand/sand_surface.gd") as GDScript).new()
	root.add_child(sand_real)
	sand_real.call("setup", 11.0)
	sand_real.set_process(false)
	sand_real.set("profile_on", true)
	var pools_ms: float = 0.0
	var pool_calls_peak: int = 0
	var sand: _BbSand = _BbSand.new()
	sand.real = sand_real
	root.add_child(sand)
	var fx: BloodFx = BloodFx.new()
	fx.auto_step = false
	root.add_child(fx)
	fx.set_process(false)
	fx._build()
	fx.set_quality(q)
	fx.rng.seed = 4242
	fx.sand = sand
	fx.profile_on = true
	var a: _BbBody = _body(0, Vector3(-1, 0, 0))
	var b: _BbBody = _body(1, Vector3(1, 0, 0))
	fx.track(a)
	fx.track(b)
	var before: int = fx.sim.count
	fx.on_gore({"kind": "run_through", "part": "torso", "point": Vector3(-1, 1.2, 0.2), "normal": Vector3(0, 0, 1), "amount": 1.5}, a)
	fx.on_gore({"kind": "behead", "part": "head", "point": Vector3(1, 1.6, 0), "normal": Vector3(0, 1, 0), "amount": 1.5}, b)
	var gore_frame: int = fx.sim.count - before
	var worst_emit: int = 0
	var worst_step: float = 0.0
	var worst_flush: float = 0.0
	var worst_tex: int = 0
	var tex_sum: int = 0
	for i: int in frames:
		fx.prof = {}
		sand.texels = 0
		var c0: int = fx.sim.count
		var t0: int = Time.get_ticks_usec()
		fx.step(1.0 / 60.0)
		sand_real.set("prof", {})
		sand_real.call("_process", 1.0 / 60.0)
		pools_ms += float((sand_real.get("prof") as Dictionary).get("pools", 0.0))
		pool_calls_peak = maxi(pool_calls_peak, (sand_real.get("_pools") as Array).size())
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		var emitted: int = fx.stat_emitted if i > 0 else fx.sim.count - before
		if i == 0:
			emitted = maxi(fx.sim.count - c0, 0) + gore_frame
		worst_emit = maxi(worst_emit, emitted)
		worst_step = maxf(worst_step, ms)
		worst_flush = maxf(worst_flush, float(fx.prof.get("flush_splats", 0.0)))
		worst_tex = maxi(worst_tex, sand.texels)
		tex_sum += sand.texels
	print("BENCH " + JSON.stringify({"quality": q, "gore_call_drops": gore_frame, "worst_frame_drops": worst_emit,
			"worst_step_ms": snappedf(worst_step, 0.01), "worst_flush_ms": snappedf(worst_flush, 0.01),
			"texels_mean": tex_sum / frames, "texels_worst": worst_tex,
			"apply_blood_ms_total": snappedf(float(sand.us) / 1000.0, 0.01), "pools_ms_mean": snappedf(pools_ms / frames, 0.01),
			"pools_peak": pool_calls_peak, "spawn_frames": Tuning.shared().gore_spawn_frames}))
	fx.free()
	a.free()
	b.free()
	sand.free()
	sand_real.free()
