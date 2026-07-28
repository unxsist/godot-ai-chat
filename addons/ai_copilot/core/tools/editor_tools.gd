class_name AiCopilotEditorTools
extends RefCounted

static var _last_opened_path := ""
static var _settings: AiCopilotSettings = null

static func register_all(registry: AiCopilotToolRegistry, settings: AiCopilotSettings = null) -> void:
	_settings = settings
	registry.register_tool("get_open_scenes", "List currently open tabs in the editor (scripts and scenes).", {"type":"object","properties":{},"required":[]}, Callable(AiCopilotEditorTools, "_get_open_scenes"), false)
	registry.register_tool("open_script", "Open a script at the given path in the editor.", {"type":"object","properties":{"path":{"type":"string","description":"res:// path to open"}},"required":["path"]}, Callable(AiCopilotEditorTools, "_open_script"), false)
	# Only expose viewport_screenshot when a vision-capable model is configured;
	# otherwise a non-multimodal model would call it, get an image it can't read, and loop.
	if _vision_available():
		registry.register_tool("viewport_screenshot", "Capture the editor viewport as a PNG image for you to visually inspect. Only available because a vision model is configured.", {"type":"object","properties":{},"required":[]}, Callable(AiCopilotEditorTools, "_viewport_screenshot"), false)
	registry.register_tool("check_scripts", "Compile-check GDScript files for parse/compile errors. Pass a single 'path' to check one file, or omit to check every .gd script in the project. Returns 'OK: no errors' or a list of files with their error messages. ALWAYS call this after writing or editing scripts and fix any reported errors before finishing.", {"type":"object","properties":{"path":{"type":"string","description":"Optional single res:// .gd path. Omit to check all project scripts."}},"required":[]}, Callable(AiCopilotEditorTools, "_check_scripts"), false)

static func _vision_available() -> bool:
	if _settings == null:
		return false
	return String(_settings.get_value("vision_model")).strip_edges() != ""


static func _get_open_scenes(_call, _args) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var se := EditorInterface.get_script_editor()
	var lines := PackedStringArray()
	if se:
		var scripts: Array = se.get_open_scripts()
		for s in scripts:
			if s is Script and s.resource_path.begins_with("res://"):
				lines.append(s.resource_path)
	var sroot := EditorInterface.get_edited_scene_root()
	if sroot and sroot.scene_file_path != "":
		lines.append(sroot.scene_file_path)
	return AiCopilotLLMTypes.ToolResult.new("\n".join(lines), false)

static func _open_script(_call, args) -> AiCopilotLLMTypes.ToolResult:
	var path := String(args.get("path", ""))
	var cpath := AiCopilotToolPath.canonicalize_in_res(path)
	if cpath == "": return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if AiCopilotToolPath.is_self_blocked(cpath): return AiCopilotLLMTypes.ToolResult.new("plugin source is off-limits", true)
	open_resource_at(cpath)
	return AiCopilotLLMTypes.ToolResult.new("opened %s" % cpath, false)

static var _pending_screenshot_b64 := ""

