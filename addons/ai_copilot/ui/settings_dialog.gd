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
var _tab_conn_btn: Button
var _tab_adv_btn: Button
var _section_conn: Control
var _section_adv: Control

func _ready() -> void:
	title = "AI Copilot Settings"
	ok_button_text = "Save"
	confirmed.connect(_on_save)
	var body := _build_body()
	add_child(body)

func set_client(c: AiCopilotLLMClient) -> void:
	_client = c

func _build_body() -> Control:
	var root := VBoxContainer.new()
	root.name = "Body"
	root.custom_minimum_size = Vector2(AiCopilotUI.scale(560), AiCopilotUI.scale(300))
	root.add_theme_constant_override("separation", 12)

	# --- Segmented section switcher (clear, unambiguous active state) -------
	var seg := HBoxContainer.new()
	seg.alignment = BoxContainer.ALIGNMENT_CENTER
	seg.add_theme_constant_override("separation", 0)
	root.add_child(seg)

	_tab_conn_btn = _make_seg_button("Connection", true)
	_tab_adv_btn = _make_seg_button("Advanced", false)
	# radio-style group
	var grp := ButtonGroup.new()
	_tab_conn_btn.button_group = grp
	_tab_adv_btn.button_group = grp
	_tab_conn_btn.pressed.connect(func(): _show_section(0))
	_tab_adv_btn.pressed.connect(func(): _show_section(1))
	seg.add_child(_tab_conn_btn)
	seg.add_child(_tab_adv_btn)

	# --- Content panel (card) that holds whichever section is active --------
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("1b1b21")
	card_style.set_corner_radius_all(6)
	card_style.set_border_width_all(1)
	card_style.border_color = Color("2e2e39")
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", card_style)
	root.add_child(card)

	_section_conn = _make_connection_tab()
	_section_adv = _make_advanced_tab()
	card.add_child(_section_conn)
	card.add_child(_section_adv)
	_show_section(0)
	return root

