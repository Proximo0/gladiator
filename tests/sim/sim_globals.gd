extends RefCounted
## Process-wide state that outlives a sim's world (`sim_base.clear()` frees only the nodes it built): static vars of
## every game script, Engine and tree settings, Flags, held input actions, audio buses, the default physics space and
## stray nodes. sim_suite captures a baseline before the first sim file, then calls `reset()` before every later file so
## each starts from the state a fresh process gives it. `snapshot()` summarises the same state for comparison
## (tests/unit/test_sim_globals.gd, and the suite's "sim_isolation" row).

const SCAN_DIRS: PackedStringArray = ["res://game"]

var _statics: Array = []  ## [[GDScript, var name], ...] for every top-level `static var` under SCAN_DIRS
var _static_base: Array = []  ## baseline value of each, same order (containers deep-copied)
var _rng_state: Dictionary = {}  ## index in _statics -> baseline RandomNumberGenerator state
var _obj_state: Dictionary = {}  ## index in _statics -> baseline to_dict() of a shared object (Tuning, PlayerProgress)
var _engine: Dictionary = {}
var _flags_args: Dictionary = {}
var _flags_hashes: Array = []
var _root_kids: Array = []  ## nodes under the root at baseline (autoloads, the suite host)
var _host_kids: Array = []
var _gravity: Dictionary = {}
var _buses: Array = []  ## per bus [name, volume_db, mute, solo, bypass, [effect enabled, ...]]
var _captured: bool = false
var _old_worlds: Array[World3D] = []  ## replaced worlds stay referenced: freeing one mid-run errors ("scenario is null")


## Records the starting state. Call once, before any sim file runs.
func capture(host: Node) -> void:
	_statics = _find_statics()
	_static_base.clear()
	for i: int in range(_statics.size()):
		var v: Variant = _read_static(i)
		if v is RandomNumberGenerator:
			_rng_state[i] = [(v as RandomNumberGenerator).seed, (v as RandomNumberGenerator).state]
		elif v is Object and _restorable(v):
			_obj_state[i] = (v as Object).call("to_dict").duplicate(true)
		_static_base.append(_copy(v))
	_engine = _engine_state()
	var flags: Node = _flags(host)
	if flags != null:
		_flags_args = (flags.get("args") as Dictionary).duplicate(true)
		_flags_hashes = (flags.get("_hash_providers") as Array).duplicate()
	_root_kids = host.get_tree().root.get_children()
	_host_kids = host.get_children()
	_gravity = _gravity_state(host)
	_buses = _bus_state()
	_captured = true


