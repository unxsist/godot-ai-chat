class_name AiCopilotProviders
extends RefCounted

# Registry of LLM providers, modeled after KiloCode's provider profiles.
# Every provider here speaks the OpenAI /chat/completions protocol, so they
# differ only by base URL, auth header, and (optionally) recommended models.
#
# Fields per provider:
#   id            stable identifier (stored in settings)
#   name          display name
#   base_url      OpenAI-compatible base (we append /chat/completions and /models)
#   auth_header   header name for the key ("Authorization" => "Bearer <key>")
#   auth_prefix   value prefix (e.g. "Bearer ")
#   needs_key     whether an API key is required (false for local servers)
#   keys_url      where to get an API key (shown as a hint)
#   models        recommended model ids (used before/if /models isn't fetched)
#   recommended   show in the "Recommended" group of the picker
#   editable_url  allow the user to override base_url (custom/local)

const PROVIDERS := [
	{
		"id": "openai", "name": "OpenAI", "base_url": "https://api.openai.com/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://platform.openai.com/api-keys",
		"models": ["gpt-4o", "gpt-4o-mini", "o3-mini"], "recommended": true, "editable_url": false,
	},
	{
		"id": "openrouter", "name": "OpenRouter", "base_url": "https://openrouter.ai/api/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://openrouter.ai/keys",
		"models": ["anthropic/claude-3.5-sonnet", "openai/gpt-4o", "google/gemini-2.0-flash-exp"],
		"recommended": true, "editable_url": false,
	},
	{
		"id": "anthropic_openai", "name": "Anthropic (OpenAI-compatible)", "base_url": "https://api.anthropic.com/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://console.anthropic.com/settings/keys",
		"models": ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"], "recommended": true, "editable_url": false,
	},
	{
		"id": "google", "name": "Google Gemini (OpenAI-compatible)", "base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://aistudio.google.com/apikey",
		"models": ["gemini-2.0-flash", "gemini-1.5-pro"], "recommended": true, "editable_url": false,
	},
	{
		"id": "deepseek", "name": "DeepSeek", "base_url": "https://api.deepseek.com/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://platform.deepseek.com/api_keys",
		"models": ["deepseek-chat", "deepseek-reasoner"], "recommended": true, "editable_url": false,
	},
	{
		"id": "groq", "name": "Groq", "base_url": "https://api.groq.com/openai/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://console.groq.com/keys",
		"models": ["llama-3.3-70b-versatile", "moonshotai/kimi-k2-instruct"], "recommended": false, "editable_url": false,
	},
	{
		"id": "fireworks", "name": "Fireworks AI", "base_url": "https://api.fireworks.ai/inference/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://fireworks.ai/account/api-keys",
		"models": ["accounts/fireworks/models/kimi-k2-instruct"], "recommended": false, "editable_url": false,
	},
	{
		"id": "togetherai", "name": "Together AI", "base_url": "https://api.together.xyz/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://api.together.ai/settings/api-keys",
		"models": ["meta-llama/Llama-3.3-70B-Instruct-Turbo"], "recommended": false, "editable_url": false,
	},
	{
		"id": "xai", "name": "xAI (Grok)", "base_url": "https://api.x.ai/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://console.x.ai",
		"models": ["grok-2-latest"], "recommended": false, "editable_url": false,
	},
	{
		"id": "mistral", "name": "Mistral AI", "base_url": "https://api.mistral.ai/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://console.mistral.ai/api-keys",
		"models": ["mistral-large-latest", "codestral-latest"], "recommended": false, "editable_url": false,
	},
	{
		"id": "cerebras", "name": "Cerebras", "base_url": "https://api.cerebras.ai/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://cloud.cerebras.ai",
		"models": ["llama-3.3-70b"], "recommended": false, "editable_url": false,
	},
	{
		"id": "deepinfra", "name": "DeepInfra", "base_url": "https://api.deepinfra.com/v1/openai",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://deepinfra.com/dash/api_keys",
		"models": [], "recommended": false, "editable_url": false,
	},
	{
		"id": "moonshot", "name": "Moonshot (Kimi)", "base_url": "https://api.moonshot.ai/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": true,
		"keys_url": "https://platform.moonshot.ai/console/api-keys",
		"models": ["kimi-k2-0711-preview"], "recommended": false, "editable_url": false,
	},
	{
		"id": "ollama", "name": "Ollama (local)", "base_url": "http://localhost:11434/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": false,
		"keys_url": "https://ollama.com",
		"models": [], "recommended": false, "editable_url": true,
	},
	{
		"id": "lmstudio", "name": "LM Studio (local)", "base_url": "http://localhost:1234/v1",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": false,
		"keys_url": "https://lmstudio.ai",
		"models": [], "recommended": false, "editable_url": true,
	},
	{
		"id": "custom", "name": "OpenAI-Compatible (custom)", "base_url": "",
		"auth_header": "Authorization", "auth_prefix": "Bearer ", "needs_key": false,
		"keys_url": "",
		"models": [], "recommended": false, "editable_url": true,
	},
]

const DEFAULT_PROVIDER_ID := "openai"

static func all() -> Array:
	return PROVIDERS

static func get_provider(id: String) -> Dictionary:
	for p in PROVIDERS:
		if p["id"] == id:
			return p
	return {}

static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in PROVIDERS:
		out.append(p["id"])
	return out

# Resolve the effective base URL for a provider, honoring a user override for
# custom/local providers.
static func base_url_for(id: String, override_url: String = "") -> String:
	var p := get_provider(id)
	if p.is_empty():
		return override_url.strip_edges()
	if bool(p.get("editable_url", false)) and override_url.strip_edges() != "":
		return override_url.strip_edges()
	if p["id"] == "custom":
		return override_url.strip_edges()
	return String(p["base_url"])

static func auth_header_for(id: String, key: String) -> Dictionary:
	var p := get_provider(id)
	if p.is_empty():
		return {"name": "Authorization", "value": "Bearer " + key}
	return {"name": String(p.get("auth_header", "Authorization")), "value": String(p.get("auth_prefix", "Bearer ")) + key}
