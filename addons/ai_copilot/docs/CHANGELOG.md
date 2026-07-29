# Changelog

## 1.0.1
- Packaging: `README.md` and `LICENSE` now ship inside the `addons/ai_copilot/` folder, and the release archive contains only the addon (no `.gitignore`). Per Asset Library review feedback.

## 1.0.0
First stable release.

### Highlights
- **Agentic chat dock** — a Copilot/Claude-style sidebar in the Godot 4.7 editor. The agent plans, calls tools over multiple rounds, checks its own work, and stops when done.
- **15+ LLM providers** via a provider picker: OpenAI, OpenRouter, Anthropic, Google Gemini, DeepSeek, Groq, Fireworks, Together AI, xAI (Grok), Mistral, Cerebras, DeepInfra, Moonshot, Ollama, LM Studio, and a generic OpenAI-compatible (custom) endpoint. Live `/models` fetching; local providers work over http and custom ports with no API key.
- **Inline diff approvals** — approve mode shows a colored before/after diff for every `write_file` / `edit_file` before it's applied, with an Expand button for the full side-by-side view.
- **Runtime error capture** — the `run_and_capture` tool plays the game (or a scene) in a time-limited process and reports runtime errors/warnings (null refs, index errors, `push_error`) with file:line and GDScript backtrace — bugs that compile-checks can't catch.
- **Native-feeling UI** — dark chat dock with token streaming, live markdown (bold/italic/code/links/lists), syntax-highlighted code blocks, grouped tool pills, and a live plan panel. Editor-scaled fonts.

### Tools
`read_file`, `list_files`, `glob`, `grep`, `write_file`, `edit_file`, `delete_file`, `rename_file`, `run_command`, `create_scene`, `add_node`, `run_scene`, `run_project`, `run_and_capture`, `open_script`, `get_open_scenes`, `check_scripts`, `viewport_screenshot`, `project_get_setting`, `project_set_setting`, `project_add_input_action`, `todowrite`.

### Also included
- Approve/allow-shell/temperature/context-window and other options under a Connection / Advanced settings split.
- Session persistence across editor restarts and automatic conversation compaction near the context window.
- Vision support (viewport screenshot) when a vision model is configured.
- Sandboxed to `res://`; the agent cannot touch its own addon folder.
- Public tool-registration API for adding your own tools.
