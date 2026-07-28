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
