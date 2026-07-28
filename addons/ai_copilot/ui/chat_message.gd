@tool
class_name AiCopilotChatMessage
extends MarginContainer

var _role: String = ""
var _bubble: PanelContainer
var _master: VBoxContainer
var _stream_rich: RichTextLabel
var _stream_raw: String = ""
var _reasoning_rich: RichTextLabel = null
var _tool_section: VBoxContainer
var _tool_dots: Dictionary = {}
var _tool_labels: Dictionary = {}
var _built: bool = false
var _spinner: Label = null
var _spin_frames := ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
var _spin_i := 0
var _spin_accum := 0.0
var _thinking := false

func set_role(r: String) -> void:
	_role = r
	if is_inside_tree():
		_build()

func get_role() -> String:
	return _role

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	for c in get_children():
		c.queue_free()
	# reset grouped-tool state (nodes are being freed above)
	_cur_group = null
	_cur_group_name = ""
	_cur_group_count = 0
	_cur_group_head_label = null
	_cur_group_head_dot = null
	_cur_group_chevron = null
	_cur_group_call_ids = []
	_tool_dots.clear()
	_tool_labels.clear()
	_stream_raw = ""

	add_theme_constant_override("margin_left", 10)
	add_theme_constant_override("margin_right", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var is_user := _role == "user"

	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)

	if is_user:
		var lead := Control.new()
		lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lead.size_flags_stretch_ratio = 0.28
		outer.add_child(lead)

	_bubble = _make_bubble(is_user)
	_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubble.size_flags_stretch_ratio = 0.72 if is_user else 1.0
	outer.add_child(_bubble)

	_master = VBoxContainer.new()
	_master.add_theme_constant_override("separation", 7)
	_bubble.add_child(_master)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var badge := ColorRect.new()
	badge.custom_minimum_size = Vector2(AiCopilotUI.scale(3), AiCopilotUI.scale(13))
	badge.color = Color("5a9bd4") if is_user else Color("7ec98a")
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var who := Label.new()
	who.text = "You" if is_user else "Agent"
	who.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
	who.add_theme_color_override("font_color", Color("9cc4f0") if is_user else Color("8fd89a"))
	head.add_child(who)

	if not is_user:
		_spinner = Label.new()
		_spinner.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
		_spinner.add_theme_color_override("font_color", Color("8a8a95"))
		_spinner.visible = false
		head.add_child(_spinner)
	_master.add_child(head)

	_stream_rich = _make_rich()
	_stream_rich.visible = false
	_master.add_child(_stream_rich)

	if not is_user:
		_tool_section = VBoxContainer.new()
		_tool_section.add_theme_constant_override("separation", 3)
		_tool_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_master.add_child(_tool_section)

func _make_rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.selection_enabled = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", AiCopilotUI.fs_body())
	r.add_theme_font_size_override("bold_font_size", AiCopilotUI.fs_body())
	r.add_theme_font_size_override("mono_font_size", AiCopilotUI.fs_mono())
	r.add_theme_color_override("default_color", Color("dde3ee"))
	return r

