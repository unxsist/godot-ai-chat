class_name AiCopilotCompactor
extends RefCounted

const TAIL_KEEP := 6

func should_compact(history: Array, threshold: float, context_window: int) -> bool:
	var est := _estimate_tokens(history)
	var cap := int(context_window * threshold)
	return est > cap

func _estimate_tokens(history: Array) -> int:
	var chars := 0
	for m in history:
		if m is AiCopilotLLMTypes.Message:
			var c = m.content
			if typeof(c) == TYPE_STRING:
				chars += c.length()
			elif c is Array:
				for part in c:
					if typeof(part) == TYPE_DICTIONARY:
						if part.get("type") == "text":
							chars += String(part.get("text", "")).length()
						elif part.get("type") == "image_url":
							chars += 512
			for tc in m.tool_calls:
				chars += tc.arguments_raw.length() + tc.name.length()
	return int(chars / 4.0)

func compact(history: Array, client: AiCopilotLLMClient, model: String) -> Array:
	if history.size() <= TAIL_KEEP + 2:
		return history
	var to_summarize: Array = history.slice(0, history.size() - TAIL_KEEP)
	var keep_tail: Array = history.slice(history.size() - TAIL_KEEP, history.size())
	var important: PackedStringArray = []
	for m in to_summarize:
		if m is AiCopilotLLMTypes.Message and m.role == "tool" and m.name in ["write_file", "edit_file", "rename_file", "delete_file"]:
			important.append("%s: %s" % [m.name, str(m.content)])
	var summary_prompt: String = "Summarize the following developer conversation in concise bullet points, preserving key file writes/edits.\n\nConversation:\n" + _text_dump(to_summarize) + "\n\nImportant tool results:\n" + "\n".join(important)
	var summary_response: AiCopilotLLMTypes.Message = await client.send_messages_batch([
		{"role":"system","content":"You summarize coding sessions."},
		{"role":"user","content":summary_prompt}
	], {"model": model, "temperature": 0.0, "max_tokens": 1500})
	var new_history: Array = []
	new_history.append(AiCopilotLLMTypes.Message.new("system", "[compacted summary]\n" + str(summary_response.content) + "\n\n[important preserved tool results]\n" + "\n".join(important)))
	new_history.append_array(keep_tail)
	return new_history

func _text_dump(history: Array) -> String:
	var out := PackedStringArray()
	for m in history:
		if m is AiCopilotLLMTypes.Message:
			out.append("[%s] %s" % [m.role, str(m.content)])
			for tc in m.tool_calls:
				out.append("  → %s(%s)" % [tc.name, tc.arguments_raw])
	return "\n".join(out)
