# pi-nvim

Bridge between [pi](https://github.com/badlogic/pi) coding agent and Neovim. Run pi in one terminal pane and Neovim in another — send files, selections, and prompts from Neovim directly into your running pi session.

![demo](./demo/demo.gif)

## How it works

The repo contains two components:

1. **Pi extension** (`index.ts`) — opens a unix socket when pi starts. External tools can send JSON messages to inject prompts into the active pi session.
2. **Neovim plugin** (`lua/pi-nvim/`) — connects to that socket via libuv. Sends context from your editor to pi.

Discovery is automatic: the extension writes socket info to `/tmp/pi-nvim-sockets/`, and the Neovim plugin scans that directory, preferring sessions matching your cwd.

On Windows, unix sockets don't exist, so the extension binds a named pipe (`\\.\pipe\pi-nvim-*`) and writes the manifests into `%TEMP%/pi-nvim-sockets/` instead — the plugin reads the actual connect address from the manifest's `socket` field. Unix behavior is unchanged.

## Install

### Pi side

```bash
pi install npm:pi-nvim
```

Or add to `~/.pi/agent/settings.json`:

```json
{
  "packages": ["https://github.com/carderne/pi-nvim"]
}
```

Then `/reload` in pi.

### Neovim side

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "carderne/pi-nvim" }
```

Then in your config:

```lua
require("pi-nvim").setup()
```

Options (defaults):

```lua
require("pi-nvim").setup({
  socket_path = nil, -- auto-discover
  set_default_keymaps = true,
})
```

## Usage

Start pi in one terminal. Start Neovim in another. The pi extension automatically opens a socket on session start.

### Commands

| Command | Description |
|---|---|
| `:Pi` | Open the Send to pi dialog (works in normal and visual mode) |
| `:PiSend` | Type a prompt and send to pi |
| `:PiSendFile` | Send current file path + prompt |
| `:PiSendSelection` | Send visual selection + prompt |
| `:PiSendBuffer` | Send entire buffer + prompt |
| `:PiAppendSelection` | Append a line range to the Pi terminal draft without submitting |
| `:PiAppendSelectionPrompt` | Append a line range with a user prompt to the Pi terminal draft |
| `:PiAppendFile` | Append the current absolute file path to the draft |
| `:PiAppendBuffer` | Append the entire buffer (including unsaved edits) to the draft |
| `:PiPing` | Check if pi is reachable |
| `:PiSessions` | List/switch between running pi sessions |

### Default keybindings

`<leader>p` is mapped to `:Pi` in both normal and visual mode by default.

To disable the default mappings:

```lua
require("pi-nvim").setup({
  set_default_keymaps = false,
})
```

### The `:Pi` dialog

Opens a floating window in the center of the screen:

- Shows the current **file name** (always sent)
- If you had a **visual selection**, it shows the line range and sends the selected text
- If no selection, you can press **Tab** to toggle sending the **entire buffer**
- Type a prompt and press **Enter** to send (or just Enter with no prompt)
- Press **Esc** or **Ctrl-C** to cancel

### Additional keybindings

```lua
vim.keymap.set("n", "<leader>pp", ":PiSend<CR>")
vim.keymap.set("n", "<leader>pf", ":PiSendFile<CR>")
vim.keymap.set("v", "<leader>ps", ":PiSendSelection<CR>")
vim.keymap.set("n", "<leader>pb", ":PiSendBuffer<CR>")
vim.keymap.set("n", "<leader>pi", ":PiPing<CR>")
```

### Collect context, then write your message in Kitty

The append actions add context to the running Pi terminal's input editor. They
preserve any existing draft, keep focus in Neovim, and **do not start or queue an
agent turn**. Collect several snippets, switch to your Pi pane, write your
question, and press Enter there when ready. No separate Neovim draft is kept.

```lua
local pi = require("pi-nvim")
vim.keymap.set("x", "<leader>ps", pi.append_selection,
  { desc = "Add selection to Pi draft" })
vim.keymap.set("x", "<leader>pa", pi.append_selection_prompt,
  { desc = "Add selection with message to Pi draft" })
vim.keymap.set("n", "<leader>pf", pi.append_file,
  { desc = "Add file reference to Pi draft" })
vim.keymap.set("n", "<leader>pb", pi.append_buffer,
  { desc = "Add buffer to Pi draft" })
```

The visual mapping captures characterwise, linewise, and blockwise selections.
`:10,20PiAppendSelection` appends an explicit line range. Selections and buffers
are code snapshots with absolute file paths; file references contain only the
path, so save the file if you want the agent to read recent edits from disk.
These mappings are opt-in; the existing default `<leader>p` still opens the
send dialog and existing `PiSend*` commands still submit immediately.

Use `:PiSessions` to select the intended agent when several are running. Both
the Lua plugin and Pi extension must include append support. Reload/restart Pi
after updating its extension and restart Neovim after changing mappings.
Appending requires Pi's TUI with `ctx.mode`, `getEditorText`, and `setEditorText`
APIs (tested against Pi 1.5.0 APIs); RPC/print/JSON modes are rejected rather than
risking draft replacement. Drafts have the same lifetime as Pi's normal input
editor; this feature does not persist them separately across restarts.

## Protocol

The socket accepts newline-delimited JSON:

```json
{"type": "prompt", "message": "your prompt here"}
{"type": "append_draft", "message": "context to append without submitting"}
{"type": "ping"}
```

Responses:

```json
{"ok": true}
{"ok": true, "type": "pong"}
{"ok": false, "error": "..."}
```

This means you can also send prompts from any tool:

```bash
echo '{"type":"prompt","message":"hello"}' | socat - UNIX-CONNECT:/tmp/pi-nvim-sockets/<hash>.sock
```

## Draft regression tests

Run from the repository root (Node.js 24+ for the TypeScript stripping test):

```bash
node tests/draft.test.mjs
nvim --headless -u NONE -l tests/draft.lua
```

The protocol test mocks Pi's editor and socket/filesystem infrastructure so it
cannot modify a live session. The Neovim test checks selection capture,
formatting, commands, and focus preservation without sending to a live agent.

## License

MIT