# A pill-style segmented toggle button. First/last get rounded outer corners.
func _make_seg_button(text: String, is_first: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(AiCopilotUI.scale(140), AiCopilotUI.scale(32))
	b.add_theme_font_size_override("font_size", AiCopilotUI.fs_body())

	var mk := func(bg: Color, fg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		if is_first:
			s.corner_radius_top_left = 6
			s.corner_radius_bottom_left = 6
		else:
			s.corner_radius_top_right = 6
			s.corner_radius_bottom_right = 6
		return s

	var normal := mk.call(Color("222228"), Color("9aa0ae"), Color("34343f"))
	var hover := mk.call(Color("2a2a32"), Color("cfd4e0"), Color("3a3a46"))
	var active := mk.call(Color("3d6fb0"), Color("ffffff"), Color("4d82c8"))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", active)
	b.add_theme_stylebox_override("hover_pressed", active)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("9aa0ae"))
	b.add_theme_color_override("font_hover_color", Color("cfd4e0"))
	b.add_theme_color_override("font_pressed_color", Color("ffffff"))
	b.add_theme_color_override("font_hover_pressed_color", Color("ffffff"))
	return b

func _show_section(idx: int) -> void:
	if _section_conn:
		_section_conn.visible = idx == 0
	if _section_adv:
		_section_adv.visible = idx == 1
	if _tab_conn_btn:
		_tab_conn_btn.button_pressed = idx == 0
	if _tab_adv_btn:
		_tab_adv_btn.button_pressed = idx == 1

func _make_connection_tab() -> Control:
	var conn := VBoxContainer.new()
	conn.name = "Connection"
	conn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	conn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conn.add_theme_constant_override("separation", 10)

	# Provider picker
	var prov_row := _labeled_row("Provider")
	_provider_btn = OptionButton.new()
	_provider_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_providers()
	_provider_btn.item_selected.connect(_on_provider_selected)
	prov_row.add_child(_provider_btn)
	conn.add_child(prov_row)

	# API-key acquisition hint
	_keys_hint = RichTextLabel.new()
	_keys_hint.bbcode_enabled = true
	_keys_hint.fit_content = true
	_keys_hint.scroll_active = false
	_keys_hint.meta_underlined = true
	_keys_hint.custom_minimum_size = Vector2(AiCopilotUI.scale(480), AiCopilotUI.scale(20))
	_keys_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_hint.add_theme_font_size_override("normal_font_size", AiCopilotUI.fs_small())
	_keys_hint.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	conn.add_child(_keys_hint)

	# Base URL (editable only for custom/local)
	_base_url_row = _row("base_url", "Base URL", "LineEdit")
	_base_url_edit = _inputs["base_url"]
	conn.add_child(_base_url_row)

	# API key
	_api_key_row = _row("api_key", "API key", "PasswordInput")
	_api_key_edit = _inputs["api_key"]
	conn.add_child(_api_key_row)

	# Model row: label + field + dropdown + fetch
	var model_row := _labeled_row("Model")
	_model_edit = LineEdit.new()
	_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_edit.custom_minimum_size.x = AiCopilotUI.scale(200)
	_model_edit.placeholder_text = "model id (e.g. gpt-4o)"
	_model_edit.clip_contents = true
	_inputs["model"] = _model_edit
	model_row.add_child(_model_edit)
	_model_menu = MenuButton.new()
	_model_menu.text = "▾"
	_model_menu.tooltip_text = "Pick from recommended / fetched models"
	_model_menu.get_popup().id_pressed.connect(_on_model_picked)
	model_row.add_child(_model_menu)
	_fetch_btn = Button.new()
	_fetch_btn.text = "Fetch"
	_fetch_btn.pressed.connect(_on_fetch_models)
	model_row.add_child(_fetch_btn)
	conn.add_child(model_row)

	_fetch_status = Label.new()
	_fetch_status.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
	_fetch_status.add_theme_color_override("font_color", Color("8a8a95"))
	conn.add_child(_fetch_status)

	var model_hint := Label.new()
	model_hint.text = "Fetch lists the models your endpoint exposes — you can also type any model id."
	model_hint.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
	model_hint.add_theme_color_override("font_color", Color("707078"))
	model_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model_hint.custom_minimum_size.x = AiCopilotUI.scale(480)
	conn.add_child(model_hint)
	return conn

func _make_advanced_tab() -> Control:
	var adv := VBoxContainer.new()
	adv.name = "Advanced"
	adv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	adv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adv.add_theme_constant_override("separation", 10)
	adv.add_child(_row("vision_model", "Vision model", "LineEdit"))
	adv.add_child(_row("model_context_window", "Context window (tokens)", "SpinBox"))
	adv.add_child(_row("temperature", "Temperature", "SpinBox"))
	adv.add_child(_row("max_tokens", "Max tokens", "SpinBox"))
	adv.add_child(_row("compact_threshold", "Compact threshold (0..1)", "SpinBox"))
	adv.add_child(HSeparator.new())
	adv.add_child(_row("approve_default", "Approve mode by default", "CheckBox"))
	adv.add_child(_row("allow_shell", "Allow shell tool", "CheckBox"))
	adv.add_child(_row("verbose_logging", "Verbose logging", "CheckBox"))
	return adv

# A row with a fixed-width label, ready for callers to add the input control(s).
func _labeled_row(label_text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = AiCopilotUI.scale(150)
	h.add_child(l)
	return h

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
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = AiCopilotUI.scale(150)
	h.add_child(l)
	var w: Control = null
	match kind:
		"LineEdit":
			w = LineEdit.new()
			w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		"PasswordInput":
			w = LineEdit.new()
			(w as LineEdit).secret = true
			w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		"SpinBox":
			w = SpinBox.new()
			(w as SpinBox).custom_minimum_size.x = AiCopilotUI.scale(160)
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
	# always open on the Connection section
	_show_section(0)

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
