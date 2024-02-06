local Object = require("ogpt.common.object")
local utils = require("ogpt.utils")

local SimpleView = Object("SimpleView")

function SimpleView:init(name, opts)
  local _defaults = {

    buf = {
      swapfile = false,
      bufhidden = "delete",
      syntax = "markdown",
      buftype = "nofile",
    },
    buf_vars = {},
    win = {
      wrap = true,
      cursorline = true,
    },
    enter = false,
    keymaps = {},
    new_win = false,
    events = {
      {
        events = { "BufWipeout", "BufDelete" },
        callback = function()
          -- vim.print("GOTHERE")
        end,
      },
    },
  }
  -- Set default values for the options table if it's not provided.
  local _opts = vim.tbl_deep_extend("force", _defaults, opts or {})
  self.opts = _opts
  self.name = name
  self.bufnr = nil
  self.winid = nil
  self.visible = false
end

function SimpleView:unmount()
  local force = true
  local winid = vim.fn.bufwinid(self.bufnr or -1)
  if winid ~= -1 then
    vim.api.nvim_win_close(self.winid, force)
  end
  self.visible = false
end

-- mount can take name or filename
function SimpleView:show()
  self:mount()
end

-- mount can take name or filename
function SimpleView:hide()
  if self.visible then
    self:unmount()
  end
end

-- mount can take name or filename
function SimpleView:mount(name, opts)
  if self.visible then
    return
  end
  self.visible = true
  opts = opts or {}
  opts = vim.tbl_deep_extend("force", self.opts, opts)
  name = name or self.name
  local start_win = vim.api.nvim_get_current_win()
  local buf = vim.fn.bufnr(name)
  local previous_winid = vim.fn.bufwinid(buf)
  -- Open a new vertical window at the far right.
  -- vim.api.nvim_command("botright " .. "vnew")
  -- if vim.fn.filereadable(name) == 1 then
  if previous_winid ~= -1 and not self.opts.new_win then
    vim.api.nvim_set_current_win(previous_winid)
    vim.api.nvim_command("edit " .. name)
  else
    vim.api.nvim_command("vnew " .. name)
  end
  self.bufnr = vim.api.nvim_get_current_buf()
  self.winid = vim.api.nvim_get_current_win()

  vim.api.nvim_buf_set_option(self.bufnr, "filetype", name)

  -- vim.api.nvim_exec_autocmds("Syntax", { buffer = self.bufnr, Syntax = opts.buf.filetype })

  -- Set the buffer type to "nofile" to prevent it from being saved.
  -- vim.api.nvim_buf_set_option(self.bufnr, "buftype", "nofile")
  for opt, val in pairs(opts.buf) do
    vim.api.nvim_buf_set_option(self.bufnr, opt, val)
  end

  -- -- Disable swapfile for the buffer.
  -- vim.api.nvim_buf_set_option(self.bufnr, "swapfile", false)
  --
  -- -- Set the buffer's hidden option to "wipe" to destroy it when it's hidden.
  -- vim.api.nvim_buf_set_option(self.bufnr, "bufhidden", "delete")
  -- -- Set the window options as specified in the options table.
  -- -- vim.api.nvim_win_set_option(win, "wrap", opts.win.wrap)
  -- -- vim.api.nvim_win_set_option(win, "cursorline", opts.win.cursorline)
  --
  -- Set buffer variables as specified in the options table.
  for key, value in pairs(opts.buf_vars or {}) do
    vim.api.nvim_buf_set_var(self.bufnr, key, value)
  end

  -- Set the keymaps for the window as specified in the options table.
  for keymap, command in pairs(opts.keymaps) do
    vim.keymap.set("n", keymap, command, { noremap = true, buffer = self.bufnr })
  end

  local group = vim.api.nvim_create_augroup(name .. "_augroup", {})
  for _, event in ipairs(opts.events) do
    local _copy = utils.shallow_copy(event)
    -- local _copy = event
    local event_names = _copy.events
    _copy.events = nil
    opts = vim.tbl_extend("force", opts or {}, {
      group = group,
      buffer = self.bufnr,
    })
    vim.api.nvim_create_autocmd(event_names, _copy)
  end

  if not self.opts.enter then
    vim.api.nvim_set_current_win(start_win)
  end
end

function SimpleView:map(mode, key, command)
  mode = vim.tbl_islist(mode) and mode or { mode }
  vim.keymap.set(mode, key, command, { buffer = self.bufnr })
end

return SimpleView
