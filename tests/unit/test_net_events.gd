extends TestCase


func _hit() -> Dictionary:
	return {"attacker": 0, "target": 1, "part": "head", "weapon_id": "gladius", "contact": "edge",
		"point": Vector3(1.234, 1.7, -0.5), "normal": Vector3(0, 0, 1), "rel_vel": Vector3(8.5, -1.25, 0.0),
		"cut": 12.5, "pierce": 0.0, "blunt": 3.25, "total": 15.75, "glanced": false, "hit_on_weapon": false,
		"finisher": "behead", "armor_ids": ["galea"], "sever": true, "armor_wear": {"galea": 0.4},
		"knockback": Vector3(1, 0, 0), "effective_mass": 1.2}


func test_round_trip_keeps_what_clients_read() -> void:
	var bytes: PackedByteArray = NetEvents.encode([[77, 1, "hit", _hit()], [78, 1, "gore", {"kind": "behead", "part": "head", "amount": 12.5, "point": Vector3(1, 2, 3), "normal": Vector3.UP}]])
	var back: Array = NetEvents.decode(bytes)
	assert_eq(back.size(), 2)
	assert_eq(int(back[0][0]), 77)
	assert_eq(int(back[0][1]), 1)
	assert_eq(str(back[0][2]), "hit")
	var ev: Dictionary = back[0][3]
	assert_eq(int(ev["attacker"]), 0)
	assert_eq(int(ev["target"]), 1)
	assert_eq(ev["part"], "head")
	assert_eq(ev["weapon_id"], "gladius")
	assert_eq(ev["finisher"], "behead")
	assert_eq(ev["armor_ids"], ["galea"])
	assert_true(bool(ev["sever"]))
	assert_false(ev.has("glanced"), "false flags are left out")
	assert_false(ev.has("pierce"), "zeros are left out")
	assert_false(ev.has("armor_wear"), "keys outside the table are dropped")
	assert_near(float(ev["cut"]), 12.5, 0.01)
	assert_true(((ev["point"] as Vector3) - Vector3(1.234, 1.7, -0.5)).length() < 0.001)
	assert_true(((ev["rel_vel"] as Vector3) - Vector3(8.5, -1.25, 0.0)).length() < 0.01)
	assert_eq(str(back[1][2]), "gore")
	assert_eq((back[1][3] as Dictionary)["kind"], "behead")


func test_hit_is_compact() -> void:
	var bytes: PackedByteArray = NetEvents.encode([[1, 1, "hit", _hit()]])
	assert_true(bytes.size() < 90, "%d bytes" % bytes.size())


func test_decode_rejects_garbage() -> void:
	assert_eq(NetEvents.decode(PackedByteArray([NetConfig.MSG_EVENTS, 3, 1])), [])
	assert_eq(NetEvents.decode(PackedByteArray([NetConfig.MSG_SNAP, 0])), [])


func test_caps_records_per_packet() -> void:
	var many: Array = []
	for i: int in range(40):
		many.append([i, 0, "gore", {"kind": "bleed"}])
	assert_eq(NetEvents.decode(NetEvents.encode(many)).size(), NetEvents.MAX_PER_PACKET)
