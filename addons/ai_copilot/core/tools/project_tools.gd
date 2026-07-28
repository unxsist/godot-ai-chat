class_name AiCopilotProjectTools
extends RefCounted

static func register_all(registry: AiCopilotToolRegistry) -> void:
	registry.register_tool(
		"project_get_setting",
		"Read a project setting from project.godot by its property path (e.g. 'application/config/name', 'display/window/size/viewport_width'). Returns the current value or 'null' if unset.",
		{"type":"object","properties":{
			"setting":{"type":"string","description":"ProjectSettings property path"}
		},"required":["setting"]},
		Callable(AiCopilotProjectTools, "_get_setting"), false)
	registry.register_tool(
		"project_set_setting",
		"Safely change a project setting in project.godot via Godot's ProjectSettings API (cannot corrupt the file). Value is parsed as JSON when possible (numbers, bools, strings, arrays), otherwise treated as a string. Saves project.godot afterward. Use this instead of editing project.godot as text.",
		{"type":"object","properties":{
			"setting":{"type":"string","description":"ProjectSettings property path, e.g. run/main_scene"},
			"value":{"type":"string","description":"New value. JSON-parsed if valid (e.g. 800, true, \"res://x.tscn\"), else used as a plain string."}
		},"required":["setting","value"]},
		Callable(AiCopilotProjectTools, "_set_setting"), true)
	registry.register_tool(
		"project_add_input_action",
		"Add or update an input action (input map) in project.godot safely. Provide the action name and a list of key names (e.g. [\"W\",\"UP\"]). Existing events for the action are replaced. Saves project.godot.",
		{"type":"object","properties":{
			"action":{"type":"string","description":"Action name, e.g. move_up"},
			"keys":{"type":"array","description":"Key names like W, S, UP, DOWN, SPACE, ENTER, ESCAPE","items":{"type":"string"}},
			"deadzone":{"type":"number","description":"Deadzone (default 0.5)","default":0.5}
		},"required":["action","keys"]},
		Callable(AiCopilotProjectTools, "_add_input_action"), true)

static func _get_setting(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var key := String(args.get("setting", ""))
	if key == "":
		return AiCopilotLLMTypes.ToolResult.new("setting is required", true)
	if not ProjectSettings.has_setting(key):
		return AiCopilotLLMTypes.ToolResult.new("%s = null (not set)" % key, false)
	var v = ProjectSettings.get_setting(key)
	return AiCopilotLLMTypes.ToolResult.new("%s = %s" % [key, str(v)], false)

static func _set_setting(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint():
		return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var key := String(args.get("setting", ""))
	var raw := String(args.get("value", ""))
	if key == "":
		return AiCopilotLLMTypes.ToolResult.new("setting is required", true)
	if key.begins_with("editor_plugins/") or key.begins_with("autoload/AiCopilot"):
		return AiCopilotLLMTypes.ToolResult.new("that setting is managed by the plugin and can't be changed", true)
	var value = _coerce(raw)
	ProjectSettings.set_setting(key, value)
	var err := ProjectSettings.save()
	if err != OK:
		return AiCopilotLLMTypes.ToolResult.new("failed to save project settings (err %d)" % err, true)
	return AiCopilotLLMTypes.ToolResult.new("set %s = %s and saved project.godot" % [key, str(value)], false)

static func _add_input_action(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint():
		return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var action := String(args.get("action", ""))
	var keys = args.get("keys", [])
	var deadzone := float(args.get("deadzone", 0.5))
	if action == "":
		return AiCopilotLLMTypes.ToolResult.new("action is required", true)
	if not (keys is Array) or keys.is_empty():
		return AiCopilotLLMTypes.ToolResult.new("keys must be a non-empty array", true)
	var events: Array = []
	var bad: PackedStringArray = []
	for k in keys:
		var kc := OS.find_keycode_from_string(str(k))
		if kc == KEY_NONE:
			bad.append(str(k))
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = kc
		events.append(ev)
	if events.is_empty():
		return AiCopilotLLMTypes.ToolResult.new("no valid keys (unrecognized: %s). Use names like W, UP, SPACE, ENTER." % ", ".join(bad), true)
	var setting := "input/" + action
	ProjectSettings.set_setting(setting, {"deadzone": deadzone, "events": events})
	var err := ProjectSettings.save()
	if err != OK:
		return AiCopilotLLMTypes.ToolResult.new("failed to save project settings (err %d)" % err, true)
	var note := ""
	if bad.size() > 0:
		note = " (ignored unrecognized keys: %s)" % ", ".join(bad)
	return AiCopilotLLMTypes.ToolResult.new("added input action '%s' with %d key(s)%s" % [action, events.size(), note], false)

static func _coerce(raw: String):
	var s := raw.strip_edges()
	if s == "": return ""
	var parsed = JSON.parse_string(s)
	if parsed != null:
		return parsed
	# JSON.parse_string returns null for the literal "null" too; treat that as null
	if s == "null":
		return null
	return raw
