extends "res://tests/sim/sim_base.gd"
## The Quick Match screens end to end in one process, two MenuFlows (the client's under its own SubViewport world),
## each with its own ServiceStub that pairs them over a localhost ENet port: search (timer, usual wait), found ->
## loadout confirm (the client changes arms and readies; the host waits for its own ready) -> fight -> the result
## panel with the rating change -> the rematch handshake (rated, a derived match id) -> the client leaves mid-fight
## and the host is told in plain words -> back to the queue; then a confirm abandoned by the other side and a host
## whose client never connects both land back in the search with a plain line.

const PORT_BASE: int = 21000  ## + a per-process offset, so two suites on one machine do not share the port
const RATED_TICKS: int = 700  ## past Rating.MIN_RATED_TICKS so the forced result is rated

var _vp: SubViewport
var _port: int = PORT_BASE + (OS.get_process_id() % 4000) * 2


func _wait_until(cond: Callable, cap: int) -> int:
	var n: int = 0
	while n < cap and not bool(cond.call()):
		await host.get_tree().physics_frame
		n += 1
	return n


func _stub(f: MenuFlow, my_id: String, role: String, opp_id: String, opp_name: String) -> ServiceStub:
	f.call("_ensure_service")
	var s: ServiceStub = f.get("_service") as ServiceStub
	s.auto_match = false
	s.profile = {"id": my_id}
	s.role = role
	s.port = _port
	s.address = "127.0.0.1"
	s.opponent = {"id": opp_id, "name": opp_name, "rating": 1000, "games": 0}
	return s


func _panel_text(f: MenuFlow) -> String:
	var p: Node = f.get("_pause")
	if p == null:
		return ""
	var out: PackedStringArray = []
	for n: Node in p.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	for b: Node in p.find_children("*", "Button", true, false):
		out.append("[%s]" % (b as Button).text)
	return " | ".join(out)


## The host ends the fight now with `winner` and a rated length; both sides reach their result panel.
func _finish_fight(fh: MenuFlow, fc: MenuFlow, winner: int) -> int:
	var mh: Match = fh.current_match
	mh.tick = RATED_TICKS
	mh.call("_finish", {"winner": winner, "reason": "ko"}, [])
	return await _wait_until(func() -> bool:
		return int(fh.screen) == MenuFlow.Screen.RESULT and int(fc.screen) == MenuFlow.Screen.RESULT, 900)


