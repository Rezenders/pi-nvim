-- Run from the repository: nvim --headless -u NONE -l tests/draft.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local pi = require("pi-nvim")
pi.setup({ set_default_keymaps = false })
local sent, notices = {}, {}
vim.notify = function(message, level) notices[#notices + 1] = { message, level } end
pi.send_raw = function(msg, cb)
  sent[#sent + 1] = msg
  if cb then cb(nil, { ok = true }) end
end
local function last() return sent[#sent].message end
local function includes(text) assert(last():find(text, 1, true), last()) end
vim.api.nvim_buf_set_name(0, "/tmp/pi-nvim-draft-example.lua")
vim.bo.filetype = "lua"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "second line", "``` nested fence", "你好 🦊" })
local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()

vim.cmd("PiAppendFile")
assert(last() == "File: /tmp/pi-nvim-draft-example.lua")
vim.cmd("2,3PiAppendSelection")
includes("lines 2-3:")
includes("second line\n``` nested fence")
includes("````lua")
vim.ui.input = function(opts, cb) cb("command prompt note") end
vim.cmd("2,3PiAppendSelectionPrompt")
includes("command prompt note\n\nFrom /tmp/pi-nvim-draft-example.lua, lines 2-3:")
vim.cmd("PiAppendBuffer")
includes("abcdef\nsecond line")
includes("你好 🦊")

-- Direct visual mappings must capture the active selection, not old marks.
vim.api.nvim_win_set_cursor(0, { 1, 1 })
vim.cmd("normal! v2l")
pi.append_selection()
includes("lines 1-1:")
includes("\nbcd\n")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("normal! Vj")
pi.append_selection()
includes("lines 2-3:")
includes("second line\n``` nested fence")
-- Blockwise selection.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! \22jl")
pi.append_selection()
includes("\nab\nse\n")
-- Reverse characterwise selection.
vim.api.nvim_win_set_cursor(0, { 1, 3 })
vim.cmd("normal! v2h")
pi.append_selection()
includes("\nbcd\n")

-- Append selection with prompt.
vim.ui.input = function(opts, cb) cb("look at this") end
vim.api.nvim_win_set_cursor(0, { 1, 1 })
vim.cmd("normal! v2l")
pi.append_selection_prompt()
includes("look at this\n\nFrom /tmp/pi-nvim-draft-example.lua, lines 1-1:")
includes("\nbcd\n")

-- Cancel prompt should not append.
vim.ui.input = function(opts, cb) cb(nil) end
local cancel_count = #sent
vim.api.nvim_win_set_cursor(0, { 1, 1 })
vim.cmd("normal! v2l")
pi.append_selection_prompt()
assert(#sent == cancel_count)

local count = #sent
pi.append_selection() -- no active selection or range
pi.append_draft("  ")
assert(#sent == count)
for _, msg in ipairs(sent) do assert(msg.type == "append_draft") end
assert(vim.api.nvim_get_current_win() == win)
assert(vim.api.nvim_get_current_buf() == buf)
assert(vim.bo.modified, "Unsaved edits must not be written as a side effect")
pi.send_raw = function(_, cb) cb(nil, { ok = false, error = "old extension" }) end
pi.append_file()
assert(notices[#notices][1]:find("old extension", 1, true))
assert(notices[#notices][2] == vim.log.levels.ERROR)
assert(loadfile(vim.fn.expand("~/.config/nvim/init.lua")))
print("Neovim draft tests passed")
vim.cmd("qa!")
