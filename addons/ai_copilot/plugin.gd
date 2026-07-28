@tool
class_name AiCopilotPlugin
extends EditorPlugin

var _panel: AiCopilotChatPanel = null

func _enter_tree() -> void:
	_ensure_user_dir()
	add_autoload_singleton("AiCopilot", "res://addons/ai_copilot/api.gd")
	_panel = preload("res://addons/ai_copilot/ui/chat_panel.tscn").instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BR, _panel)
	_panel.name = "AI Copilot"
	print("[ai_copilot] plugin enter_tree v%s" % AiCopilotConst.PLUGIN_VERSION)

func _exit_tree() -> void:
	if _panel:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null
	remove_autoload_singleton("AiCopilot")
	print("[ai_copilot] plugin exit_tree")

func _ensure_user_dir() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		push_error("[ai_copilot] cannot open user://")
		return
	if not d.dir_exists("ai_copilot"):
		var err := d.make_dir_recursive("ai_copilot")
		if err != OK:
			push_error("[ai_copilot] cannot create user://ai_copilot (%d)" % err)
