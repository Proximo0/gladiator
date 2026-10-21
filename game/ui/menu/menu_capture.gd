extends Node3D
## Dev tool: boots MenuFlow like the main scene and saves a PNG of each menu screen.
## godot --path . --resolution 1280x720 res://game/ui/menu/menu_capture.tscn -- --capture --out=/tmp/menu --tag=landscape
## --shots=title,loadout,loadout2p,options,controls,fight,pause,result (default: all)

const SHOT_LIST: PackedStringArray = ["title", "loadout", "loadout2p", "options", "controls", "fight", "pause", "result"]

var _flow: MenuFlow


func _ready() -> void:
	_flow = MenuFlow.new()
	add_child(_flow)
	_flow.setup(self)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


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
			"loadout":
				_flow._open_loadout("player_vs_cpu")
				_flow._loadout._panel_a.weapon_picker.select("longsword")
				_flow._loadout._panel_a.armor_pickers["head"].select("helm_iron")
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
		await _snap(s, 4 if s == "fight" else 40)
	get_tree().paused = false
	get_tree().quit()