static func _viewport_screenshot(_call, _args) -> AiCopilotLLMTypes.ToolResult:
	if not _vision_available():
		return AiCopilotLLMTypes.ToolResult.new("viewport_screenshot is unavailable: no vision model configured. Do not call it again.", true)
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var vp := EditorInterface.get_editor_main_screen() as Control
	if vp == null: return AiCopilotLLMTypes.ToolResult.new("cannot locate editor viewport", true)
	var tex: ViewportTexture = vp.get_viewport().get_texture()
	if tex == null: return AiCopilotLLMTypes.ToolResult.new("no viewport texture", true)
	var img := tex.get_image() as Image
	if img == null: return AiCopilotLLMTypes.ToolResult.new("viewport image empty", true)
	var scaled := Image.new()
	scaled.copy_from(img)
	if img.get_width() > 1024:
		scaled.resize(1024, int(float(img.get_height()) * 1024.0 / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	var png := scaled.save_png_to_buffer()
	var b64 := Marshalls.raw_to_base64(png)
	_pending_screenshot_b64 = b64
	return AiCopilotLLMTypes.ToolResult.new("[screenshot attached (%d bytes)]" % png.size(), false, {"_image_b64": b64})

static func open_resource_at(path: String) -> void:
	if not Engine.is_editor_hint(): return
	_last_opened_path = path
	if path.ends_with(".gd"):
		var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
		if script and script is Script:
			EditorInterface.edit_script(script)
	elif path.ends_with(".tscn") or path.ends_with(".scn"):
		EditorInterface.open_scene_from_path(path)
	elif path.ends_with(".tres") or path.ends_with(".res"):
		var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if r is Resource:
			EditorInterface.edit_resource(r)

static func open_script_at(path: String, line: int = 0) -> void:
	if not Engine.is_editor_hint(): return
	var s := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
	if s and s is Script:
		EditorInterface.edit_script(s)
		if line > 0:
			var se := EditorInterface.get_script_editor()
			if se and se.get_current_editor():
				var te: TextEdit = se.get_current_editor().get_text_editor()
				te.set_caret_line(line)

static func get_pending_screenshot() -> String:
	var b := _pending_screenshot_b64
	_pending_screenshot_b64 = ""
	return b

static func _check_scripts(_call, args) -> AiCopilotLLMTypes.ToolResult:
	var single := String(args.get("path", ""))
	var paths: PackedStringArray = []
	if single != "":
		var cpath := AiCopilotToolPath.canonicalize_in_res(single)
		if cpath == "":
			return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
		if not cpath.ends_with(".gd"):
			return AiCopilotLLMTypes.ToolResult.new("not a .gd script: %s" % cpath, true)
		paths.append(cpath)
	else:
		_collect_scripts("res://", paths)

	if paths.is_empty():
		return AiCopilotLLMTypes.ToolResult.new("OK: no scripts found to check", false)

	var errors: PackedStringArray = []
	for p in paths:
		var err := _compile_check(p)
		if err != "":
			errors.append(err)

	if errors.is_empty():
		return AiCopilotLLMTypes.ToolResult.new("OK: no errors in %d script(s)" % paths.size(), false)
	return AiCopilotLLMTypes.ToolResult.new("Found errors in %d script(s). Fix these exact lines, then run check_scripts again:\n\n%s" % [errors.size(), "\n\n".join(errors)], true)

# Runs the CURRENT editor binary (OS.get_executable_path) headless in --check-only
# mode to get the real parser error message + line number. Fully self-contained:
# it reuses the already-running Godot, no external tools.
static func _compile_check(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "%s: file does not exist" % path
	var exe := OS.get_executable_path()
	if exe == "" or not Engine.is_editor_hint():
		return _compile_check_fallback(path)
	var project_dir := ProjectSettings.globalize_path("res://")
	var output: Array = []
	OS.execute(exe, ["--headless", "--path", project_dir, "--check-only", "--script", path], output, true, true)
	var text := "\n".join(output)
	var diag := _parse_diagnostics(text, path)
	if diag != "":
		return "%s:\n%s" % [path, diag]
	return ""

static func _parse_diagnostics(text: String, path: String) -> String:
	var lines := text.split("\n", false)
	var msgs: PackedStringArray = []
	var i := 0
	while i < lines.size():
		var line := lines[i].strip_edges()
		if line.begins_with("SCRIPT ERROR:") or (line.begins_with("ERROR:") and line.find("Parse error") != -1):
			var msg := line.replace("SCRIPT ERROR:", "").strip_edges()
			# next line usually holds `at: res://file.gd:LINE`
			var loc := ""
			if i + 1 < lines.size():
				var at_line := lines[i + 1].strip_edges()
				var m := at_line.find(path + ":")
				if m != -1:
					var after := at_line.substr(m + path.length() + 1)
					var num := ""
					for ch in after:
						if ch >= "0" and ch <= "9":
							num += ch
						else:
							break
					if num != "":
						loc = " (line %s)" % num
			if msg != "" and msg.find("Failed to load") == -1:
				msgs.append("  - %s%s" % [msg, loc])
		i += 1
	if msgs.is_empty():
		return ""
	return "\n".join(msgs)

# Fallback when we can't run the editor binary: coarse reload() check.
static func _compile_check_fallback(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	var gd := GDScript.new()
	gd.source_code = src
	var result := gd.reload(true)
	if result != OK:
		return "%s: parse/compile error (code %d). Re-read the file and check syntax, type inference on ':=', and undeclared identifiers." % [path, result]
	return ""

static func _collect_scripts(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null: return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == ".." or n.begins_with(".") or n == ".godot" or n == ".git":
			n = dir.get_next()
			continue
		var full := dir_path.trim_suffix("/") + "/" + n
		if AiCopilotToolPath.is_self_blocked(full):
			n = dir.get_next()
			continue
		if dir.current_is_dir():
			_collect_scripts(full, out)
		elif n.ends_with(".gd"):
			out.append(full)
		n = dir.get_next()
	dir.list_dir_end()

