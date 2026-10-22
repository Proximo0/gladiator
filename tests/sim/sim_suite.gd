extends Node
## Runs the regression sims found by sim_files() (each tests/sim/sim_<name>.gd extends sim_base.gd and returns
## [[name, ok, detail], ...] from run()). Prints "SIM <name> PASS|FAIL <detail>" and "SIMS passed=N failed=M".
## Part of tools/run_sims.sh. Run alone: godot --headless --path . res://tests/sim/sim_suite.tscn [-- name ... | -name ...]
## Each file starts from the same process state (sim_globals.gd: statics, Engine, Flags, input, audio, a fresh physics
## world); a row "<file> isolation" fails if anything still differs. A file that hits a script error or returns no rows
## fails, and "SIMFILE <name> <i>/<n>" before each file shows where a hang is; a file still running after
## --sim-timeout=<s> (default 300 s of frames, counted at 60 per second whatever Engine.time_scale is) fails and ends
## the suite. --no-reset skips the reset (to measure leaks).

## The suite runs every tests/sim/sim_*.gd with a `func run(` in alphabetical order, so a new sim needs no edit here.
## Markers in a sim's own text (not inherited by scripts that extend it): "## suite: skip" keeps a file out (a base
## class or a long soak), "## suite: last" runs it after the others (alphabetical among themselves).
const SIM_DIR: String = "res://tests/sim/"
const SKIP_MARK: String = "## suite: skip"
const LAST_MARK: String = "## suite: last"


const DEFAULT_TIMEOUT_S: float = 300.0


## Counts script errors (and other engine errors) from any thread, so a sim that dies mid-run cannot pass quietly.
class SuiteErrorLog extends Logger:
	var script_errors: int = 0
	var errors: int = 0
	var first: String = ""
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			script_errors += 1
			if first == "":
				first = "%s:%d %s" % [file, line, rationale if rationale != "" else code]
		elif error_type == ERROR_TYPE_ERROR:
			errors += 1
		_lock.unlock()

	func take() -> Array:
		_lock.lock()
		var out: Array = [script_errors, errors, first]
		script_errors = 0
		errors = 0
		first = ""
		_lock.unlock()
		return out


var _passed: int = 0
var _failed: int = 0
var _current: String = ""


func _ready() -> void:
	# Args pick sims: "sim_a sim_b" runs only those; "-sim_a" skips one (CI shards: the last shard skips the others' sims).
	var only := PackedStringArray()
	var skip := PackedStringArray()
	var reset: bool = true
	var timeout_s: float = DEFAULT_TIMEOUT_S
	var shuffle_seed: int = -1
	var files: PackedStringArray = sim_files()
	for a: String in OS.get_cmdline_user_args():
		if a == "--no-reset":
			reset = false
		elif a == "--list":
			print("\n".join(files))
			get_tree().quit(0)
			return
		elif a.begins_with("--shuffle="):
			shuffle_seed = int(a.trim_prefix("--shuffle="))
		elif a.begins_with("--sim-timeout="):
			timeout_s = float(a.trim_prefix("--sim-timeout="))
		elif a.begins_with("--"):
			continue
		elif a.begins_with("-"):
			skip.append(a.substr(1))
		else:
			only.append(a)
	for n: String in only + skip:
		if not files.has(n):
			_report(["sim_suite", false, "unknown sim name %s (no tests/sim/%s.gd with a run(), or marked skip)" % [n, n]])
	var todo: Array = []
	for f: String in files:
		if (only.is_empty() or only.has(f)) and not skip.has(f):
			todo.append(f)
	if shuffle_seed >= 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = shuffle_seed
		for i: int in range(todo.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var t: Variant = todo[i]
			todo[i] = todo[j]
			todo[j] = t
		print("SIMORDER seed=%d %s" % [shuffle_seed, " ".join(PackedStringArray(todo))])
	var log := SuiteErrorLog.new()
	OS.add_logger(log)
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	watchdog.timeout.connect(_hung.bind(timeout_s))
	add_child(watchdog)
	var globals: RefCounted = (load("res://tests/sim/sim_globals.gd") as GDScript).new()
	globals.capture(self)
	var start: Dictionary = globals.snapshot(self)
	for i: int in range(todo.size()):
		var f: String = todo[i]
		_current = f
		print("SIMFILE %s %d/%d" % [f, i + 1, todo.size()])
		if i > 0 and reset:
			globals.reset(self)
			var left: PackedStringArray = globals.diff(start, globals.snapshot(self))
			if not left.is_empty():
				_report([f + " isolation", false, "state differs from the first file's start: " + "; ".join(left)])
		log.take()
		watchdog.start(timeout_s)
		var scr: GDScript = load("res://tests/sim/%s.gd" % f) as GDScript
		var rows: Variant = []
		if scr == null or not scr.can_instantiate():
			_report([f, false, "script did not load"])
		else:
			var sim: Variant = scr.new()
			sim.host = self
			rows = await sim.run()
		watchdog.stop()
		var errs: Array = log.take()
		var n: int = 0
		if rows is Array:
			for r: Variant in rows:
				if r is Array and (r as Array).size() >= 3:
					_report(r)
					n += 1
		if n == 0 and scr != null:
			_report([f, false, "returned no rows (the sim died or never reached its checks)"])
		if int(errs[0]) > 0:
			_report([f + " script errors", false, "%d, first: %s" % [errs[0], errs[2]]])
	_current = ""
	print("SIMS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Sim file names (no extension) in run order: every sim_*.gd under SIM_DIR whose own text has `func run(` and no
## SKIP_MARK, alphabetical, then the LAST_MARK ones.
static func sim_files() -> PackedStringArray:
	var first := PackedStringArray()
	var last := PackedStringArray()
	for fn: String in DirAccess.get_files_at(SIM_DIR):
		if not (fn.begins_with("sim_") and fn.ends_with(".gd")) or fn == "sim_suite.gd":
			continue
		var text: String = FileAccess.get_file_as_string(SIM_DIR + fn)
		if text.find("\nfunc run(") < 0 or text.find(SKIP_MARK) >= 0:
			continue
		if text.find(LAST_MARK) >= 0:
			last.append(fn.get_basename())
		else:
			first.append(fn.get_basename())
	first.sort()
	last.sort()
	first.append_array(last)
	return first


func _report(r: Array) -> void:
	var verdict: String = "PASS" if r[1] else "FAIL"
	if r[1] == null:
		verdict = "INFO"
	elif r[1]:
		_passed += 1
	else:
		_failed += 1
	print("SIM %s %s %s" % [r[0], verdict, r[2]])


## The watchdog fired: the current file has not finished within `timeout_s` seconds of frames. Report it and stop the suite.
func _hung(timeout_s: float) -> void:
	_report([_current, false, "still running after %.0f s (hung); the files after it did not run" % timeout_s])
	print("SIMS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1)