## Puts everything capture() recorded back. Returns the names of what had changed, so a sim that leaks shows up.
func reset(host: Node) -> PackedStringArray:
	var changed := PackedStringArray()
	if not _captured:
		return changed
	var tree: SceneTree = host.get_tree()
	# A fresh World3D is a fresh physics space. Jolt keeps body ids, broadphase and contact caches per space, so a
	# reused space makes the same sim give different results (sim_practice: 781, 1817, then 2608 ticks stuck at
	# "thrust" on three runs in one process; 781 every time with a new world).
	_old_worlds.append(tree.root.world_3d)
	tree.root.world_3d = World3D.new()
	for n: Node in tree.root.get_children():
		if not _root_kids.has(n):
			changed.append("root node %s" % n.name)
			n.free()
	for n: Node in host.get_children():
		if not _host_kids.has(n):
			changed.append("host node %s" % n.name)
			n.free()
	for i: int in range(_statics.size()):
		var scr: GDScript = _statics[i][0]
		var name: String = _statics[i][1]
		var now: Variant = _read_static(i)
		if _rng_state.has(i) and now is RandomNumberGenerator:
			var rng: RandomNumberGenerator = now
			if rng.state != int(_rng_state[i][1]):
				changed.append("static %s.%s" % [_short(scr), name])
			rng.seed = int(_rng_state[i][0])
			rng.state = int(_rng_state[i][1])
			continue
		if _obj_state.has(i):
			var base_obj: Object = _static_base[i]
			if is_instance_valid(base_obj) and base_obj.call("to_dict") != _obj_state[i]:
				changed.append("static %s.%s values" % [_short(scr), name])
				_put_dict(base_obj, _obj_state[i])  # the shared object edited in place (a tuning panel, a sim's set_value)
		if _same(now, _static_base[i]):
			continue
		changed.append("static %s.%s" % [_short(scr), name])
		if now is Node and is_instance_valid(now) and not (now as Node).is_inside_tree() and not _same(now, _static_base[i]):
			(now as Node).free()  # a node a static kept out of the tree (the presenter's spare arena)
		scr.set(name, _copy(_static_base[i]))
	var eng: Dictionary = _engine_state()
	for k: String in _engine:
		if eng[k] != _engine[k]:
			changed.append("engine %s" % k)
	Engine.time_scale = float(_engine["time_scale"])
	Engine.physics_ticks_per_second = int(_engine["physics_ticks_per_second"])
	Engine.max_physics_steps_per_frame = int(_engine["max_physics_steps_per_frame"])
	Engine.max_fps = int(_engine["max_fps"])
	Engine.physics_jitter_fix = float(_engine["physics_jitter_fix"])
	if tree.paused:
		changed.append("tree paused")
		tree.paused = false
	var flags: Node = _flags(host)
	if flags != null:
		if flags.get("args") != _flags_args:
			changed.append("Flags.args")
		flags.set("args", _flags_args.duplicate(true))
		if int(flags.get("commands")) != 0:
			changed.append("Flags.commands")
		flags.set("commands", 0)
		if (flags.get("_hash_providers") as Array).size() != _flags_hashes.size():
			changed.append("Flags hash providers")
		var hp: Array[Callable] = []
		for c: Callable in _flags_hashes:
			hp.append(c)
		flags.set("_hash_providers", hp)
	for a: StringName in InputMap.get_actions():
		if Input.is_action_pressed(a):
			changed.append("input %s held" % a)
			Input.action_release(a)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _gravity_state(host) != _gravity:
		changed.append("physics space gravity")
		var space: RID = host.get_viewport().find_world_3d().space
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, _gravity["g"])
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, _gravity["dir"])
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_LINEAR_DAMP, _gravity["ldamp"])
		PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP, _gravity["adamp"])
	if _bus_state() != _buses:
		changed.append("audio buses")
		_restore_buses()
	return changed


## A comparable summary of the same state. Two equal snapshots mean two sims start alike.
func snapshot(host: Node) -> Dictionary:
	var s: Dictionary = {}
	if _statics.is_empty():
		_statics = _find_statics()
	for i: int in range(_statics.size()):
		s["static %s.%s" % [_short(_statics[i][0]), _statics[i][1]]] = _digest(_read_static(i))
	var eng: Dictionary = _engine_state()
	for k: String in eng:
		s["engine " + k] = eng[k]
	var tree: SceneTree = host.get_tree()
	s["tree paused"] = tree.paused
	var names: PackedStringArray = []
	for n: Node in tree.root.get_children():
		names.append(str(n.name))
	s["root nodes"] = names
	s["host nodes"] = host.get_child_count()
	var groups: Dictionary = {}
	_count_groups(tree.root, groups)
	s["groups"] = groups
	var flags: Node = _flags(host)
	if flags != null:
		s["Flags.args"] = (flags.get("args") as Dictionary).duplicate(true)
		s["Flags.commands"] = flags.get("commands")
		s["Flags hash providers"] = (flags.get("_hash_providers") as Array).size()
	var held: PackedStringArray = []
	for a: StringName in InputMap.get_actions():
		if Input.is_action_pressed(a):
			held.append(str(a))
	s["input held"] = held
	s["physics space"] = _gravity_state(host)
	s["audio buses"] = _bus_state()
	return s


