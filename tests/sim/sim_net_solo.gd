extends SceneTree
## Runs one net sim on its own, outside the suite: godot --headless --fixed-fps 60 --path . -s
## res://tests/sim/sim_net_solo.gd [-- sim_net_loopback]. Prints the suite's SIM lines and a SIMS total.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var name: String = args[0] if not args.is_empty() else "sim_net_loopback"
	var holder := Node.new()
	root.add_child(holder)
	var scr: GDScript = load("res://tests/sim/%s.gd" % name) as GDScript
	var sim: Variant = scr.new()
	sim.host = holder
	var rows: Array = await sim.run()
	var failed: int = 0
	var passed: int = 0
	for r: Array in rows:
		var verdict: String = "INFO" if r[1] == null else ("PASS" if r[1] else "FAIL")
		if r[1] != null:
			if r[1]:
				passed += 1
			else:
				failed += 1
		print("SIM %s %s %s" % [r[0], verdict, r[2]])
	print("SIMS passed=%d failed=%d" % [passed, failed])
	quit(1 if failed > 0 else 0)
