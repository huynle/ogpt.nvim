local classes = require("ogpt.common.classes")
local utils = require("ogpt.utils")
local Config = require("ogpt.config")

local SimpleView = classes.class()

function SimpleView:init(visitor, opts)
  self.visitor = visitor
  -- Set default values for the options table if it's not provided.
  opts = vim.tbl_extend("force", {
    buf = {
      swapfile = false,
      bufhidden = "wipe",
      filetype = "markdown",
      vars = {},
    },
    win = {
      wrap = true,
      cursorline = true,
    },
    enter = false,
    keymaps = {},
    new_win = false,
  }, opts or {})
  self.opts = opts

  self.name = visitor.name or opts.buf.filetype
  self.bufnr = nil
end

-- Define a function that creates a new window with the given options.
-- The function returns the buffer and window handles.
-- function SimpleView:show(opts)
-- 	self.visible = true
-- 	opts = vim.tbl_extend("force", self.opts, opts or {})
--
-- 	-- Save the handle of the window from which we open the navigation.
-- 	local start_win = vim.api.nvim_get_current_win()
--
-- 	-- Get the buffer handle.
-- 	-- local buf = vim.fn.bufnr(self.name)
-- 	local buf = self.bufnr
--
-- 	-- Get the window handle.
-- 	local win
--
-- 	-- If the buffer already exists, find the window that displays it and return its handle.
-- 	if buf ~= -1 then
-- 		for _, win_id in ipairs(vim.api.nvim_list_wins()) do
-- 			local bufnr = vim.api.nvim_win_get_buf(win_id)
-- 			if bufnr == buf then
-- 				vim.api.nvim_set_current_win(win_id)
-- 				vim.api.nvim_set_current_win(start_win)
-- 				return buf, win_id
-- 			end
-- 		end
-- 	end
--
-- 	-- Reset the current window to the one from which we opened the navigation.
-- 	vim.api.nvim_set_current_win(start_win)
--
-- 	-- Return the buffer and window handles.
-- 	return buf, win
-- end

function SimpleView:unmount()
  -- local buf, win = self:mount()
  -- Close the window
  local force = true
  vim.api.nvim_win_close(self.winid, force)
end

-- mount can take name or filename
function SimpleView:show()
  self:mount()
end

-- mount can take name or filename
function SimpleView:hide()
  local force = true
  local winid = vim.fn.bufwinid(self.bufnr)
  if winid ~= -1 then
    vim.api.nvim_win_close(self.winid, force)
  end
end

