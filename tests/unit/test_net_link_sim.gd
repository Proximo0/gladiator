extends TestCase


func test_delays_by_latency() -> void:
	var l := NetLinkSim.new(5, 0, 0.0, 1)
	l.send(10, PackedByteArray([1]), false)
	assert_eq(l.receive(14).size(), 0)
	assert_eq(l.receive(15).size(), 1)


func test_loss_only_hits_unreliable() -> void:
	var l := NetLinkSim.new(0, 0, 0.5, 7)
	for i: int in range(200):
		l.send(0, PackedByteArray([1]), false)
		l.send(0, PackedByteArray([2]), true)
	var got: Array[PackedByteArray] = l.receive(0)
	var rel: int = 0
	for p: PackedByteArray in got:
		if p[0] == 2:
			rel += 1
	assert_eq(rel, 200)
	assert_true(l.dropped > 60 and l.dropped < 140, "dropped %d" % l.dropped)


func test_reliable_stays_in_order_under_jitter() -> void:
	var l := NetLinkSim.new(2, 10, 0.0, 3)
	for i: int in range(50):
		l.send(i, PackedByteArray([i]), true)
	var seen: Array = []
	for t: int in range(100):
		for p: PackedByteArray in l.receive(t):
			seen.append(int(p[0]))
	var sorted: Array = seen.duplicate()
	sorted.sort()
	assert_eq(seen, sorted)
	assert_eq(seen.size(), 50)


func test_same_seed_same_drops() -> void:
	var a := NetLinkSim.new(0, 4, 0.3, 11)
	var b := NetLinkSim.new(0, 4, 0.3, 11)
	for i: int in range(100):
		a.send(i, PackedByteArray([i]), false)
		b.send(i, PackedByteArray([i]), false)
	assert_eq(a.dropped, b.dropped)
	assert_eq(a.receive(200), b.receive(200))
