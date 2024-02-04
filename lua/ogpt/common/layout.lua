local NuiLayout = require("nui.layout")

Layout = NuiLayout:extend("OgptLayout")

function Layout:init(options, box, edgy)
  Layout.super.init(self, options, box)
  self.edgy = edgy
  self.init_update = false
end

function Layout:update(...)
  -- ensure layout cannot get updated after the first time, used for setting up
  if not self.init_update or not self.edgy then
    Layout.super.update(self, ...)
    self.init_update = true
  end
end

return Layout
