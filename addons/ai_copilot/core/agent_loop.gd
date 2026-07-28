class_name AiCopilotAgentLoop
extends Node

signal assistant_token(text: String)
signal assistant_message_complete(message: AiCopilotLLMTypes.Message)
signal tool_call_started(call: AiCopilotLLMTypes.ToolCall)
signal tool_call_completed(call: AiCopilotLLMTypes.ToolCall, result: AiCopilotLLMTypes.ToolResult)
signal tool_call_awaiting_approval(call: AiCopilotLLMTypes.ToolCall)
signal step_started(step_num: int, max_steps: int)
signal turn_finished(reason: String)
signal error_emitted(message: String)
signal history_compacted(history: Array)

var _client: AiCopilotLLMClient
var _registry: AiCopilotToolRegistry
var _settings: AiCopilotSettings
var _repo_context: String = ""
var _max_steps: int = AiCopilotConst.SAFETY_STEP_CAP
var _stop_requested: bool = false
var _busy: bool = false
var _approve_mode: bool = true
var _last_tool_call_signature: String = ""
var _consecutive_same_tool: int = 0
var _last_tool_name: String = ""
var _malformed_retried := false
var _pending_approval: Dictionary = {}
var _pending_image: Dictionary = {}

func _init(p_client: AiCopilotLLMClient, p_registry: AiCopilotToolRegistry, p_settings: AiCopilotSettings) -> void:
	_client = p_client
	_registry = p_registry
	_settings = p_settings

func configure(approve_mode: bool, system_prompt: String) -> void:
	_approve_mode = approve_mode
	_repo_context = system_prompt

func request_stop() -> void:
	_stop_requested = true

func set_approve_mode(on: bool) -> void:
	_approve_mode = on

func run(history: Array, options: Dictionary = {}) -> void:
	if _busy:
		error_emitted.emit("agent already busy")
		return
	_busy = true
	_stop_requested = false
	_malformed_retried = false
	_last_tool_call_signature = ""
	_consecutive_same_tool = 0
	_last_tool_name = ""
	var max_steps := int(options.get("max_steps", _max_steps))
	var opts := options.duplicate()
	opts["tools"] = _registry.to_openai_tools()
	var step := 0
	while step < max_steps:
		if _stop_requested:
			turn_finished.emit("cancelled")
			_busy = false
			return
		step += 1
		step_started.emit(step, max_steps)
		var is_last_step := step >= max_steps
		var payload_messages := _to_dicts(history)
		# On the final allowed step, tell the model to stop calling tools and
		# summarize instead of getting cut off mid-task (KiloCode's approach).
		var step_opts := opts
		if is_last_step:
			payload_messages.append(AiCopilotLLMTypes.Message.new("system", AiCopilotConst.MAX_STEPS_PROMPT).to_dict())
			step_opts = opts.duplicate()
			step_opts.erase("tools")
		if _pending_image.has("base64"):
			var img_msg := AiCopilotLLMTypes.Message.new("user", [
				{"type":"text","text":"Here is the current editor viewport:"},
				{"type":"image_url","image_url":{"url":"data:image/png;base64," + _pending_image["base64"]}}
			])
			payload_messages.append(img_msg.to_dict())
			history.append(img_msg)
			_pending_image.clear()
		var check_compact := false
		if not _stop_requested:
			check_compact = true
		var assistant_msg: AiCopilotLLMTypes.Message
		var use_stream := _client._strategy.get_works()
		if use_stream:
			assistant_msg = await _client.send_messages_stream(payload_messages, step_opts)
		else:
			assistant_msg = await _client.send_messages_fake_stream(payload_messages, step_opts)
		if assistant_msg == null:
			error_emitted.emit("LLM returned null message")
			turn_finished.emit("error")
			_busy = false
			return
		history.append(assistant_msg)
		assistant_message_complete.emit(assistant_msg)
		if assistant_msg.tool_calls.is_empty() and str(assistant_msg.content).strip_edges() == "":
			turn_finished.emit("empty_response")
			_busy = false
			return
		if assistant_msg.tool_calls.is_empty():
			turn_finished.emit("final_text")
			_busy = false
			return
		for tc in assistant_msg.tool_calls:
			if _stop_requested:
				turn_finished.emit("cancelled")
				_busy = false
				return
			tool_call_started.emit(tc)

			if _registry.get_tool(tc.name) == null:
				var available := _registry.list_names()
				var hint := ", ".join(available.slice(0, 6))
				var missing := AiCopilotLLMTypes.ToolResult.new("unknown tool: %s. Available tools include: %s" % [tc.name, hint], true)
				tool_call_completed.emit(tc, missing)
				history.append(_make_tool_msg(tc, missing))
				continue

			var needs_appr := _approve_mode and _needs_approval(tc.name)
			if needs_appr:
				tool_call_awaiting_approval.emit(tc)
				var verdict := await _wait_for_approval(tc)
				if verdict == -1:
					var rej := AiCopilotLLMTypes.ToolResult.new("user rejected tool execution", true)
					tool_call_completed.emit(tc, rej)
					history.append(_make_tool_msg(tc, rej))
					continue

			if tc.args_malformed():
				if not _malformed_retried:
					_malformed_retried = true
					history.append(AiCopilotLLMTypes.Message.new("system", "[your last tool args were invalid JSON for %s; please retry]" % tc.name))
					continue
				else:
					error_emitted.emit("malformed tool args persisted after retry; aborting turn")
					turn_finished.emit("error")
					_busy = false
					return
			_malformed_retried = false

			var result: AiCopilotLLMTypes.ToolResult = _registry.execute(tc)
			tool_call_completed.emit(tc, result)
			if result.data.has("_image_b64"):
				_pending_image["base64"] = result.data["_image_b64"]
			history.append(_make_tool_msg(tc, result))
	turn_finished.emit("max_steps")
	_busy = false

func _to_dicts(history: Array) -> Array:
	var out := []
	out.append(AiCopilotLLMTypes.Message.new("system", _repo_context).to_dict())
	for m in history:
		if m is AiCopilotLLMTypes.Message:
			out.append(m.to_dict())
	return out

func _make_tool_msg(call: AiCopilotLLMTypes.ToolCall, result: AiCopilotLLMTypes.ToolResult) -> AiCopilotLLMTypes.Message:
	var m := AiCopilotLLMTypes.Message.new("tool", result.content)
	m.tool_call_id = call.id
	m.name = call.name
	if result.is_error:
		m.content = "[ERROR] " + result.content
	return m

func _needs_approval(tool_name: String) -> bool:
	return tool_name in ["write_file", "edit_file", "delete_file", "rename_file", "run_command", "project_set_setting", "project_add_input_action", "run_project", "run_scene", "create_scene", "add_node"]

func _wait_for_approval(call: AiCopilotLLMTypes.ToolCall) -> int:
	_pending_approval[call.id] = 0
	while _pending_approval.get(call.id, 0) == 0:
		await get_tree().process_frame
		if _stop_requested:
			return -1
	return _pending_approval.get(call.id, -1)

func approve(call_id: String) -> void:
	_pending_approval[call_id] = 1

func reject(call_id: String) -> void:
	_pending_approval[call_id] = -1
