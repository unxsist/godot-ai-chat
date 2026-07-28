class_name AiCopilotToolPath
extends RefCounted

static func canonicalize_in_res(path: String) -> String:
	if path.is_empty(): return ""
	var s := path.strip_edges()
	if not (s.begins_with("res://") or s.begins_with("/")):
		s = "res://" + s
	var global: String
	if s.begins_with("res://"):
		global = ProjectSettings.globalize_path(s)
	else:
		global = s
	if global.is_empty(): return ""
	var local := ProjectSettings.localize_path(global)
	if local.begins_with("res://"): return local
	return ""

static func is_inside_res(path: String) -> bool:
	var c := canonicalize_in_res(path)
	return c != "" and c.begins_with("res://")

static func is_self_blocked(path: String) -> bool:
	var c := canonicalize_in_res(path)
	if c == "": return false
	return c.begins_with(AiCopilotConst.SELF_BLOCK_PATH_PREFIX)

static func file_size(path: String) -> int:
	if not FileAccess.file_exists(path): return -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return -1
	var size := f.get_length()
	f.close()
	return size

static func _ensure_parent_dir(path: String) -> void:
	var parent := path.get_base_dir()
	if parent != "" and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
