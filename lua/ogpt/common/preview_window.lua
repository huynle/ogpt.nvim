local Popup = require("nui.popup")
local Config = require("ogpt.config")
local event = require("nui.utils.autocmd").event

local PreviewWindow = Popup:extend("PreviewWindow")

function PreviewWindow:init(options)
  options = vim.tbl_deep_extend("keep", options or {}, Config.options.preview_window)

  PreviewWindow.super.init(self, options)
end

function PreviewWindow:mount(action)
  action = action or {}

  PreviewWindow.super.mount(self)

  -- close
  local keys = Config.options.preview_window.keymaps.close
  if type(keys) ~= "table" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    self:map("n", key, function()
      action.stop = true
      self:unmount()
    end)
  end

  -- -- unmount component when cursor leaves buffer
  -- self:on(event.BufLeave, function()
  --   action.stop = true
  --   self:unmount()
  -- end)

  -- unmount component when cursor leaves buffer
  self:on(event.WinClosed, function()
    action.stop = true
    self:unmount()
  end)

  -- dynamically resize
  -- https://github.com/MunifTanjim/nui.nvim/blob/main/lua/nui/popup/README.md#popupupdate_layout
  self:on(event.CursorMoved, function()
    action:update_popup_size(self)
  end)
end

return PreviewWindow
