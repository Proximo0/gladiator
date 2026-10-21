class_name TuningPanel
extends CanvasLayer
## Live tuning panel for Tuning.shared(). Toggled with the "debug_tuning" action (backquote); while that action
## does not exist, the backquote key toggles it directly. Rows are built from Tuning.FIELDS, grouped by the group
## column (collapsible), filtered by the text box (a filter opens every matching group), and kept in sync with
## Tuning.changed. Presets are JSON files of diff_from_defaults() under user://presets/. Saving never writes in a
## scripted run (Flags.is_scripted_run()).

const PRESET_DIR: String = "user://presets"
const PRESET_EXT: String = ".json"
const TOGGLE_ACTION: StringName = &"debug_tuning"
const TOGGLE_KEY: Key = KEY_QUOTELEFT
const PANEL_LAYER: int = 100
## Sizes are in real screen pixels; the layer is scaled to the window (1920x1080 design, stretched to 1280x720).
const PANEL_PX: float = 460.0
const FONT_PX: float = 15.0
const LABEL_PX: float = 150.0
const SLIDER_PX: float = 90.0
const SPIN_PX: float = 80.0
const MODIFIED_COLOR := Color(1.0, 0.78, 0.35)
const PANEL_COLOR := Color(0.06, 0.07, 0.10, 0.86)
const PANEL_MARGIN_PX: float = 10.0

var _tuning: Tuning = null
var _panel: PanelContainer = null
var _rows: Dictionary = {}  ## field -> {"row", "label", "slider", "spin"}
var _sections: Dictionary = {}  ## group -> {"box", "body", "header"}
var _collapsed: Dictionary = {}  ## group -> bool
var _filter_edit: LineEdit = null
var _name_edit: LineEdit = null
var _preset_menu: OptionButton = null
var _preset_names: PackedStringArray = PackedStringArray()
var _status: Label = null
var _list: VBoxContainer = null
var _syncing: bool = false


func _init() -> void:
	layer = PANEL_LAYER
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_tuning = Tuning.shared()
	_build()
	_apply_metrics()
	get_viewport().size_changed.connect(_apply_metrics)
	_tuning.changed.connect(_on_tuning_changed)
	_refresh_presets()
	_refresh_all()


func _exit_tree() -> void:
	if _tuning != null and _tuning.changed.is_connected(_on_tuning_changed):
		_tuning.changed.disconnect(_on_tuning_changed)


func _unhandled_input(event: InputEvent) -> void:
	if is_toggle_event(event):
		visible = not visible
		if visible:
			_refresh_presets()
			_refresh_all()
		get_viewport().set_input_as_handled()


# ---- pure logic (static, unit tested) -------------------------------------------------------------------------------

## True for the press that opens or closes the panel: the "debug_tuning" action, or the backquote key while that
## action does not exist.
static func is_toggle_event(event: InputEvent) -> bool:
	if InputMap.has_action(TOGGLE_ACTION):
		return event.is_action_pressed(TOGGLE_ACTION)
	var key: InputEventKey = event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode == TOGGLE_KEY


## Group names in the order their first field appears in Tuning.FIELDS.
static func group_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f: Array in Tuning.FIELDS:
		var group: String = f[5]
		if not out.has(group):
			out.append(group)
	return out


## True when the filter text (trimmed, case-insensitive) occurs in the field's name, group or doc. Empty matches all.
static func matches_filter(info: Dictionary, filter: String) -> bool:
	var q: String = filter.strip_edges().to_lower()
	if q.is_empty():
		return true
	for key: String in ["name", "group", "doc"]:
		if str(info.get(key, "")).to_lower().contains(q):
			return true
	return false


## The visible layout: [{"group": String, "fields": Array of field names}] in group order, each group's fields in
## FIELDS order, keeping only fields that match the filter. Groups with no matching field are left out.
static func group_fields(filter: String) -> Array:
	var out: Array = []
	for group: String in group_names():
		var fields: Array = []
		for f: Array in Tuning.FIELDS:
			var name: String = f[0]
			if f[5] == group and matches_filter(Tuning.field_info(name), filter):
				fields.append(name)
		if not fields.is_empty():
			out.append({"group": group, "fields": fields})
	return out


static func is_modified(field: String, value: float) -> bool:
	var info: Dictionary = Tuning.field_info(field)
	if info.is_empty():
		return false
	return not is_equal_approx(value, float(info["default"]))


## Design-space units for a size in real pixels, given the viewport's stretch scale (1.0 when not stretched).
static func to_design(px: float, stretch: float) -> float:
	return px / maxf(stretch, 0.01)


static func header_text(group: String, modified: int) -> String:
	return group if modified == 0 else "%s (%d changed)" % [group, modified]


