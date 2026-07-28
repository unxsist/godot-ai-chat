@tool
class_name AiCopilotChatPanel
extends Control

signal send_requested(text: String)

var _settings: AiCopilotSettings
var _client: AiCopilotLLMClient
var _settings_dialog: AiCopilotSettingsDialog
var _toolbar: AiCopilotToolbar
var _composer: AiCopilotComposer
var _scroll: ScrollContainer
var _messages_box: VBoxContainer
var _todo_panel: PanelContainer
var _todo_list: VBoxContainer
var _registry: AiCopilotToolRegistry
var _agent: AiCopilotAgentLoop
var _repo: AiCopilotRepoContext
var _history: Array = []
var _busy: bool = false
var _live_bubble: AiCopilotChatMessage = null

func _ready() -> void:
	custom_minimum_size = Vector2(340, 240)
	DirAccess.make_dir_recursive_absolute(AiCopilotConst.USER_DIR)

	_settings = AiCopilotSettings.new()
	AiCopilotLogger.set_verbose(bool(_settings.get_value("verbose_logging")))
	_client = AiCopilotLLMClient.new(_settings)
	add_child(_client)
	# Connect streaming signals ONCE (guarded by _busy) — avoids leaked
	# per-send connections that could spawn stray bubbles on later turns.
	_client.chunk_received.connect(_on_stream_chunk)
	_client.reasoning_received.connect(_on_stream_reasoning)

	_registry = AiCopilotToolRegistry.new()

	_settings_dialog = preload("res://addons/ai_copilot/ui/settings_dialog.tscn").instantiate()
	add_child(_settings_dialog)
	_settings_dialog.set_client(_client)
	_settings_dialog.changed.connect(_on_settings_saved)
	_settings_dialog.load_from(_settings)

	AiCopilotFSTools.register_all(_registry)
	AiCopilotShellTools.register_all(_registry)
	AiCopilotEditorTools.register_all(_registry, _settings)
	AiCopilotPlanTools.register_all(_registry)
	AiCopilotProjectTools.register_all(_registry)
	AiCopilotGodotTools.register_all(_registry)

	if Engine.has_meta("AiCopilotAPI"):
		var api_node = Engine.get_meta("AiCopilotAPI")
		if api_node: api_node.registry = _registry

	_repo = AiCopilotRepoContext.new()
	var sys: String = _repo.build_system_prompt(_registry)

	_agent = AiCopilotAgentLoop.new(_client, _registry, _settings)
	add_child(_agent)
	_agent.configure(bool(_settings.get_value("approve_default")), sys)
	_agent.assistant_message_complete.connect(_on_assistant_message)
	_agent.tool_call_completed.connect(func(_c, _r): _save())
	_agent.turn_finished.connect(func(_r): _save())
	_agent.tool_call_awaiting_approval.connect(_on_tool_approve)
	_agent.tool_call_started.connect(_on_tool_started)
	_agent.tool_call_completed.connect(_on_tool_completed)
	_agent.step_started.connect(_on_step_started)
	_agent.turn_finished.connect(_on_turn_finished)
	_agent.error_emitted.connect(_on_error)
	_agent.history_compacted.connect(func(h): _history = h; _rerender())

	_history = AiCopilotSessionStore.load_history()

	var bg := ColorRect.new()
	bg.color = Color("121216")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top_bar := PanelContainer.new()
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = Color("1a1a20")
	tb_style.border_color = Color("2a2a33")
	tb_style.border_width_bottom = 1
	tb_style.content_margin_left = 8
	tb_style.content_margin_right = 8
	tb_style.content_margin_top = 4
	tb_style.content_margin_bottom = 4
	top_bar.add_theme_stylebox_override("panel", tb_style)
	root.add_child(top_bar)

	_toolbar = preload("res://addons/ai_copilot/ui/toolbar.tscn").instantiate()
	top_bar.add_child(_toolbar)
	_toolbar.set_model_label(_settings.get_value("model"))
	_toolbar.settings_clicked.connect(open_settings)
	_toolbar.clear_clicked.connect(_on_clear)
	_toolbar.stop_clicked.connect(func(): _agent.request_stop())
	_toolbar.mode_toggled.connect(func(on): _agent.set_approve_mode(on))
	_toolbar.regenerate_requested.connect(_on_regenerate)
	_toolbar.set_approve_mode(bool(_settings.get_value("approve_default")))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_messages_box = VBoxContainer.new()
	_messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages_box.add_theme_constant_override("separation", 10)
	var mm := MarginContainer.new()
	mm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mm.add_theme_constant_override("margin_top", 10)
	mm.add_theme_constant_override("margin_bottom", 10)
	mm.add_child(_messages_box)
	_scroll.add_child(mm)

	_todo_panel = PanelContainer.new()
	var tp_style := StyleBoxFlat.new()
	tp_style.bg_color = Color("16161c")
	tp_style.border_color = Color("2a2a33")
	tp_style.border_width_top = 1
	tp_style.content_margin_left = 12
	tp_style.content_margin_right = 12
	tp_style.content_margin_top = 6
	tp_style.content_margin_bottom = 6
	_todo_panel.add_theme_stylebox_override("panel", tp_style)
	_todo_panel.visible = false
	root.add_child(_todo_panel)
	_todo_list = VBoxContainer.new()
	_todo_list.add_theme_constant_override("separation", 2)
	_todo_panel.add_child(_todo_list)

	_composer = preload("res://addons/ai_copilot/ui/composer.tscn").instantiate()
	root.add_child(_composer)
	_composer.send.connect(_on_send)

	_rerender()