func run() -> Array:
	var rows: Array = []
	await sandbox()
	Flags.args["online-service"] = "stub"
	var host_root := Node3D.new()
	world.add_child(host_root)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(64, 64)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.add_child(_vp)
	var client_root := Node3D.new()
	_vp.add_child(client_root)
	var fh := MenuFlow.new()
	host_root.add_child(fh)
	fh.setup(host_root)
	var fc := MenuFlow.new()
	client_root.add_child(fc)
	fc.setup(client_root)
	await step(2)
	var sh: ServiceStub = _stub(fh, "aaaa-host", OnlineService.ROLE_HOST, "bbbb-client", "Bo")
	var sc: ServiceStub = _stub(fc, "bbbb-client", OnlineService.ROLE_CLIENT, "aaaa-host", "Ann")
	var hs: OnlineScreen = fh.get("_online")
	var cs: OnlineScreen = fc.get("_online")
	hs.player_name = "Ann"  # the names the services announce are the names the sessions carry
	cs.player_name = "Bo"

	# Search: the timer runs and the usual wait comes from the backend.
	fh.call("_open_online", true)
	fc.call("_open_online", true)
	await step(130)
	var head: String = str(hs.get("_headline").text)
	var wait: String = str(hs.get("_wait_line").text)
	rows.append(row("quick_flow_search", sh.is_searching() and hs.flow.phase == QuickMatchFlow.Phase.SEARCHING
		and hs.flow.search_s > 1.5 and head == "Finding an opponent" and wait.contains("0:12"),
		"searching %.1f s: '%s' / '%s' / '%s'" % [hs.flow.search_s, head, wait, str(hs.get("_range_line").text)]))

	# Found -> confirm: both connected, the countdown runs, nobody starts before the host is ready.
	sh.fulfil()
	sc.fulfil()
	var n: int = await _wait_until(func() -> bool:
		return cs.flow.phase == QuickMatchFlow.Phase.CONFIRM and fh.get("_net") != null and (fh.get("_net") as NetSession).remote_joined, 600)
	var lp: LoadoutPanel = cs.get("_panel")
	lp.weapon_picker.select("spear", true)
	cs.press_ready()
	await step(40)
	var host_waits: bool = fh.current_match == null and hs.flow.remote_ready
	var remote_line: String = str(hs.get("_remote_line").text)
	rows.append(row("quick_flow_confirm", n < 600 and host_waits and remote_line == "Bo is ready" and str(hs.get("_headline").text) == "Ready your arms",
		"confirm after %d ticks; host sees '%s', not started while its own countdown runs (%d s left)" % [n, remote_line, hs.flow.confirm_left()]))
	hs.press_ready()
	n = await _wait_until(func() -> bool: return fh.current_match != null and fc.current_match != null, 300)
	await step(30)
	var mh: Match = fh.current_match
	var spear: bool = mh != null and (mh.fighters[1] as Fighter).weapon != null and (mh.fighters[1] as Fighter).weapon.weapon_id == "spear"
	rows.append(row("quick_flow_fight", mh != null and spear and hs.has_open_match() and cs.has_open_match(),
		"both in the fight %d ticks after the host's ready; the client's confirm pick (spear) reached the host: %s" % [n, str(spear)]))

	# Result: the rating change view counts up once the verdict arrives.
	n = await _finish_fight(fh, fc, 0)
	var mid: String = str(hs.get("_info")["match_id"])
	sh.timeout_match(mid)
	sc.timeout_match(str(cs.get("_info")["match_id"]))
	await step(5)
	var hp: Node = fh.get("_pause")
	var views: Array = hp.find_children("*", "RatingChangeView", true, false) if hp != null else []
	var ptext: String = _panel_text(fh)
	rows.append(row("quick_flow_result", n < 900 and views.size() == 1 and (views[0] as RatingChangeView).is_rated()
		and int((views[0] as RatingChangeView).summary.get("delta", 0)) > 0 and ptext.contains("[Rematch Bo]"),
		"result panels after %d ticks; host panel: %s" % [n, ptext]))

	# Rematch handshake: the host asks, the client sees the invite and accepts, the host starts a rated rematch.
	fh.call("_on_panel", "net_rematch")
	n = await _wait_until(func() -> bool: return cs.rematch.state == RematchHandshake.State.INVITED, 300)
	await step(2)
	var invite: String = _panel_text(fc)
	var asked: String = _panel_text(fh)
	var old_h: int = fh.current_match.get_instance_id()
	fc.call("_on_panel", "net_rematch")
	var m2: int = await _wait_until(func() -> bool:
		return fh.current_match != null and fh.current_match.get_instance_id() != old_h and fc.current_match != null \
			and not fc.current_match.over, 400)
	var rid_h: String = str(hs.get("_info")["match_id"])
	var rid_c: String = str(cs.get("_info")["match_id"])
	rows.append(row("quick_flow_rematch", invite.contains("Ann wants a rematch!") and invite.contains("[Accept rematch]")
		and asked.contains("Waiting for Bo") and m2 < 400 and rid_h == rid_c and rid_h.ends_with("-r1") and hs.has_open_match(),
		"invite after %d ticks ('%s'); rematch built after %d; ids %s / %s" % [n, invite.left(120), m2, rid_h, rid_c]))

	# The client walks out of the rematch: the host is told in plain words and offered the queue.
	await step(30)
	fc.call("_on_panel", "title")
	n = await _wait_until(func() -> bool: return fh.get("_net") == null, 400)
	await step(2)
	var left_text: String = _panel_text(fh)
	rows.append(row("quick_flow_left", left_text.contains("Bo left the arena") and left_text.contains("[Find another opponent]"),
		"host after %d ticks: %s" % [n, left_text]))

	# Back to the queue on both; a confirm the client abandons puts the host back in the search with a plain line.
	fh.call("_on_panel", "online")
	fc.call("_open_online", true)
	await step(5)
	sh.fulfil()
	sc.fulfil()
	await _wait_until(func() -> bool: return fh.get("_net") != null and (fh.get("_net") as NetSession).remote_joined, 600)
	await step(5)
	cs.call("_on_back")  # Leave on the confirm
	n = await _wait_until(func() -> bool: return hs.flow.phase == QuickMatchFlow.Phase.SEARCHING and str(hs.get("_banner").text) != "", 400)
	var banner: String = str(hs.get("_banner").text)
	rows.append(row("quick_flow_requeue", hs.flow.phase == QuickMatchFlow.Phase.SEARCHING and sh.is_searching()
		and banner == "Bo left the arena. Back in the queue.", "host back searching after %d ticks: '%s'" % [n, banner]))

	# A client that never connects: the host gives the match up and searches again.
	sh.fulfil()
	n = await _wait_until(func() -> bool:
		return hs.flow.phase == QuickMatchFlow.Phase.SEARCHING and str(hs.get("_banner").text).begins_with("Could not reach"), 1500)
	rows.append(row("quick_flow_join_timeout", hs.flow.phase == QuickMatchFlow.Phase.SEARCHING and sh.is_searching()
		and str(hs.get("_banner").text).begins_with("Could not reach Bo"), "after %d ticks: '%s'" % [n, str(hs.get("_banner").text)]))

	# Nobody found: a plain message and Search again.
	hs.call("_on_match_failed", "Nobody else is searching on this network")
	await step(2)
	rows.append(row("quick_flow_no_match", hs.flow.phase == QuickMatchFlow.Phase.IDLE and str(hs.get("_headline").text) == "No opponents found"
		and (hs.get("_start") as Button).visible, "'%s' / '%s'" % [str(hs.get("_headline").text), str(hs.get("_card").text)]))
	fh.call("_show_title")
	fc.call("_show_title")
	await step(3)
	Flags.args.erase("online-service")
	Engine.time_scale = 1.0
	host.get_tree().paused = false
	await clear()
	return rows
