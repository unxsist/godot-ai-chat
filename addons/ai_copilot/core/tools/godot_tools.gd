class_name AiCopilotGodotTools
extends RefCounted

static func register_all(registry: AiCopilotToolRegistry) -> void:
	registry.register_tool(
		"run_project",
		"Play the project's main scene inside this editor (like pressing F5). Use this to test the game — never launch Godot via run_command.",
		{"type":"object","properties":{},"required":[]},
		Callable(AiCopilotGodotTools, "_run_project"), true)
	registry.register_tool(
		"run_scene",
		"Play a specific scene inside this editor (like F6). Provide a res:// .tscn path.",
		{"type":"object","properties":{"path":{"type":"string","description":"res:// path to a .tscn scene"}},"required":["path"]},
		Callable(AiCopilotGodotTools, "_run_scene"), true)
	registry.register_tool(
		"stop_project",
		"Stop the currently running game/scene.",
		{"type":"object","properties":{},"required":[]},
		Callable(AiCopilotGodotTools, "_stop_project"), false)
	registry.register_tool(
		"run_and_capture",
		"Run the game (or a specific scene) in a separate process for a few seconds and capture its RUNTIME errors and warnings: null references, index out of bounds, failed assertions, push_error/push_warning — each with the message, file:line, and GDScript backtrace. This catches errors that only happen while the game runs, which check_scripts (compile-only) cannot. Use after writing gameplay code: fix reported runtime errors, then run again. The process is auto-terminated after 'seconds'.",
		{"type":"object","properties":{
			"scene":{"type":"string","description":"Optional res:// .tscn to run. Omit to run the project's main scene."},
			"seconds":{"type":"number","description":"How long to let the game run before stopping it (1-30).","default":5}
		},"required":[]},
		Callable(AiCopilotGodotTools, "_run_and_capture"), true)
	registry.register_tool(
		"get_project_info",
		"Get a summary of the project: name, main scene, Godot version, autoloads, input actions, and top-level directories/scripts/scenes counts.",
		{"type":"object","properties":{},"required":[]},
		Callable(AiCopilotGodotTools, "_get_project_info"), false)
	registry.register_tool(
		"create_scene",
		"Create a new scene file with a typed root node and save it as a .tscn. Safer than hand-writing scene text. Example: create_scene(path='res://main.tscn', root_type='Node2D', root_name='Main').",
		{"type":"object","properties":{
			"path":{"type":"string","description":"res:// path for the new .tscn"},
			"root_type":{"type":"string","description":"Root node class, e.g. Node2D, Node3D, Control, CharacterBody2D"},
			"root_name":{"type":"string","description":"Name for the root node","default":"Root"}
		},"required":["path","root_type"]},
		Callable(AiCopilotGodotTools, "_create_scene"), true)
	registry.register_tool(
		"add_node",
		"Add a child node to an existing scene and save it. parent is the path within the scene ('.' or '' = root, or e.g. 'Player'). Optionally attach a script and set simple properties (JSON object of name->value, e.g. {\"position\":[100,50]}).",
		{"type":"object","properties":{
			"scene":{"type":"string","description":"res:// path of the .tscn to modify"},
			"node_type":{"type":"string","description":"Node class to add, e.g. Sprite2D, CollisionShape2D, Label"},
			"node_name":{"type":"string","description":"Name for the new node"},
			"parent":{"type":"string","description":"Parent node path inside the scene; '' or '.' = root","default":""},
			"script":{"type":"string","description":"Optional res:// script to attach to the new node"},
			"properties":{"type":"string","description":"Optional JSON object of property name->value to set on the node"}
		},"required":["scene","node_type","node_name"]},
		Callable(AiCopilotGodotTools, "_add_node"), true)

# ---------- run / stop ----------

static func _run_project(_c, _a) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var main := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main == "":
		return AiCopilotLLMTypes.ToolResult.new("No main scene set. Set run/main_scene via project_set_setting or use run_scene with a specific scene.", true)
	EditorInterface.play_main_scene()
	return AiCopilotLLMTypes.ToolResult.new("Playing main scene: %s" % main, false)

