local Popup = require("ogpt.common.view")
local Config = require("ogpt.config")

local UtilWindow = Popup:extend("UtilWindow")

function UtilWindow:init(options, edgy)
  local popup_defaults = {
    border = {
      text = {
        top = options.display or "UTIL",
      },
    },
    buf_options = {
      filetype = options.filetype or "ogpt-util-window",
    },
  }
  local popup_options = vim.tbl_deep_extend("force", Config.options.util_window, popup_defaults)

  self.virtual_text = options.virtual_text
  self.default_text = options.default_text or ""
  self.working = false
  self.on_change = options.on_change
  self.on_close = options.on_close
  self.on_submit = options.on_submit
  self.keymaps = options.keymaps or {}

  UtilWindow.super.init(self, popup_options, edgy)
  self:set_text(vim.fn.split(self.default_text, "\n"))
  self:set_keymaps()
end

function UtilWindow:set_keymaps()
  for _, keymap in ipairs(self.keymaps) do
    self.map(keymap)
  end
end

function UtilWindow:toggle_placeholder()
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")

  if self.extmark then
    vim.api.nvim_buf_del_extmark(self.bufnr, Config.namespace_id, self.extmark)
  end

  if #text == 0 then
    self.extmark = vim.api.nvim_buf_set_extmark(self.bufnr, Config.namespace_id, 0, 0, {
      virt_text = {
        {
          self.virtual_text or "",
          "@comment",
        },
      },
      virt_text_pos = "overlay",
    })
  end
end

function UtilWindow:set_text(text)
  self.working = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, text)
  self.working = false
end

function UtilWindow:mount(UI, ...)
  -- UI.super.mount(self.ui, ...)
  UtilWindow.super.mount(self, UI, ...)

  self:toggle_placeholder()
  vim.api.nvim_buf_attach(self.bufnr, false, {
    on_lines = function()
      self:toggle_placeholder()

      if not self.working then
        local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
        local text = table.concat(lines, "\n")
        if self.on_change and type(self.on_change) == "function" then
          self.on_change(text)
        end
      end
    end,
  })
end

return UtilWindow
