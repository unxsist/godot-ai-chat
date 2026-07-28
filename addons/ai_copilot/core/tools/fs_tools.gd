class_name AiCopilotFSTools
extends RefCounted

const READ_LIMIT := AiCopilotConst.LARGE_FILE_BYTES
const READ_DEFAULT_LINES := 2000
const MAX_LINE_LEN := 2000

static func register_all(registry: AiCopilotToolRegistry) -> void:
	registry.register_tool(
		"read_file",
		"Read a UTF-8 text file. Returns content with line numbers (format: `<line>: <text>`). Reads up to 2000 lines from the start by default; use offset (1-based line) and limit to page through larger files. Prefer grep to locate content in big files before reading.",
		{"type":"object","properties":{
			"path":{"type":"string","description":"res:// path or project-relative path"},
			"offset":{"type":"integer","description":"1-based line to start from","default":1},
			"limit":{"type":"integer","description":"Max lines to read","default":2000}
		},"required":["path"]},
		Callable(AiCopilotFSTools, "_read_file"), false)
	registry.register_tool(
		"glob",
		"Find files by glob pattern (e.g. `**/*.gd`, `res://scenes/*.tscn`). Fast; returns matching paths one per line. Use this to locate files by name/type instead of listing directories.",
		{"type":"object","properties":{
			"pattern":{"type":"string","description":"Glob pattern, e.g. **/*.gd or *.tscn"},
			"path":{"type":"string","description":"Directory to search under","default":"res://"},
			"limit":{"type":"integer","description":"Max results","default":200}
		},"required":["pattern"]},
		Callable(AiCopilotFSTools, "_glob"), false)
	registry.register_tool(
		"list_files",
		"List entries in one directory (names + trailing / for dirs). Use glob to search by pattern or grep to search contents; only use list_files to inspect a single directory's immediate contents.",
		{"type":"object","properties":{
			"path":{"type":"string","description":"res:// path","default":"res://"},
			"recursive":{"type":"boolean","description":"Walk all children","default":false}
		},"required":[]},
		Callable(AiCopilotFSTools, "_list_files"), false)
	registry.register_tool(
		"grep",
		"Search file contents by regex (ripgrep). Returns matches grouped by file with line numbers. Use `include` to filter by file glob (e.g. *.gd), `path` to narrow the directory. This is the fastest way to find code, symbols, or text — prefer it over reading many files.",
		{"type":"object","properties":{
			"pattern":{"type":"string","description":"Regex pattern to search for in file contents"},
			"path":{"type":"string","description":"Directory to search under","default":"res://"},
			"include":{"type":"string","description":"File glob to include, e.g. *.gd or *.{tscn,gd}"},
			"limit":{"type":"integer","description":"Max matches","default":200}
		},"required":["pattern"]},
		Callable(AiCopilotFSTools, "_grep"), false)
	registry.register_tool(
		"write_file",
		"Create or overwrite a file with the given UTF-8 text. Provide the complete file content. Use edit_file for small changes to existing files. Refuses paths outside res:// and project.godot.",
		{"type":"object","properties":{
			"path":{"type":"string","description":"Target res:// path"},
			"content":{"type":"string","description":"Full text content to write"}
		},"required":["path","content"]},
		Callable(AiCopilotFSTools, "_write_file"), true)
	registry.register_tool(
		"edit_file",
		"Replace exact text in one file. old_string must match exactly (including whitespace/indentation) and be unique unless replace_all=true. To make a match unique, include surrounding context lines. Prefer read_file first so you copy the text verbatim.",
		{"type":"object","properties":{
			"path":{"type":"string","description":"Target res:// path"},
			"old_string":{"type":"string","description":"Exact text to find (copy verbatim, including indentation)"},
			"new_string":{"type":"string","description":"Replacement text (must differ from old_string)"},
			"replace_all":{"type":"boolean","description":"Replace every occurrence","default":false}
		},"required":["path","old_string","new_string"]},
		Callable(AiCopilotFSTools, "_edit_file"), true)
	registry.register_tool(
		"delete_file",
		"Delete a file. Refuses paths outside res:// and inside the plugin's addon directory.",
		{"type":"object","properties":{"path":{"type":"string","description":"res:// path of file to delete"}},"required":["path"]},
		Callable(AiCopilotFSTools, "_delete_file"), true)
	registry.register_tool(
		"rename_file",
		"Rename or move a file within res://. Refreshes the editor filesystem afterward.",
		{"type":"object","properties":{"src":{"type":"string"},"dst":{"type":"string"}},"required":["src","dst"]},
		Callable(AiCopilotFSTools, "_rename_file"), true)

# ---------- read ----------