static func _run_scene(_c, args) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var cpath := AiCopilotToolPath.canonicalize_in_res(String(args.get("path", "")))
	if cpath == "": return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if not FileAccess.file_exists(cpath):
		return AiCopilotLLMTypes.ToolResult.new("scene does not exist: %s" % cpath, true)
	EditorInterface.play_custom_scene(cpath)
	return AiCopilotLLMTypes.ToolResult.new("Playing scene: %s" % cpath, false)

static func _stop_project(_c, _a) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	EditorInterface.stop_playing_scene()
	return AiCopilotLLMTypes.ToolResult.new("Stopped.", false)

# ---------- run & capture runtime errors ----------

# Runs the game in a separate, time-limited process (using the current editor
# binary + --quit-after) and captures its stderr/stdout. Godot prints runtime
# errors (null refs, index errors, push_error/warning) with file:line + a
# GDScript backtrace, which we parse out. This catches errors that only occur
# while running — unlike check_scripts, which is compile-only.
static func _run_and_capture(_c, args) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint():
		return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var exe := OS.get_executable_path()
	if exe == "":
		return AiCopilotLLMTypes.ToolResult.new("cannot locate Godot executable", true)
	var project_dir := ProjectSettings.globalize_path("res://")
	var seconds := clampf(float(args.get("seconds", 5)), 1.0, 30.0)
	var frames := int(seconds * 60.0)

	var run_args := PackedStringArray(["--path", project_dir, "--quit-after", str(frames)])
	var scene := String(args.get("scene", "")).strip_edges()
	var target := "main scene"
	if scene != "":
		var cpath := AiCopilotToolPath.canonicalize_in_res(scene)
		if cpath == "":
			return AiCopilotLLMTypes.ToolResult.new("scene path outside project", true)
		if not FileAccess.file_exists(cpath):
			return AiCopilotLLMTypes.ToolResult.new("scene does not exist: %s" % cpath, true)
		run_args.append(cpath)
		target = cpath
	else:
		var main := String(ProjectSettings.get_setting("application/run/main_scene", ""))
		if main == "":
			return AiCopilotLLMTypes.ToolResult.new("No main scene set. Pass a 'scene' or set run/main_scene.", true)
		target = main

	var output: Array = []
	# Blocking: the child self-terminates after --quit-after frames.
	OS.execute(exe, run_args, output, true, false)
	var text := "\n".join(output)
	var parsed := _parse_runtime_errors(text)
	var errs: int = parsed["errors"]
	var warns: int = parsed["warnings"]
	var body: String = parsed["text"]
	if errs == 0 and warns == 0:
		return AiCopilotLLMTypes.ToolResult.new("Ran %s for %.0fs — no runtime errors or warnings." % [target, seconds], false)
	var header := "Ran %s for %.0fs — %d error(s), %d warning(s):\n\n" % [target, seconds, errs, warns]
	return AiCopilotLLMTypes.ToolResult.new(header + body, errs > 0)

