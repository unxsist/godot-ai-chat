class_name AiCopilotLLMTypes
extends RefCounted

class Message:
	extends RefCounted
	var role: String
	var content: Variant
	var tool_calls: Array
	var tool_call_id: String
	var name: String

	func _init(p_role: String = "", p_content: Variant = "") -> void:
		role = p_role
		content = p_content
		tool_calls = []
		tool_call_id = ""
		name = ""

	func to_dict() -> Dictionary:
		var d := {"role": role}
		if role == "assistant" and tool_calls.size() > 0:
			var arr := []
			for tc in tool_calls:
				if tc is AiCopilotLLMTypes.ToolCall:
					arr.append({
						"id": tc.id,
						"type": "function",
						"function": {"name": tc.name, "arguments": tc.arguments_raw}
					})
			d["tool_calls"] = arr
			if _content_is_empty():
				d["content"] = null
			else:
				d["content"] = content
		elif role == "tool":
			d["content"] = content
			d["tool_call_id"] = tool_call_id
		else:
			d["content"] = content
		return d

	func _content_is_empty() -> bool:
		if content == null:
			return true
		if content is String:
			return content == ""
		if content is Array:
			return content.is_empty()
		return false

	static func from_dict(d: Dictionary):
		var msg = Message.new(d.get("role", ""), d.get("content", ""))
		if d.has("tool_calls") and d["tool_calls"] is Array:
			for tc in d["tool_calls"]:
				var call := ToolCall.new(
					tc.get("id", ""),
					tc.get("function", {}).get("name", ""),
					tc.get("function", {}).get("arguments", "")
				)
				msg.tool_calls.append(call)
		if d.has("tool_call_id"):
			msg.tool_call_id = d["tool_call_id"]
		if d.has("name"):
			msg.name = d["name"]
		return msg

	func clone():
		var m := Message.new(role, content)
		m.tool_call_id = tool_call_id
		m.name = name
		for tc in tool_calls:
			m.tool_calls.append(tc.clone())
		return m

class ToolCall:
	extends RefCounted
	var id: String
	var name: String
	var arguments_raw: String

	func _init(p_id: String = "", p_name: String = "", p_args: String = "") -> void:
		id = p_id
		name = p_name
		arguments_raw = p_args

	func arguments() -> Dictionary:
		if arguments_raw == "":
			return {}
		var parsed = JSON.parse_string(arguments_raw)
		if parsed == null or not (parsed is Dictionary):
			return {}
		return parsed

	# True only when arguments_raw is a real JSON parse failure (not empty, not valid).
	func args_malformed() -> bool:
		var raw := arguments_raw.strip_edges()
		if raw == "" or raw == "{}":
			return false
		var parsed = JSON.parse_string(raw)
		return parsed == null or not (parsed is Dictionary)

	func clone():
		return ToolCall.new(id, name, arguments_raw)

class ToolResult:
	extends RefCounted
	var content: String
	var is_error: bool
	var data: Dictionary

	func _init(p_content: String = "", p_err: bool = false, p_data: Dictionary = {}) -> void:
		content = p_content
		is_error = p_err
		data = p_data

class ResponseChunk:
	extends RefCounted
	var delta_text: String
	var tool_call_index: int = -1
	var tool_call_id_delta: String
	var tool_call_name_delta: String
	var tool_call_args_delta: String
	var finish_reason: String

	func _init() -> void:
		delta_text = ""
		tool_call_id_delta = ""
		tool_call_name_delta = ""
		tool_call_args_delta = ""
		finish_reason = ""

class Usage:
	extends RefCounted
	var prompt_tokens: int
	var completion_tokens: int
	var total_tokens: int

	func _init(p: int = 0, c: int = 0) -> void:
		prompt_tokens = p
		completion_tokens = c
		total_tokens = p + c

	func to_dict() -> Dictionary:
		return {"prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens, "total_tokens": total_tokens}
