@tool
class_name AiCopilotUI
extends RefCounted

# Editor display scale (1.0, 1.5, 2.0 on HiDPI). 1.0 outside editor.
static func editor_scale() -> float:
	if Engine.is_editor_hint():
		var s := EditorInterface.get_editor_scale()
		if s > 0.0:
			return s
	return 1.0

# Editor base font size, already reflecting the theme. Falls back to 14.
static func _theme_font_size() -> int:
	if Engine.is_editor_hint():
		var th := EditorInterface.get_editor_theme()
		if th and th.get_default_font_size() > 0:
			return th.get_default_font_size()
	return 14

# Body text: match the editor's own default font size.
static func fs_body() -> int:
	return _theme_font_size()

static func fs_small() -> int:
	return max(int(round(_theme_font_size() * 0.85)), int(round(11 * editor_scale())))

static func fs_tiny() -> int:
	return max(int(round(_theme_font_size() * 0.78)), int(round(10 * editor_scale())))

static func fs_mono() -> int:
	return max(int(round(_theme_font_size() * 0.92)), int(round(12 * editor_scale())))

static func base_font_size() -> int:
	return _theme_font_size()

# Scale a raw pixel value by the editor display scale.
static func scale(px: float) -> int:
	return int(round(px * editor_scale()))
