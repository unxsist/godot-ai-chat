class_name AiCopilotConst

const PLUGIN_NAME := "AI Copilot"
const PLUGIN_VERSION := "1.0.1"
const PLUGIN_DIR := "res://addons/ai_copilot/"
const USER_DIR := "user://ai_copilot/"
const SESSION_FILE := "user://ai_copilot/session.json"
const SETTINGS_FILE := "user://ai_copilot/settings.cfg"
const SALT_FILE := "user://ai_copilot/.salt"
const LOG_DIR := "user://ai_copilot/"

const DEFAULT_ENDPOINT := "https://api.fireworks.ai/inference/v1"
const CHAT_COMPLETIONS_PATH := "/chat/completions"
const PROVIDER_NAME := "fireworks"

# Hidden safety cap on the agentic loop. The loop normally ends when the model
# returns a text-only response (no tool calls); this only prevents runaway loops.
const SAFETY_STEP_CAP := 50
const MAX_STEPS_PROMPT := "You have reached the maximum number of tool-call steps for this task. Do NOT call any more tools. Reply with text only: briefly summarize what you accomplished and list anything still remaining."
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
