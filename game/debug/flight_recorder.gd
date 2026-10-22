class_name FlightRecorder
extends Node
## Flight recorder: keeps a whole match in memory (seed, loadouts, personalities, Tuning diff and the inputs of every
## tick) so it replays bit-identically from tick 0 (see tools/replay.sh). Duck-typed against Match: it needs the
## signals `inputs_applied(tick, inputs)` and `match_over(result)`, plus `seed` and `fighters` when present.
##
## File format (version 1, JSON):
##   {version, seed, loadouts, personalities, tuning: {diff}, time_limit_s, fight_start_tick, ticks: N,
##    inputs: [[[5 ints],[5 ints]], ...], result, trace_every, trace: [[tick, hash, [mm ints: every part of every fighter]], ...]}
## `fight_start_tick` is the match tick the fight clock starts from (the intro's release; 0 without an intro or in an
## older file). It is read from the Match on every tick and at match_over, not with the header at tick 0, because the
## offline intro skip sets it between two physics ticks, long after the header was taken.
## `trace` is how a replay measures its divergence (metres) and finds the first tick that differs.
## F12 saves the recording; `match_over` saves it too when the run has `--record`. A scripted (headless, capture) run
## never writes unless `--record` is given.

signal saved(path: String)

const VERSION: int = 1
const TRACE_EVERY: int = 10
const AXIS_MAX: int = 1000
const BUTTON_MASK: int = 0xffff  ## the 16 FighterInput button bits (ROLL 256 and SHOVE, KICK, CLINCH up to 2048 were cut off at 8)
const DIR: String = "user://recordings"

var last_path: String = ""

var _match: Node = null
var _seed: int = 0
var _loadouts: Array = []
var _personalities: Array = []
var _tuning: Dictionary = {}
var _time_limit_s: float = 0.0
var _fight_start_tick: int = 0
var _inputs: Array = []
var _trace: Array = []
var _result: Dictionary = {}
var _have_header: bool = false


func attach(m: Node) -> void:
	_match = m
	_reset()
	m.connect("inputs_applied", _on_inputs_applied)
	m.connect("match_over", _on_match_over)


func _reset() -> void:
	_seed = 0
	_loadouts = []
	_personalities = []
	_tuning = {}
	_time_limit_s = 0.0
	_fight_start_tick = 0
	_inputs = []
	_trace = []
	_result = {}
	_have_header = false


func tick_count() -> int:
	return _inputs.size()


## The recording so far as a plain Dictionary (the file format).
func recording() -> Dictionary:
	return {
		"version": VERSION, "seed": _seed, "loadouts": _loadouts.duplicate(true),
		"personalities": _personalities.duplicate(true), "tuning": _tuning.duplicate(true),
		"time_limit_s": _time_limit_s, "fight_start_tick": _fight_start_tick, "ticks": _inputs.size(), "inputs": _inputs.duplicate(true), "result": _result.duplicate(true),
		"trace_every": TRACE_EVERY, "trace": _trace.duplicate(true),
	}


## Writes the recording. Empty path = user://recordings/<time>_<seed>.json. Returns the path, or "" when nothing was
## written (scripted run without --record, nothing recorded, or a write error).
func save(path: String = "") -> String:
	if _inputs.is_empty():
		return ""
	if path == "":
		if _is_scripted() and not Flags.args.has("record"):
			return ""
		DirAccess.make_dir_recursive_absolute(DIR)
		var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		path = "%s/%s_%d.json" % [DIR, stamp, _seed]
	else:
		var d: String = path.get_base_dir()
		if d != "" and not DirAccess.dir_exists_absolute(d):
			DirAccess.make_dir_recursive_absolute(d)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(to_json(recording()))
	f.close()
	last_path = path
	saved.emit(path)
	return path


func _is_scripted() -> bool:
	return Flags.is_scripted_run()


func _unhandled_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F12:
		save()


func _on_inputs_applied(tick: int, inputs: Array) -> void:
	if tick == 0 and not _inputs.is_empty():
		_reset()  # a looping bot match started over
	if not _have_header:
		_capture_header()
	var row: Array = []
	for a: Variant in inputs:
		row.append(quantize_input(a as Array))
	_inputs.append(row)
	_read_fight_start()
	if tick % TRACE_EVERY == 0 and _match != null:
		var fighters: Variant = _match.get("fighters")
		if fighters is Array:
			var s: Array = sample_state(fighters as Array)
			_trace.append([tick, s[0], s[1]])


