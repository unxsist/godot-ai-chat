class_name AiCopilotLLMClient
extends Node

signal request_completed(response: AiCopilotLLMTypes.Message)
signal request_failed(http_status: int, body: String)
signal usage_received(usage: AiCopilotLLMTypes.Usage)
signal chunk_received(chunk: AiCopilotLLMTypes.ResponseChunk)
signal reasoning_received(text: String)

var _settings: AiCopilotSettings
var _strategy: AiCopilotStreamingStrategy

func _init(p_settings: AiCopilotSettings) -> void:
	_settings = p_settings
	_strategy = AiCopilotStreamingStrategy.new()

func send_messages_batch(messages: Array, options: Dictionary = {}) -> AiCopilotLLMTypes.Message:
	var payload := _build_payload(messages, options, false)
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = AiCopilotConst.HTTP_TIMEOUT_MS / 1000.0
	var url := (_settings.get_value("endpoint") as String) + AiCopilotConst.CHAT_COMPLETIONS_PATH
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + (_settings.get_value("api_key") as String),
	])
	var body := JSON.stringify(payload, "", false)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		request_failed.emit(0, "")
		http.queue_free()
		return AiCopilotLLMTypes.Message.new("assistant", "")
	var result: Array = await http.request_completed
	var r_result: int = result[0]
	var r_code: int = result[1]
	var r_body: PackedByteArray = result[3]
	var body_str := r_body.get_string_from_utf8()
	http.queue_free()
	if r_result != HTTPRequest.RESULT_SUCCESS or r_code < 200 or r_code >= 300:
		push_error("[ai_copilot] http %d: %s" % [r_code, body_str.left(512)])
		request_failed.emit(r_code, body_str)
		return AiCopilotLLMTypes.Message.new("assistant", "")
	return _parse_response(body_str)

func send_messages_stream(messages: Array, options: Dictionary = {}) -> AiCopilotLLMTypes.Message:
	var payload := _build_payload(messages, options, true)
	var endpoint := _settings.get_value("endpoint") as String
	var host := _extract_host(endpoint)
	var base_path := _extract_path(endpoint)
	var path := base_path + AiCopilotConst.CHAT_COMPLETIONS_PATH
	var auth_header := "Bearer " + (_settings.get_value("api_key") as String)
	var body := JSON.stringify(payload, "", false)
	var sse := AiCopilotSSEStream.new(host, path, auth_header, body)
	var accum := _Accumulator.new()
	sse.data_line.connect(_on_data.bind(accum))
	sse.done_received.connect(_on_done.bind(accum))
	sse.heartbeat.connect(func(): pass)
	sse.stream_error.connect(func(m): push_error("[ai_copilot] sse err: " + m))
	await sse.run(self)
	var final_msg: AiCopilotLLMTypes.Message = accum.build_message()
	if final_msg == null:
		return AiCopilotLLMTypes.Message.new("assistant", "")
	return final_msg

func send_messages_fake_stream(messages: Array, options: Dictionary = {}) -> AiCopilotLLMTypes.Message:
	var msg := await send_messages_batch(messages, options)
	var text := str(msg.content)
	var chunk_size := max(1, int(text.length() / 60.0))
	var i := 0
	while i < text.length():
		var ch := AiCopilotLLMTypes.ResponseChunk.new()
		var end := min(i + chunk_size, text.length())
		ch.delta_text = text.substr(i, end - i)
		chunk_received.emit(ch)
		i = end
		await get_tree().process_frame
	return msg

func _on_data(json_str: String, accum: _Accumulator) -> void:
	var parsed = JSON.parse_string(json_str)
	if parsed == null:
		return
	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		return
	var first: Dictionary = choices[0]
	var delta: Dictionary = first.get("delta", {})
	var chunk := AiCopilotLLMTypes.ResponseChunk.new()
	chunk.delta_text = delta.get("content", "")
	var reasoning := ""
	if delta.has("reasoning_content") and delta["reasoning_content"] != null:
		reasoning = str(delta["reasoning_content"])
	elif delta.has("reasoning") and delta["reasoning"] != null:
		reasoning = str(delta["reasoning"])
	if reasoning != "":
		reasoning_received.emit(reasoning)
	if delta.has("tool_calls"):
		var tcs: Array = delta["tool_calls"]
		for tc in tcs:
			var idx := int(tc.get("index", 0))
			var fn: Dictionary = tc.get("function", {})
			chunk.tool_call_index = idx
			chunk.tool_call_id_delta = tc.get("id", "")
			chunk.tool_call_name_delta = fn.get("name", "")
			chunk.tool_call_args_delta = fn.get("arguments", "")
			accum.feed_tool_call(chunk)
	if chunk.delta_text != "":
		accum.feed_text(chunk.delta_text)
		chunk_received.emit(chunk)
	if first.has("finish_reason") and first["finish_reason"] != null:
		chunk.finish_reason = first["finish_reason"]
		accum.set_finish(chunk.finish_reason)
	if parsed.has("usage") and parsed["usage"] != null:
		var u: Dictionary = parsed["usage"]
		var usage := AiCopilotLLMTypes.Usage.new(int(u.get("prompt_tokens", 0)), int(u.get("completion_tokens", 0)))
		usage_received.emit(usage)

