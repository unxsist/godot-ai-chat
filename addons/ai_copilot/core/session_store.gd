class_name AiCopilotSessionStore
extends RefCounted

static func save(history: Array) -> void:
	DirAccess.make_dir_recursive_absolute(AiCopilotConst.USER_DIR)
	var payload: Array = []
	for m in history:
		if m is AiCopilotLLMTypes.Message:
			if m.content is Array:
				payload.append({"role": m.role, "content": "[image removed for persistence]"})
			else:
				payload.append(m.to_dict())
	var f := FileAccess.open(AiCopilotConst.SESSION_FILE, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(payload, "  "))
	f.flush()
	f.close()

static func load_history() -> Array:
	if not FileAccess.file_exists(AiCopilotConst.SESSION_FILE): return []
	var content := FileAccess.get_file_as_string(AiCopilotConst.SESSION_FILE)
	if content == "": return []
	var parsed = JSON.parse_string(content)
	if parsed == null or not (parsed is Array): return []
	var out: Array = []
	for d in parsed:
		if d is Dictionary:
			out.append(AiCopilotLLMTypes.Message.from_dict(d))
	return out

static func clear() -> void:
	if FileAccess.file_exists(AiCopilotConst.SESSION_FILE):
		DirAccess.remove_absolute(AiCopilotConst.SESSION_FILE)
