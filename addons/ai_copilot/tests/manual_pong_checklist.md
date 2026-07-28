# Manual end-to-end v0.1 acceptance

## Setup
- [ ] Open Godot 4.7.1.
- [ ] Open `project.godot`.
- [ ] Enable AI Copilot plugin.
- [ ] Open settings; paste Fireworks API key.
- [ ] Set default model to an OpenAI-compatible tool-call-capable model.
- [ ] Save settings; restart Godot; verify dock + history restored.

## The test: "Make a Pong game"

- [ ] Send: "Build me a basic Pong game in Godot 4.7. Two paddles, a ball, score to 5. Open the main scene when done."
- [ ] Observe agent streams tokens; tool calls (`fs.write_file`, `fs.write_file res://main.tscn ...`) appear as approve-mode diff dialogs.
- [ ] Approve dialogs; let agent finish (~5–15 steps).
- [ ] Agent's last message mentions success; the main.tscn opens automatically.
- [ ] Hit F5; game runs with two paddles controllable via W/S and arrow keys.
- [ ] Score reaches 5 → game ends.

## Caveats
- File edits are not atomic; if agent crashes mid-batch, partial files may persist.
- Tool args JSON failures cause a one-time retry followed by an abort.
- Stop button halts after the current tool finishes.
- Compaction fires after ~23 turns (model dependent).