func _make_bubble(is_user: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("22364d") if is_user else Color("1c1c22")
	s.set_corner_radius_all(10)
	if is_user:
		s.corner_radius_top_right = 3
	else:
		s.corner_radius_top_left = 3
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.border_color = Color("2e4a6a") if is_user else Color("2a2a33")
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	return p

# Live streaming append (before final render). Accumulates raw markdown and
# re-renders it as bbcode each token so bold/italic/code/links show live.
# Unclosed markers (e.g. "**bol" before "d**" arrives) are left literal by the
# formatter and resolve once the closing marker streams in.
func append_text(t: String) -> void:
	if _stream_rich == null:
		return
	_stream_rich.visible = true
	_stream_raw += t
	_stream_rich.text = AiCopilotMDToBBCode.render_stream(_stream_raw)
	set_thinking(false)

func append_reasoning(t: String) -> void:
	if _reasoning_rich == null:
		_reasoning_rich = _make_rich()
		_reasoning_rich.add_theme_color_override("default_color", Color("7c7c88"))
		_reasoning_rich.add_theme_font_size_override("normal_font_size", AiCopilotUI.fs_small())
		# insert reasoning above the stream text
		_master.add_child(_reasoning_rich)
		if _stream_rich:
			_master.move_child(_reasoning_rich, _stream_rich.get_index())
	_reasoning_rich.visible = true
	_reasoning_rich.text += t
	set_thinking(false)

func set_thinking(on: bool) -> void:
	_thinking = on
	if _spinner:
		_spinner.visible = on
	set_process(on)
	if not on and _spinner:
		_spinner.text = ""

func has_reasoning() -> bool:
	return _reasoning_rich != null and _reasoning_rich.text.strip_edges() != ""

func _process(delta: float) -> void:
	if not _thinking or _spinner == null:
		return
	_spin_accum += delta
	if _spin_accum >= 0.09:
		_spin_accum = 0.0
		_spin_i = (_spin_i + 1) % _spin_frames.size()
		_spinner.text = _spin_frames[_spin_i] + " thinking…"

func get_text() -> String:
	return _stream_raw

# Final render: rebuild body as ordered segments (text / code)
func set_text(raw: String) -> void:
	if not _built:
		await ready
	if not _master:
		return
	# clear everything except header, reasoning, and tool section
	for c in _master.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is ColorRect:
			continue
		elif c == _tool_section:
			continue
		elif c == _reasoning_rich:
			continue
		else:
			c.queue_free()
	_stream_rich = null
	set_thinking(false)

	var segments := AiCopilotMDToBBCode.convert_segments(raw)
	var insert_before := _tool_section
	for seg in segments:
		var w: Control
		if seg.type == "code":
			w = _make_code_block(seg)
		else:
			w = _make_rich()
			w.text = seg.bbcode
		if insert_before and insert_before.get_parent() == _master:
			_master.add_child(w)
			_master.move_child(w, insert_before.get_index())
		else:
			_master.add_child(w)

func _make_code_block(seg: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("101015")
	cs.set_corner_radius_all(6)
	cs.content_margin_left = 10
	cs.content_margin_right = 10
	cs.content_margin_top = 6
	cs.content_margin_bottom = 6
	cs.border_color = Color("2a2a33")
	cs.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", cs)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)

	var top := HBoxContainer.new()
	var lang := Label.new()
	lang.text = seg.lang if seg.lang != "" else "gdscript"
	lang.add_theme_color_override("font_color", Color("6a6a7a"))
	lang.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lang)
	var copy := Button.new()
	copy.text = "Copy"
	copy.flat = true
	copy.add_theme_color_override("font_color", Color("7a9ac0"))
	copy.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	copy.focus_mode = Control.FOCUS_NONE
	var code_text: String = seg.code
	copy.pressed.connect(func(): DisplayServer.clipboard_set(code_text))
	top.add_child(copy)
	cv.add_child(top)

	var line_count: int = seg.code.split("\n").size()
	var ce := CodeEdit.new()
	ce.text = seg.code
	ce.editable = false
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce.gutters_draw_line_numbers = false
	ce.scroll_fit_content_height = true
	var line_height := AiCopilotUI.fs_mono() + AiCopilotUI.scale(6)
	ce.custom_minimum_size = Vector2(0, clamp(line_count * line_height + AiCopilotUI.scale(10), AiCopilotUI.scale(28), AiCopilotUI.scale(340)))
	ce.add_theme_font_size_override("font_size", AiCopilotUI.fs_mono())
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	ce.add_theme_stylebox_override("normal", st)
	ce.add_theme_stylebox_override("focus", st)
	if seg.lang == "" or seg.lang.to_lower() == "gdscript":
		ce.syntax_highlighter = AiCopilotGDHighlighter.new()
	cv.add_child(ce)
	return card

func add_tool_indicator(tc: AiCopilotLLMTypes.ToolCall) -> void:
	if _tool_section == null:
		return
	# Group consecutive calls to the SAME tool under one collapsible header.
	# A different tool (or the same tool after a different one) starts a new group.
	if _cur_group_name == tc.name and _cur_group != null:
		_add_call_row(_cur_group, tc)
		_cur_group_count += 1
		_update_group_header()
	else:
		_start_group(tc)

func update_tool_result(tc: AiCopilotLLMTypes.ToolCall, result: AiCopilotLLMTypes.ToolResult) -> void:
	var dot: ColorRect = _tool_dots.get(tc.id, null)
	var lbl: Label = _tool_labels.get(tc.id, null)
	if dot:
		dot.color = Color("e05252") if result.is_error else Color("52c072")
	if lbl:
		lbl.text = str(result.content).left(2000)
	_refresh_group_head_status()

# --- grouped tool indicators --------------------------------------------

var _cur_group: VBoxContainer = null          # container holding per-call rows
var _cur_group_name := ""
var _cur_group_count := 0
var _cur_group_head_label: Label = null
var _cur_group_head_dot: ColorRect = null
var _cur_group_chevron: Label = null
var _cur_group_call_ids: Array = []

func _start_group(tc: AiCopilotLLMTypes.ToolCall) -> void:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("16161c")
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 8
	ps.content_margin_right = 8
	ps.content_margin_top = 5
	ps.content_margin_bottom = 5
	ps.border_color = Color("2a2a33")
	ps.set_border_width_all(1)
	pill.add_theme_stylebox_override("panel", ps)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	pill.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(AiCopilotUI.scale(8), AiCopilotUI.scale(8))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = Color("e0b040")
	row.add_child(dot)

	var name_l := Label.new()
	name_l.text = tc.name
	name_l.add_theme_font_size_override("font_size", AiCopilotUI.fs_small())
	name_l.add_theme_color_override("font_color", Color("c6cbe0"))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var chevron := Label.new()
	chevron.text = "▸"
	chevron.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	chevron.add_theme_color_override("font_color", Color("707080"))
	row.add_child(chevron)

	# container for per-call detail rows (hidden until expanded)
	var calls := VBoxContainer.new()
	calls.visible = false
	calls.add_theme_constant_override("separation", 4)
	col.add_child(calls)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.focus_mode = Control.FOCUS_NONE
	var expanded := [false]
	btn.pressed.connect(func():
		expanded[0] = not expanded[0]
		calls.visible = expanded[0]
		chevron.text = "▾" if expanded[0] else "▸")
	pill.add_child(btn)

	_tool_section.add_child(pill)

	# set group state
	_cur_group = calls
	_cur_group_name = tc.name
	_cur_group_count = 1
	_cur_group_head_label = name_l
	_cur_group_head_dot = dot
	_cur_group_chevron = chevron
	_cur_group_call_ids = []

	_add_call_row(calls, tc)
	_update_group_header()

# Add one call's detail row (args + result) inside a group container.
func _add_call_row(container: VBoxContainer, tc: AiCopilotLLMTypes.ToolCall) -> void:
	_cur_group_call_ids.append(tc.id)
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	container.add_child(wrap)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	wrap.add_child(head)
	var d := ColorRect.new()
	d.custom_minimum_size = Vector2(AiCopilotUI.scale(6), AiCopilotUI.scale(6))
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.color = Color("e0b040")
	head.add_child(d)
	_tool_dots[tc.id] = d
	var ae := Label.new()
	ae.text = tc.arguments_raw.left(600) if tc.arguments_raw.strip_edges() != "" else "(no args)"
	ae.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ae.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ae.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	ae.add_theme_color_override("font_color", Color("8a90a2"))
	head.add_child(ae)

	var rl := Label.new()
	rl.text = "running..."
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.add_theme_font_size_override("font_size", AiCopilotUI.fs_tiny())
	rl.add_theme_color_override("font_color", Color("6f7080"))
	wrap.add_child(rl)
	_tool_labels[tc.id] = rl

func _update_group_header() -> void:
	if _cur_group_head_label == null:
		return
	if _cur_group_count > 1:
		_cur_group_head_label.text = "%s  ×%d" % [_cur_group_name, _cur_group_count]
	else:
		_cur_group_head_label.text = _cur_group_name

# Header dot goes green when all calls in the group succeeded, red if any errored,
# amber while any are still running.
func _refresh_group_head_status() -> void:
	if _cur_group_head_dot == null:
		return
	var any_err := false
	var any_running := false
	for cid in _cur_group_call_ids:
		var d: ColorRect = _tool_dots.get(cid, null)
		if d == null:
			continue
		if d.color == Color("e05252"):
			any_err = true
		elif d.color == Color("e0b040"):
			any_running = true
	if any_err:
		_cur_group_head_dot.color = Color("e05252")
	elif any_running:
		_cur_group_head_dot.color = Color("e0b040")
	else:
		_cur_group_head_dot.color = Color("52c072")
