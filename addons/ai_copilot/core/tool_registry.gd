class_name AiCopilotToolRegistry
extends RefCounted

signal tool_registered(name: String)
signal tool_unregistered(name: String)

class ToolDef:
	extends RefCounted
	var name: String
	var description: String
	var parameters: Dictionary
	var executor: Callable
	var mutating: bool

	func _init(n: String, d: String, p: Dictionary, e: Callable, m: bool = false) -> void:
		name = n
		description = d
		parameters = p
		executor = e
		mutating = m

var _tools: Dictionary = {}

func register_tool(name: String, description: String, parameters: Dictionary, executor: Callable, mutating: bool = false) -> bool:
	if _tools.has(name):
		push_error("[ai_copilot] tool already registered: %s" % name)
		return false
	if not _validate_name(name):
		push_error("[ai_copilot] invalid tool name '%s': alnum + underscore, max 64 chars" % name)
		return false
	_tools[name] = ToolDef.new(name, description, parameters, executor, mutating)
	tool_registered.emit(name)
	return true

func unregister_tool(name: String) -> void:
	if _tools.erase(name):
		tool_unregistered.emit(name)

func get_tool(name: String) -> ToolDef:
	return _tools.get(name, null)

func list_names() -> PackedStringArray:
	return PackedStringArray(_tools.keys())

func to_openai_tools() -> Array:
	var arr := []
	for name in _tools:
		var def: ToolDef = _tools[name]
		arr.append({
			"type": "function",
			"function": {
				"name": def.name,
				"description": def.description,
				"parameters": def.parameters,
			}
		})
	return arr

func execute(call: AiCopilotLLMTypes.ToolCall) -> AiCopilotLLMTypes.ToolResult:
	var def: ToolDef = _tools.get(call.name, null)
	if def == null:
		return AiCopilotLLMTypes.ToolResult.new("unknown tool: %s" % call.name, true)
	var args := call.arguments()
	var result: AiCopilotLLMTypes.ToolResult = null
	var runner := func():
		return def.executor.call(call, args)
	result = runner.call()
	if result == null:
		return AiCopilotLLMTypes.ToolResult.new("tool returned null: %s" % call.name, true)
	return result

func _validate_name(name: String) -> bool:
	if name.length() == 0 or name.length() > 64:
		return false
	for c in name:
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "."
		if not ok:
			return false
	return true
