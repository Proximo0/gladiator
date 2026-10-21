extends "res://tests/sim/sim_base.gd"
## The Online menu end to end in one process: two MenuFlows (the client's under a SubViewport with its own world),
## the host hosts on a localhost port, the client joins by typing the address, the client changes its weapon in the
## lobby, the host presses FIGHT and both build their match with the right driver; then the client leaves mid-fight
## and the host is told the connection closed.

const PORT: int = 17941
const FIGHT_TICKS: int = 180

var _vp: SubViewport


func _wait_until(cond: Callable, cap: int) -> int:
	var n: int = 0
	while n < cap and not bool(cond.call()):
		await host.get_tree().physics_frame
		n += 1
	return n


func run() -> Array:
	var rows: Array = []
	await sandbox()
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

	fh.call("_on_title", "online")
	var hs: OnlineScreen = fh.get("_online")
	hs.get("_port_edit").text = str(PORT)
	hs.call("_on_host")
	fc.call("_on_title", "online")
	var cs: OnlineScreen = fc.get("_online")
	cs.get("_addr_edit").text = "127.0.0.1:%d" % PORT
	cs.call("_on_join")
	var hn: NetSession = fh.get("_net")
	var cn: NetSession = fc.get("_net")
	var n: int = await _wait_until(func() -> bool: return hn.remote_joined and cn.remote_joined, 300)
	rows.append(row("net_menu_join", hn.remote_joined and cn.remote_joined, "host and client in the lobby after %d ticks" % n))
	var lp: LoadoutPanel = cs.get("_panel")
	lp.weapon_picker.select("spear", true)
	await _wait_until(func() -> bool: return str(hn.remote_loadout.get("weapon", "")) == "spear", 120)
	var start_btn: Button = hs.get("_start")
	rows.append(row("net_menu_lobby_pick", str(hn.remote_loadout.get("weapon", "")) == "spear" and not start_btn.disabled,
		"host sees the client's %s, FIGHT enabled=%s" % [str(hn.remote_loadout.get("weapon", "")), str(not start_btn.disabled)]))
	start_btn.pressed.emit()
	n = await _wait_until(func() -> bool: return fh.current_match != null and fc.current_match != null, 300)
	await step(FIGHT_TICKS)
	var mh: Match = fh.current_match
	var mc: Match = fc.current_match
	var ok: bool = mh != null and mc != null and mh.get_node_or_null("NetHost") != null and mc.get_node_or_null("NetClient") != null
	var cd: NetClientDriver = mc.get_node_or_null("NetClient") as NetClientDriver if mc != null else null
	var weapon_ok: bool = mc != null and (mc.fighters[1] as Fighter).weapon != null and (mc.fighters[1] as Fighter).weapon.weapon_id == "spear"
	rows.append(row("net_menu_fight", ok and weapon_ok and cd != null and cd.snapshots_received > 60,
		"both matches built (%d ticks), client side 1 holds %s, %d snapshots shown" % [n,
		(mc.fighters[1] as Fighter).weapon.weapon_id if weapon_ok else "?", cd.snapshots_received if cd != null else -1]))
	# The Esc menu does not pause an online match, but this side's keys stop reaching its fighter.
	if cd != null:
		cd.input_source = func() -> FighterInput:
			var f := FighterInput.new()
			f.move_y = 1000
			return f
	var rd: InputReader = mh.readers[0] as InputReader
	var dev_before: String = rd.device if rd != null else "?"
	await step(3)
	var moving: int = cd.local_input.move_y if cd != null else -1
	fc.call("_pause_game")
	fh.call("_pause_game")
	await step(4)
	var paused_tree: bool = host.get_tree().paused
	var mv_blocked: int = cd.local_input.move_y
	var dev_blocked: String = rd.device
	var blocked_ok: bool = cn.input_blocked and hn.input_blocked and cd.local_input.move_y == 0 and rd.device == "none"
	fc.call("_resume")
	fh.call("_resume")
	await step(4)
	var back_ok: bool = not cn.input_blocked and not hn.input_blocked and cd.local_input.move_y == 1000 and rd.device == dev_before
	rows.append(row("net_menu_esc_neutral", moving == 1000 and blocked_ok and back_ok and not paused_tree,
		"input %d, in the menu: client move_y %d, host reader '%s' (was '%s'), tree paused=%s; after resume move_y %d, reader '%s'" % [
		moving, mv_blocked, dev_blocked, dev_before, str(paused_tree), cd.local_input.move_y, rd.device]))
	fc.call("_show_title")
	n = await _wait_until(func() -> bool: return fh.get("_net") == null, 300)
	rows.append(row("net_menu_leave", fh.get("_net") == null and int(fh.screen) == MenuFlow.Screen.RESULT and fh.current_match != null,
		"host told the client left after %d ticks (screen %d)" % [n, int(fh.screen)]))
	fh.call("_show_title")
	await step(2)
	Engine.time_scale = 1.0
	host.get_tree().paused = false
	await clear()
	return rows
