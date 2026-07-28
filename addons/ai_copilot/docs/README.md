# AI Copilot — Godot Editor Plugin

A Copilot/Claude-style chat sidebar embedded in the Godot 4.7 editor. Chat with an LLM
that can edit your project: read files, write scripts, refactor scenes, run shell commands,
and inspect the live editor state.

## Features

- Chat sidebar (right-dock), markdown + fenced-code rendering with syntax highlighting.
- 15+ LLM providers via a provider picker (OpenAI, OpenRouter, Anthropic, Gemini, DeepSeek, Groq, Fireworks, Together, xAI, Mistral, Cerebras, Ollama, LM Studio, custom…) with live `/models` fetch.
- Streaming token-by-token (with graceful fallback to batch).
- Agent loop with tool calls (multi-round, max 20 steps per message).
- Approve mode (default) shows an inline diff for `write_file` / `edit_file` before applying.
- Tools: `read_file`, `list_files`, `glob`, `grep`, `write_file`, `edit_file`, `delete_file`, `rename_file`, `run_command`, `create_scene`, `add_node`, `run_scene`, `run_project`, `run_and_capture` (run the game and collect runtime errors), `open_script`, `get_open_scenes`, `check_scripts`, `viewport_screenshot`, `project_get_setting` / `project_set_setting`, `project_add_input_action`, `todowrite`.
- Runtime error checking: `run_and_capture` runs the game in a time-limited process and reports runtime errors/warnings (null refs, index errors, `push_error`) with file:line + backtrace — catching bugs `check_scripts` (compile-only) can't.
- Sandbox: agent cannot access outside `res://` or inside `res://addons/ai_copilot/`.
- Session persistence across editor restarts.
- Auto-compaction when conversation approaches the model context window.
- Public tool registration API.

## Screenshot

![AI Copilot docked in the Godot editor](screenshots/editor.png)

*The agent writing a pause menu into the demo project — code, tool calls, and results inline in the dock.*

## Installation

1. Copy `addons/ai_copilot/` into your project's `addons/` directory.
2. In Godot: **Project → Project Settings → Plugins → enable "AI Copilot"**.
3. Click the gear in the dock; set your Fireworks API key and model.

## Adding your own tools

```gdscript
@tool
extends Node

func _ready() -> void:
    var api := Engine.get_meta("AiCopilotAPI", null)
    if api == null: return
    api.registry.register_tool(
        "greet_player",
        "Salute the player by name.",
        {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]},
        func(call, args):
            return AiCopilotLLMTypes.ToolResult.new("Hello, %s!" % String(args.get("name", "stranger")), false),
        false
    )
```

## Settings

Open the settings dialog (gear/menu in the dock). Pick a **provider** from the
dropdown, paste your API key, then **Fetch models** to list what the endpoint
offers (or type a model id directly). Local providers (Ollama, LM Studio) need
no key — just start the server and fetch.

Supported providers (all OpenAI `/chat/completions` compatible): OpenAI,
OpenRouter, Anthropic, Google Gemini, DeepSeek, Groq, Fireworks, Together AI,
xAI (Grok), Mistral, Cerebras, DeepInfra, Moonshot, Ollama, LM Studio, and a
generic **OpenAI-Compatible (custom)** entry with an editable base URL.

| Key | Default | Notes |
|---|---|---|
| provider | openai | Selected provider id |
| base_url | (provider default) | Editable for custom / local providers |
| model | (none) | Chat completions model; use Fetch models to list |
| vision_model | (none) | Required for viewport screenshot |
| model_context_window | 32000 | For compaction threshold |
| api_key | (none) | Stored XOR'd with per-install salt |
| temperature | 0.2 | |
| max_tokens | 4096 | |
| max_steps | 20 | Tool call limit per message |
| approve_default | true | Mutating tools need approval |
| allow_shell | true | Disable to unregister shell.run |
| compact_threshold | 0.7 | Conversation / context window |
| verbose_logging | false | Toggle debug logging |

Upgrading from a pre-provider version keeps working: your old `endpoint` is
auto-mapped to the matching provider (or a custom base URL).

## License

MIT