# Extract runtime error/warning blocks from Godot process output. Each block is
# an ERROR:/WARNING:/SCRIPT ERROR: line followed by indented "at:" and backtrace
# lines. Ignores our own tooling noise.
static func _parse_runtime_errors(text: String) -> Dictionary:
	var lines := text.split("\n", false)
	var out: PackedStringArray = []
	var errors := 0
	var warnings := 0
	var i := 0
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		var kind := ""
		if stripped.begins_with("SCRIPT ERROR:"):
			kind = "ERROR"
			stripped = stripped.substr("SCRIPT ERROR:".length()).strip_edges()
		elif stripped.begins_with("ERROR:"):
			kind = "ERROR"
			stripped = stripped.substr("ERROR:".length()).strip_edges()
		elif stripped.begins_with("WARNING:"):
			kind = "WARNING"
			stripped = stripped.substr("WARNING:".length()).strip_edges()
		if kind == "":
			i += 1
			continue
		# collect the following indented context lines (at: / backtrace)
		var ctx: PackedStringArray = []
		var at_loc := ""
		var res_loc := ""
		var j := i + 1
		while j < lines.size():
			var raw := lines[j]
			if raw.strip_edges() == "":
				break
			# context lines are indented; a new top-level message is not
			if not (raw.begins_with(" ") or raw.begins_with("\t")):
				break
			var c := raw.strip_edges()
			if c.begins_with("at:") and at_loc == "":
				at_loc = c.substr(3).strip_edges()
			# prefer the first res:// backtrace frame as the headline location
			if res_loc == "" and c.find("res://") != -1:
				var rb := c.find("res://")
				res_loc = c.substr(rb).rstrip(")")
			ctx.append("    " + c)
			j += 1
		if kind == "ERROR":
			errors += 1
		else:
			warnings += 1
		var loc := res_loc if res_loc != "" else at_loc
		var locpart := ("  [%s]" % loc) if loc != "" else ""
		out.append("[%s] %s%s" % [kind, stripped, locpart])
		for c in ctx:
			out.append(c)
		i = j
	return {"errors": errors, "warnings": warnings, "text": "\n".join(out)}

# ---------- project info ----------

static func _get_project_info(_c, _a) -> AiCopilotLLMTypes.ToolResult:
	var lines := PackedStringArray()
	lines.append("Name: %s" % ProjectSettings.get_setting("application/config/name", "Unnamed"))
	lines.append("Godot: 4.7.1")
	lines.append("Main scene: %s" % ProjectSettings.get_setting("application/run/main_scene", "(none)"))
	# autoloads
	var autoloads := PackedStringArray()
	for p in ProjectSettings.get_property_list():
		var n := String(p.get("name", ""))
		if n.begins_with("autoload/"):
			autoloads.append(n.substr("autoload/".length()))
	if autoloads.size() > 0:
		lines.append("Autoloads: %s" % ", ".join(autoloads))
	# input actions
	var actions := PackedStringArray()
	for p in ProjectSettings.get_property_list():
		var n := String(p.get("name", ""))
		if n.begins_with("input/"):
			actions.append(n.substr("input/".length()))
	if actions.size() > 0:
		lines.append("Input actions: %s" % ", ".join(actions))
	return AiCopilotLLMTypes.ToolResult.new("\n".join(lines), false)

# ---------- scene building ----------

static func _create_scene(_c, args) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var cpath := AiCopilotToolPath.canonicalize_in_res(String(args.get("path", "")))
	var root_type := String(args.get("root_type", ""))
	var root_name := String(args.get("root_name", "Root"))
	if cpath == "": return AiCopilotLLMTypes.ToolResult.new("path outside project", true)
	if AiCopilotToolPath.is_self_blocked(cpath): return AiCopilotLLMTypes.ToolResult.new("plugin dir is off-limits", true)
	if not cpath.ends_with(".tscn"): return AiCopilotLLMTypes.ToolResult.new("path must end with .tscn", true)
	if not ClassDB.class_exists(root_type) or not ClassDB.can_instantiate(root_type):
		return AiCopilotLLMTypes.ToolResult.new("unknown or non-instantiable node type: %s" % root_type, true)
	var root: Node = ClassDB.instantiate(root_type)
	if root == null:
		return AiCopilotLLMTypes.ToolResult.new("failed to instantiate %s" % root_type, true)
	root.name = root_name if root_name != "" else "Root"
	var final_name := root.name
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.queue_free()
		return AiCopilotLLMTypes.ToolResult.new("failed to pack scene", true)
	AiCopilotToolPath._ensure_parent_dir(cpath)
	var err := ResourceSaver.save(packed, cpath)
	root.queue_free()
	if err != OK:
		return AiCopilotLLMTypes.ToolResult.new("failed to save scene (err %d)" % err, true)
	_scan()
	EditorInterface.open_scene_from_path(cpath)
	return AiCopilotLLMTypes.ToolResult.new("created scene %s with %s root '%s'" % [cpath, root_type, final_name], false)

