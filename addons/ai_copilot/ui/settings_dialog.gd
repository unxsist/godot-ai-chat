@tool
class_name AiCopilotSettingsDialog
extends AcceptDialog

signal changed()

var _inputs: Dictionary = {}
var _provider_btn: OptionButton
var _base_url_row: HBoxContainer
var _base_url_edit: LineEdit
var _api_key_row: HBoxContainer
var _api_key_edit: LineEdit
var _keys_hint: RichTextLabel
var _model_edit: LineEdit
var _model_menu: MenuButton
var _fetch_btn: Button
var _fetch_status: Label
var _client: AiCopilotLLMClient = null
var _settings_ref: AiCopilotSettings = null

func _ready() -> void:
	title = "AI Copilot Settings"
	ok_button_text = "Save"
	confirmed.connect(_on_save)
	var body := _build_body()
	add_child(body)

func set_client(c: AiCopilotLLMClient) -> void:
	_client = c

func _build_body() -> Control:
	var v := VBoxContainer.new()
	v.name = "Body"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)

	# --- Provider picker -------------------------------------------------
	var prov_row := HBoxContainer.new()
	var prov_label := Label.new()
	prov_label.text = "Provider"
	prov_label.custom_minimum_size.x = 200
	prov_row.add_child(prov_label)
	_provider_btn = OptionButton.new()
	_provider_btn.custom_minimum_size.x = 360
	_populate_providers()
	_provider_btn.item_selected.connect(_on_provider_selected)
	prov_row.add_child(_provider_btn)
	v.add_child(prov_row)

	# API-key acquisition hint
	_keys_hint = RichTextLabel.new()
	_keys_hint.bbcode_enabled = true
	_keys_hint.fit_content = true
	_keys_hint.meta_underlined = true
	_keys_hint.custom_minimum_size = Vector2(560, 0)
	_keys_hint.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	v.add_child(_keys_hint)

	# --- Base URL (editable only for custom/local) -----------------------
	_base_url_row = _row("base_url", "Base URL", "LineEdit")
	_base_url_edit = _inputs["base_url"]
	v.add_child(_base_url_row)

	# --- API key ---------------------------------------------------------
	_api_key_row = _row("api_key", "API key", "PasswordInput")
	_api_key_edit = _inputs["api_key"]
	v.add_child(_api_key_row)

	# --- Model row: field + fetch + dropdown -----------------------------
	var model_row := HBoxContainer.new()
	var model_label := Label.new()
	model_label.text = "Model"
	model_label.custom_minimum_size.x = 200
	model_row.add_child(model_label)
	_model_edit = LineEdit.new()
	_model_edit.custom_minimum_size.x = 250
	_model_edit.placeholder_text = "model id (e.g. gpt-4o)"
	_inputs["model"] = _model_edit
	model_row.add_child(_model_edit)
	_model_menu = MenuButton.new()
	_model_menu.text = "▾"
	_model_menu.tooltip_text = "Pick from recommended / fetched models"
	_model_menu.get_popup().id_pressed.connect(_on_model_picked)
	model_row.add_child(_model_menu)
	_fetch_btn = Button.new()
	_fetch_btn.text = "Fetch models"
	_fetch_btn.pressed.connect(_on_fetch_models)
	model_row.add_child(_fetch_btn)
	v.add_child(model_row)
	_fetch_status = Label.new()
	_fetch_status.add_theme_font_size_override("font_size", 11)
	_fetch_status.add_theme_color_override("font_color", Color("8a8a95"))
	v.add_child(_fetch_status)

	v.add_child(HSeparator.new())

	# --- Remaining settings ---------------------------------------------
	v.add_child(_row("vision_model", "Vision model (optional)", "LineEdit"))
	v.add_child(_row("model_context_window", "Model context window (tokens)", "SpinBox"))
	v.add_child(_row("temperature", "Temperature", "SpinBox"))
	v.add_child(_row("max_tokens", "Max tokens", "SpinBox"))
	v.add_child(_row("max_steps", "Max steps", "SpinBox"))
	v.add_child(_row("approve_default", "Approve mode by default", "CheckBox"))
	v.add_child(_row("allow_shell", "Allow shell tool", "CheckBox"))
	v.add_child(_row("compact_threshold", "Compact threshold (0..1)", "SpinBox"))
	v.add_child(_row("verbose_logging", "Verbose logging", "CheckBox"))
	return v

