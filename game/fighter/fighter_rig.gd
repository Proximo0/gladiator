class_name FighterRig
extends RefCounted
## Static body plan of a fighter: the 11 parts in their rest pose (standing, arms hanging, feet at y = 0),
## shapes, masses, joint pivots, angular limits and PD drive settings. Positions are in the fighter's local
## frame (X right, Y up, -Z forward). Limits are [x_lo, x_hi, y_lo, y_hi, z_lo, z_hi] radians of the child
## relative to its parent, about the rest axes. "freq" (rad/s) and "torque" (N·m) set the joint's PD drive.

const PARTS: Array[Dictionary] = [
	{"name": "pelvis", "parent": "", "shape": "box", "size": Vector3(0.32, 0.20, 0.20), "mass": 11.0,
		"center": Vector3(0, 0.98, 0), "pivot": Vector3(0, 0.98, 0), "lim": [0, 0, 0, 0, 0, 0], "freq": 0.0, "torque": 0.0},
	{"name": "torso", "parent": "pelvis", "shape": "box", "size": Vector3(0.36, 0.48, 0.22), "mass": 27.0,
		"center": Vector3(0, 1.33, 0), "pivot": Vector3(0, 1.08, 0), "lim": [-0.7, 0.4, -0.7, 0.7, -0.4, 0.4],
		"freq": 14.0, "torque": 500.0},
	{"name": "head", "parent": "torso", "shape": "sphere", "size": Vector3(0.11, 0.11, 0.11), "mass": 5.0,
		"center": Vector3(0, 1.70, 0), "pivot": Vector3(0, 1.58, 0), "lim": [-0.7, 0.6, -1.1, 1.1, -0.5, 0.5],
		"freq": 12.0, "torque": 80.0},
	{"name": "upper_arm_l", "parent": "torso", "shape": "capsule", "size": Vector3(0.05, 0.30, 0.05), "mass": 2.2,
		"center": Vector3(-0.23, 1.39, 0), "pivot": Vector3(-0.23, 1.53, 0), "lim": [-1.0, 3.0, -1.4, 1.4, -2.6, 0.6],
		"freq": 10.0, "torque": 150.0},
	{"name": "upper_arm_r", "parent": "torso", "shape": "capsule", "size": Vector3(0.05, 0.30, 0.05), "mass": 2.2,
		"center": Vector3(0.23, 1.39, 0), "pivot": Vector3(0.23, 1.53, 0), "lim": [-1.0, 3.0, -1.4, 1.4, -0.6, 2.6],
		"freq": 10.0, "torque": 150.0},
	{"name": "forearm_l", "parent": "upper_arm_l", "shape": "capsule", "size": Vector3(0.045, 0.34, 0.045), "mass": 1.7,
		"center": Vector3(-0.23, 1.08, 0), "pivot": Vector3(-0.23, 1.25, 0), "lim": [0.0, 2.6, -1.2, 1.2, -0.15, 0.15],
		"freq": 10.0, "torque": 100.0},
	{"name": "forearm_r", "parent": "upper_arm_r", "shape": "capsule", "size": Vector3(0.045, 0.34, 0.045), "mass": 1.7,
		"center": Vector3(0.23, 1.08, 0), "pivot": Vector3(0.23, 1.25, 0), "lim": [0.0, 2.6, -1.2, 1.2, -0.15, 0.15],
		"freq": 10.0, "torque": 100.0},
	{"name": "thigh_l", "parent": "pelvis", "shape": "capsule", "size": Vector3(0.07, 0.44, 0.07), "mass": 8.5,
		"center": Vector3(-0.10, 0.68, 0), "pivot": Vector3(-0.10, 0.90, 0), "lim": [-0.7, 2.0, -0.6, 0.6, -0.9, 0.5],
		"freq": 14.0, "torque": 450.0},
	{"name": "thigh_r", "parent": "pelvis", "shape": "capsule", "size": Vector3(0.07, 0.44, 0.07), "mass": 8.5,
		"center": Vector3(0.10, 0.68, 0), "pivot": Vector3(0.10, 0.90, 0), "lim": [-0.7, 2.0, -0.6, 0.6, -0.5, 0.9],
		"freq": 14.0, "torque": 450.0},
	{"name": "shin_l", "parent": "thigh_l", "shape": "capsule", "size": Vector3(0.05, 0.42, 0.05), "mass": 4.5,
		"center": Vector3(-0.10, 0.27, 0), "pivot": Vector3(-0.10, 0.46, 0), "lim": [-2.5, 0.0, -0.2, 0.2, -0.1, 0.1],
		"freq": 14.0, "torque": 350.0},
	{"name": "shin_r", "parent": "thigh_r", "shape": "capsule", "size": Vector3(0.05, 0.42, 0.05), "mass": 4.5,
		"center": Vector3(0.10, 0.27, 0), "pivot": Vector3(0.10, 0.46, 0), "lim": [-2.5, 0.0, -0.2, 0.2, -0.1, 0.1],
		"freq": 14.0, "torque": 350.0},
]

