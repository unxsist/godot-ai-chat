# Changelog

## 0.1.0
- Initial release
- Chat sidebar with streaming token reveal
- Tool-calling agent loop (max 20 steps)
- Approve mode with diff preview
- fs, shell, editor tools
- Vision support for viewport screenshot
- Session persistence
- Auto-compaction
- Public extensibility hook
- Fix: text preceding a fenced code block was duplicated after the block in the message renderer
- Fix: approval card was never configured (set_call ran before the view built its widgets), so the diff/actions never appeared
- Approval card redesigned: dark themed, shows an inline colored diff for `write_file`/`edit_file` automatically (no extra click), with an Expand button for the full side-by-side view
- Diff preview dialog restyled to match the editor dark theme with syntax highlighting
- Fix: a tall approval diff pushed the Approve/Reject buttons out of reach — the inline diff now caps its height and scrolls internally, and the chat panel waits for layout before auto-scrolling
- Fix: the approval card (`ToolView`) is now a `MarginContainer`, so it reports its real height to the chat list; previously it claimed only 80px and its diff + buttons overflowed outside the scrollable area
- Fix: streaming now falls back to a non-streaming (batch) request when the SSE stream errors, returns a non-2xx status, or yields no data — previously such failures showed an empty response with no thinking/text
- Docs: replaced the three separate UI screenshots with a single hero image of the plugin docked in the real Godot editor
- Multi-provider support: pick from 15+ OpenAI-compatible providers (OpenAI, OpenRouter, Anthropic, Gemini, DeepSeek, Groq, Fireworks, Together, xAI, Mistral, Cerebras, DeepInfra, Moonshot, Ollama, LM Studio, custom) via a provider dropdown in settings, with per-provider base URL/auth, an API-key hint link, and live `/models` fetching. Local providers work over http (no TLS) and custom ports. Existing installs auto-migrate their old endpoint to the matching provider.
- Fix: reasoning/thinking is now emitted from the batch (and streaming-fallback) path too, and accepts both `reasoning_content` and `reasoning` keys — previously thinking was dropped whenever a request didn't stream
- New `run_and_capture` tool: runs the game (or a scene) in a time-limited subprocess and reports runtime errors/warnings — null references, index errors, failed assertions, `push_error`/`push_warning` — with file:line and GDScript backtrace. Catches runtime bugs that `check_scripts` (compile-only) cannot.
- Settings reorganized into **Connection** and **Advanced** tabs — provider/key/model up front, everything else tucked away.
- Removed the `max_steps` setting: the agent loop ends naturally when the model replies without tool calls (a hidden safety cap gracefully asks it to summarize if ever reached).
- Consecutive calls to the same tool are now grouped under one collapsible pill (e.g. `read_file ×3`); a different tool starts a new group.
- Markdown rendering fixes: links now work, added italics (`*x*` / `_x_`) and ordered lists, protected inline code, and made inline formatting position-safe (`snake_case` no longer italicized).
- Markdown now renders **live while streaming** (bold/italic/code/links/lists), not only after the message completes. Unclosed markers mid-stream stay literal until their closing marker arrives.
