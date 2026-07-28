class_name AiCopilotSettings
extends RefCounted

signal setting_changed(key: String, value)

const KEYS := {
	"endpoint": AiCopilotConst.DEFAULT_ENDPOINT,
	"model": "",
	"vision_model": "",
	"model_context_window": 32000,
	"api_key": "",
	"temperature": 0.2,
	"max_tokens": 4096,
	"max_steps": AiCopilotConst.MAX_STEPS_DEFAULT,
	"approve_default": true,
	"allow_shell": true,
	"compact_threshold": AiCopilotConst.COMPACT_THRESHOLD_DEFAULT,
	"verbose_logging": false,
}

var _config := ConfigFile.new()
var _salt: PackedByteArray = PackedByteArray()

func _init() -> void:
	_salt = AiCopilotSalt.ensure_salt()
	_ensure_user_dir()
	var err := _config.load(AiCopilotConst.SETTINGS_FILE)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("[ai_copilot] settings load err=%d" % err)

func _ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(AiCopilotConst.USER_DIR)

func get_value(key: String):
	var default = KEYS.get(key, null)
	if key == "api_key":
		var stored := _config.get_value("secrets", "api_key", "") as String
		if stored == "":
			return ""
		return _xor_decrypt(stored)
	return _config.get_value("general", key, default)

func set_value(key: String, value) -> void:
	if key == "api_key":
		var enc := _xor_encrypt(str(value))
		_config.set_value("secrets", "api_key", enc)
	else:
		_config.set_value("general", key, value)
	_config.save(AiCopilotConst.SETTINGS_FILE)
	setting_changed.emit(key, value)

func _xor_encrypt(plaintext: String) -> String:
	if _salt.size() != 32 or plaintext == "":
		return ""
	var bytes := plaintext.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(bytes.size())
	for i in bytes.size():
		out[i] = bytes[i] ^ _salt[i % 32]
	return Marshalls.raw_to_base64(out)

func _xor_decrypt(b64: String) -> String:
	if _salt.size() != 32 or b64 == "":
		return ""
	var bytes := Marshalls.base64_to_raw(b64)
	var out := PackedByteArray()
	out.resize(bytes.size())
	for i in bytes.size():
		out[i] = bytes[i] ^ _salt[i % 32]
	return out.get_string_from_utf8()
