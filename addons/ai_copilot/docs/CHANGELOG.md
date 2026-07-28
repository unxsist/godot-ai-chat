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