-- mount can take name or filename
function SimpleView:mount(name, opts)
  name = name or self.name
  -- Save the handle of the window from which we open the navigation.
  local start_win = vim.api.nvim_get_current_win()

  -- Try to get the buffer handle.
  local buf = vim.fn.bufnr(name)
  if buf ~= -1 and vim.fn.bufexists(buf) then
  -- buffer is still sitting out there and is valid
  else
    -- pull it from vim global
    buf = vim.g[name]
  end

  local previous_winid
  if not self.opts.new_win then
    previous_winid = self.winid
  end

  -- If the buffer already exists, find the window that displays it and return its handle.
  if buf and vim.fn.bufexists(buf) then
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      local bufnr = vim.api.nvim_win_get_buf(win_id)
      if bufnr == buf then
        -- if not self.opts.enter then
        -- 	vim.api.nvim_set_current_win(start_win)
        -- else
        -- 	vim.api.nvim_set_current_win(win_id)
        -- end
        previous_winid = win_id
        break
        -- self.bufnr = buf
        -- self.winid = win_id
        -- return buf, win_id
      end
    end
  end

  -- -- If the buffer already exists, find the window that displays it and return its handle.
  -- if buf and vim.fn.bufexists(buf) then
  -- 	for _, win_id in ipairs(vim.api.nvim_list_wins()) do
  -- 		local bufnr = vim.api.nvim_win_get_buf(win_id)
  -- 		if bufnr == buf then
  -- 			if not self.opts.enter then
  -- 				vim.api.nvim_set_current_win(start_win)
  -- 			else
  -- 				vim.api.nvim_set_current_win(win_id)
  -- 			end
  -- 			self.bufnr = buf
  -- 			self.winid = win_id
  -- 			return buf, win_id
  -- 		end
  -- 	end
  -- end

  -- Open a new vertical window at the far right.
  -- vim.api.nvim_command("botright " .. "vnew")
  if vim.fn.filereadable(name) == 1 then
    if previous_winid then
      vim.api.nvim_set_current_win(previous_winid)
      vim.api.nvim_command("edit " .. name)
    else
      vim.api.nvim_command("vnew " .. name)
    end
    self.bufnr = vim.api.nvim_get_current_buf()
  else
    if previous_winid and not self.opts.new_win and (self.bufnr ~= nil and vim.fn.bufwinid(self.bufnr) ~= -1) then
      vim.api.nvim_set_current_win(previous_winid)
      self.bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(self.bufnr, -1, -1, false, {})
    else
      vim.api.nvim_command("vnew")
      self.bufnr = vim.api.nvim_get_current_buf()
      -- Set the buffer's filetype to the filetype specified in the options table.
      vim.api.nvim_buf_set_option(self.bufnr, "filetype", self.opts.buf.filetype)
      -- Set the name of the buffer to the buffer name specified in the options table.
      vim.api.nvim_buf_set_name(self.bufnr, name)
    end
  end

  -- Get the buffer and window handles of the new window.
  self.winid = vim.api.nvim_get_current_win()

  -- -- Set the buffer type to "nofile" to prevent it from being saved.
  vim.api.nvim_buf_set_option(self.bufnr, "buftype", "nofile")

  -- Disable swapfile for the buffer.
  vim.api.nvim_buf_set_option(self.bufnr, "swapfile", false)

  -- Set the buffer's hidden option to "wipe" to destroy it when it's hidden.
  vim.api.nvim_buf_set_option(self.bufnr, "bufhidden", "delete")

  -- -- Set so that the cusor does not jump
  -- vim.api.nvim_buf_set_option(self.bufnr, "switchbuf", "useopen")

  -- -- Set the name of the buffer to the buffer name specified in the options table.
  -- vim.api.nvim_buf_set_name(self.bufnr, name or self.name)

  -- Set buffer variables as specified in the options table.
  for key, value in pairs(self.opts.buf.vars or {}) do
    vim.api.nvim_buf_set_var(self.bufnr, key, value)
  end

  -- Set the window options as specified in the options table.
  -- vim.api.nvim_win_set_option(win, "wrap", opts.win.wrap)
  -- vim.api.nvim_win_set_option(win, "cursorline", opts.win.cursorline)

  -- Set the keymaps for the window as specified in the options table.
  for keymap, command in pairs(self.opts.keymaps) do
    vim.keymap.set("n", keymap, command, { noremap = true, buffer = self.bufnr })
  end

  if not self.opts.enter then
    vim.api.nvim_set_current_win(start_win)
  end
  vim.g[name] = self.bufnr
end

function SimpleView:map(mode, key, command)
  mode = vim.tbl_islist(mode) and mode or { mode }
  vim.keymap.set(mode, key, command, { buffer = self.bufnr })
end

function SimpleView:apply_map(opts)
  -- accept output and replace
  self:map("n", Config.options.popup.keymaps.accept, function()
    -- local _lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    vim.api.nvim_buf_set_text(
      opts.main_bufnr,
      opts.selection_idx.start_row - 1,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.end_row - 1,
      opts.selection_idx.end_col,
      opts.lines
    )
    vim.cmd("q")
  end)

  -- accept output and prepend
  self:map("n", Config.options.popup.keymaps.prepend, function()
    local _lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    table.insert(_lines, "")
    table.insert(_lines, "")
    vim.api.nvim_buf_set_text(
      opts.main_bufnr,
      opts.selection_idx.end_row - 1,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.end_row - 1,
      opts.selection_idx.start_col - 1,
      _lines
    )
    vim.cmd("q")
  end)

  -- accept output and append
  self:map("n", Config.options.popup.keymaps.append, function()
    local _lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    table.insert(_lines, 1, "")
    table.insert(_lines, "")
    vim.api.nvim_buf_set_text(
      opts.main_bufnr,
      opts.selection_idx.end_row,
      opts.selection_idx.start_col - 1,
      opts.selection_idx.end_row,
      opts.selection_idx.start_col - 1,
      _lines
    )
    vim.cmd("q")
  end)

  -- yank code in output and close
  self:map("n", Config.options.popup.keymaps.yank_code, function()
    local _lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    local _code = utils.getSelectedCode(_lines)
    vim.fn.setreg(Config.options.yank_register, _code)

    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
    vim.cmd("q")
  end)

  -- yank output and close
  self:map("n", Config.options.popup.keymaps.yank_to_register, function()
    local _lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    vim.fn.setreg(Config.options.yank_register, _lines)

    if vim.fn.mode() == "i" then
      vim.api.nvim_command("stopinsert")
    end
    vim.cmd("q")
  end)
end

return SimpleView