## Turns a user-typed preset name into a safe file stem: runs of characters outside [A-Za-z0-9_-] become one "_",
## leading and trailing "_" are dropped, and an empty result becomes "preset".
static func safe_preset_name(name: String) -> String:
	var s: String = name.strip_edges()
	var out: String = ""
	var last_underscore: bool = false
	for i: int in s.length():
		var ch: String = s.substr(i, 1)
		var keep: bool = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-"
		if keep:
			out += ch
			last_underscore = false
		elif not last_underscore:
			out += "_"
			last_underscore = true
	out = out.trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "preset"


static func preset_path(name: String) -> String:
	return "%s/%s%s" % [PRESET_DIR, safe_preset_name(name), PRESET_EXT]


## Preset names (without extension) from a directory listing: only .json files, sorted.
static func preset_names(files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in files:
		if f.ends_with(PRESET_EXT):
			out.append(f.trim_suffix(PRESET_EXT))
	out.sort()
	return out


## Full value set for a preset diff: every field, the diff's value where given, the default elsewhere.
## Unknown keys in the diff are ignored.
static func preset_values(diff: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for f: Array in Tuning.FIELDS:
		var field: String = f[0]
		out[field] = float(diff[field]) if diff.has(field) else float(f[1])
	return out


## Writes a preset diff as JSON. Refused (ERR_UNAVAILABLE) in a scripted run.
static func write_preset(path: String, diff: Dictionary) -> Error:
	if Flags.is_scripted_run():
		return ERR_UNAVAILABLE
	var root: DirAccess = DirAccess.open("user://")
	if root == null:
		return DirAccess.get_open_error()
	var dir_err: Error = root.make_dir_recursive(PRESET_DIR.trim_prefix("user://"))
	if dir_err != OK:
		return dir_err
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(diff, "\t"))
	return OK


## Reads a preset file. {"ok": false, "values": {}} when missing or not a JSON object.
static func read_preset(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"ok": false, "values": {}}
	return {"ok": true, "values": parsed}


static func list_presets() -> PackedStringArray:
	var root: DirAccess = DirAccess.open("user://")
	if root == null or not root.dir_exists("presets"):
		return PackedStringArray()
	return preset_names(DirAccess.get_files_at(PRESET_DIR))


# ---- UI -------------------------------------------------------------------------------------------------------------

func _build() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	add_child(panel)
	_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter fields"
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	top.add_child(_filter_edit)
	var reset_all := Button.new()
	reset_all.text = "Reset all"
	reset_all.pressed.connect(_on_reset_all)
	top.add_child(reset_all)

	var presets := HBoxContainer.new()
	col.add_child(presets)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Preset name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets.add_child(_name_edit)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_on_save)
	presets.add_child(save)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load)
	presets.add_child(load_button)

	_preset_menu = OptionButton.new()
	_preset_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_menu.item_selected.connect(_on_preset_selected)
	col.add_child(_preset_menu)

	_status = Label.new()
	_status.clip_text = true
	_status.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	col.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for group: String in group_names():
		_build_section(group)


## Sizes the panel and its rows so they read the same in real pixels whatever the window size.
func _apply_metrics() -> void:
	var k: float = to_design(1.0, get_viewport().get_stretch_transform().x.x)
	_panel.offset_left = -PANEL_PX * k
	_panel.add_theme_stylebox_override("panel", _panel_style(PANEL_MARGIN_PX * k))
	_panel.add_theme_font_size_override("font_size", roundi(FONT_PX * k))
	for field: String in _rows:
		var r: Dictionary = _rows[field]
		var label: Label = r["label"]
		var slider: HSlider = r["slider"]
		var spin: SpinBox = r["spin"]
		label.custom_minimum_size.x = LABEL_PX * k
		slider.custom_minimum_size.x = SLIDER_PX * k
		spin.custom_minimum_size.x = SPIN_PX * k