## Foot box on each shin (part-local): size and offset from the shin centre.
const FOOT_SIZE: Vector3 = Vector3(0.10, 0.07, 0.25)
const FOOT_OFFSET: Vector3 = Vector3(0, -0.235, -0.06)
## Ankle point (part-local on the shin) and grip point (part-local on the forearm).
const ANKLE_LOCAL: Vector3 = Vector3(0, -0.20, 0)
const HAND_LOCAL: Vector3 = Vector3(0, -0.14, 0)
const THIGH_LEN: float = 0.44
const SHIN_LEN: float = 0.40
const UPPER_ARM_LEN: float = 0.28
const FOREARM_LEN: float = 0.31
## Rest height of the ankle above the ground.
const ANKLE_HEIGHT: float = 0.07


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Dictionary in PARTS:
		out.append(str(p["name"]))
	return out


static func part(name: String) -> Dictionary:
	for p: Dictionary in PARTS:
		if p["name"] == name:
			return p
	return {}


static func total_mass() -> float:
	var m: float = 0.0
	for p: Dictionary in PARTS:
		m += float(p["mass"])
	return m


## Names of `name` and every part hanging below it.
static func subtree(name: String) -> PackedStringArray:
	var out := PackedStringArray([name])
	var i: int = 0
	while i < out.size():
		for p: Dictionary in PARTS:
			if p["parent"] == out[i]:
				out.append(str(p["name"]))
		i += 1
	return out


## Scalar inertia (kg·m²) of the subtree under joint `name` about its pivot, in the rest pose, plus `extra_mass`
## at `extra_offset` from the pivot (a held weapon).
static func joint_inertia(name: String, extra_mass: float = 0.0, extra_offset: float = 0.0) -> float:
	var pivot: Vector3 = part(name).get("pivot", Vector3.ZERO)
	var i: float = extra_mass * extra_offset * extra_offset
	for n: String in subtree(name):
		var p: Dictionary = part(n)
		var m: float = float(p["mass"])
		var size: Vector3 = p["size"]
		var r: float = (p["center"] as Vector3).distance_to(pivot)
		var own: float = m * maxf(size.y * size.y, size.x * size.x) / 12.0
		if p["shape"] == "sphere":
			own = 0.4 * m * size.x * size.x
		i += m * r * r + own
	return maxf(i, 0.001)


## A part's own scalar inertia about its centre (largest principal axis, from its shape).
static func own_inertia(name: String) -> float:
	var p: Dictionary = part(name)
	var m: float = float(p.get("mass", 1.0))
	var size: Vector3 = p.get("size", Vector3.ONE * 0.1)
	if p.get("shape", "") == "sphere":
		return 0.4 * m * size.x * size.x
	if p.get("shape", "") == "box":
		return m * (maxf(size.x, size.z) ** 2 + size.y * size.y) / 12.0
	return m * (size.y * size.y / 12.0 + size.x * size.x / 4.0)


## Inertia that limits a joint's explicit PD gains: parent and child each turning about the joint pivot,
## combined like a reduced mass. `boost` maps part names to inertia overrides (boosted bodies).
static func pair_inertia(name: String, boost: Dictionary) -> float:
	var c: Dictionary = part(name)
	var pn: String = str(c.get("parent", ""))
	if pn == "":
		return 0.001
	var pivot: Vector3 = c["pivot"]
	var ic: float = float(boost.get(name, own_inertia(name))) + float(c["mass"]) * (c["center"] as Vector3).distance_squared_to(pivot)
	var p: Dictionary = part(pn)
	var ip: float = float(boost.get(pn, own_inertia(pn))) + float(p["mass"]) * (p["center"] as Vector3).distance_squared_to(pivot)
	return ic * ip / (ic + ip)


## Inertia about the bone axis (Y) for joint `name`: the child's own axial inertia combined with its parent's
## like a reduced mass. Boosted bodies use their boost value.
static func twist_inertia(name: String, boost: Dictionary) -> float:
	var c: Dictionary = part(name)
	var pn: String = str(c.get("parent", ""))
	if pn == "":
		return 0.001
	var ic: float = float(boost.get(name, axial_inertia(name)))
	var ip: float = float(boost.get(pn, axial_inertia(pn)))
	return ic * ip / (ic + ip)


## A part's own inertia about its long (Y) axis.
static func axial_inertia(name: String) -> float:
	var p: Dictionary = part(name)
	var m: float = float(p.get("mass", 1.0))
	var size: Vector3 = p.get("size", Vector3.ONE * 0.1)
	match str(p.get("shape", "")):
		"sphere":
			return 0.4 * m * size.x * size.x
		"box":
			return m * (size.x * size.x + size.z * size.z) / 12.0
	return 0.5 * m * size.x * size.x
