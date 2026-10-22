extends Node3D
## Dev tool: boots MenuFlow like the main scene and saves a PNG of each menu screen.
## godot --path . --resolution 1280x720 res://game/ui/menu/menu_capture.tscn -- --capture --out=/tmp/menu --tag=landscape
## --shots=title,loadout,loadout_locked,loadout2p,options,controls,fight,pause,result (default: all)

const SHOT_LIST: PackedStringArray = ["title", "title_nav", "quick", "leaderboard", "shop", "loadout", "loadout_locked", "loadout2p", "options", "controls", "fight", "pause", "result", "offer", "practice", "practice_swing", "practice_grab", "practice_free"]

var _flow: MenuFlow


func _ready() -> void:
	_flow = MenuFlow.new()
	add_child(_flow)
	_flow.setup(self)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## A pad/keyboard action press and release, through the real input path.
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _snap(shot_name: String, wait: int = 40) -> void:
	await _frames(wait)
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s_%s.png" % [Flags.get_arg("out", "/tmp/menu"), Flags.get_arg("tag", "shot"), shot_name]
	img.save_png(path)


func _run() -> void:
	var wanted: PackedStringArray = SHOT_LIST
	if Flags.args.has("shots"):
		wanted = Flags.get_arg("shots").split(",")
	DirAccess.make_dir_recursive_absolute(Flags.get_arg("out", "/tmp/menu"))
	await _frames(20)
	for s: String in wanted:
		match s:
			"title":
				_flow._show_title()
			"title_nav":
				_flow._show_title()
				await _frames(4)
				for i: int in 3:
					_press("ui_down")
					await _frames(2)
			"quick":
				_flow._open_online(true)
			"leaderboard":
				_flow._open_leaderboard()
			"shop":
				_flow._open_shop(false)
			"loadout":
				_flow._open_loadout("player_vs_cpu")
				_flow._loadout._panel_a.weapon_picker.select("longsword")
				_flow._loadout._panel_a.armor_pickers["head"].select("helm_iron")
			"loadout_locked":
				_flow._open_loadout("player_vs_cpu")
				_flow._loadout._panel_a.weapon_picker.select("falchion")  # locked (unless --unlock-all): greyed, with its note
			"loadout2p":
				_flow._open_loadout("local_2p")
			"options":
				_flow._on_title("options")
			"controls":
				_flow._options.open(true)
			"fight":
				_flow._begin_fight("player_vs_cpu")
				await _frames(8)
			"pause":
				_flow._pause_game()
			"result":
				_flow._resume()
				_flow._show_result({"winner": 0}, _flow._fight_token)
			"offer":
				_flow._show_practice_offer()
			"practice":
				_flow._begin_practice()
				await _frames(90)
			"practice_swing":
				_flow._begin_practice()
				await _frames(20)
				_flow._practice.skip_step()
				_flow._practice.skip_step()
				await _frames(60)
				get_tree().paused = true  # freeze the tick so the sample tip speed stays on the bar
				_flow._practice_panel.update_live(4.6, 3.0, 0.34, 4.6)
				await _snap(s, 4)
				get_tree().paused = false
				continue
			"practice_grab":
				_flow._begin_practice()
				await _frames(20)
				for i: int in 6:
					_flow._practice.skip_step()
				await _frames(120)
			"practice_free":
				_flow._begin_practice()
				await _frames(20)
				_flow._practice.skip_all()
				await _frames(120)
		await _snap(s, 4 if s == "fight" else 40)
	get_tree().paused = false
	get_tree().quit()