static func _read_file(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var path_arg := String(args.get("path", ""))
	var offset := int(args.get("offset", 1))
	var limit := int(args.get("limit", READ_DEFAULT_LINES))
	if offset < 1: offset = 1
	if limit < 1: limit = READ_DEFAULT_LINES
	var cpath := AiCopilotToolPath.canonicalize_in_res(path_arg)
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project: %s" % path_arg, true)
	if AiCopilotToolPath.is_self_blocked(cpath):
		return AiCopilotLLMTypes.ToolResult.new("plugin source is off-limits", true)
	if not FileAccess.file_exists(cpath):
		return AiCopilotLLMTypes.ToolResult.new("file does not exist: %s. Use glob or grep to find the correct path." % cpath, true)
	var content := FileAccess.get_file_as_string(cpath)
	if content == "" and FileAccess.get_open_error() != OK:
		return AiCopilotLLMTypes.ToolResult.new("read error on %s" % cpath, true)
	var lines := content.split("\n")
	var total := lines.size()
	var start := offset - 1
	if start >= total:
		return AiCopilotLLMTypes.ToolResult.new("offset %d is past end of file (%d lines)" % [offset, total], true)
	var end := min(start + limit, total)
	var out := PackedStringArray()
	for i in range(start, end):
		var line := lines[i]
		if line.length() > MAX_LINE_LEN:
			line = line.substr(0, MAX_LINE_LEN) + "…"
		out.append("%d: %s" % [i + 1, line])
	var body := "\n".join(out)
	if end < total:
		body += "\n\n[showing lines %d-%d of %d. Use offset=%d to continue.]" % [offset, end, total, end + 1]
	return AiCopilotLLMTypes.ToolResult.new(body, false, {"path": cpath, "lines": total})

# ---------- glob ----------

static func _glob(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var pattern := String(args.get("pattern", ""))
	var path_arg := String(args.get("path", "res://"))
	var limit := int(args.get("limit", 200))
	if pattern == "":
		return AiCopilotLLMTypes.ToolResult.new("pattern is required", true)
	var cpath := AiCopilotToolPath.canonicalize_in_res(path_arg)
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	var regex := _glob_to_regex(pattern)
	var results: PackedStringArray = []
	_glob_walk(cpath, regex, results, limit)
	if results.is_empty():
		return AiCopilotLLMTypes.ToolResult.new("No files found matching %s" % pattern, false)
	return AiCopilotLLMTypes.ToolResult.new("\n".join(results), false, {"count": results.size()})

static func _glob_walk(dir_path: String, regex: RegEx, out: PackedStringArray, cap: int) -> void:
	if out.size() >= cap: return
	var dir := DirAccess.open(dir_path)
	if dir == null: return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n == "." or n == ".." or n.begins_with(".") or n == ".godot" or n == ".git":
			n = dir.get_next(); continue
		var full := dir_path.trim_suffix("/") + "/" + n
		if AiCopilotToolPath.is_self_blocked(full):
			n = dir.get_next(); continue
		if dir.current_is_dir():
			_glob_walk(full, regex, out, cap)
		elif regex.search(full) != null:
			out.append(full)
		if out.size() >= cap: return
		n = dir.get_next()
	dir.list_dir_end()

# Convert a glob (**, *, ?, {a,b}) to a RegEx that matches full res:// paths.
static func _glob_to_regex(glob: String) -> RegEx:
	var g := glob
	# strip a leading res:// so it matches against full paths flexibly
	g = g.trim_prefix("res://")
	var rx := ""
	var i := 0
	while i < g.length():
		var c := g[i]
		match c:
			"*":
				if i + 1 < g.length() and g[i + 1] == "*":
					rx += ".*"
					i += 1
				else:
					rx += "[^/]*"
			"?":
				rx += "[^/]"
			".":
				rx += "\\."
			"{":
				rx += "(?:"
			"}":
				rx += ")"
			",":
				rx += "|"
			"(", ")", "+", "^", "$", "|", "\\", "[", "]":
				rx += "\\" + c
			_:
				rx += c
		i += 1
	var re := RegEx.new()
	re.compile("(^|/)" + rx + "$")
	return re

# ---------- list_files ----------

static func _list_files(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var path_arg := String(args.get("path", "res://"))
	var recursive := bool(args.get("recursive", false))
	var cpath := AiCopilotToolPath.canonicalize_in_res(path_arg)
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project: %s" % path_arg, true)
	var dir := DirAccess.open(cpath)
	if dir == null:
		return AiCopilotLLMTypes.ToolResult.new("cannot open dir: %s" % cpath, true)
	var out := PackedStringArray()
	_list_inner(dir, cpath, recursive, out, 200)
	var content := "\n".join(out)
	if content.length() > 4000:
		content = content.substr(0, 4000) + "\n... (truncated; use glob to narrow)"
	return AiCopilotLLMTypes.ToolResult.new(content, false, {"path": cpath, "count": out.size()})

static func _list_inner(dir: DirAccess, base: String, recursive: bool, out: PackedStringArray, cap: int) -> void:
	if out.size() >= cap:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == ".." or name.begins_with("."):
			name = dir.get_next()
			continue
		if name == ".godot" or name == ".git" or name == ".DS_Store":
			name = dir.get_next()
			continue
		var is_dir := dir.current_is_dir()
		var full := base.trim_suffix("/") + "/" + name
		if AiCopilotToolPath.is_self_blocked(full):
			name = dir.get_next()
			continue
		out.append(full + ("/" if is_dir else ""))
		if is_dir and recursive:
			var sub := DirAccess.open(full)
			if sub != null:
				_list_inner(sub, full, recursive, out, cap)
		if out.size() >= cap:
			return
		name = dir.get_next()
	dir.list_dir_end()

# ---------- grep (ripgrep) ----------

static func _grep(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var pattern := String(args.get("pattern", ""))
	var path_arg := String(args.get("path", "res://"))
	var include := String(args.get("include", ""))
	var limit := int(args.get("limit", 200))
	if pattern == "":
		return AiCopilotLLMTypes.ToolResult.new("pattern is required", true)
	var cpath := AiCopilotToolPath.canonicalize_in_res(path_arg)
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return AiCopilotLLMTypes.ToolResult.new("invalid regex: %s" % pattern, true)
	var inc_regex: RegEx = null
	if include != "":
		inc_regex = _glob_to_regex(include)
	# collect matches grouped by file
	var by_file := {}
	var order: PackedStringArray = []
	var count := [0]
	_grep_walk(cpath, inc_regex, regex, by_file, order, count, limit)
	if count[0] == 0:
		return AiCopilotLLMTypes.ToolResult.new("No matches for %s" % pattern, false)
	var lines := PackedStringArray(["Found %d match(es):" % count[0]])
	for f in order:
		lines.append("")
		lines.append(f + ":")
		for l in by_file[f]:
			lines.append(l)
	return AiCopilotLLMTypes.ToolResult.new("\n".join(lines), false, {"count": count[0]})

static func _grep_walk(dir_path: String, inc_regex: RegEx, regex: RegEx, by_file: Dictionary, order: PackedStringArray, count: Array, cap: int) -> void:
	if count[0] >= cap: return
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
			_grep_walk(full, inc_regex, regex, by_file, order, count, cap)
		else:
			if inc_regex == null or inc_regex.search(full) != null:
				_grep_file(full, regex, by_file, order, count, cap)
		if count[0] >= cap: return
		n = dir.get_next()
	dir.list_dir_end()

static func _grep_file(file_path: String, regex: RegEx, by_file: Dictionary, order: PackedStringArray, count: Array, cap: int) -> void:
	if _looks_binary(file_path):
		return
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null: return
	var line_num := 0
	while not f.eof_reached() and count[0] < cap:
		var line := f.get_line()
		line_num += 1
		if regex.search(line) != null:
			var preview := line.strip_edges()
			if preview.length() > 300:
				preview = preview.substr(0, 300) + "…"
			if not by_file.has(file_path):
				by_file[file_path] = []
				order.append(file_path)
			by_file[file_path].append("  %d: %s" % [line_num, preview])
			count[0] += 1
	f.close()

static func _looks_binary(path: String) -> bool:
	for ext in [".png", ".jpg", ".jpeg", ".webp", ".import", ".ttf", ".otf", ".wav", ".ogg", ".mp3", ".res", ".scn", ".ctex", ".bin", ".exr", ".glb", ".gltf", ".zip"]:
		if path.ends_with(ext):
			return true
	return false

# ---------- write ----------

static func _write_file(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var cpath := AiCopilotToolPath.canonicalize_in_res(String(args.get("path", "")))
	var content := String(args.get("content", ""))
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if AiCopilotToolPath.is_self_blocked(cpath):
		return AiCopilotLLMTypes.ToolResult.new("plugin source is off-limits", true)
	if cpath == "res://project.godot":
		return AiCopilotLLMTypes.ToolResult.new("Cannot overwrite project.godot — it would corrupt the project.", true)
	_editor_save_all()
	AiCopilotToolPath._ensure_parent_dir(cpath)
	var f := FileAccess.open(cpath, FileAccess.WRITE)
	if f == null:
		return AiCopilotLLMTypes.ToolResult.new("cannot write to %s" % cpath, true)
	f.store_string(content)
	f.flush()
	f.close()
	_editor_scan()
	AiCopilotEditorTools.open_resource_at(cpath)
	return AiCopilotLLMTypes.ToolResult.new("wrote %d bytes to %s" % [content.length(), cpath], false)

# ---------- edit ----------

static func _edit_file(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var cpath := AiCopilotToolPath.canonicalize_in_res(String(args.get("path", "")))
	var old := _normalize_eol(String(args.get("old_string", "")))
	var new_s := _normalize_eol(String(args.get("new_string", "")))
	var replace_all := bool(args.get("replace_all", false))
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if AiCopilotToolPath.is_self_blocked(cpath):
		return AiCopilotLLMTypes.ToolResult.new("plugin source is off-limits", true)
	if cpath == "res://project.godot":
		return AiCopilotLLMTypes.ToolResult.new("Cannot edit project.godot directly — it would corrupt the project. Use write_file for scene/script files instead.", true)
	if old == "":
		return AiCopilotLLMTypes.ToolResult.new("old_string must not be empty. Use write_file to create or overwrite a file.", true)
	if old == new_s:
		return AiCopilotLLMTypes.ToolResult.new("No changes to apply: old_string and new_string are identical.", true)
	if not FileAccess.file_exists(cpath):
		return AiCopilotLLMTypes.ToolResult.new("file does not exist: %s. Use glob/grep to find it, or write_file to create it." % cpath, true)
	var cont := _normalize_eol(FileAccess.get_file_as_string(cpath))
	var count := cont.count(old)
	if count == 0:
		return AiCopilotLLMTypes.ToolResult.new("Could not find old_string in %s. It must match EXACTLY, including whitespace and indentation. Read the file again and copy the text verbatim." % cpath, true)
	if count > 1 and not replace_all:
		return AiCopilotLLMTypes.ToolResult.new("Found %d matches for old_string in %s. Add more surrounding context to make it unique, or set replace_all=true." % [count, cpath], true)
	var new_content := cont.replace(old, new_s)
	_editor_save_all()
	var f := FileAccess.open(cpath, FileAccess.WRITE)
	if f == null:
		return AiCopilotLLMTypes.ToolResult.new("cannot write to %s" % cpath, true)
	f.store_string(new_content)
	f.flush()
	f.close()
	_editor_scan()
	AiCopilotEditorTools.open_resource_at(cpath)
	return AiCopilotLLMTypes.ToolResult.new("edited %s (%d replacement%s)" % [cpath, count, "" if count == 1 else "s"], false)

# ---------- delete / rename ----------

static func _delete_file(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var cpath := AiCopilotToolPath.canonicalize_in_res(String(args.get("path", "")))
	if cpath == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if AiCopilotToolPath.is_self_blocked(cpath):
		return AiCopilotLLMTypes.ToolResult.new("plugin source is off-limits", true)
	if not FileAccess.file_exists(cpath):
		return AiCopilotLLMTypes.ToolResult.new("file does not exist: %s" % cpath, true)
	_editor_save_all()
	var err := DirAccess.remove_absolute(cpath)
	if err != OK:
		return AiCopilotLLMTypes.ToolResult.new("delete err: %s" % cpath, true)
	_editor_scan()
	return AiCopilotLLMTypes.ToolResult.new("deleted %s" % cpath, false)

static func _rename_file(_call: AiCopilotLLMTypes.ToolCall, args: Dictionary) -> AiCopilotLLMTypes.ToolResult:
	var src := AiCopilotToolPath.canonicalize_in_res(String(args.get("src", "")))
	var dst := AiCopilotToolPath.canonicalize_in_res(String(args.get("dst", "")))
	if src == "" or dst == "":
		return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if AiCopilotToolPath.is_self_blocked(src) or AiCopilotToolPath.is_self_blocked(dst):
		return AiCopilotLLMTypes.ToolResult.new("plugin source is off-limits", true)
	if not FileAccess.file_exists(src):
		return AiCopilotLLMTypes.ToolResult.new("source does not exist: %s" % src, true)
	if FileAccess.file_exists(dst):
		return AiCopilotLLMTypes.ToolResult.new("destination already exists: %s" % dst, true)
	_editor_save_all()
	AiCopilotToolPath._ensure_parent_dir(dst)
	var err := DirAccess.rename_absolute(src, dst)
	if err != OK:
		return AiCopilotLLMTypes.ToolResult.new("rename err %s → %s" % [src, dst], true)
	_editor_scan()
	AiCopilotEditorTools.open_resource_at(dst)
	return AiCopilotLLMTypes.ToolResult.new("renamed %s → %s" % [src, dst], false)

# ---------- helpers ----------

static func _normalize_eol(s: String) -> String:
	return s.replace("\r\n", "\n")

static func _editor_save_all() -> void:
	if not Engine.is_editor_hint(): return
	EditorInterface.save_all_scenes()

static func _editor_scan() -> void:
	if not Engine.is_editor_hint(): return
	EditorInterface.get_resource_filesystem().scan()
