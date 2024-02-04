local NuiLayout = require("nui.layout")

Layout = NuiLayout:extend("OgptLayout")

function Layout:init(options, box, edgy)
  Layout.super.init(self, options, box)
end

return Layout