static func _add_node(_c, args) -> AiCopilotLLMTypes.ToolResult:
	if not Engine.is_editor_hint(): return AiCopilotLLMTypes.ToolResult.new("not in editor", true)
	var scene_path := AiCopilotToolPath.canonicalize_in_res(String(args.get("scene", "")))
	var node_type := String(args.get("node_type", ""))
	var node_name := String(args.get("node_name", ""))
	var parent_path := String(args.get("parent", ""))
	var script_path := String(args.get("script", ""))
	var props_raw := String(args.get("properties", ""))
	if scene_path == "": return AiCopilotLLMTypes.ToolResult.new("scene path outside project", true)
	if AiCopilotToolPath.is_self_blocked(scene_path): return AiCopilotLLMTypes.ToolResult.new("plugin dir is off-limits", true)
	if not FileAccess.file_exists(scene_path):
		return AiCopilotLLMTypes.ToolResult.new("scene does not exist: %s. Use create_scene first." % scene_path, true)
	if not ClassDB.class_exists(node_type) or not ClassDB.can_instantiate(node_type):
		return AiCopilotLLMTypes.ToolResult.new("unknown node type: %s" % node_type, true)
	var packed: PackedScene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		return AiCopilotLLMTypes.ToolResult.new("failed to load scene: %s" % scene_path, true)
	var root: Node = packed.instantiate()
	if root == null:
		return AiCopilotLLMTypes.ToolResult.new("failed to instantiate scene", true)
	var parent: Node = root
	if parent_path != "" and parent_path != ".":
		parent = root.get_node_or_null(parent_path)
		if parent == null:
			root.free()
			return AiCopilotLLMTypes.ToolResult.new("parent node not found in scene: %s" % parent_path, true)
	var child: Node = ClassDB.instantiate(node_type)
	if child == null:
		root.free()
		return AiCopilotLLMTypes.ToolResult.new("failed to instantiate %s" % node_type, true)
	child.name = node_name if node_name != "" else node_type
	if script_path != "":
		var sp := AiCopilotToolPath.canonicalize_in_res(script_path)
		if sp != "" and FileAccess.file_exists(sp):
			var scr = ResourceLoader.load(sp, "Script", ResourceLoader.CACHE_MODE_IGNORE)
			if scr is Script:
				child.set_script(scr)
	# apply simple properties
	var applied := PackedStringArray()
	if props_raw.strip_edges() != "":
		var parsed = JSON.parse_string(props_raw)
		if parsed is Dictionary:
			for k in parsed.keys():
				var v = _coerce_value(parsed[k])
				child.set(k, v)
				applied.append(String(k))
	parent.add_child(child)
	# ownership required so the node is saved into the scene
	_set_owner_recursive(child, root)
	var child_name := child.name
	var repacked := PackedScene.new()
	if repacked.pack(root) != OK:
		root.queue_free()
		return AiCopilotLLMTypes.ToolResult.new("failed to repack scene", true)
	var err := ResourceSaver.save(repacked, scene_path)
	root.queue_free()
	if err != OK:
		return AiCopilotLLMTypes.ToolResult.new("failed to save scene (err %d)" % err, true)
	_scan()
	_reload_open_scene(scene_path)
	var note := (" props: %s" % ", ".join(applied)) if applied.size() > 0 else ""
	return AiCopilotLLMTypes.ToolResult.new("added %s '%s' under '%s' in %s%s" % [node_type, child_name, (parent_path if parent_path != "" else "root"), scene_path, note], false)

# ---------- helpers ----------

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for c in node.get_children():
		_set_owner_recursive(c, owner)

static func _coerce_value(v):
	# arrays of 2/3 numbers -> Vector2/3 for convenience
	if v is Array:
		if v.size() == 2 and (v[0] is float or v[0] is int):
			return Vector2(float(v[0]), float(v[1]))
		if v.size() == 3 and (v[0] is float or v[0] is int):
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return v

static func _scan() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

static func _reload_open_scene(path: String) -> void:
	if not Engine.is_editor_hint(): return
	var root := EditorInterface.get_edited_scene_root()
	if root and root.scene_file_path == path:
		EditorInterface.reload_scene_from_path(path)
