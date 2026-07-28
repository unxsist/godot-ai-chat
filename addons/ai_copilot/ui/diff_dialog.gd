@tool
class_name AiCopilotDiffDialog
extends AcceptDialog

func _ready() -> void:
	title = "Diff preview"
	ok_button_text = "Close"
	size = Vector2i(900, 600)

func show_diff(path: String, old_text: String, new_text: String) -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(_make_pane("Old — %s" % path, old_text))
	box.add_child(_make_pane("New", new_text))

func _make_pane(title: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	p.add_child(v)
	var lbl := Label.new()
	lbl.text = title
	v.add_child(lbl)
	var ce := CodeEdit.new()
	ce.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ce.editable = false
	ce.text = text
	v.add_child(ce)
	return p