## Keys whose values differ between two snapshots, "key: a -> b".
static func diff(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys: Array = a.keys()
	for k: Variant in b.keys():
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	for k: Variant in keys:
		var va: Variant = a.get(k, "<none>")
		var vb: Variant = b.get(k, "<none>")
		if typeof(va) != typeof(vb) or va != vb:
			out.append("%s: %s -> %s" % [k, str(va).left(80), str(vb).left(80)])
	return out


func _find_statics() -> Array:
	var out: Array = []
	var files := PackedStringArray()
	for d: String in SCAN_DIRS:
		_gd_files(d, files)
	files.sort()
	var re := RegEx.create_from_string("(?m)^static var ([A-Za-z_][A-Za-z0-9_]*)")
	for path: String in files:
		var src: String = FileAccess.get_file_as_string(path)
		var hits: Array[RegExMatch] = re.search_all(src)
		if hits.is_empty():
			continue
		var scr: GDScript = load(path) as GDScript
		if scr == null:
			continue
		for m: RegExMatch in hits:
			out.append([scr, m.get_string(1)])
	return out


func _gd_files(dir: String, out: PackedStringArray) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		_gd_files(dir.path_join(d), out)


func _read_static(i: int) -> Variant:
	return (_statics[i][0] as GDScript).get(_statics[i][1])


static func _restorable(o: Object) -> bool:
	return is_instance_valid(o) and o.has_method("to_dict") and (o.has_method("apply_dict") or o.has_method("from_dict"))


## Field by field where the object has apply_dict (Tuning): its set_value clamps, and a test may have set a field outside
## the panel range before the baseline.
static func _put_dict(o: Object, d: Dictionary) -> void:
	if o.has_method("apply_dict"):
		for k: Variant in d:
			o.set(k, d[k])
	else:
		o.call("from_dict", d.duplicate(true))


static func _short(scr: GDScript) -> String:
	return scr.resource_path.get_file().get_basename()


## Containers and packed arrays are shared by reference, so the baseline keeps its own copy.
static func _copy(v: Variant) -> Variant:
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		return v.duplicate()
	return v


## Equal for restore purposes: containers by content, objects by identity.
static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Object:
		return is_same(a, b)
	return a == b


## A value small enough to compare and print: containers by size and hash, objects by class and content.
static func _digest(v: Variant) -> Variant:
	if v == null:
		return "null"
	if v is Object:
		if not is_instance_valid(v):
			return "freed"
		var o: Object = v
		if o.has_method("to_dict"):
			return "%s %d" % [o.get_class(), hash(o.call("to_dict"))]
		if o is RandomNumberGenerator:
			return "rng %d" % (o as RandomNumberGenerator).state
		if o is Node:
			return "node in_tree=%s" % (o as Node).is_inside_tree()
		return o.get_class()
	if v is Array or v is Dictionary:
		return "size %d hash %d" % [v.size(), hash(v)]
	if typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
		return "size %d hash %d" % [v.size(), hash(v)]
	return v


static func _engine_state() -> Dictionary:
	return {
		"time_scale": Engine.time_scale,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
		"max_fps": Engine.max_fps,
		"physics_jitter_fix": Engine.physics_jitter_fix,
	}


static func _flags(host: Node) -> Node:
	return host.get_tree().root.get_node_or_null("Flags")


static func _gravity_state(host: Node) -> Dictionary:
	var space: RID = host.get_viewport().find_world_3d().space
	return {
		"g": PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY),
		"dir": PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR),
		"ldamp": PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_LINEAR_DAMP),
		"adamp": PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP),
	}


static func _count_groups(n: Node, groups: Dictionary) -> void:
	for g: StringName in n.get_groups():
		if not str(g).begins_with("_"):
			groups[str(g)] = int(groups.get(str(g), 0)) + 1
	for c: Node in n.get_children():
		_count_groups(c, groups)


static func _bus_state() -> Array:
	var out: Array = []
	for b: int in range(AudioServer.bus_count):
		var fx: Array = []
		for e: int in range(AudioServer.get_bus_effect_count(b)):
			fx.append(AudioServer.is_bus_effect_enabled(b, e))
		out.append([AudioServer.get_bus_name(b), AudioServer.get_bus_volume_db(b), AudioServer.is_bus_mute(b),
				AudioServer.is_bus_solo(b), AudioServer.is_bus_bypassing_effects(b), fx])
	return out


func _restore_buses() -> void:
	if AudioServer.bus_count != _buses.size():
		var layout: AudioBusLayout = load(str(ProjectSettings.get_setting("audio/buses/default_bus_layout",
				"res://default_bus_layout.tres"))) as AudioBusLayout
		if layout != null:
			AudioServer.set_bus_layout(layout)
		else:
			AudioServer.bus_count = maxi(1, _buses.size())
	for b: int in range(mini(AudioServer.bus_count, _buses.size())):
		var row: Array = _buses[b]
		AudioServer.set_bus_volume_db(b, float(row[1]))
		AudioServer.set_bus_mute(b, bool(row[2]))
		AudioServer.set_bus_solo(b, bool(row[3]))
		AudioServer.set_bus_bypass_effects(b, bool(row[4]))
		var fx: Array = row[5]
		for e: int in range(mini(fx.size(), AudioServer.get_bus_effect_count(b))):
			AudioServer.set_bus_effect_enabled(b, e, bool(fx[e]))
