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
	var url := _settings.effective_base_url() + AiCopilotConst.CHAT_COMPLETIONS_PATH
	var auth := _settings.effective_auth_header()
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"%s: %s" % [auth["name"], auth["value"]],
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

# Fetch available model ids from the provider's OpenAI-compatible /models
# endpoint. Returns {"ok": bool, "models": PackedStringArray, "error": String,
# "status": int}. Ported from KiloCode's fetch-models.ts.
func fetch_models() -> Dictionary:
	var base := _settings.effective_base_url()
	if base.strip_edges() == "":
		return {"ok": false, "models": PackedStringArray(), "error": "no base URL set", "status": 0}
	var url := base.rstrip("/") + "/models"
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0
	var auth := _settings.effective_auth_header()
	var headers := PackedStringArray(["Content-Type: application/json"])
	if String(_settings.get_value("api_key")).strip_edges() != "":
		headers.append("%s: %s" % [auth["name"], auth["value"]])
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "models": PackedStringArray(), "error": "request error %d" % err, "status": 0}
	var result: Array = await http.request_completed
	var r_code: int = result[1]
	var body_str: String = (result[3] as PackedByteArray).get_string_from_utf8()
	http.queue_free()
	if r_code < 200 or r_code >= 300:
		return {"ok": false, "models": PackedStringArray(), "error": "HTTP %d: %s" % [r_code, body_str.left(200)], "status": r_code}
	var parsed = JSON.parse_string(body_str)
	var out := PackedStringArray()
	if parsed is Dictionary and parsed.has("data") and parsed["data"] is Array:
		var seen := {}
		for item in parsed["data"]:
			if item is Dictionary and item.has("id"):
				var mid := String(item["id"]).strip_edges()
				if mid != "" and not seen.has(mid):
					seen[mid] = true
					out.append(mid)
	out.sort()
	return {"ok": true, "models": out, "error": "", "status": r_code}

func send_messages_stream(messages: Array, options: Dictionary = {}) -> AiCopilotLLMTypes.Message:
	var payload := _build_payload(messages, options, true)
	var endpoint := _settings.effective_base_url()
	var host := _extract_host(endpoint)
	var base_path := _extract_path(endpoint)
	var path := base_path + AiCopilotConst.CHAT_COMPLETIONS_PATH
	var auth := _settings.effective_auth_header()
	var body := JSON.stringify(payload, "", false)
	var sse := AiCopilotSSEStream.new(host, path, String(auth["value"]), body, String(auth["name"]), _is_tls(endpoint), _extract_port(endpoint))
	var accum := _Accumulator.new()
	var had_error := [false]
	sse.data_line.connect(_on_data.bind(accum))
	sse.done_received.connect(_on_done.bind(accum))
	sse.heartbeat.connect(func(): pass)
	sse.stream_error.connect(func(m):
		had_error[0] = true
		push_error("[ai_copilot] sse err: " + m))
	await sse.run(self)
	# Fall back to a non-streaming request if the stream failed or produced
	# nothing (bad endpoint, HTTP error, model without SSE support, etc.).
	if had_error[0] or not sse.any_data:
		AiCopilotLogger.warn("streaming failed (code=%d, data=%s); falling back to batch" % [sse.response_code, str(sse.any_data)])
		return await send_messages_batch(messages, options)
	var final_msg: AiCopilotLLMTypes.Message = accum.build_message()
	if final_msg == null:
		return await send_messages_batch(messages, options)
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
	# Emit reasoning if present (parity with the streaming path: some providers
	# use "reasoning_content", others "reasoning").
	var r := ""
	if msg.has("reasoning_content") and msg["reasoning_content"] != null:
		r = str(msg["reasoning_content"])
	elif msg.has("reasoning") and msg["reasoning"] != null:
		r = str(msg["reasoning"])
	if r.strip_edges() != "":
		reasoning_received.emit(r)
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
	# strip an explicit :port
	var colon := s.rfind(":")
	if colon != -1:
		s = s.substr(0, colon)
	return s

func _extract_port(full_url: String) -> int:
	var s := _strip_scheme(full_url)
	var slash := s.find("/")
	if slash != -1:
		s = s.substr(0, slash)
	var colon := s.rfind(":")
	if colon != -1:
		return int(s.substr(colon + 1))
	return -1

func _is_tls(full_url: String) -> bool:
	return not full_url.begins_with("http://")

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
