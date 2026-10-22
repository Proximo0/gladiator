class_name MatchResults
extends PanelContainer
## The results screen after a fight: the verdict (VICTORIA / MORS / AEQVO MARTE), how it ended, both fighters'
## numbers side by side (hits landed, blood lost, limbs severed, longest combo), the fight time, the rating change of
## a ranked fight and any unlock, then a row of buttons (keyboard, pad and touch: they take focus like every menu).
## Built from MatchReport.build(); emits chosen(id) with the entry ids MenuFlow already handles. The rows reveal one
## by one (`animate`); a rebuild for a late rating verdict passes animate=false so nothing jumps. A Quick Match adds
## its rating change (OnlineScreen's RatingChangeView) under the heading with `add_view`.

signal chosen(id: String)

const WIDTH: float = 1180.0
const WIDTH_PORTRAIT: float = 900.0
const HEAD_FONT: int = 100
const HEAD_FONT_COMPACT: int = 76  ## landscape with a rating view: the heading gives up room so the screen fits 1080
const RULE_H: float = 34.0
const RULE_H_COMPACT: float = 20.0
const NAME_FONT: int = 40
const VALUE_FONT: int = 44
const LABEL_FONT: int = 26
const REVEAL_DELAY_S: float = 0.25
const REVEAL_STEP_S: float = 0.12
const REVEAL_FADE_S: float = 0.18
const WIN_COLOR: Color = Color(0.95, 0.84, 0.55)
const LOSS_COLOR: Color = Color(0.86, 0.36, 0.28)
const OUTLINE: Color = Color(0.12, 0.05, 0.03, 0.95)

var portrait: bool = false
var _buttons: Array[Button] = []
var _reveal: Array[Control] = []
var _col: VBoxContainer = null
var _head: Label = null
var _rules: Array[Control] = []
var _head_end: int = 0  ## the column index just under the heading (verdict, who won, how it ended)


## Builds one centred on `root` (a MenuFlow layer) and focuses its first button.
static func open(root: Control, data: Dictionary, entries: Array, animate: bool) -> MatchResults:
	var r := MatchResults.new()
	r.build(data, entries, root.size.x / maxf(root.size.y, 1.0) < 1.2, animate)
	r.set_anchors_preset(Control.PRESET_CENTER)
	r.grow_horizontal = Control.GROW_DIRECTION_BOTH
	r.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(r)
	r.focus_first.call_deferred()
	return r


