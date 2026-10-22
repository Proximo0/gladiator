extends "res://tests/sim/sim_base.gd"
## Arena dressing collision: a fighter sprints straight at a weapon rack, a barrier, a gate column and a portcullis.
## With DecorLayout's colliders (as Match._build_collision and the Arena build them) the torso and pelvis stop in
## front of the piece; the same run without them is reported as INFO, showing how deep a fighter used to sink into
## the dressing before reaching the wall.

const FIGHTER: String = "res://game/fighter/fighter.gd"
const RADIUS: float = 11.0
const START_GAP: float = 2.4  ## metres from the piece's front to the fighter's start
const TICKS: int = 240
const WALL_SIDES: int = 48
const WALL_DEPTH: float = 1.0
const WALL_HEIGHT: float = 3.0


func run() -> Array:
	var rows: Array = []
	var targets: Array = [
		["rack", DecorLayout.RACK_ANGLES[0]],
		["barrier", DecorLayout.BARRIER_ANGLES[0]],
		["gate_column", DecorLayout.GATE_ANGLES[0] + DecorLayout.GATE_COLUMN_OFFSET / RADIUS],
		["portcullis", DecorLayout.GATE_ANGLES[0]],
	]
	for t: Array in targets:
		var front: float = _front_radius(float(t[1]))
		var without: float = await _run_into(float(t[1]), front, false)
		var with: float = await _run_into(float(t[1]), front, true)
		rows.append(row("decor_clip_%s_before" % t[0], null, "no collider: torso/pelvis %.2f m past the front" % without))
		rows.append(row("decor_clip_%s" % t[0], with <= 0.0, "with collider: %.2f m past the front (front at r=%.2f)" % [with, front]))
	return rows


## Radius of the innermost collider face near angle `a` (the dressing's front).
func _front_radius(a: float) -> float:
	var best: float = RADIUS
	for c: Dictionary in DecorLayout.colliders(RADIUS):
		var xf: Transform3D = c["xf"]
		var ang: float = atan2(xf.origin.z, xf.origin.x)
		if absf(wrapf(ang - a, -PI, PI)) > 0.08:
			continue
		var depth: float = (c["box"] as Vector3).z * 0.5 if c.has("box") else (c["cyl"] as Vector2).x
		best = minf(best, Vector2(xf.origin.x, xf.origin.z).length() - depth)
	return best


## Sprints a fighter from the centre side at angle `a` into the wall for TICKS; returns the furthest its torso or
## pelvis origin got past radius `front` (negative: it stopped short).
func _run_into(a: float, front: float, colliders: bool) -> float:
	await sandbox(true)
	_walls()
	if colliders:
		ArenaDressing.add_colliders(world, DecorLayout.colliders(RADIUS))
	var out := Vector3(cos(a), 0.0, sin(a))
	var f: Node3D = (load(FIGHTER) as GDScript).new()
	world.add_child(f)
	f.position = out * (front - START_GAP)
	f.rotation.y = atan2(-out.x, -out.z)  # fighter forward (-Z) points out at the wall
	f.setup({"weapon": "longsword", "offhand": "", "armor": {}}, 0, Tuning.new())
	var inp := FighterInput.new()
	inp.move_y = 1000
	inp.buttons = FighterInput.SPRINT | FighterInput.TURN_LOCK
	var past: float = -INF
	for i: int in range(TICKS):
		await step(1)
		f.apply_input(inp)
		for n: String in ["torso", "pelvis"]:
			var body: RigidBody3D = f.parts[n]
			past = maxf(past, body.global_position.dot(out) - front)
	await clear()
	return past


## Floor and the 48-sided wall, as Match._build_collision builds them.
func _walls() -> void:
	var fb := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 1, 40)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	fb.add_child(fcs)
	world.add_child(fb)
	var wall := StaticBody3D.new()
	var width: float = 2.0 * (RADIUS + WALL_DEPTH) * tan(PI / float(WALL_SIDES)) + 0.3
	for i: int in WALL_SIDES:
		var wa: float = TAU * (float(i) + 0.5) / float(WALL_SIDES)
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, WALL_HEIGHT + 2.5, WALL_DEPTH)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Arena.ring_basis(wa), Vector3((RADIUS + WALL_DEPTH * 0.5) * cos(wa), (WALL_HEIGHT - 2.5) * 0.5, (RADIUS + WALL_DEPTH * 0.5) * sin(wa)))
		wall.add_child(cs)
	world.add_child(wall)
