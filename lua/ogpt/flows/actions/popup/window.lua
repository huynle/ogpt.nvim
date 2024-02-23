local Popup = require("ogpt.common.popup")
local popup_keymap = require("ogpt.flows.actions.popup.keymaps")
local Config = require("ogpt.config")
local event = require("nui.utils.autocmd").event
local Utils = require("ogpt.utils")

local PopupWindow = Popup:extend("PopupWindow")

function PopupWindow:init(options, edgy)
  options = vim.tbl_deep_extend("keep", options or {}, Config.options.popup)
  self.options = options

  PopupWindow.super.init(self, options, edgy)
end

function PopupWindow:update_popup_size(opts)
  if self.edgy then
    return
  end
  opts = vim.tbl_extend("force", self.options, opts or {})
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
  }, opts.default_ui or {})
  return ui_opts
end

function PopupWindow:mount(opts)
  PopupWindow.super.mount(self)

  -- self:update_popup_size(opts)
  popup_keymap.apply_map(self, opts)

  -- unmount component when closing window
  self:on(event.WinClosed, function()
    if opts.stop and type(opts.stop) == "function" then
      opts.stop()
    end
    self:unmount()
  end)

  -- dynamically resize
  if self.options.dynamic_resize then
    -- set the event
    -- https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/popup/README.md#popupupdate_layout
    self:on(event.CursorMoved, function()
      self:update_popup_size(opts)
    end)
  else
    opts = {
      cur_win = opts.cur_win,
      name = opts.name,
      ui_h = self.options.size.height,
      ui_w = self.options.size.width,
      selection_idx = opts.selection_idx,
    }
  end

  -- create the inital window
  self:update_popup_size(opts)
end

return PopupWindow