func _on_done(accum: _Accumulator) -> void:
	accum.set_done()

func _build_payload(messages: Array, options: Dictionary, stream: bool) -> Dictionary:
	var out := {
		"model": options.get("model", _settings.get_value("model")),
		"messages": messages,
		"stream": stream,
	}
	if options.has("temperature"):
		out["temperature"] = float(options["temperature"])
	else:
		out["temperature"] = float(_settings.get_value("temperature"))
	if options.has("max_tokens"):
		out["max_tokens"] = int(options["max_tokens"])
	else:
		out["max_tokens"] = int(_settings.get_value("max_tokens"))
	if options.has("tools") and options["tools"].size() > 0:
		out["tools"] = options["tools"]
	return out

func _parse_response(body_str: String) -> AiCopilotLLMTypes.Message:
	var parsed = JSON.parse_string(body_str)
	if parsed == null or not (parsed is Dictionary):
		push_error("[ai_copilot] non-JSON response")
		request_failed.emit(0, body_str)
		return AiCopilotLLMTypes.Message.new("assistant", "")
	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		push_error("[ai_copilot] no choices in response")
		return AiCopilotLLMTypes.Message.new("assistant", "")
	var first: Dictionary = choices[0]
	var msg: Dictionary = first.get("message", {})
	if msg.has("reasoning_content") and msg["reasoning_content"] != null and str(msg["reasoning_content"]) != "":
		reasoning_received.emit(str(msg["reasoning_content"]))
	var m: AiCopilotLLMTypes.Message = AiCopilotLLMTypes.Message.from_dict(msg)
	if parsed.has("usage"):
		var u: Dictionary = parsed["usage"]
		var usage := AiCopilotLLMTypes.Usage.new(int(u.get("prompt_tokens", 0)), int(u.get("completion_tokens", 0)))
		usage_received.emit(usage)
	request_completed.emit(m)
	return m

func _strip_scheme(url: String) -> String:
	var s := url
	if s.begins_with("https://"):
		s = s.substr(8)
	elif s.begins_with("http://"):
		s = s.substr(7)
	return s

func _extract_host(full_url: String) -> String:
	var s := _strip_scheme(full_url)
	var slash := s.find("/")
	if slash != -1:
		s = s.substr(0, slash)
	return s

func _extract_path(full_url: String) -> String:
	var s := _strip_scheme(full_url)
	var slash := s.find("/")
	if slash != -1:
		return s.substr(slash)
	return ""

class _Accumulator:
	extends RefCounted
	var text := ""
	var tool_calls_by_index: Dictionary = {}
	var finish_reason := ""

	func feed_text(t: String) -> void:
		text += t

	func feed_tool_call(c: AiCopilotLLMTypes.ResponseChunk) -> void:
		var key: int = c.tool_call_index
		if not tool_calls_by_index.has(key):
			tool_calls_by_index[key] = {"id": "", "name": "", "args": ""}
		var e: Dictionary = tool_calls_by_index[key]
		if c.tool_call_id_delta != "":
			e["id"] = c.tool_call_id_delta
		if c.tool_call_name_delta != "":
			e["name"] = c.tool_call_name_delta
		e["args"] += c.tool_call_args_delta

	func set_finish(r: String) -> void:
		finish_reason = r

	func set_done() -> void:
		pass

	func build_message():
		var m: AiCopilotLLMTypes.Message = AiCopilotLLMTypes.Message.new("assistant", text)
		for key in tool_calls_by_index.keys():
			var e: Dictionary = tool_calls_by_index[key]
			var tc := AiCopilotLLMTypes.ToolCall.new(e["id"], e["name"], e["args"])
			m.tool_calls.append(tc)
		return m