func open_settings() -> void:
	_settings_dialog.load_from(_settings)
	# Let AcceptDialog size the window from the content's minimum size.
	_settings_dialog.reset_size()
	_settings_dialog.popup_centered()

func _on_settings_saved() -> void:
	var data := _settings_dialog.collect()
	for key in data:
		_settings.set_value(key, data[key])
	_toolbar.set_model_label(_settings.get_value("model"))
	AiCopilotLogger.set_verbose(bool(_settings.get_value("verbose_logging")))
	# Re-gate the vision screenshot tool when the vision model setting changes.
	var has_vision := String(_settings.get_value("vision_model")).strip_edges() != ""
	AiCopilotEditorTools._settings = _settings
	if has_vision and _registry.get_tool("viewport_screenshot") == null:
		_registry.register_tool("viewport_screenshot", "Capture the editor viewport as a PNG image for you to visually inspect. Only available because a vision model is configured.", {"type":"object","properties":{},"required":[]}, Callable(AiCopilotEditorTools, "_viewport_screenshot"), false)
	elif not has_vision and _registry.get_tool("viewport_screenshot") != null:
		_registry.unregister_tool("viewport_screenshot")

func _on_clear() -> void:
	_history.clear()
	AiCopilotSessionStore.clear()
	for c in _messages_box.get_children():
		c.queue_free()
	if _todo_panel:
		_todo_panel.visible = false
	if _todo_list:
		for c in _todo_list.get_children():
			c.queue_free()

func _on_send(text: String) -> void:
	if _busy: return
	_busy = true
	_toolbar.set_stop_enabled(true)
	var user_msg := AiCopilotLLMTypes.Message.new("user", text)
	_history.append(user_msg)
	var sp := _repo.build_system_prompt(_registry)
	_agent._repo_context = sp
	_add_bubble("user", text)
	_live_bubble = null

	var compact_check := AiCopilotCompactor.new()
	var ctx := int(_settings.get_value("model_context_window"))
	var thr := float(_settings.get_value("compact_threshold"))
	if compact_check.should_compact(_history, thr, ctx):
		var comp := AiCopilotCompactor.new()
		_history = await comp.compact(_history, _client, String(_settings.get_value("model")))
		_rerender()

	await _agent.run(_history)
	_live_bubble = null
	_busy = false
	_toolbar.set_stop_enabled(false)

