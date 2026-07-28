class_name AiCopilotLogger
extends RefCounted

static var _verbose: bool = true

static func set_verbose(v: bool) -> void: _verbose = v

static func info(msg: String) -> void: _write("INFO", msg)
static func warn(msg: String) -> void: _write("WARN", msg)
static func err(msg: String) -> void: _write("ERR ", msg)
static func debug(msg: String) -> void: if _verbose: _write("DBG ", msg)

static func _write(level: String, msg: String) -> void:
	var ts := Time.get_datetime_string_from_system(false, true)
	var safe := _redact(msg)
	var line := "%s | %s | %s" % [ts, level, safe]
	DirAccess.make_dir_recursive_absolute(AiCopilotConst.LOG_DIR)
	var fname := AiCopilotConst.LOG_DIR + "/log_%s.log" % Time.get_date_string_from_system().replace(":", "")
	var mode := FileAccess.WRITE
	if FileAccess.file_exists(fname):
		mode = FileAccess.READ_WRITE
	var f := FileAccess.open(fname, mode)
	if f == null: return
	f.seek_end()
	f.store_line(line)
	f.flush()
	f.close()

static func _redact(s: String) -> String:
	var out := s
	var re := RegEx.new()
	re.compile("(?i)(Authorization:\\s*Bearer\\s+)([A-Za-z0-9_\\-\\.]{6,})")
	out = re.sub(out, "$1[REDACTED]", true)
	re.compile("(?i)(\"api_?key\"\\s*:\\s*\")([^\"]+)(\")")
	out = re.sub(out, "$1[REDACTED]$3", true)
	return out

static func log_tool_call(call: AiCopilotLLMTypes.ToolCall) -> void:
	info("TOOL_CALL %s args=%s" % [call.name, _redact(call.arguments_raw.left(512))])

static func log_tool_result(result: AiCopilotLLMTypes.ToolResult) -> void:
	info("TOOL_RESULT err=%s content=%s" % [result.is_error, str(result.content).left(512)])
