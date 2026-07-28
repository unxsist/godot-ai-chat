class_name AiCopilotSettings
extends RefCounted

signal setting_changed(key: String, value)

const KEYS := {
	"provider": AiCopilotProviders.DEFAULT_PROVIDER_ID,
	"base_url": "",
	"endpoint": AiCopilotConst.DEFAULT_ENDPOINT,
	"model": "",
	"vision_model": "",
	"model_context_window": 32000,
	"api_key": "",
	"temperature": 0.2,
	"max_tokens": 4096,
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
	_migrate_endpoint_to_provider()

# Pre-provider installs stored a raw `endpoint` with no `provider` key. Map that
# endpoint onto a known provider (or "custom" with the endpoint as base_url) so
# existing users keep working after upgrading.
func _migrate_endpoint_to_provider() -> void:
	if _config.has_section_key("general", "provider"):
		return
	var ep := String(_config.get_value("general", "endpoint", "")).strip_edges()
	if ep == "":
		return
	var matched := ""
	for p in AiCopilotProviders.all():
		if String(p.get("base_url", "")) != "" and ep == String(p["base_url"]):
			matched = String(p["id"])
			break
	if matched != "":
		_config.set_value("general", "provider", matched)
	else:
		_config.set_value("general", "provider", "custom")
		_config.set_value("general", "base_url", ep)
	_config.save(AiCopilotConst.SETTINGS_FILE)

func _ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(AiCopilotConst.USER_DIR)

# --- provider resolution -------------------------------------------------

# Base URL for the currently selected provider (honors custom/local override).
func effective_base_url() -> String:
	var pid := String(get_value("provider"))
	var override := String(get_value("base_url"))
	var url := AiCopilotProviders.base_url_for(pid, override)
	# Back-compat: pre-provider installs only had a raw endpoint.
	if url == "":
		url = String(get_value("endpoint"))
	return url

# {name, value} auth header for the current provider + stored key.
func effective_auth_header() -> Dictionary:
	return AiCopilotProviders.auth_header_for(String(get_value("provider")), String(get_value("api_key")))

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
