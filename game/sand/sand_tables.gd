class_name SandTables
extends RefCounted
## Process-lifetime cache of the sand floor's static tables, the slow part of SandSurface.setup (about 110-180 ms of
## GDScript loops): the tileable noise image, the base relief grid and its shader image, and the subdivided disc's
## vertex/index arrays. Each depends only on its key (arena radius, map extent, mesh cell), never on a match, so a
## second arena build reuses them. `prewarm` computes missing tables on a WorkerThreadPool task (CPU work only: packed
## arrays and Images, no RenderingServer calls), `is_ready` is the ready flag, and the getters wait for a running task
## or compute synchronously when none was started. Main thread callers only; presentation only.

const NOISE_SIZE: int = 256
const NOISE_FREQS: Array[float] = [0.09, 0.035, 0.012]

static var _results: Dictionary = {}  ## key -> Dictionary of tables
static var _tasks: Dictionary = {}  ## key -> WorkerThreadPool task id still to be waited on
static var _mutex: Mutex = Mutex.new()


static func noise_key() -> String:
	return "noise"


static func base_key(arena_radius: float, extent: float, seed_v: int) -> String:
	return "base:%.4f:%.4f:%d" % [arena_radius, extent, seed_v]


static func disc_key(r: float, cell: float) -> String:
	return "disc:%.4f:%.4f" % [r, cell]


## Starts background tasks for every table a SandSurface.setup with these numbers needs and does not have yet.
static func prewarm(arena_radius: float, extent: float, seed_v: int, disc_r: float, cell: float) -> void:
	_start(noise_key(), build_noise)
	_start(base_key(arena_radius, extent, seed_v), build_base.bind(arena_radius, extent, seed_v))
	_start(disc_key(disc_r, cell), build_disc.bind(disc_r, cell))


## True when every table for these numbers is computed (no wait needed).
static func is_ready(arena_radius: float, extent: float, seed_v: int, disc_r: float, cell: float) -> bool:
	for k: String in [noise_key(), base_key(arena_radius, extent, seed_v), disc_key(disc_r, cell)]:
		if not _has_result(k):
			return false
	return true


## {"image": Image RGB8 256 px with mipmaps}: R fine grain, G medium clumps, B large ripples.
static func noise() -> Dictionary:
	return _take(noise_key(), build_noise)


## {"base": PackedFloat32Array (SandMap.build_base), "image": Image RGBAH (height, slopes)}.
static func base(arena_radius: float, extent: float, seed_v: int) -> Dictionary:
	return _take(base_key(arena_radius, extent, seed_v), build_base.bind(arena_radius, extent, seed_v))


## {"verts": PackedVector3Array, "indices": PackedInt32Array} of the disc mesh (SandSurface.build_disc_mesh).
static func disc(r: float, cell: float) -> Dictionary:
	return _take(disc_key(r, cell), build_disc.bind(r, cell))


## Drops every cached table (waits for running tasks first). Tests.
static func clear() -> void:
	for k: String in _tasks.keys():
		_wait(k)
	_mutex.lock()
	_results.clear()
	_mutex.unlock()


# ---------------------------------------------------------------- builders (thread-safe: no nodes, no RenderingServer)

static func build_noise() -> Dictionary:
	var chans: Array[PackedByteArray] = []
	for k: int in range(3):
		var fn: FastNoiseLite = FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = 11 + k * 7
		fn.frequency = NOISE_FREQS[k]
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM if k > 0 else FastNoiseLite.FRACTAL_NONE
		var im: Image = fn.get_seamless_image(NOISE_SIZE, NOISE_SIZE, false, false, 0.1, true)
		im.convert(Image.FORMAT_L8)
		chans.append(im.get_data())
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(NOISE_SIZE * NOISE_SIZE * 3)
	for i: int in range(NOISE_SIZE * NOISE_SIZE):
		bytes[i * 3] = chans[0][i]
		bytes[i * 3 + 1] = chans[1][i]
		bytes[i * 3 + 2] = chans[2][i]
	var img: Image = Image.create_from_data(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_RGB8, bytes)
	img.generate_mipmaps()
	return {"image": img}


static func build_base(arena_radius: float, extent: float, seed_v: int) -> Dictionary:
	var b: PackedFloat32Array = SandMap.build_base(arena_radius, extent, seed_v)
	var nb: int = SandMap.base_size(extent)
	var im: Image = Image.create_from_data(nb, nb, false, Image.FORMAT_RGBAF, SandMap.base_to_rgba_bytes(b, extent))
	im.convert(Image.FORMAT_RGBAH)
	return {"base": b, "image": im}


## Grid cells of size `cell` over the disc of radius `r`; a cell is kept when any corner is inside. Shared corners
## are one vertex. Two triangles per cell, clockwise seen from above (+Y, Godot front faces).
static func build_disc(r: float, cell: float) -> Dictionary:
	var gn: int = int(ceil(2.0 * r / cell)) + 1
	var r2: float = r * r
	# A grid point is inside when its own distance is; a cell is kept when any of its 4 corners is inside.
	var inside: PackedByteArray = PackedByteArray()
	inside.resize(gn * gn)
	for gz: int in range(gn):
		var pz: float = -r + float(gz) * cell
		for gx: int in range(gn):
			var px: float = -r + float(gx) * cell
			inside[gz * gn + gx] = 1 if px * px + pz * pz <= r2 else 0
	var idx: PackedInt32Array = PackedInt32Array()
	idx.resize(gn * gn)
	idx.fill(-1)
	var verts: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for cz: int in range(gn - 1):
		var row: int = cz * gn
		for cx: int in range(gn - 1):
			var g0: int = row + cx
			if inside[g0] == 0 and inside[g0 + 1] == 0 and inside[g0 + gn] == 0 and inside[g0 + gn + 1] == 0:
				continue
			var q: PackedInt32Array = PackedInt32Array([g0, g0 + 1, g0 + gn, g0 + gn + 1])
			for k: int in range(4):
				var gi: int = q[k]
				if idx[gi] < 0:
					idx[gi] = verts.size()
					verts.append(Vector3(-r + float(gi % gn) * cell, 0.0, -r + float(gi / gn) * cell))
				q[k] = idx[gi]
			indices.append_array(PackedInt32Array([q[0], q[1], q[2], q[1], q[3], q[2]]))
	return {"verts": verts, "indices": indices}


# ---------------------------------------------------------------- cache

static func _has_result(key: String) -> bool:
	_mutex.lock()
	var has: bool = _results.has(key)
	_mutex.unlock()
	return has


static func _start(key: String, builder: Callable) -> void:
	if _has_result(key) or _tasks.has(key):
		return
	_tasks[key] = WorkerThreadPool.add_task(_run.bind(key, builder), false, "SandTables " + key)


static func _run(key: String, builder: Callable) -> void:
	var out: Dictionary = builder.call()
	_mutex.lock()
	_results[key] = out
	_mutex.unlock()


static func _wait(key: String) -> void:
	if _tasks.has(key):
		WorkerThreadPool.wait_for_task_completion(int(_tasks[key]))
		_tasks.erase(key)


static func _take(key: String, builder: Callable) -> Dictionary:
	_wait(key)
	_mutex.lock()
	var out: Dictionary = _results.get(key, {})
	_mutex.unlock()
	if out.is_empty():
		out = builder.call()
		_mutex.lock()
		_results[key] = out
		_mutex.unlock()
	return out
