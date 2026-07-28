@tool
class_name AiCopilotGDHighlighter
extends SyntaxHighlighter

const COLOR_KEYWORD := Color("ff7085")
const COLOR_TYPE := Color("8ed8ff")
const COLOR_STRING := Color("bda68c")
const COLOR_NUMBER := Color("e0e0e0")
const COLOR_COMMENT := Color("808080")
const COLOR_FUNC := Color("ffe082")
const COLOR_DEFAULT := Color("e0e0e0")

var _keywords: Array[String] = [
	"func", "var", "const", "if", "elif", "else", "for", "while", "return", "match",
	"extends", "class", "class_name", "signal", "static", "true", "false", "null",
	"self", "await", "and", "or", "not", "break", "continue", "pass", "is", "as", "in", "enum"
]
var _types: Array[String] = ["int", "float", "String", "bool", "void", "Array", "Dictionary",
	"Vector2", "Vector3", "Rect2", "Node", "RefCounted", "Variant", "Callable",
	"PackedStringArray", "PackedByteArray"]

func _get_line_syntax_highlighting(line_num: int) -> Dictionary:
	var code_edit := get_text_edit() as CodeEdit
	if code_edit == null:
		return {}
	var line := code_edit.get_line(line_num)
	var out := Dictionary()
	var pos := 0
	while pos < line.length():
		var ch := line[pos]
		if ch == "#":
			out[pos] = {"color": COLOR_COMMENT}
			return out
		if ch == "\"":
			var end := pos + 1
			while end < line.length() and line[end] != "\"":
				end += 1
			out[pos] = {"color": COLOR_STRING}
			if end + 1 <= line.length():
				out[end + 1] = {"color": COLOR_DEFAULT}
			pos = end + 1
			continue
		if ch.is_valid_int() or (ch == "." and pos + 1 < line.length() and line[pos + 1].is_valid_int()):
			out[pos] = {"color": COLOR_NUMBER}
			pos += 1
			continue
		var word_start := pos
		while pos < line.length():
			var chc := line[pos]
			if not ((chc >= "A" and chc <= "Z") or (chc >= "a" and chc <= "z") or (chc >= "0" and chc <= "9") or chc == "_"):
				break
			pos += 1
		if pos > word_start:
			var word := line.substr(word_start, pos - word_start)
			var color: Color = COLOR_DEFAULT
			if word in _keywords:
				color = COLOR_KEYWORD
			elif word in _types:
				color = COLOR_TYPE
			elif pos < line.length() and line[pos] == "(":
				color = COLOR_FUNC
			out[word_start] = {"color": color}
			continue
		pos += 1
	return out
