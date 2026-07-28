class_name AiCopilotShellTools
extends RefCounted

# Commands the agent must NEVER run — it should use in-editor tools instead.
const GODOT_LAUNCH_PATTERNS := [
	"--path", "--editor", "godot.app", "open -a godot",
]

# Tokens that would let a command escape the project directory.
const ESCAPE_PATTERNS := [
	"cd ", "cd\t", "pushd", "popd", "chdir",
	"..",            # any parent-directory traversal
	"~",             # home directory
	"$home", "${home}", "$pwd",
]

static func register_all(registry: AiCopilotToolRegistry) -> void:
	registry.register_tool(
		"run_command",
		"Run a shell command INSIDE the project folder for build/tooling tasks (git, ls, cat, mkdir, formatters, etc.). The command is confined to the project directory: absolute paths, '..', '~', and directory-changing commands (cd/pushd) are rejected. NEVER use this to launch Godot/the editor/the game — use run_project/stop_project instead. Returns combined stdout+stderr.",
		{"type":"object","properties":{"command":{"type":"string","description":"Shell command line, using only project-relative paths. No cd, no absolute paths, no '..'"}},"required":["command"]},
		Callable(AiCopilotShellTools, "_run"), true)

static func _run(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var cmd := String(args.get("command", ""))
	if cmd.strip_edges() == "":
		return AiCopilotLLMTypes.ToolResult.new("command is required", true)

	var banned := _is_banned(cmd)
	if banned != "":
		return AiCopilotLLMTypes.ToolResult.new("command rejected: matched destructive blocklist '%s'" % banned, true)

	var godot := _is_godot_launch(cmd)
	if godot != "":
		return AiCopilotLLMTypes.ToolResult.new("Refused: never launch Godot or the game via run_command (matched '%s'). Use run_project / stop_project — those run inside this editor." % godot, true)

	var escape := _is_escape(cmd)
	if escape != "":
		return AiCopilotLLMTypes.ToolResult.new("Refused: run_command is confined to the project folder. Remove '%s' — use only project-relative paths (no cd, no absolute paths, no '..', no '~')." % escape, true)

	# Absolute paths anywhere in the command are rejected outright.
	if _has_absolute_path(cmd):
		return AiCopilotLLMTypes.ToolResult.new("Refused: absolute paths are not allowed. Use project-relative paths only (the command runs in the project root).", true)

	# cwd is ALWAYS the project root; never overridable.
	var project_root := ProjectSettings.globalize_path("res://")
	if not DirAccess.dir_exists_absolute(project_root):
		return AiCopilotLLMTypes.ToolResult.new("project root not found", true)

	# Run confined: force cwd to the project root via a wrapper that cd's in first.
	# The command itself has already been vetted to contain no cd/absolute/.. tokens.
	var wrapped := "cd %s && ( %s )" % [_shell_quote(project_root), cmd]
	var output: Array = []
	var err := OS.execute("sh", ["-c", wrapped], output, true, true)
	var text := ""
	if output.size() > 0:
		text = "\n".join(output)
	if text.strip_edges() == "":
		text = "(no output, exit=%d)" % err
	return AiCopilotLLMTypes.ToolResult.new(text, err != 0, {"cwd": project_root, "exit_code": err})

static func _is_banned(cmd: String) -> String:
	var lower := cmd.to_lower()
	for p in AiCopilotConst.BANNED_SHELL_PATTERNS:
		if lower.find(p) != -1: return p
	return ""

static func _is_godot_launch(cmd: String) -> String:
	var lower := cmd.to_lower()
	for p in GODOT_LAUNCH_PATTERNS:
		if lower.find(p) != -1: return p
	# Match `godot` / `godot4` / `godot.exe` only when it's the command being run
	# (start of line or right after a shell separator), not inside a filename.
	var re := RegEx.new()
	re.compile("(?:^|[;&|]|&&|\\|\\|)\\s*\\.?/?godot[0-9]*(?:\\.exe)?\\b")
	if re.search(lower) != null:
		return "godot"
	return ""

static func _is_escape(cmd: String) -> String:
	var lower := cmd.to_lower()
	for p in ESCAPE_PATTERNS:
		if lower.find(p) != -1: return p
	return ""

# Detect absolute paths: a token starting with "/" (Unix) or a Windows drive like "C:\".
static func _has_absolute_path(cmd: String) -> bool:
	var re := RegEx.new()
	# leading / after start or whitespace, or a drive letter path
	re.compile("(^|[\\s=:\"'])(/|[A-Za-z]:[\\\\/])")
	return re.search(cmd) != null

static func _shell_quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"
