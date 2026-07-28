@tool
class_name AiCopilotSettingsDialog
extends AcceptDialog

signal changed()

var _inputs: Dictionary = {}

func _ready() -> void:
	title = "AI Copilot Settings"
	ok_button_text = "Save"
	confirmed.connect(_on_save)
	var body := _build_body()
	add_child(body)

func _build_body() -> Control:
	var v := VBoxContainer.new()
	v.name = "Body"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_child(_row("endpoint", "Endpoint URL", "LineEdit"))
	v.add_child(_row("model", "Default model", "LineEdit"))
	v.add_child(_row("vision_model", "Vision model (optional)", "LineEdit"))
	v.add_child(_row("model_context_window", "Model context window (tokens)", "SpinBox"))
	v.add_child(_row("api_key", "API key", "PasswordInput"))
	v.add_child(_row("temperature", "Temperature", "SpinBox"))
	v.add_child(_row("max_tokens", "Max tokens", "SpinBox"))
	v.add_child(_row("max_steps", "Max steps", "SpinBox"))
	v.add_child(_row("approve_default", "Approve mode by default", "CheckBox"))
	v.add_child(_row("allow_shell", "Allow shell tool", "CheckBox"))
	v.add_child(_row("compact_threshold", "Compact threshold (0..1)", "SpinBox"))
	v.add_child(_row("verbose_logging", "Verbose logging", "CheckBox"))
	return v

func _row(key: String, label_text: String, kind: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 200
	h.add_child(l)
	var w: Control = null
	match kind:
		"LineEdit":
			w = LineEdit.new()
			w.custom_minimum_size.x = 360
		"PasswordInput":
			w = LineEdit.new()
			(w as LineEdit).secret = true
			w.custom_minimum_size.x = 360
		"SpinBox":
			w = SpinBox.new()
			match key:
				"temperature":
					(w as SpinBox).min_value = 0.0
					(w as SpinBox).max_value = 2.0
					(w as SpinBox).step = 0.05
				"max_tokens":
					(w as SpinBox).min_value = 1
					(w as SpinBox).max_value = 200000
				"model_context_window":
					(w as SpinBox).min_value = 4096
					(w as SpinBox).max_value = 1000000
				"max_steps":
					(w as SpinBox).min_value = 1
					(w as SpinBox).max_value = 100
				"compact_threshold":
					(w as SpinBox).min_value = 0.1
					(w as SpinBox).max_value = 0.95
					(w as SpinBox).step = 0.05
		"CheckBox":
			w = CheckBox.new()
	w.name = "Input_" + key
	h.add_child(w)
	_inputs[key] = w
	return h

func load_from(settings: AiCopilotSettings) -> void:
	for key in AiCopilotSettings.KEYS:
		var value = settings.get_value(key)
		var w: Control = _inputs.get(key, null)
		if w == null:
			continue
		if w is LineEdit:
			(w as LineEdit).text = str(value)
		elif w is SpinBox:
			(w as SpinBox).value = float(value)
		elif w is CheckBox:
			(w as CheckBox).button_pressed = bool(value)

func _on_save() -> void:
	changed.emit()

func collect() -> Dictionary:
	var out := {}
	for key in _inputs:
		var w: Control = _inputs[key]
		if w is LineEdit:
			out[key] = (w as LineEdit).text
		elif w is SpinBox:
			out[key] = (w as SpinBox).value
		elif w is CheckBox:
			out[key] = (w as CheckBox).button_pressed
	return out
