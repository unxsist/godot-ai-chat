@tool
class_name AiCopilotComposer
extends Control

signal send(text: String)

var _edit: CodeEdit
var _btn_send: Button

func _ready() -> void:
	custom_minimum_size = Vector2(0, AiCopilotUI.scale(72))

	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color("1a1a1e")
	bg_style.content_margin_left = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_top = 6
	bg_style.content_margin_bottom = 6
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bg.add_child(h)

	_edit = CodeEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, AiCopilotUI.scale(48))
	_edit.add_theme_font_size_override("font_size", AiCopilotUI.fs_body())
	_edit.placeholder_text = "Ask the agent to make changes..."
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = Color("121215")
	edit_style.set_corner_radius_all(6)
	edit_style.content_margin_left = 10
	edit_style.content_margin_right = 10
	edit_style.content_margin_top = 6
	edit_style.content_margin_bottom = 6
	_edit.add_theme_stylebox_override("normal", edit_style)

	h.add_child(_edit)

	_btn_send = Button.new()
	_btn_send.text = "Send"
	_btn_send.custom_minimum_size = Vector2(AiCopilotUI.scale(80), 0)
	_btn_send.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_btn_send.add_theme_font_size_override("font_size", AiCopilotUI.fs_body())
	_btn_send.connect("pressed", _do_send)
	h.add_child(_btn_send)

	_edit.gui_input.connect(_on_edit_input)

func _on_edit_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.is_echo():
		if ev.keycode == KEY_ENTER and not ev.shift_pressed:
			_do_send()
			get_viewport().set_input_as_handled()

func _do_send() -> void:
	var t := _edit.text.strip_edges()
	if t == "":
		return
	_edit.text = ""
	send.emit(t)
	_edit.grab_focus()

func set_send_enabled(enabled: bool) -> void:
	_btn_send.disabled = not enabled
	_edit.editable = enabled