func _panel_style(margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.set_content_margin_all(margin)
	return sb


func _build_section(group: String) -> void:
	var box := VBoxContainer.new()
	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.pressed.connect(_on_header_pressed.bind(group))
	box.add_child(header)
	var body := VBoxContainer.new()
	box.add_child(body)
	for f: Array in Tuning.FIELDS:
		var field: String = f[0]
		if f[5] == group:
			body.add_child(_build_row(field))
	_list.add_child(box)
	_sections[group] = {"box": box, "body": body, "header": header}


func _build_row(field: String) -> Control:
	var info: Dictionary = Tuning.field_info(field)
	var doc: String = info["doc"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = field
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = doc
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = info["min"]
	slider.max_value = info["max"]
	slider.step = info["step"]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = doc
	slider.value_changed.connect(_on_widget_changed.bind(field))
	row.add_child(slider)

	var spin := SpinBox.new()
	spin.min_value = info["min"]
	spin.max_value = info["max"]
	spin.step = info["step"]
	spin.tooltip_text = doc
	spin.value_changed.connect(_on_widget_changed.bind(field))
	row.add_child(spin)

	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Reset to default (%s)" % str(info["default"])
	reset.pressed.connect(_on_reset_field.bind(field))
	row.add_child(reset)

	_rows[field] = {"row": row, "label": label, "slider": slider, "spin": spin}
	return row


## Copies the tuning value into a row's widgets and marks the label when the value differs from the default.
func _refresh_row(field: String) -> void:
	if not _rows.has(field):
		return
	var r: Dictionary = _rows[field]
	var value: float = float(_tuning.get(field))
	var slider: HSlider = r["slider"]
	var spin: SpinBox = r["spin"]
	var label: Label = r["label"]
	var saved: bool = _syncing
	_syncing = true
	slider.value = value
	spin.value = value
	_syncing = saved
	if is_modified(field, value):
		label.add_theme_color_override("font_color", MODIFIED_COLOR)
	else:
		label.remove_theme_color_override("font_color")


func _refresh_all() -> void:
	if _rows.is_empty():
		return
	for field: String in _rows:
		_refresh_row(field)
	_layout()


## Shows the rows and groups the filter keeps, and updates group headers (collapse marker and changed count).
func _layout() -> void:
	var filter: String = _filter_edit.text
	var filtering: bool = not filter.strip_edges().is_empty()
	var shown_fields: Dictionary = {}
	var shown_groups: Dictionary = {}
	for entry: Dictionary in group_fields(filter):
		shown_groups[entry["group"]] = true
		for field: String in entry["fields"]:
			shown_fields[field] = true
	for field: String in _rows:
		var row: Control = _rows[field]["row"]
		row.visible = shown_fields.has(field)
	for group: String in _sections:
		var section: Dictionary = _sections[group]
		var box: Control = section["box"]
		var body: Control = section["body"]
		var header: Button = section["header"]
		var expanded: bool = filtering or not bool(_collapsed.get(group, false))
		box.visible = shown_groups.has(group)
		body.visible = expanded
		var marker: String = "-" if expanded else "+"
		header.text = "%s %s" % [marker, header_text(group, _modified_in(group))]


func _modified_in(group: String) -> int:
	var n: int = 0
	for f: Array in Tuning.FIELDS:
		var field: String = f[0]
		if f[5] == group and is_modified(field, float(_tuning.get(field))):
			n += 1
	return n


func _set_status(message: String) -> void:
	_status.text = message


func _refresh_presets() -> void:
	_preset_names = list_presets()
	_preset_menu.clear()
	_preset_menu.add_item("Saved presets")
	_preset_menu.set_item_disabled(0, true)
	for preset_name: String in _preset_names:
		_preset_menu.add_item(preset_name)
	_preset_menu.select(0)


## Sets every field to the given full value set. Each set emits Tuning.changed.
func _apply_values(values: Dictionary) -> void:
	for f: Array in Tuning.FIELDS:
		var field: String = f[0]
		_tuning.set_value(field, float(values[field]))
	_refresh_all()


func _on_tuning_changed(field: String, _value: float) -> void:
	_refresh_row(field)
	_layout()


func _on_widget_changed(value: float, field: String) -> void:
	if _syncing:
		return
	_tuning.set_value(field, value)


func _on_reset_field(field: String) -> void:
	_tuning.set_value(field, float(Tuning.field_info(field)["default"]))


func _on_reset_all() -> void:
	_apply_values(preset_values({}))
	_set_status("Reset all to defaults.")


func _on_filter_changed(_text: String) -> void:
	_layout()


func _on_header_pressed(group: String) -> void:
	_collapsed[group] = not bool(_collapsed.get(group, false))
	_layout()


func _on_save() -> void:
	var preset_name: String = _name_edit.text.strip_edges()
	if Flags.is_scripted_run():
		_set_status("Scripted run: presets are not written.")
		return
	if preset_name.is_empty():
		_set_status("Type a preset name first.")
		return
	var err: Error = write_preset(preset_path(preset_name), _tuning.diff_from_defaults())
	if err != OK:
		_set_status("Save failed: %s" % error_string(err))
		return
	_refresh_presets()
	_set_status("Saved %s." % safe_preset_name(preset_name))


func _on_load() -> void:
	var preset_name: String = _name_edit.text.strip_edges()
	if preset_name.is_empty():
		_set_status("Type or pick a preset name first.")
		return
	var result: Dictionary = read_preset(preset_path(preset_name))
	if not bool(result["ok"]):
		_set_status("No readable preset named %s." % safe_preset_name(preset_name))
		return
	_apply_values(preset_values(result["values"]))
	_set_status("Loaded %s." % safe_preset_name(preset_name))


func _on_preset_selected(index: int) -> void:
	if index <= 0 or index > _preset_names.size():
		return
	_name_edit.text = _preset_names[index - 1]
	_on_load()
