local NuiPopup = require("nui.popup")

Popup = NuiPopup:extend("OgptPopup")

function Popup:init(options, edgy)
  options = options or {}
  self.edgy = false
  if options.edgy and options.border or edgy then
    self.edgy = true
    options.border = nil
  end
  Popup.super.init(self, options)
end

return Popup
