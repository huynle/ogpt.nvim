local NuiPopup = require("nui.popup")
local Config = require("ogpt.config")

Popup = NuiPopup:extend("OgptPopup")

function Popup:init(options)
  if Config.options.chat.edgy and options.border then
    options.border = nil
  end
  Popup.super.init(self, options)
end

return Popup
