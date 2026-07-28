class_name AiCopilotPlanTools
extends RefCounted

static var _todos: Array = []

static func register_all(registry: AiCopilotToolRegistry) -> void:
	registry.register_tool(
		"todowrite",
		"Track a plan for multi-step work. Pass the full todo list each time (replaces the previous list). Use it for tasks with 3+ steps: write the plan up front, mark exactly one item in_progress, and update statuses as you go. Skip it for trivial single-step requests.",
		{"type":"object","properties":{
			"todos":{"type":"array","description":"The full, updated todo list","items":{"type":"object","properties":{
				"content":{"type":"string","description":"What the step does"},
				"status":{"type":"string","enum":["pending","in_progress","completed","cancelled"]}
			},"required":["content","status"]}}
		},"required":["todos"]},
		Callable(AiCopilotPlanTools, "_todowrite"), false)

static func _todowrite(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var todos = args.get("todos", [])
	if not (todos is Array):
		return AiCopilotLLMTypes.ToolResult.new("todos must be an array", true)
	_todos = todos
	var lines := PackedStringArray()
	var glyphs := {"pending": "[ ]", "in_progress": "[~]", "completed": "[x]", "cancelled": "[-]"}
	for t in todos:
		if t is Dictionary:
			var status := String(t.get("status", "pending"))
			var g: String = glyphs.get(status, "[ ]")
			lines.append("%s %s" % [g, str(t.get("content", ""))])
	return AiCopilotLLMTypes.ToolResult.new("Plan updated:\n" + "\n".join(lines), false, {"todos": _todos})

static func get_todos() -> Array:
	return _todos
