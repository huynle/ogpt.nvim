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

function Popup:mount()
  Popup.super.mount(self)
  -- syntax and filetype don't always get set in the correct order.
  -- This for syntax to be the last thing to be set.
  if self._.buf_options["syntax"] then
    vim.api.nvim_buf_set_option(self.bufnr, "syntax", self._.buf_options["syntax"])
  end
end

return Popup
