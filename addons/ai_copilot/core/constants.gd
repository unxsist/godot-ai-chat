class_name AiCopilotConst

const PLUGIN_NAME := "AI Copilot"
const PLUGIN_VERSION := "0.1.0"
const PLUGIN_DIR := "res://addons/ai_copilot/"
const USER_DIR := "user://ai_copilot/"
const SESSION_FILE := "user://ai_copilot/session.json"
const SETTINGS_FILE := "user://ai_copilot/settings.cfg"
const SALT_FILE := "user://ai_copilot/.salt"
const LOG_DIR := "user://ai_copilot/"

const DEFAULT_ENDPOINT := "https://api.fireworks.ai/inference/v1"
const CHAT_COMPLETIONS_PATH := "/chat/completions"
const PROVIDER_NAME := "fireworks"

const MAX_STEPS_DEFAULT := 20
const COMPACT_THRESHOLD_DEFAULT := 0.7
const LARGE_FILE_BYTES := 200 * 1024
const PATH_SANDOX_ROOT := "res://"
const SELF_BLOCK_PATH_PREFIX := "res://addons/ai_copilot/"

const HTTP_TIMEOUT_MS := 120_000

const BANNED_SHELL_PATTERNS := [
	"rm -rf /",
	"rm -rf ~",
	"rm -rf /*",
	"rm -rf ~/*",
	":(){:|:&};:",
	"mkfs",
	"dd if=/dev/zero",
	"shutdown",
	"halt -p",
]
