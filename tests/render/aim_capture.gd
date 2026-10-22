extends Node
## Aim-aid renders in the real game: the armed view, then the weapon-lost prompt after a drop. Run in a real (xvfb) window:
## godot --path . --resolution 1280x720 res://tests/render/aim_capture.tscn -- --out=DIR --name=practice [--touch] [--mode=player_vs_cpu]
## Without --mode it opens practice through the menu flow. Never part of the check suite; writes only the PNGs it is told to.

var _out: String = "/tmp/aim_capture/"
var _name: String = "shot"
var _cpu: bool = false
var _menu_cpu: bool = false  ## start the CPU fight through the menu flow (default loadout), like a new player
var _main: Node = null
var _frame: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--name="):
			_name = a.substr(7)
		elif a == "--mode=player_vs_cpu":
			_cpu = true
		elif a == "--menu-cpu":
			_menu_cpu = true
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.render_loop_enabled = false  # software GL is slow: draw only the frames we save
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _match() -> Match:
	if _cpu and not _menu_cpu:
		return _main.get("_match") as Match
	var flow: Object = _main.get("_flow")
	return flow.get("current_match") as Match if flow != null else null


func _process(_d: float) -> void:
	_frame += 1
	if _frame % 100 == 0:
		print("AIMCAP frame ", _frame)
	if _frame == 20 and _menu_cpu:
		(_main.get("_flow") as Object).call("_begin_fight", "player_vs_cpu")
	elif _frame == 20 and not _cpu:
		(_main.get("_flow") as Object).call("_begin_practice")
	if _frame == 120 or _frame == 330:
		RenderingServer.render_loop_enabled = true
	if _frame == 124:
		_save("armed")
		RenderingServer.render_loop_enabled = false
	if _frame == 125 and _match() != null:
		var f0: Fighter = _match().fighters[0] as Fighter
		print("AIMCAP player weapon=", f0.weapon.weapon_id if f0.weapon != null else "none", " state=", f0.state_name())
	if _frame == 130 and _match() != null:
		(_match().fighters[0] as Fighter).drop_weapon()
	if _frame == 334:
		_save("lost")
		get_tree().quit()


func _save(tag: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s%s_%s.png" % [_out, _name, tag])
