@tool
class_name AiCopilotToolView
extends MarginContainer

signal accept(call: AiCopilotLLMTypes.ToolCall)
signal reject(call: AiCopilotLLMTypes.ToolCall)

const MUTATING_FILE_TOOLS := ["write_file", "edit_file"]
const DIFF_CONTEXT_LINES := 3
const DIFF_MAX_LINES := 60
const DIFF_MAX_HEIGHT := 260  # px (pre-scale); diff scrolls internally beyond this

var _call: AiCopilotLLMTypes.ToolCall
var _approve_mode: bool = true

var _built: bool = false
var _card: PanelContainer
var _title_label: Label
var _args_label: Label
var _result_label: Label
var _diff_box: VBoxContainer
var _expand_btn: Button
var _accept_btn: Button
var _reject_btn: Button

func _ready() -> void:
	if not _built:
		_build()
	_refresh()

func _build() -> void:
	_built = true
	for c in get_children():
		c.queue_free()

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Outer padding around the card (this node is itself a MarginContainer, so it
	# reports the card's full height as its minimum — no manual sizing needed).
	add_theme_constant_override("margin_left", AiCopilotUI.scale(10))
	add_theme_constant_override("margin_right", AiCopilotUI.scale(10))
	add_theme_constant_override("margin_top", AiCopilotUI.scale(2))
	add_theme_constant_override("margin_bottom", AiCopilotUI.scale(2))

	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("191921")
	cs.set_corner_radius_all(10)
	cs.set_border_width_all(1)
	cs.border_color = Color("d9a441")  # amber = awaiting your decision
	cs.content_margin_left = 12
	cs.content_margin_right = 12
	cs.content_margin_top = 10
	cs.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", cs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(card)
	_card = card

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# header row: dot + title + expand
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	v.add_child(header)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(AiCopilotUI.scale(8), AiCopilotUI.scale(8))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = Color("e0b040")
	header.add_child(dot)

	_title_label = Label.new()
	_title_label.text = "Approve change"
	_title_label.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
	_title_label.add_theme_color_override("font_color", Color("e6ce8a"))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_expand_btn = Button.new()
	_expand_btn.text = "Expand"
	_expand_btn.flat = true
	_expand_btn.focus_mode = Control.FOCUS_NONE
	_expand_btn.visible = false
	_expand_btn.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	_expand_btn.add_theme_color_override("font_color", Color("7a9ac0"))
	_expand_btn.pressed.connect(_on_expand)
	header.add_child(_expand_btn)

	# args (non-file tools) / path (file tools)
	_args_label = Label.new()
	_args_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_args_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_args_label.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	_args_label.add_theme_color_override("font_color", Color("8b8f9e"))
	v.add_child(_args_label)

	# inline diff container
	_diff_box = VBoxContainer.new()
	_diff_box.add_theme_constant_override("separation", 0)
	_diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_box.visible = false
	v.add_child(_diff_box)

	# result label (after execution)
	_result_label = Label.new()
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	_result_label.add_theme_color_override("font_color", Color("8a94a4"))
	_result_label.visible = false
	v.add_child(_result_label)

	# action buttons
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)

	_reject_btn = Button.new()
	_reject_btn.text = "Reject"
	_reject_btn.focus_mode = Control.FOCUS_NONE
	_reject_btn.add_theme_color_override("font_color", Color("e07070"))
	_reject_btn.pressed.connect(_on_reject)
	actions.add_child(_reject_btn)

	_accept_btn = Button.new()
	_accept_btn.text = "Approve"
	_accept_btn.focus_mode = Control.FOCUS_NONE
	_accept_btn.add_theme_color_override("font_color", Color("7ec98a"))
	_accept_btn.pressed.connect(_on_accept)
	actions.add_child(_accept_btn)

func set_call(call: AiCopilotLLMTypes.ToolCall, approve_mode: bool) -> void:
	_call = call
	_approve_mode = approve_mode
	if not _built:
		_build()
	_refresh()

func _refresh() -> void:
	if _call == null or not _built:
		return
	var is_file := _call.name in MUTATING_FILE_TOOLS
	_title_label.text = "Approve change  •  %s" % _call.name
	_accept_btn.visible = _approve_mode
	_reject_btn.visible = _approve_mode

	if is_file:
		var args := _call.arguments()
		_args_label.text = String(args.get("path", ""))
		_render_inline_diff(args)
		_expand_btn.visible = true
	else:
		_args_label.text = _call.arguments_raw
		_diff_box.visible = false
		_expand_btn.visible = false

func set_result(result: AiCopilotLLMTypes.ToolResult) -> void:
	if not _built:
		_build()
	if _result_label:
		_result_label.text = result.content
		_result_label.visible = result.content.strip_edges() != ""

# ------------------------------------------------------------------ diff