## `data` from MatchReport.build(); `entries` [[id, label], ...] for the buttons.
func build(data: Dictionary, entries: Array, p_portrait: bool, animate: bool = true) -> void:
	portrait = p_portrait
	theme = MenuTheme.theme()
	var sb: StyleBoxFlat = MenuTheme.box(MenuTheme.PANEL_BG, MenuTheme.BRONZE, 4, 34.0)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(WIDTH_PORTRAIT if portrait else WIDTH, 0.0)
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	_col = v
	var won_any: bool = (data.get("won", [false, false]) as Array).has(true)
	var local_won: bool = bool((data.get("won", [false, false]) as Array)[0])
	var head_col: Color = MenuTheme.PARCHMENT
	if won_any:
		head_col = WIN_COLOR if (local_won or str(data.get("latin", "")) == "VICTORIA") else LOSS_COLOR
	var h: Label = _centred(str(data.get("latin", "")), HEAD_FONT, head_col)
	h.add_theme_color_override("font_outline_color", OUTLINE)
	h.add_theme_constant_override("outline_size", 12)
	v.add_child(h)
	_head = h
	v.add_child(_centred(str(data.get("english", "")), MenuTheme.FONT_BODY, MenuTheme.OCHRE))
	if str(data.get("cause_latin", "")) != "":
		var c: Label = _centred("%s  -  %s" % [str(data.get("cause_latin", "")), str(data.get("cause_english", ""))],
				MenuTheme.FONT_SMALL, MenuTheme.PARCHMENT)
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(c)
	_head_end = v.get_child_count()
	v.add_child(_rule())
	var names: Array = data.get("names", ["", ""])
	var won: Array = data.get("won", [false, false])
	v.add_child(_row(_name_cell(str(names[0]), bool(won[0]), true), _gap(), _name_cell(str(names[1]), bool(won[1]), false)))
	for r: Array in data.get("rows", []):
		var line: HBoxContainer = _row(_value(str(r[1]), HORIZONTAL_ALIGNMENT_LEFT), _label_cell(str(r[0])),
				_value(str(r[2]), HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(line)
		_reveal.append(line)
	var t: HBoxContainer = _row(_gap(), _label_cell("Fight time  %s" % str(data.get("time", "0:00"))), _gap())
	v.add_child(t)
	_reveal.append(t)
	if bool(data.get("has_rating", false)):
		var delta: int = int(data.get("rating_delta", 0))
		var rt: String = str(data.get("rating_text", ""))
		if delta != 0:
			rt = "%s   %s" % [rt, MatchReport.signed(delta)]
		var rl: Label = _centred(rt, VALUE_FONT - 6, WIN_COLOR if delta > 0 else (LOSS_COLOR if delta < 0 else MenuTheme.PARCHMENT))
		rl.add_theme_color_override("font_outline_color", OUTLINE)
		rl.add_theme_constant_override("outline_size", 8)
		v.add_child(rl)
		_reveal.append(rl)
	if str(data.get("unlocked", "")) != "":
		var u: Label = _centred(str(data.get("unlocked", "")), MenuTheme.FONT_SMALL, MenuTheme.OCHRE)
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(u)
		_reveal.append(u)
	v.add_child(_rule())
	var box: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12 if portrait else 18)
	v.add_child(box)
	for entry: Array in entries:
		var btn: Button = MenuTheme.button(str(entry[1]), 0.0 if portrait else 300.0)
		if portrait:
			btn.custom_minimum_size = Vector2(0.0, 84.0)  # a thumb target on a phone
		else:
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = str(entry[0])
		btn.pressed.connect(func() -> void: chosen.emit(id))
		box.add_child(btn)
		_buttons.append(btn)
	if animate:
		_play_reveal()


## Puts `view` (a ranked fight's RatingChangeView) in the column just under the heading, above the numbers; a
## second view goes under the first. On a landscape screen the heading and rules tighten to make room for it.
func add_view(view: Control) -> void:
	if not portrait:
		_head.add_theme_font_size_override("font_size", HEAD_FONT_COMPACT)
		for r: Control in _rules:
			r.custom_minimum_size.y = RULE_H_COMPACT
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(view)
	_col.move_child(view, _head_end)
	_head_end += 1


func button_count() -> int:
	return _buttons.size()


func focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _play_reveal() -> void:
	modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, REVEAL_FADE_S)
	for i: int in _reveal.size():
		var c: Control = _reveal[i]
		c.modulate.a = 0.0
		var rt: Tween = create_tween()
		rt.tween_interval(REVEAL_DELAY_S + REVEAL_STEP_S * float(i))
		rt.tween_property(c, "modulate:a", 1.0, REVEAL_FADE_S)


func _centred(text: String, px: int, colour: Color) -> Label:
	var l: Label = MenuTheme.label(text, px, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _rule() -> Control:
	var r := Control.new()
	r.custom_minimum_size = Vector2(0.0, RULE_H)
	_rules.append(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.draw.connect(func() -> void: MenuTheme.draw_meander(r, r.size.x * 0.12, 6.0, r.size.x * 0.76, 13.0, 2.5))
	return r


func _row(a: Control, b: Control, c: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	for x: Control in [a, b, c]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x.size_flags_stretch_ratio = 1.0
		hb.add_child(x)
	b.size_flags_stretch_ratio = 1.3
	return hb


func _gap() -> Control:
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _name_cell(text: String, winner: bool, left: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	var n: Label = MenuTheme.label(text, NAME_FONT if not portrait else NAME_FONT - 8, WIN_COLOR if winner else MenuTheme.PARCHMENT)
	n.horizontal_alignment = align
	n.clip_text = true
	v.add_child(n)
	var tag: Label = MenuTheme.label("VICTOR" if winner else " ", 22, MenuTheme.OCHRE)
	tag.horizontal_alignment = align
	v.add_child(tag)
	return v


func _value(text: String, align: HorizontalAlignment) -> Label:
	var l: Label = MenuTheme.label(text, VALUE_FONT if not portrait else VALUE_FONT - 6, MenuTheme.PARCHMENT)
	l.horizontal_alignment = align
	return l


func _label_cell(text: String) -> Label:
	var l: Label = MenuTheme.label(text, LABEL_FONT, MenuTheme.DIM_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
