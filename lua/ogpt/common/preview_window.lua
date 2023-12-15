local Popup = require("nui.popup")
local Config = require("ogpt.config")

local PreviewWindow = Popup:extend("PreviewWindow")

function PreviewWindow:init(options)
  options = vim.tbl_deep_extend("keep", options or {}, Config.options.preview_window)

  PreviewWindow.super.init(self, options)
end

function PreviewWindow:mount()
  PreviewWindow.super.mount(self)

  -- close
  local keys = Config.options.chat.keymaps.close
  if type(keys) ~= "table" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    self:map("n", key, function()
      self:unmount()
    end)
  end
end

return PreviewWindow
