local Popup = require("nui.popup")
local Config = require("ogpt.config")
local event = require("nui.utils.autocmd").event
local Utils = require("ogpt.utils")

local PopupWindow = Popup:extend("PopupWindow")

function PopupWindow:init(options)
  options = vim.tbl_deep_extend("keep", options or {}, Config.options.popup)

  PopupWindow.super.init(self, options)
end

function PopupWindow:update_popup_size(opts)
  opts.lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local ui_opts = self:calculate_size(opts)
  self:update_layout(ui_opts)
end

function PopupWindow:calculate_size(opts)
  opts = opts or {}
  -- compute size
  -- the width is calculated based on the maximum number of lines and the height is calculated based on the width
  local cur_win = opts.cur_win
  local max_h = math.ceil(vim.api.nvim_win_get_height(cur_win) * 0.75)
  local max_w = math.ceil(vim.api.nvim_win_get_width(cur_win) * 0.5)
  local ui_w = 0
  local len = 0
  local ncount = 0
  local lines = opts.lines or Utils.split_string_by_line(opts.text or "")

  for _, v in ipairs(lines) do
    local l = string.len(v)
    if v == "" then
      ncount = ncount + 1
    end
    ui_w = math.max(l, ui_w)
    len = len + l
  end
  ui_w = math.min(ui_w, max_w)
  ui_w = math.max(ui_w, 10)
  local ui_h = math.ceil(len / ui_w) + ncount
  ui_h = math.min(ui_h, max_h)
  ui_h = math.max(ui_h, 1)

  -- use opts
  ui_w = opts.ui_w or ui_w
  ui_h = opts.ui_h or ui_h

  -- build ui opts
  local ui_opts = vim.tbl_deep_extend("keep", {
    size = {
      width = ui_w,
      height = ui_h,
    },
    border = {
      style = "rounded",
      text = {
        top = " " .. (opts.title or opts.name or opts.args) .. " ",
        top_align = "left",
      },
    },
    relative = {
      type = "buf",
      position = {
        row = opts.selection_idx.start_row,
        col = opts.selection_idx.start_col,
      },
    },
  }, opts.default_ui)
  return ui_opts
end

function PopupWindow:mount(opts)
  PopupWindow.super.mount(self)

  self:update_popup_size(opts)

  -- close
  local keys = Config.options.popup.keymaps.close
  if type(keys) ~= "table" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    self:map("n", key, function()
      if opts.stop and type(opts.stop) == "function" then
        opts.stop()
      end
      self:unmount()
    end)
  end

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
    local _code = Utils.getSelectedCode(_lines)
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

  -- -- unmount component when cursor leaves buffer
  -- self:on(event.BufLeave, function()
  --   action.stop = true
  --   self:unmount()
  -- end)

  -- unmount component when cursor leaves buffer
  self:on(event.WinClosed, function()
    if opts.stop and type(opts.stop) == "function" then
      opts.stop()
    end
    self:unmount()
  end)

  -- dynamically resize
  -- https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/popup/README.md#popupupdate_layout
  self:on(event.CursorMoved, function()
    self:update_popup_size(opts)
  end)
end

return PopupWindow
