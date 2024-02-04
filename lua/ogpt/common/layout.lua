local NuiLayout = require("nui.layout")

Layout = NuiLayout:extend("OgptLayout")

function Layout:init(options, box, edgy)
  Layout.super.init(self, options, box)
  self.edgy = edgy
end

function Layout:update(...)
  if not self.edgy then
    Layout.super.update(self, ...)
  end
end

return Layout
