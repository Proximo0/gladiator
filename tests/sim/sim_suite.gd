extends Node
## Runs the regression sims listed in SIM_FILES (each tests/sim/sim_<name>.gd extends sim_base.gd and returns
## [[name, ok, detail], ...] from run()). Prints "SIM <name> PASS|FAIL <detail>" and "SIMS passed=N failed=M".
## Part of tools/run_sims.sh. Run alone: godot --headless --path . res://tests/sim/sim_suite.tscn [-- name ... | -name ...]

const SIM_FILES: Array = [
	"sim_example",
	"sim_fighter_core",
	"sim_close_combat",
	"sim_fighter_replay",
	"sim_match_smoke",
	"sim_practice",
	"sim_camera_degenerate",
	"sim_camera_finale",
	"sim_camera_follow",
	"sim_killcam",
	"sim_audio_bot",
	"sim_hit_feel",
	"sim_net_loopback",
	"sim_net_presented",
	"sim_net_menu",
	"sim_net_drop",
	"sim_net_quick",
	"sim_net_feel",
	"sim_net_cheat",
	"sim_killcam_net",
	"sim_net_quick_flow",
	"sim_touch",
	"sim_sandbox_isolation",
	"sim_match_show",  # last: the audio bot sim before it is sensitive to what ran earlier in the process
]


func _ready() -> void:
	# Args pick sims: "sim_a sim_b" runs only those; "-sim_a" skips one (CI shards: the last shard skips the others' sims).
	var only: PackedStringArray = PackedStringArray()
	var skip: PackedStringArray = PackedStringArray()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("-"):
			skip.append(a.substr(1))
		else:
			only.append(a)
	var passed: int = 0
	var failed: int = 0
	for n: String in only + skip:
		if not SIM_FILES.has(n):
			print("SIM sim_suite FAIL unknown sim name %s (not in SIM_FILES)" % n)
			failed += 1
	for f: String in SIM_FILES:
		if (not only.is_empty() and not only.has(f)) or skip.has(f):
			continue
		var scr: GDScript = load("res://tests/sim/%s.gd" % f) as GDScript
		var sim: Variant = scr.new()
		sim.host = self
		var rows: Array = await sim.run()
		for r: Array in rows:
			var verdict: String = "PASS" if r[1] else "FAIL"
			if r[1] == null:
				verdict = "INFO"
			elif r[1]:
				passed += 1
			else:
				failed += 1
			print("SIM %s %s %s" % [r[0], verdict, r[2]])
	print("SIMS passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
