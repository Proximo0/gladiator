class_name MenuSounds
extends Node
## Menu sounds and hover focus for every menu screen at once, from one place: a focus tick when the player moves the
## focus (keys, pad or mouse), a select "shing" on accept or click, a knock on back, a clunk on a locked pick.
## The mouse moving onto a button or picker focuses it, so the highlight under the mouse and the pad/keyboard focus
## are always the same control. Programmatic focus (a screen opening) stays silent. MenuFlow switches it off in a
## fight (`active`) and says when Back means something (`back_ok`).

var active: bool = true
var back_ok: bool = false
var _input_frame: int = -10


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _input(event: InputEvent) -> void:
	if not active:
		return
	var frame: int = Engine.get_process_frames()
	if event is InputEventMouseMotion:
		_input_frame = frame  # MenuNav focuses what the mouse is over: that focus change gets its tick
		return
	if not event.is_pressed():
		return
	_input_frame = frame
	var vp: Viewport = get_viewport()
	if event is InputEventMouseButton:
		if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			return
		var hov: Control = vp.gui_get_hovered_control()
		_sound_for_press(hov)
		return
	var owner: Control = vp.gui_get_focus_owner()
	if event.is_action_pressed("ui_accept"):
		_sound_for_press(owner)
	elif event.is_action_pressed("ui_cancel"):
		if back_ok:
			UiSfx.play_ui(self, "back")
	elif owner is MenuPicker and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		UiSfx.play_ui(self, "focus")


func _sound_for_press(c: Control) -> void:
	if c is MenuPicker:
		UiSfx.play_ui(self, "focus" if (c as MenuPicker).enabled else "locked")
	elif c is BaseButton:
		UiSfx.play_ui(self, "locked" if (c as BaseButton).disabled else "select")


func _on_focus_changed(_c: Control) -> void:
	if active and Engine.get_process_frames() - _input_frame <= 1:
		UiSfx.play_ui(self, "focus")

