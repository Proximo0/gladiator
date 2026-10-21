extends SceneTree
## Child process of sim_match_smoke: plays one headless bot match from a fresh process and prints
## "MATCHSIG <winner>|<reason>|<ticks>|<stats>|<state hash>". Run: godot --headless --fixed-fps 60 -s this -- --seed=N
## (Engine state carries over between matches inside one process, so a repeat check needs a fresh process.)

const CAP_S: float = 60.0


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var seed_value: int = 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
	var m: Node3D = (load("res://game/match/match.gd") as GDScript).new()
	root.add_child(m)
	m.setup({"mode": "bot_vs_bot", "seed": seed_value, "presentation": false, "time_limit_s": CAP_S})
	var guard: int = int(CAP_S * 60.0) + 600
	var n: int = 0
	while not bool(m.get("over")) and n < guard:
		await physics_frame
		n += 1
	var st: Dictionary = ((m.get("result") as Dictionary).get("stats", {}) as Dictionary).duplicate()
	st.erase("wall_time_s")
	print("MATCHSIG %s|%s|%s|%s|%d" % [(m.get("result") as Dictionary).get("winner"), (m.get("result") as Dictionary).get("reason"),
		(m.get("result") as Dictionary).get("ticks"),
		JSON.stringify(st), m.call("state_hash")])
	quit(0)