## The Match's fight clock start (duck-typed; absent on a match without a fight clock).
func _read_fight_start() -> void:
	if _match == null:
		return
	var fs: Variant = _match.get("fight_start_tick")
	if fs != null:
		_fight_start_tick = maxi(int(fs), 0)


func _capture_header() -> void:
	_have_header = true
	_tuning = Tuning.shared().diff_from_defaults()
	var sd: Variant = _match.get("seed")
	_seed = int(sd) if sd != null else 0
	var fighters: Variant = _match.get("fighters")
	if fighters is Array:
		for f: Variant in fighters as Array:
			var lo: Variant = (f as Object).get("loadout")
			_loadouts.append((lo as Dictionary).duplicate(true) if lo is Dictionary else {})
	var cfg: Variant = _match.get("config")
	if cfg is Dictionary:
		_time_limit_s = float((cfg as Dictionary).get("time_limit_s", 0.0))
		var cp: Variant = (cfg as Dictionary).get("personalities")
		if cp is Array:
			_personalities = (cp as Array).duplicate(true)
	var pers: Variant = _match.get("personalities")
	if pers is Array:
		_personalities = (pers as Array).duplicate(true)


func _on_match_over(result: Dictionary) -> void:
	_result = json_safe(result) as Dictionary
	_read_fight_start()
	if result.has("seed"):
		_seed = int(result["seed"])
	if result.get("loadouts") is Array:
		_loadouts = (json_safe(result["loadouts"]) as Array)
	if result.get("personalities") is Array:
		_personalities = (json_safe(result["personalities"]) as Array)
	if Flags.args.has("record"):
		save()


# ---------------------------------------------------------------- pure helpers (static, unit-tested)

## One fighter's input as 5 ints: axes rounded and clamped to -1000..1000, buttons masked to 16 bits.
static func quantize_input(a: Array) -> Array:
	var out: Array = []
	for i: int in range(5):
		var v: int = roundi(float(a[i])) if i < a.size() else 0
		if i < 4:
			out.append(clampi(v, -AXIS_MAX, AXIS_MAX))
		else:
			out.append(v & BUTTON_MASK)
	return out


