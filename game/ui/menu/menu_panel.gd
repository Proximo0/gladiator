class_name MenuPanel
extends PanelContainer
## A centred card with a Latin heading, English line, optional text and a column of buttons. Used for pause and the
## end of a match. Emits chosen(id); the first button takes focus when shown.

signal chosen(id: String)

var _buttons: Array[Button] = []


func build(latin: String, english: String, body: String, entries: Array) -> void:
	theme = MenuTheme.theme()
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620.0, 0.0)
	add_child(v)
	var h := MenuTheme.label(latin, 76, MenuTheme.PARCHMENT)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.03, 0.9))
	h.add_theme_constant_override("outline_size", 10)
	v.add_child(h)
	if english != "":
		var e := MenuTheme.label(english, MenuTheme.FONT_SMALL, MenuTheme.OCHRE)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(e)
	if body != "":
		var b := MenuTheme.label(body, MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 16.0)
	v.add_child(gap)
	for entry: Array in entries:
		var btn: Button = MenuTheme.button(str(entry[1]))
		btn.pressed.connect(func() -> void: chosen.emit(str(entry[0])))
		v.add_child(btn)
		_buttons.append(btn)
	# Up from the first button wraps to the last and down from the last to the first; left and right stay put.
	for i: int in _buttons.size():
		var b: Button = _buttons[i]
		b.focus_neighbor_top = b.get_path_to(_buttons[posmod(i - 1, _buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(_buttons[posmod(i + 1, _buttons.size())])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


func focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
