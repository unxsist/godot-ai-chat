class_name AiCopilotStreamingStrategy
extends RefCounted

signal probe_done(works: bool)

const CACHE_FILE := "user://ai_copilot/.sse_ok"
const CACHE_MAX_AGE := 60 * 60 * 24

var _works: bool = true

func get_works() -> bool:
	return _works

func probe(host_node: Node, settings: AiCopilotSettings) -> void:
	var cached = _read_cache()
	if cached != null:
		_works = cached
		probe_done.emit(_works)
		return
	if (settings.get_value("model") as String) == "":
		_works = false
		_write_cache(false)
		probe_done.emit(false)
		return
	var tiny := [{"role":"user","content":"ping"}]
	var endpoint := settings.get_value("endpoint") as String
	var host := _extract_host(endpoint)
	var base_path := _extract_path(endpoint)
	var sse := AiCopilotSSEStream.new(
		host, base_path + AiCopilotConst.CHAT_COMPLETIONS_PATH,
		"Bearer " + (settings.get_value("api_key") as String),
		JSON.stringify({"model": settings.get_value("model"), "messages": tiny, "stream": true}, "", false)
	)
	var got := [false]
	sse.data_line.connect(func(_j): got[0] = true)
	sse.done_received.connect(func(): pass)
	sse.stream_error.connect(func(_m): got[0] = false)
	await sse.run(host_node)
	_works = got[0]
	_write_cache(_works)
	probe_done.emit(_works)

func _read_cache():
	if not FileAccess.file_exists(CACHE_FILE): return null
	var mtime := FileAccess.get_modified_time(CACHE_FILE)
	var now := Time.get_unix_time_from_system()
	if now - mtime > CACHE_MAX_AGE: return null
	var f := FileAccess.open(CACHE_FILE, FileAccess.READ)
	if f == null: return null
	return f.get_8() != 0

func _write_cache(works: bool) -> void:
	var f := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if f == null: return
	f.store_8(1 if works else 0)
	f.close()

func _strip_scheme(url: String) -> String:
	var s := url
	if s.begins_with("https://"): s = s.substr(8)
	elif s.begins_with("http://"): s = s.substr(7)
	return s

func _extract_host(full_url: String) -> String:
	var s := _strip_scheme(full_url)
	var slash := s.find("/")
	if slash != -1: s = s.substr(0, slash)
	return s

func _extract_path(full_url: String) -> String:
	var s := _strip_scheme(full_url)
	var slash := s.find("/")
	if slash != -1: return s.substr(slash)
	return ""
