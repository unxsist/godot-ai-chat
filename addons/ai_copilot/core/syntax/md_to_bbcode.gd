class_name AiCopilotMDToBBCode
extends RefCounted

static func convert(md: String) -> Dictionary:
	var lines := md.split("\n")
	var bb := PackedStringArray()
	var code_blocks := []
	var i := 0
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		if stripped.begins_with("```"):
			var lang := stripped.substr(3).strip_edges()
			var buf := PackedStringArray()
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with("```"):
				buf.append(lines[i])
				i += 1
			i += 1
			var placeholder := "\n\n"
			code_blocks.append({"lang": lang, "code": "\n".join(buf)})
			bb.append(placeholder)
			continue
		if stripped.begins_with("### "):
			bb.append("[b][color=gray]%s[/color][/b]" % _escape_bb(stripped.substr(4)))
		elif stripped.begins_with("## "):
			bb.append("[b]%s[/b]" % _escape_bb(stripped.substr(3)))
		elif stripped.begins_with("# "):
			bb.append("[b]%s[/b]" % _escape_bb(stripped.substr(2)))
		elif stripped == "---" or stripped == "***":
			bb.append("[color=gray]---")
		elif stripped.begins_with("> "):
			bb.append("[color=gray]| %s[/color]" % _inline_format(stripped.substr(2)))
		elif stripped.begins_with("- ") or stripped.begins_with("* "):
			bb.append("  * %s" % _inline_format(stripped.substr(2)))
		elif stripped == "":
			bb.append("")
		else:
			bb.append(_inline_format(stripped))
		i += 1
	return {"text": "\n".join(bb), "code_blocks": code_blocks}

# Returns ordered segments: [{type:"text", bbcode:String} | {type:"code", lang:String, code:String}]
static func convert_segments(md: String) -> Array:
	var lines := md.split("\n")
	var segments: Array = []
	var buf := PackedStringArray()
	var i := 0
	var flush_text := func():
		if buf.size() > 0:
			var joined := "\n".join(buf).strip_edges()
			if joined != "":
				segments.append({"type": "text", "bbcode": "\n".join(buf)})
			buf.clear()
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		if stripped.begins_with("```"):
			flush_text.call()
			var lang := stripped.substr(3).strip_edges()
			var cbuf := PackedStringArray()
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with("```"):
				cbuf.append(lines[i])
				i += 1
			i += 1
			segments.append({"type": "code", "lang": lang, "code": "\n".join(cbuf)})
			continue
		if stripped.begins_with("### "):
			buf.append("[b][color=#9aa]%s[/color][/b]" % _escape_bb(stripped.substr(4)))
		elif stripped.begins_with("## "):
			buf.append("[b]%s[/b]" % _escape_bb(stripped.substr(3)))
		elif stripped.begins_with("# "):
			buf.append("[b]%s[/b]" % _escape_bb(stripped.substr(2)))
		elif stripped == "---" or stripped == "***":
			buf.append("[color=#555]────────[/color]")
		elif stripped.begins_with("> "):
			buf.append("[color=#99a]▏ %s[/color]" % _inline_format(stripped.substr(2)))
		elif stripped.begins_with("- ") or stripped.begins_with("* "):
			buf.append("  • %s" % _inline_format(stripped.substr(2)))
		elif stripped == "":
			buf.append("")
		else:
			buf.append(_inline_format(stripped))
		i += 1
	flush_text.call()
	return segments

static func _inline_format(s: String) -> String:
	var result := _escape_bb(s)
	var rg := RegEx.new()
	if rg.compile("`([^`]+)`") == OK:
		for m in rg.search_all(result):
			result = result.replace(m.get_string(), "[code]%s[/code]" % m.get_string(1))
	rg = RegEx.new()
	if rg.compile("\\*\\*([^*]+)\\*\\*") == OK:
		for m in rg.search_all(result):
			result = result.replace(m.get_string(), "[b]%s[/b]" % m.get_string(1))
	rg = RegEx.new()
	if rg.compile("\\[([^\\]]+)\\]\\(([^\\)]*)\\)") == OK:
		for m in rg.search_all(result):
			result = result.replace(m.get_string(), "[url=%s]%s[/url]" % [m.get_string(2), m.get_string(1)])
	return result

static func _escape_bb(s: String) -> String:
	return s.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
