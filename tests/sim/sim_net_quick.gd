extends "res://tests/sim/sim_base.gd"
## Quick Match end to end. Part 1: two separate engine processes (sim_net_quick_peer.gd) sign in to ServiceLocal,
## find each other by UDP over loopback, take the roles the service gives them (smaller device id hosts), play a
## real match over ENet and report it; both must agree on the winner and the ratings must move by the Elo rule.
## Part 2: the Quick Match menu against ServiceStub in this process: search, found, host listens, Cancel, and the
## result line from the agreed reports. Takes ~35 s of real time (the children run in real time).

const GPORT: int = 17961
const DPORT: int = 17790
const WAIT_MS: int = 90000


func _spawn(id: String, player_name: String, weapon: String) -> Dictionary:
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s",
		"res://tests/sim/sim_net_quick_peer.gd", "--", "--id=%s" % id, "--name=%s" % player_name, "--gport=%d" % GPORT,
		"--dport=%d" % DPORT, "--weapon=%s" % weapon]
	return OS.execute_with_pipe(OS.get_executable_path(), args)


func _line(out: String) -> Dictionary:
	for l: String in out.split("\n"):
		if l.begins_with("QPEER "):
			var d: Dictionary = {}
			for tok: String in l.substr(6).split(" "):
				var kv: PackedStringArray = tok.split("=", true, 1)
				d[kv[0]] = kv[1] if kv.size() > 1 else ""
			if l.contains(" FAIL "):
				d["fail"] = l
			return d
	return {}


func run() -> Array:
	var rows: Array = []
	var a: Dictionary = _spawn("aaaa000000000001", "Ann", "gladius")
	var b: Dictionary = _spawn("bbbb000000000002", "Bo", "spear")
	if a.is_empty() or b.is_empty():
		return [row("net_quick_spawn", false, "could not start the peer processes")]
	var t0: int = Time.get_ticks_msec()
	while (OS.is_process_running(int(a["pid"])) or OS.is_process_running(int(b["pid"]))) and Time.get_ticks_msec() - t0 < WAIT_MS:
		OS.delay_msec(100)
		await host.get_tree().physics_frame
	for p: Dictionary in [a, b]:
		if OS.is_process_running(int(p["pid"])):
			OS.kill(int(p["pid"]))
	var la: Dictionary = _line((a["stdio"] as FileAccess).get_as_text())
	var lb: Dictionary = _line((b["stdio"] as FileAccess).get_as_text())
	var found: bool = not la.is_empty() and not lb.is_empty() and not la.has("fail") and not lb.has("fail")
	rows.append(row("net_quick_found", found and la.get("role") != lb.get("role") and la.get("role") == "host" and lb.get("role") == "client"
		and la.get("opp") == "bbbb000000000002" and lb.get("oppname") == "Ann" and la.get("mid") == lb.get("mid"),
		"A %s, B %s; one match id %s" % [str(la.get("role", la.get("fail", "?"))), str(lb.get("role", lb.get("fail", "?"))), str(la.get("mid", "?"))]))
	if found:
		var w: String = str(la["winner"])
		rows.append(row("net_quick_same_result", w == str(lb["winner"]) and str(la["status"]) == "single" and str(lb["status"]) == "single",
			"both say winner '%s' (A %s, B %s)" % [w, la["status"], lb["status"]]))
		var da: int = int(la["after"]) - int(la["before"])
		var db: int = int(lb["after"]) - int(lb["before"])
		var expect_a: int = 0 if w == "" else (20 if w == "aaaa000000000001" else -20)
		rows.append(row("net_quick_ratings", da == expect_a and db == -expect_a and int(la["games"]) == 1 and int(lb["games"]) == 1,
			"A %d -> %d, B %d -> %d after one rated game (draw=%s)" % [int(la["before"]), int(la["after"]), int(lb["before"]), int(lb["after"]), str(w == "")]))
	rows.append_array(await _menu_rows())
	return rows


func _menu_rows() -> Array:
	var rows: Array = []
	await sandbox()
	var root := Node3D.new()
	world.add_child(root)
	var flow := MenuFlow.new()
	root.add_child(flow)
	flow.setup(root)
	await step(2)
	# Stub backend: fake it through the flag the menu reads.
	Flags.args["online-service"] = "stub"
	flow.call("_on_title", "quick")
	var svc: ServiceStub = flow.get("_service") as ServiceStub
	var scr: OnlineScreen = flow.get("_online")
	rows.append(row("net_quick_menu_search", svc != null and svc.is_searching() and svc.calls.has("quick_match"),
		"opening Quick Match logs in and starts the search (%s)" % str(svc.calls if svc != null else [])))
	svc.fulfil()
	var net: NetSession = flow.get("_net")
	rows.append(row("net_quick_menu_found", net.role == NetSession.ROLE_HOST and net.is_open() and str(scr.get("_card").text).contains("Verus"),
		"host listens at once, the card shows the opponent: %s" % str(scr.get("_card").text).replace("\n", " / ")))
	flow.call("_show_title")
	await step(2)  # the closed ENet host frees its port on the next idle frame
	rows.append(row("net_quick_menu_cancel", svc.calls.has("cancel") and int(flow.screen) == int(MenuFlow.Screen.TITLE) and flow.get("_net") == null,
		"leaving the search cancels it and drops the session"))
	# A rated fight: two agreeing reports give the rating line; leaving mid-fight is a loss.
	flow.call("_on_title", "quick")
	svc.fulfil()
	scr.match_started()
	scr.report_finished(0, 3000, "ko")
	svc.opponent_report(str(scr.get("_info")["match_id"]), Rating.make_report("", "", Rating.KIND_RESULT, str(svc.profile["id"]), "ko", 3000))
	rows.append(row("net_quick_menu_result", str(flow.get("_rating_line")).begins_with("Rating 1000 -> 1022"), "result line: %s" % str(flow.get("_rating_line"))))
	svc.fulfil()
	flow.call("_show_title")
	await step(2)
	flow.call("_on_title", "quick")
	svc.fulfil()
	scr.match_started()
	flow.call("_show_title")
	var left: Dictionary = svc.summaries[svc.summaries.size() - 1]
	rows.append(row("net_quick_menu_leave_loses", str(left["status"]) == "forfeit" and int(left["delta"]) < 0,
		"leaving mid-fight: %s, %+d" % [str(left["status"]), int(left["delta"])]))
	Flags.args.erase("online-service")
	await clear()
	return rows