func _compute_new_text(args: Dictionary) -> Dictionary:
	var path := String(args.get("path", ""))
	var old_text := ""
	if FileAccess.file_exists(path):
		old_text = FileAccess.get_file_as_string(path)
	var new_text := old_text
	match _call.name:
		"write_file":
			new_text = String(args.get("content", ""))
		"edit_file":
			var old_s := String(args.get("old_string", ""))
			var new_s := String(args.get("new_string", ""))
			if bool(args.get("replace_all", false)):
				new_text = old_text.replace(old_s, new_s)
			else:
				var idx := old_text.find(old_s)
				if idx != -1:
					new_text = old_text.substr(0, idx) + new_s + old_text.substr(idx + old_s.length())
	return {"old": old_text, "new": new_text}

func _render_inline_diff(args: Dictionary) -> void:
	for c in _diff_box.get_children():
		c.queue_free()
	var texts := _compute_new_text(args)
	var lines := _line_diff(String(texts["old"]).split("\n"), String(texts["new"]).split("\n"))
	if lines.is_empty():
		_diff_box.visible = false
		return
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color("101015")
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color("2a2a33")
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", s)
	_diff_box.add_child(card)

	# Cap the diff height and let it scroll internally, so a large change never
	# pushes the Approve/Reject buttons out of reach in the chat panel.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.set_meta("max_h", AiCopilotUI.scale(DIFF_MAX_HEIGHT))
	card.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	scroll.add_child(col)

	var shown := 0
	for d in lines:
		if shown >= DIFF_MAX_LINES:
			var more := Label.new()
			more.text = "…"
			more.add_theme_font_size_override("font_size", AiCopilotUI.fs_mono())
			more.add_theme_color_override("font_color", Color("6a6a7a"))
			col.add_child(more)
			break
		col.add_child(_diff_line(String(d["kind"]), String(d["text"])))
		shown += 1
	_diff_box.visible = true
	# Clamp the scroll region to the max height once the content is laid out.
	col.resized.connect(func():
		var content_h := int(col.get_combined_minimum_size().y)
		scroll.custom_minimum_size.y = min(content_h, AiCopilotUI.scale(DIFF_MAX_HEIGHT))
	)

func _diff_line(kind: String, text: String) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	var prefix := "  "
	var fg := Color("aeb4c2")
	match kind:
		"add":
			s.bg_color = Color(0.32, 0.78, 0.42, 0.13)
			prefix = "+ "
			fg = Color("9fe0ac")
		"del":
			s.bg_color = Color(0.90, 0.36, 0.36, 0.13)
			prefix = "- "
			fg = Color("f0a0a0")
		_:
			s.bg_color = Color(0, 0, 0, 0)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	row.add_theme_stylebox_override("panel", s)
	var lbl := Label.new()
	lbl.text = prefix + text
	lbl.add_theme_font_size_override("font_size", AiCopilotUI.fs_mono())
	lbl.add_theme_color_override("font_color", fg)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	return row

# Minimal LCS-free line diff: find the common prefix/suffix, mark the middle
# as removed/added, and keep a few context lines around the change.
func _line_diff(old_lines: PackedStringArray, new_lines: PackedStringArray) -> Array:
	var o := old_lines
	var n := new_lines
	var start := 0
	while start < o.size() and start < n.size() and o[start] == n[start]:
		start += 1
	var oe := o.size()
	var ne := n.size()
	while oe > start and ne > start and o[oe - 1] == n[ne - 1]:
		oe -= 1
		ne -= 1

	var out: Array = []
	var ctx_start = max(0, start - DIFF_CONTEXT_LINES)
	for i in range(ctx_start, start):
		out.append({"kind": "ctx", "text": o[i]})
	for i in range(start, oe):
		out.append({"kind": "del", "text": o[i]})
	for i in range(start, ne):
		out.append({"kind": "add", "text": n[i]})
	var ctx_end = min(o.size(), oe + DIFF_CONTEXT_LINES)
	for i in range(oe, ctx_end):
		out.append({"kind": "ctx", "text": o[i]})
	return out

# ------------------------------------------------------------------ actions

func _on_expand() -> void:
	if _call == null:
		return
	var args := _call.arguments()
	if args.is_empty():
		return
	var texts := _compute_new_text(args)
	var dlg := preload("res://addons/ai_copilot/ui/diff_dialog.tscn").instantiate()
	add_child(dlg)
	dlg.show_diff(String(args.get("path", "")), String(texts["old"]), String(texts["new"]))
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.popup_centered(Vector2i(900, 600))

func _on_accept() -> void:
	accept.emit(_call)
	_lock("Approved")

func _on_reject() -> void:
	reject.emit(_call)
	_lock("Rejected")

func _lock(verdict: String) -> void:
	_accept_btn.disabled = true
	_reject_btn.disabled = true
	_accept_btn.visible = false
	_reject_btn.visible = false
	_title_label.text = "%s  •  %s" % [verdict, _call.name]
	# Neutralize the amber "awaiting" border.
	if _card:
		var s := _card.get_theme_stylebox("panel")
		if s is StyleBoxFlat:
			(s as StyleBoxFlat).border_color = Color("2a2a33")
