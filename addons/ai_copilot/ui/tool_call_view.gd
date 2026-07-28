@tool
class_name AiCopilotToolView
extends Control

signal accept(call: AiCopilotLLMTypes.ToolCall)
signal reject(call: AiCopilotLLMTypes.ToolCall)

var _call: AiCopilotLLMTypes.ToolCall
var _name_label: Label
var _args_label: Label
var _result_label: Label
var _show_diff_btn: Button
var _accept_btn: Button
var _reject_btn: Button

func _ready() -> void:
	custom_minimum_size = Vector2(0, 80)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var header := HBoxContainer.new()
	v.add_child(header)
	_name_label = Label.new()
	header.add_child(_name_label)
	_name_label.add_theme_font_size_override("font_size", 12)
	_show_diff_btn = Button.new()
	_show_diff_btn.text = "Preview"
	_show_diff_btn.visible = false
	_show_diff_btn.connect("pressed", _on_preview)
	header.add_child(_show_diff_btn)
	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.connect("pressed", _on_accept)
	header.add_child(_accept_btn)
	_reject_btn = Button.new()
	_reject_btn.text = "Reject"
	_reject_btn.connect("pressed", _on_reject)
	header.add_child(_reject_btn)
	_args_label = Label.new()
	_args_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_args_label.text = ""
	_args_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_args_label)
	_result_label = Label.new()
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_result_label)

func set_call(call: AiCopilotLLMTypes.ToolCall, approve_mode: bool) -> void:
	_call = call
	if _name_label: _name_label.text = "Tool: %s" % call.name
	if _args_label: _args_label.text = "Args: " + call.arguments_raw
	if _accept_btn:
		_accept_btn.visible = approve_mode
		_reject_btn.visible = approve_mode
	if _show_diff_btn: _show_diff_btn.visible = _call.name in ["write_file", "edit_file"]

func set_result(result: AiCopilotLLMTypes.ToolResult) -> void:
	if _result_label: _result_label.text = result.content

func _on_preview() -> void:
	var args := _call.arguments()
	if args.is_empty(): return
	var path := args.get("path", "")
	var old_text := ""
	if FileAccess.file_exists(path):
		old_text = FileAccess.get_file_as_string(path)
	var new_text := ""
	match _call.name:
		"write_file":
			new_text = String(args.get("content", ""))
		"edit_file":
			new_text = old_text.replace(String(args.get("old_string", "")), String(args.get("new_string", "")))
	var dlg := preload("res://addons/ai_copilot/ui/diff_dialog.tscn").instantiate()
	add_child(dlg)
	dlg.show_diff(path, old_text, new_text)
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.popup_centered(Vector2i(900, 600))

func _on_accept() -> void:
	accept.emit(_call)
	_accept_btn.disabled = true
	_reject_btn.disabled = true

func _on_reject() -> void:
	reject.emit(_call)
	_accept_btn.disabled = true
	_reject_btn.disabled = true
