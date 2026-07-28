class_name AiCopilotSSEStream
extends RefCounted

signal data_line(json_str: String)
signal done_received()
signal heartbeat()
signal stream_closed()
signal stream_error(message: String)

var _http: HTTPClient
var _host: String
var _path: String
var _auth: String
var _body: String
var _buffer: String = ""
var _done: bool = false

func _init(host: String, path: String, auth_header: String, body: String) -> void:
	_host = host
	_path = path
	_auth = auth_header
	_body = body

func run(host_node: Node) -> void:
	_http = HTTPClient.new()
	var err := _http.connect_to_host(_host, -1, TLSOptions.client())
	if err != OK:
		stream_error.emit("connect_to_host err=%d" % err)
		return
	while _http.get_status() == HTTPClient.STATUS_CONNECTING or _http.get_status() == HTTPClient.STATUS_RESOLVING:
		_http.poll()
		await host_node.get_tree().process_frame
	if _http.get_status() != HTTPClient.STATUS_CONNECTED:
		stream_error.emit("not connected, status=%d" % _http.get_status())
		return
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: " + _auth,
		"Accept: text/event-stream",
	])
	err = _http.request(HTTPClient.METHOD_POST, _path, headers, _body)
	if err != OK:
		stream_error.emit("request err=%d" % err)
		return
	while _http.get_status() == HTTPClient.STATUS_REQUESTING:
		_http.poll()
		await host_node.get_tree().process_frame
	if not _http.has_response():
		stream_error.emit("no response")
		return
	while _http.get_status() == HTTPClient.STATUS_BODY:
		_http.poll()
		var chunk := _http.read_response_body_chunk()
		if chunk.size() > 0:
			_consume_bytes(chunk)
		await host_node.get_tree().process_frame
	stream_closed.emit()

func _consume_bytes(bytes: PackedByteArray) -> void:
	_buffer += bytes.get_string_from_utf8()
	if _buffer.find("\r\n\r\n") != -1:
		_buffer = _buffer.replace("\r\n\r\n", "\n\n")
		_buffer = _buffer.replace("\r\n", "\n")
	while true:
		var sep := _buffer.find("\n\n")
		if sep == -1: break
		var event_block := _buffer.substr(0, sep)
		_buffer = _buffer.substr(sep + 2)
		_dispatch_event(event_block)

func _dispatch_event(block: String) -> void:
	var lines := block.split("\n", false)
	for line in lines:
		if line.begins_with(":"):
			heartbeat.emit()
			continue
		if line.begins_with("data:"):
			var payload := line.substr(5).strip_edges()
			if payload == "[DONE]":
				_done = true
				done_received.emit()
				return
			data_line.emit(payload)