## Makes a value JSON-safe: non-finite floats become null, vectors become arrays, packed arrays plain arrays.
static func json_safe(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return v if is_finite(float(v)) else null
		TYPE_VECTOR3:
			var p: Vector3 = v
			return [json_safe(p.x), json_safe(p.y), json_safe(p.z)]
		TYPE_VECTOR2:
			var q: Vector2 = v
			return [json_safe(q.x), json_safe(q.y)]
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k: Variant in v:
				out[str(k)] = json_safe(v[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for e: Variant in v:
				arr.append(json_safe(e))
			return arr
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_FLOAT64_ARRAY:
			var pa: Array = []
			for e: Variant in Array(v):
				pa.append(json_safe(e))
			return pa
		TYPE_STRING_NAME:
			return str(v)
	return v


## The Match setup config that replays `rec` from tick 0: same seed, loadouts, personalities, time limit and fight
## clock start (the intro's release), no loop. `limit_s` overrides the time limit when > 0.
static func replay_config(rec: Dictionary, presentation: bool, limit_s: float = 0.0) -> Dictionary:
	return {
		"mode": "bot_vs_bot", "seed": int(rec.get("seed", 0)), "loadouts": rec.get("loadouts", []),
		"personalities": rec.get("personalities", []), "presentation": presentation, "loop": false,
		"time_limit_s": limit_s if limit_s > 0.0 else float(rec.get("time_limit_s", 0.0)),
		"fight_start_tick": int(rec.get("fight_start_tick", 0)),
	}


static func to_json(rec: Dictionary) -> String:
	return JSON.stringify(json_safe(rec))


## Error text for a recording Dictionary, "" when it is a valid version-1 recording.
static func validate(d: Dictionary) -> String:
	if int(d.get("version", 0)) != VERSION:
		return "unsupported version %s (want %d)" % [str(d.get("version", "none")), VERSION]
	for key: String in ["seed", "loadouts", "inputs"]:
		if not d.has(key):
			return "missing key '%s'" % key
	if not (d["inputs"] is Array):
		return "inputs is not an array"
	if int(d.get("ticks", -1)) != (d["inputs"] as Array).size():
		return "ticks (%s) does not match inputs (%d)" % [str(d.get("ticks", "none")), (d["inputs"] as Array).size()]
	return ""


## Parses recording text. Returns the recording with JSON floats turned back into ints, or {"error": text}.
static func parse(text: String) -> Dictionary:
	var js := JSON.new()
	if js.parse(text) != OK:
		return {"error": "not valid JSON"}
	var raw: Variant = js.data
	if not (raw is Dictionary):
		return {"error": "not a JSON object"}
	var d: Dictionary = raw
	var err: String = validate(d)
	if err != "":
		return {"error": err}
	d["version"] = int(d["version"])
	d["seed"] = int(d["seed"])
	d["ticks"] = int(d["ticks"])
	d["time_limit_s"] = float(d.get("time_limit_s", 0.0))
	d["fight_start_tick"] = maxi(int(d.get("fight_start_tick", 0)), 0)
	var inputs: Array = []
	for row: Variant in d["inputs"] as Array:
		var r: Array = []
		for a: Variant in row as Array:
			r.append(quantize_input(a as Array))
		inputs.append(r)
	d["inputs"] = inputs
	d["trace_every"] = int(d.get("trace_every", TRACE_EVERY))
	var trace: Array = []
	for e: Variant in d.get("trace", []) as Array:
		var ea: Array = e
		var pos: Array = []
		for x: Variant in ea[2] as Array:
			pos.append(int(x))
		trace.append([int(ea[0]), int(ea[1]), pos])
	d["trace"] = trace
	for key: String in ["personalities", "result", "tuning"]:
		if not d.has(key):
			d[key] = [] if key == "personalities" else {}
	return d


static func load_file(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "cannot open %s" % path}
	return parse(f.get_as_text())


## Every fighter part position (millimetres, ints) and a hash of the raw float positions, as [hash, PackedInt32Array].
static func sample_state(fighters: Array) -> Array:
	var raw := PackedFloat32Array()
	var mm := PackedInt32Array()
	for f: Variant in fighters:
		var parts: Variant = (f as Object).get("parts")
		for n: String in FighterRig.names():
			var b: Node3D = null
			if parts is Dictionary and (parts as Dictionary).has(n):
				b = (parts as Dictionary)[n] as Node3D
			var p: Vector3 = b.global_position if b != null and is_instance_valid(b) and b.is_inside_tree() else Vector3.ZERO
			raw.append(p.x)
			raw.append(p.y)
			raw.append(p.z)
			mm.append(roundi(p.x * 1000.0))
			mm.append(roundi(p.y * 1000.0))
			mm.append(roundi(p.z * 1000.0))
	return [hash(raw), mm]


## Compares two recordings' traces: {divergence (m, largest part distance), first_tick (-1 = none), hash_match,
## samples, same_length}. Samples are matched by tick.
static func compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var ta: Array = a.get("trace", [])
	var tb: Array = b.get("trace", [])
	var by_tick: Dictionary = {}
	for e: Variant in tb:
		by_tick[int((e as Array)[0])] = e
	var worst: float = 0.0
	var first: int = -1
	var hash_ok: bool = true
	var n: int = 0
	for e: Variant in ta:
		var ea: Array = e
		var t: int = int(ea[0])
		if not by_tick.has(t):
			continue
		n += 1
		var eb: Array = by_tick[t]
		var pa: Array = ea[2]
		var pb: Array = eb[2]
		var d: float = 0.0
		if pa.size() != pb.size():
			d = INF
		else:
			for i: int in range(0, pa.size() - 2, 3):
				var dx: float = float(int(pa[i]) - int(pb[i]))
				var dy: float = float(int(pa[i + 1]) - int(pb[i + 1]))
				var dz: float = float(int(pa[i + 2]) - int(pb[i + 2]))
				d = maxf(d, sqrt(dx * dx + dy * dy + dz * dz) / 1000.0)
		var differs: bool = d > 0.0 or int(ea[1]) != int(eb[1])
		if int(ea[1]) != int(eb[1]):
			hash_ok = false
		if differs and first < 0:
			first = t
		worst = maxf(worst, d)
	return {"divergence": worst, "first_tick": first, "hash_match": hash_ok, "samples": n, "same_length": ta.size() == tb.size()}