# Streaming callbacks — connected ONCE in _ready (see _connect_stream_signals).
# They only act while a turn is in flight, so they can stay connected without
# per-send connect/disconnect (which leaked on errored turns and spawned
# stray bubbles on later turns).
func _on_stream_chunk(c: AiCopilotLLMTypes.ResponseChunk) -> void:
	if not _busy:
		return
	if c.delta_text != "":
		_ensure_live_bubble().append_text(c.delta_text)
		_scroll_to_bottom()

func _on_stream_reasoning(t: String) -> void:
	if not _busy:
		return
	_ensure_live_bubble().append_reasoning(t)
	_scroll_to_bottom()

func _ensure_live_bubble() -> AiCopilotChatMessage:
	# Guard against a stale reference to a queue_free()'d bubble (== null only
	# becomes true after the node is actually freed at end of frame).
	if _live_bubble != null and not is_instance_valid(_live_bubble):
		_live_bubble = null
	if _live_bubble == null:
		_live_bubble = _add_bubble("assistant", "")
		_live_bubble.set_thinking(true)
	return _live_bubble

func _on_assistant_message(msg: AiCopilotLLMTypes.Message) -> void:
	# Finalize the current round's bubble text (keeps any tool pills that follow).
	if _live_bubble != null and not is_instance_valid(_live_bubble):
		_live_bubble = null
	var has_text: bool = msg.content != null and str(msg.content).strip_edges() != ""
	var has_tools: bool = msg.tool_calls.size() > 0
	if has_text:
		_ensure_live_bubble().set_text(str(msg.content))
	if _live_bubble:
		_live_bubble.set_thinking(false)
		# Drop an empty bubble that produced neither text nor tools.
		if not has_text and not has_tools and not _live_bubble.has_reasoning():
			_live_bubble.queue_free()
			_live_bubble = null
	_save()

func _on_step_started(_step: int, _max_steps: int) -> void:
	# Each LLM round gets its own bubble so text + its tools stay grouped.
	# Create it now (empty, spinning) so there's immediate feedback while the API responds.
	if _dbg_order():
		print("[order] step_started #%d; box has %d bubbles; live=%s" % [_step, _messages_box.get_child_count(), str(is_instance_valid(_live_bubble))])
	_live_bubble = _add_bubble("assistant", "")
	_live_bubble.set_thinking(true)

func _on_tool_started(tc: AiCopilotLLMTypes.ToolCall) -> void:
	var b := _ensure_live_bubble()
	b.set_thinking(false)
	b.add_tool_indicator(tc)
	_scroll_to_bottom()

func _on_tool_completed(tc: AiCopilotLLMTypes.ToolCall, result: AiCopilotLLMTypes.ToolResult) -> void:
	if _live_bubble and is_instance_valid(_live_bubble):
		_live_bubble.update_tool_result(tc, result)
	if tc.name == "todowrite" and result.data.has("todos"):
		_update_todos(result.data["todos"])

