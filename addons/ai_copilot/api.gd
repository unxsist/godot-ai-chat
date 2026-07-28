class_name AiCopilotAPI
extends Node

var registry: AiCopilotToolRegistry = null

func _enter_tree() -> void:
	registry = AiCopilotToolRegistry.new()
	Engine.set_meta("AiCopilotAPI", self)

func _exit_tree() -> void:
	Engine.remove_meta("AiCopilotAPI")