func _populate_providers() -> void:
	_provider_btn.clear()
	var idx := 0
	# recommended first, then the rest
	var ordered: Array = []
	for p in AiCopilotProviders.all():
		if bool(p.get("recommended", false)):
			ordered.append(p)
	for p in AiCopilotProviders.all():
		if not bool(p.get("recommended", false)):
			ordered.append(p)
	for p in ordered:
		_provider_btn.add_item(String(p["name"]))
		_provider_btn.set_item_metadata(idx, String(p["id"]))
		idx += 1

func _selected_provider_id() -> String:
	var i := _provider_btn.selected
	if i < 0:
		return AiCopilotProviders.DEFAULT_PROVIDER_ID
	return String(_provider_btn.get_item_metadata(i))

func _select_provider_in_ui(pid: String) -> void:
	for i in _provider_btn.item_count:
		if String(_provider_btn.get_item_metadata(i)) == pid:
			_provider_btn.select(i)
			return

func _on_provider_selected(_i: int) -> void:
	_apply_provider_ui(_selected_provider_id())

# Show/hide base-url + api-key rows and update hints for the given provider.
func _apply_provider_ui(pid: String) -> void:
	var p := AiCopilotProviders.get_provider(pid)
	if p.is_empty():
		return
	var editable := bool(p.get("editable_url", false)) or pid == "custom"
	_base_url_row.visible = editable
	if editable and _base_url_edit.text.strip_edges() == "":
		_base_url_edit.text = String(p.get("base_url", ""))
	_api_key_row.visible = bool(p.get("needs_key", true))
	# hint
	var keys_url := String(p.get("keys_url", ""))
	if keys_url != "":
		_keys_hint.text = "[color=#7a9ac0]Get an API key: [url=%s]%s[/url][/color]" % [keys_url, keys_url]
		_keys_hint.visible = true
	elif not bool(p.get("needs_key", true)):
		_keys_hint.text = "[color=#8a8a95]Local provider — no API key required. Start the server, then Fetch models.[/color]"
		_keys_hint.visible = true
	else:
		_keys_hint.text = ""
		_keys_hint.visible = false
	# refresh the model dropdown with this provider's recommended models
	_rebuild_model_menu(PackedStringArray(p.get("models", [])))

func _rebuild_model_menu(models: PackedStringArray) -> void:
	var pop := _model_menu.get_popup()
	pop.clear()
	if models.is_empty():
		pop.add_item("(use Fetch models)")
		pop.set_item_disabled(0, true)
		return
	var i := 0
	for m in models:
		pop.add_item(m, i)
		i += 1

func _on_model_picked(id: int) -> void:
	var pop := _model_menu.get_popup()
	var idx := pop.get_item_index(id)
	if idx >= 0:
		_model_edit.text = pop.get_item_text(idx)

func _on_fetch_models() -> void:
	if _client == null:
		_fetch_status.text = "Model fetch unavailable (no client)."
		return
	# Persist current provider/base_url/key so the client resolves correctly.
	_flush_connection_to_settings()
	_fetch_btn.disabled = true
	_fetch_status.text = "Fetching models…"
	var res: Dictionary = await _client.fetch_models()
	_fetch_btn.disabled = false
	if not bool(res.get("ok", false)):
		_fetch_status.text = "Fetch failed: %s" % String(res.get("error", "unknown"))
		return
	var models: PackedStringArray = res.get("models", PackedStringArray())
	if models.is_empty():
		_fetch_status.text = "No models returned by this endpoint."
		return
	_rebuild_model_menu(models)
	_fetch_status.text = "Loaded %d models — open the ▾ menu to pick one." % models.size()

# Write provider/base_url/api_key into the live settings so fetch_models works
# before the dialog is saved.
func _flush_connection_to_settings() -> void:
	if _settings_ref == null:
		return
	_settings_ref.set_value("provider", _selected_provider_id())
	_settings_ref.set_value("base_url", _base_url_edit.text)
	_settings_ref.set_value("api_key", _api_key_edit.text)

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
					(w as SpinBox).max_value = 2000000
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
	_settings_ref = settings
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
	# provider dropdown + dependent UI
	var pid := String(settings.get_value("provider"))
	_select_provider_in_ui(pid)
	_apply_provider_ui(pid)

func _on_save() -> void:
	changed.emit()

func collect() -> Dictionary:
	var out := {}
	out["provider"] = _selected_provider_id()
	for key in _inputs:
		var w: Control = _inputs[key]
		if w is LineEdit:
			out[key] = (w as LineEdit).text
		elif w is SpinBox:
			out[key] = (w as SpinBox).value
		elif w is CheckBox:
			out[key] = (w as CheckBox).button_pressed
	return out
