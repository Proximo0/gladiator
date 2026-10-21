class_name MenuStatBar
extends Control
## A labelled 0..1 bar: "CUT [=====   ]".

var label_text: String = ""
var fraction: float = 0.0:
	set(v):
		fraction = clampf(v, 0.0, 1.0)
		queue_redraw()
var tint: Color = MenuTheme.OCHRE


func _init(p_label: String = "", p_tint: Color = MenuTheme.OCHRE) -> void:
	label_text = p_label
	tint = p_tint
	custom_minimum_size = Vector2(0.0, 30.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var lw: float = 120.0
	draw_string(MenuTheme.caps_font(), Vector2(0.0, size.y * 0.5 + 8.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, lw, 24, MenuTheme.PARCHMENT)
	var r := Rect2(lw, size.y * 0.5 - 8.0, maxf(size.x - lw, 10.0), 16.0)
	draw_rect(r, Color(0.25, 0.18, 0.1, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x * fraction, r.size.y)), tint)
	draw_rect(r, MenuTheme.BRONZE.darkened(0.2), false, 2.0)
