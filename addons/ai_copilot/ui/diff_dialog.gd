@tool
class_name AiCopilotDiffDialog
extends AcceptDialog

func _ready() -> void:
	title = "Diff preview"
	ok_button_text = "Close"
	size = Vector2i(900, 600)

func show_diff(path: String, old_text: String, new_text: String) -> void:
	var wrap := MarginContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		wrap.add_theme_constant_override(m, 10)
	add_child(wrap)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	wrap.add_child(box)
	box.add_child(_make_pane("Before  —  %s" % path, old_text, Color("e07070")))
	box.add_child(_make_pane("After", new_text, Color("7ec98a")))

func _make_pane(heading: String, text: String, accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color("101015")
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color("2a2a33")
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var lbl := Label.new()
	lbl.text = heading
	lbl.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	lbl.add_theme_color_override("font_color", accent)
	v.add_child(lbl)

	var ce := CodeEdit.new()
	ce.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce.editable = false
	ce.text = text
	ce.gutters_draw_line_numbers = true
	ce.add_theme_font_size_override("font_size", AiCopilotUI.fs_mono())
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	ce.add_theme_stylebox_override("normal", st)
	ce.add_theme_stylebox_override("focus", st)
	ce.syntax_highlighter = AiCopilotGDHighlighter.new()
	v.add_child(ce)
	return p
