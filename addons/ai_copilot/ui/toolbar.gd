@tool
class_name AiCopilotToolbar
extends Control

signal settings_clicked()
signal clear_clicked()
signal stop_clicked()
signal mode_toggled(approve_mode: bool)
signal regenerate_requested()

var _model_label: Label
var _btn_stop: Button
var _mode_toggle: CheckButton
var _menu: MenuButton

const MENU_REGEN := 0
const MENU_NEW := 1
const MENU_SETTINGS := 2

func _ready() -> void:
	custom_minimum_size = Vector2(0, AiCopilotUI.scale(30))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", AiCopilotUI.scale(4))
	add_child(h)

	_model_label = Label.new()
	_model_label.text = "(set model)"
	_model_label.add_theme_color_override("font_color", Color("707078"))
	_model_label.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	_model_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_label.clip_text = true
	_model_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(_model_label)

	_btn_stop = Button.new()
	_btn_stop.text = "Stop"
	_btn_stop.flat = true
	_btn_stop.visible = false
	_btn_stop.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
	_btn_stop.add_theme_color_override("font_color", Color("e05252"))
	_btn_stop.focus_mode = Control.FOCUS_NONE
	_btn_stop.connect("pressed", func(): stop_clicked.emit())
	h.add_child(_btn_stop)

	_mode_toggle = CheckButton.new()
	_mode_toggle.text = "Approve"
	_mode_toggle.button_pressed = true
	_mode_toggle.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	_mode_toggle.focus_mode = Control.FOCUS_NONE
	_mode_toggle.connect("toggled", _on_mode_toggled)
	h.add_child(_mode_toggle)

	_menu = MenuButton.new()
	_menu.text = "⋮"
	_menu.flat = true
	_menu.focus_mode = Control.FOCUS_NONE
	_menu.add_theme_font_size_override("font_size", AiCopilotUI.fs_body())
	var pop := _menu.get_popup()
	pop.add_item("Regenerate last", MENU_REGEN)
	pop.add_item("New chat", MENU_NEW)
	pop.add_separator()
	pop.add_item("Settings", MENU_SETTINGS)
	pop.id_pressed.connect(_on_menu)
	h.add_child(_menu)

func _on_menu(id: int) -> void:
	match id:
		MENU_REGEN: regenerate_requested.emit()
		MENU_NEW: clear_clicked.emit()
		MENU_SETTINGS: settings_clicked.emit()

func set_model_label(text: String) -> void:
	if text == "":
		_model_label.text = "(set model)"
		_model_label.tooltip_text = ""
		return
	# show just the last path segment to save space; full name in tooltip
	var short := text.get_file() if text.contains("/") else text
	_model_label.text = short
	_model_label.tooltip_text = text

func set_stop_enabled(enabled: bool) -> void:
	_btn_stop.visible = enabled
	_btn_stop.disabled = not enabled

func set_approve_mode(value: bool) -> void:
	_mode_toggle.set_block_signals(true)
	_mode_toggle.button_pressed = value
	_mode_toggle.set_block_signals(false)

func _on_mode_toggled(on: bool) -> void:
	mode_toggled.emit(on)
