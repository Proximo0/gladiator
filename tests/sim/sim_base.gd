extends RefCounted
## Shared harness for the regression sims (sim_*.gd, run by tests/sim/sim_suite.gd).
## A sim extends this, and `host` (a Node in the tree) is set before `run()`. Implement `func run() -> Array`
## returning [[name, ok, detail], ...]; ok == null reports INFO only. Everything is in sim seconds (physics
## ticks), never wall clock.

const DT: float = 1.0 / 60.0

var host: Node


## A port for a sim that opens sockets: a per-process block of 64 ports (20000..45600, from the OS process id)
## plus a slot offset, so two suites running at once on one machine never listen on the same port. Slots in use:
## loopback 0/1/20, soak 22+, drop 40/41, menu 45, feel 46, quick 47 (game) 48 (stub), discovery 52..59.
static func net_port(slot: int) -> int:
	return 20000 + (OS.get_process_id() % 400) * 64 + slot
var world: Node3D
var _space_vp: SubViewport = null


## An empty Node3D under the host to build the scenario in. With `own_space` it lives in its own World3D (a
## SubViewport), so its physics run in a fresh space: a Jolt space's results depend on every body it created and
## freed before, so a long, chaotic scenario in the shared space plays out differently after other sims.
func sandbox(own_space: bool = false) -> void:
	world = Node3D.new()
	if own_space:
		_space_vp = SubViewport.new()
		_space_vp.own_world_3d = true
		host.add_child(_space_vp)
		_space_vp.add_child(world)
	else:
		host.add_child(world)
	await host.get_tree().physics_frame


func clear() -> void:
	if world != null:
		world.get_parent().remove_child(world)
		world.free()
		world = null
	if _space_vp != null:
		host.remove_child(_space_vp)
		_space_vp.free()
		_space_vp = null
	await host.get_tree().physics_frame


## Advance `ticks` physics frames.
func step(ticks: int) -> void:
	for _i: int in range(ticks):
		await host.get_tree().physics_frame


func row(name: String, ok: Variant, detail: String) -> Array:
	return [name, ok, detail]
