local NuiPopup = require("nui.popup")

Popup = NuiPopup:extend("OgptPopup")

function Popup:init(options, edgy)
  options = options or {}
  self.edgy = false
  self.init_update = false
  self.parent_winid = nil
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
  if self._.buf_options["filetype"] then
    vim.api.nvim_set_option_value("filetype", self._.buf_options["filetype"], { buf = self.bufnr })
  end
  if self._.buf_options["syntax"] then
    vim.api.nvim_set_option_value("syntax", self._.buf_options["syntax"], { buf = self.bufnr })
  end
end

function Popup:update_layout(...)
  -- ensure layout cannot get updated after the first time, used for setting up
  if not self.init_update or not self.edgy then
    Popup.super.update_layout(self, ...)
    self.init_update = true
  end
end

function Popup:show(...)
  Popup.super.show(self, ...)
end

return Popup