func _update_todos(todos) -> void:
	if _todo_list == null:
		return
	for c in _todo_list.get_children():
		c.queue_free()
	if not (todos is Array) or todos.is_empty():
		_todo_panel.visible = false
		return
	_todo_panel.visible = true
	var header := Label.new()
	var done := 0
	for t in todos:
		if t is Dictionary and String(t.get("status", "")) == "completed":
			done += 1
	header.text = "Plan  (%d/%d)" % [done, todos.size()]
	header.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	header.add_theme_color_override("font_color", Color("707078"))
	_todo_list.add_child(header)
	for t in todos:
		if not (t is Dictionary):
			continue
		var status := String(t.get("status", "pending"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mark := Label.new()
		mark.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
		match status:
			"completed":
				mark.text = "✓"
				mark.add_theme_color_override("font_color", Color("52c072"))
			"in_progress":
				mark.text = "▸"
				mark.add_theme_color_override("font_color", Color("e0b040"))
			"cancelled":
				mark.text = "✕"
				mark.add_theme_color_override("font_color", Color("806060"))
			_:
				mark.text = "○"
				mark.add_theme_color_override("font_color", Color("606068"))
		row.add_child(mark)
		var lbl := Label.new()
		lbl.text = String(t.get("content", ""))
		lbl.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if status == "completed":
			lbl.add_theme_color_override("font_color", Color("707078"))
		elif status == "cancelled":
			lbl.add_theme_color_override("font_color", Color("606060"))
		else:
			lbl.add_theme_color_override("font_color", Color("c8c8d4"))
		row.add_child(lbl)
		_todo_list.add_child(row)

func _on_tool_approve(tc: AiCopilotLLMTypes.ToolCall) -> void:
	var v := preload("res://addons/ai_copilot/ui/tool_call_view.tscn").instantiate()
	v.accept.connect(func(c): _agent.approve(c.id))
	v.reject.connect(func(c): _agent.reject(c.id))
	_messages_box.add_child(v)
	# Configure AFTER add_child so the view's _ready() has built its widgets.
	v.set_call(tc, true)
	_scroll_to_bottom()

func _on_turn_finished(_reason: String) -> void:
	_scroll_to_bottom()

func _on_error(msg: String) -> void:
	var b := _add_bubble("error", msg)
	push_error("[ai_copilot] %s" % msg)

func _on_regenerate() -> void:
	if _busy: return
	var idx := _history.size() - 1
	if idx < 1: return
	while idx >= 0 and _history[idx].role != "user":
		_history.remove_at(idx)
		idx -= 1
	if idx < 0: return
	_history.remove_at(idx)
	_rerender()
	_busy = true
	_toolbar.set_stop_enabled(true)
	_live_bubble = null
	await _agent.run(_history)
	_live_bubble = null
	_busy = false
	_toolbar.set_stop_enabled(false)

func _add_bubble(role: String, text: String) -> AiCopilotChatMessage:
	var b := AiCopilotChatMessage.new()
	_messages_box.add_child(b)
	b.set_role(role)
	if text != "":
		b.set_text(text)
	if _dbg_order():
		var order := ""
		for c in _messages_box.get_children():
			order += (c.get_role()[0] if c.has_method("get_role") and c.get_role() != "" else "?")
		print("[order] add_bubble(%s) -> [%s]" % [role, order])
	_scroll_to_bottom()
	return b

static func _dbg_order() -> bool:
	return OS.get_environment("AICOPILOT_DBG_ORDER") != ""

func _save() -> void:
	AiCopilotSessionStore.save(_history)

func _rerender() -> void:
	for c in _messages_box.get_children():
		c.queue_free()
	await get_tree().process_frame
	# Index tool results by tool_call_id for reconstruction
	var results := {}
	for m in _history:
		if m is AiCopilotLLMTypes.Message and m.role == "tool":
			results[m.tool_call_id] = m
	for m in _history:
		if not (m is AiCopilotLLMTypes.Message):
			continue
		if m.role == "tool":
			continue
		if m.role == "user":
			_add_bubble("user", str(m.content))
		elif m.role == "assistant":
			var has_text: bool = m.content != null and str(m.content).strip_edges() != ""
			var has_tools: bool = m.tool_calls.size() > 0
			if not has_text and not has_tools:
				continue
			var bubble := _add_bubble("assistant", str(m.content) if has_text else "")
			for tc in m.tool_calls:
				bubble.add_tool_indicator(tc)
				var res_msg = results.get(tc.id, null)
				if res_msg:
					var is_err := str(res_msg.content).begins_with("[ERROR]")
					bubble.update_tool_result(tc, AiCopilotLLMTypes.ToolResult.new(str(res_msg.content), is_err))
	_scroll_to_bottom()

func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# Wait for layout to settle: newly added tall items (e.g. an approval card
	# with a diff) need a couple of passes before the scrollbar's max_value
	# reflects the new content height.
	for i in range(3):
		await get_tree().process_frame
	if _scroll:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
