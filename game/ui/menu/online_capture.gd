extends Node3D
## Dev tool: boots MenuFlow against the ServiceStub and saves a PNG of each online screen state.
## godot --path . --fixed-fps 30 --resolution 720x1280 res://game/ui/menu/online_capture.tscn -- --capture --out=/tmp/online --tag=portrait
## Clocks are set directly (a few frames per shot): software GL on a busy box draws a frame in seconds. The arena
## backdrop is dropped unless --backdrop is given (it costs most of the frame).
## --shots=search,found,confirm,requeue,failed,result,result_down,rematch,left,board,board_p2,loading,offline (default: all)

const SHOT_LIST: PackedStringArray = ["search", "found", "confirm", "requeue", "failed", "result", "result_down", "rematch",
	"left", "board", "board_p2", "loading", "offline"]
const NAMES: Array = ["Verus", "Cato", "Brutus", "Livia", "Marcus", "Titus", "Aurelia", "Gaius", "Nero", "Crispus", "Julia",
	"Felix", "Sabina", "Lucan", "Spiculus", "Priscus", "Flamma", "Carpophorus", "Tetraites", "Commodus"]

var _flow: MenuFlow
var _svc: ServiceStub
var _port: int = 17880


func _ready() -> void:
	Flags.args["online-service"] = "stub"
	_flow = MenuFlow.new()
	add_child(_flow)
	_flow.setup(self)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _snap(shot_name: String, wait: int = 3) -> void:
	if not Flags.args.has("backdrop"):
		_flow.call("_free_backdrop")
	await _frames(wait)
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s_%s.png" % [Flags.get_arg("out", "/tmp/online"), Flags.get_arg("tag", "shot"), shot_name]
	img.save_png(path)


func _seed_board() -> void:
	_flow.call("_ensure_service")
	_svc = _flow.get("_service") as ServiceStub
	_svc.login("Maximus")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 120:
		var games: int = 12 + rng.randi_range(0, 80)
		var nm: String = "%s %s" % [NAMES[i % NAMES.size()], ["", "II", "III", "Maior", "Minor", "Rufus"][i / NAMES.size()]]
		_svc.add_fake_player("fake%03d" % i, nm.strip_edges(), 1880 - i * 9, games, games / 2 + rng.randi_range(-4, 6),
			rng.randi_range(-4, 6))
	var me: Dictionary = _svc.board.entry(str(_svc.profile["id"]))
	me["rating"] = 1305
	me["games"] = 23
	me["wins"] = 14
	me["losses"] = 9
	me["streak"] = 3
	_svc.call("_sync_profile")


## The online result panel the way MenuFlow draws it after a rated Quick Match.
func _fake_result(before: int, after: int, winner_side: int) -> void:
	_flow._open_online(true)
	_fulfil()
	var scr: OnlineScreen = _flow._online
	scr.set("_rated_now", true)
	_flow._hide_screens()
	_flow.screen = MenuFlow.Screen.RESULT
	var m := Match.new()
	m.names = ["Maximus", "Verus"]
	m.over = true
	m.result = {"winner": winner_side}
	_flow.current_match = m
	scr.on_summary(OnlineService.result_summary("stub-match-x%d" % after, "agree", "", before, after, "both agree"))
	_view_at(9.0)


## A match on a fresh port each time (a closed ENet host frees its port only on the next idle frame).
func _fulfil() -> void:
	_port += 1
	_svc.port = _port
	_svc.fulfil()


## Puts the panel's rating view `t` seconds into its count.
func _view_at(t: float) -> void:
	var p: Node = _flow.get("_pause")
	if p == null:
		return
	for v: Node in p.find_children("*", "RatingChangeView", true, false):
		v.set("_t", t)
		v.set_process(false)
		v.call("_redraw")


func _run() -> void:
	var wanted: PackedStringArray = SHOT_LIST
	if Flags.args.has("shots"):
		wanted = Flags.get_arg("shots").split(",")
	DirAccess.make_dir_recursive_absolute(Flags.get_arg("out", "/tmp/online"))
	await _frames(10)
	_seed_board()
	for s: String in wanted:
		match s:
			"search":
				_flow._open_online(true)
				_flow._online.flow.search_s = 14.2  # past the 0:12 usual wait: the widening line
				_flow._online.refresh()
			"found":
				_flow._open_online(true)
				_fulfil()
			"confirm":
				_flow._open_online(true)
				_fulfil()
				_flow._online.flow.tick(QuickMatchFlow.FOUND_S + 0.1)
				_flow._online.flow.tick(3.2)  # the countdown at 7
				_flow._online.flow.on_remote_ready()
				_flow._online.refresh()
			"requeue":
				_flow._open_online(true)
				_fulfil()
				await _frames(4)
				_flow.call("_on_net_closed", "Verus disconnected")  # the connection died before the fight
			"failed":
				_flow._open_online(true)
				await _frames(4)
				_flow._online.call("_on_match_failed", "Nobody else is searching on this network")
			"result":
				await _fake_result(1290, 1312, 0)
				_view_at(0.5)
				await _snap(s)  # mid count
				_view_at(9.0)
				await _snap(s + "_end")
				continue
			"result_down":
				await _fake_result(1405, 1389, 1)
				_view_at(9.0)
			"rematch":
				await _fake_result(1290, 1312, 0)
				_flow._net.remote_joined = true  # as if the opponent were still connected
				_flow._online.rematch.on_note(RematchHandshake.NOTE_ASK)
				_flow._online.result_changed.emit()
			"left":
				await _fake_result(1290, 1312, 0)
				_flow._online.on_session_closed("Verus left")
			"board":
				_flow._open_leaderboard()
			"board_p2":
				_flow._open_leaderboard()
				_flow._leaderboard.show_page(40)
			"loading":
				_svc.hold_leaderboard = true
				_flow._open_leaderboard()
			"offline":
				_svc.hold_leaderboard = false
				_svc.release_leaderboard()
				_svc.fail_leaderboard_with = "offline"
				_flow._open_leaderboard()
		await _snap(s)
		_svc.fail_leaderboard_with = ""
	get_tree().paused = false
	get_tree().quit()
