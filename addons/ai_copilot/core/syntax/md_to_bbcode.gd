class_name AiCopilotMDToBBCode
extends RefCounted

# Render markdown to a single bbcode string for LIVE streaming. Applies the same
# block + inline rules as convert_segments, but produces one bbcode string
# (code fences become inline [code] blocks) so it can be set on a RichTextLabel
# on every streamed token. Handles a still-open code fence at the end.
static func render_stream(md: String) -> String:
	var lines := md.split("\n")
	var out := PackedStringArray()
	var i := 0
	var in_code := false
	var code_buf := PackedStringArray()
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		if stripped.begins_with("```"):
			if in_code:
				# closing fence: flush the code block
				out.append("[code]%s[/code]" % _escape_bb("\n".join(code_buf)))
				code_buf = PackedStringArray()
				in_code = false
			else:
				in_code = true
			i += 1
			continue
		if in_code:
			code_buf.append(line)
			i += 1
			continue
		if stripped.begins_with("### "):
			out.append("[b][color=#9aa]%s[/color][/b]" % _escape_bb(stripped.substr(4)))
		elif stripped.begins_with("## "):
			out.append("[b]%s[/b]" % _escape_bb(stripped.substr(3)))
		elif stripped.begins_with("# "):
			out.append("[b]%s[/b]" % _escape_bb(stripped.substr(2)))
		elif stripped == "---" or stripped == "***":
			out.append("[color=#555]────────[/color]")
		elif stripped.begins_with("> "):
			out.append("[color=#99a]▏ %s[/color]" % _inline_format(stripped.substr(2)))
		elif stripped.begins_with("- ") or stripped.begins_with("* "):
			out.append("  • %s" % _inline_format(stripped.substr(2)))
		elif _is_ordered_item(stripped):
			var dot := stripped.find(". ")
			out.append("  %s. %s" % [stripped.substr(0, dot), _inline_format(stripped.substr(dot + 2))])
		else:
			out.append(_inline_format(line))
		i += 1
	# an unterminated code fence still streaming: show what we have so far
	if in_code and code_buf.size() > 0:
		out.append("[code]%s[/code]" % _escape_bb("\n".join(code_buf)))
	return "\n".join(out)

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
		elif _is_ordered_item(stripped):
			var dot := stripped.find(". ")
			buf.append("  %s. %s" % [stripped.substr(0, dot), _inline_format(stripped.substr(dot + 2))])
		elif stripped == "":
			buf.append("")
		else:
			buf.append(_inline_format(stripped))
		i += 1
	flush_text.call()
	return segments

# True for "1. text", "23. text", etc.
static func _is_ordered_item(s: String) -> bool:
	var dot := s.find(". ")
	if dot <= 0:
		return false
	var num := s.substr(0, dot)
	return num.is_valid_int()

# Inline markdown -> bbcode. Processes in a single left-to-right pass so that
# code spans are protected (their contents aren't re-formatted) and repeated
# text is handled positionally (no String.replace pitfalls).
# Supports: `code`, **bold**, __bold__, *italic*, _italic_, [text](url).
static func _inline_format(s: String) -> String:
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		var c := s[i]
		# inline code span: `...`
		if c == "`":
			var end := s.find("`", i + 1)
			if end != -1:
				out += "[code]%s[/code]" % _escape_bb(s.substr(i + 1, end - i - 1))
				i = end + 1
				continue
		# links: [text](url)
		if c == "[":
			var close := s.find("]", i + 1)
			if close != -1 and close + 1 < n and s[close + 1] == "(":
				var paren := s.find(")", close + 2)
				if paren != -1:
					var label := s.substr(i + 1, close - i - 1)
					var url := s.substr(close + 2, paren - close - 2)
					out += "[url=%s]%s[/url]" % [url, _inline_format(label)]
					i = paren + 1
					continue
		# bold: ** ** or __ __
		if (c == "*" and i + 1 < n and s[i + 1] == "*") or (c == "_" and i + 1 < n and s[i + 1] == "_"):
			var marker := s.substr(i, 2)
			var end2 := s.find(marker, i + 2)
			if end2 != -1:
				out += "[b]%s[/b]" % _inline_format(s.substr(i + 2, end2 - i - 2))
				i = end2 + 2
				continue
			# Unclosed bold marker (common mid-stream): keep it literal and skip
			# both chars so the italic rule below doesn't treat it as empty italic.
			out += _escape_bb(marker)
			i += 2
			continue
		# italic: * * or _ _  (single, not part of a word for _)
		if c == "*" or (c == "_" and _is_word_boundary(s, i)):
			var end3 := _find_italic_close(s, i + 1, c)
			if end3 != -1:
				out += "[i]%s[/i]" % _inline_format(s.substr(i + 1, end3 - i - 1))
				i = end3 + 1
				continue
		out += _escape_bb(c)
		i += 1
	return out

# Underscore italics only at word boundaries so snake_case isn't italicized.
static func _is_word_boundary(s: String, i: int) -> bool:
	if i == 0:
		return true
	var prev := s[i - 1]
	return prev == " " or prev == "\t" or prev == "(" or prev == "\""

static func _find_italic_close(s: String, from: int, marker: String) -> int:
	var j := from
	while j < s.length():
		if s[j] == marker:
			# don't treat a doubled marker as a close (that's bold)
			if j + 1 < s.length() and s[j + 1] == marker:
				j += 2
				continue
			return j
		j += 1
	return -1

static func _escape_bb(s: String) -> String:
	return s.replace("[", "[lb]")
